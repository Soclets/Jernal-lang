(* Methods on built-in types, from standard 13.3. *)

module C = Checked

let runtime_error ?what ?when_ span why =
  raise (C.Runtime_stop (Diagnostic.make ~span ?what ?when_ Diagnostic.Runtime_error why))

let int n = Value.int_of_int64 (Int64.of_int n)

let items = function Value.List l -> l.items | _ -> invalid_arg "items"

(* The offset of a position in a list of [length] items; outside the list is a check (D53, D136). *)
let offset_of span ~length (counting : Syntax.counting) (position : Value.t) : int =
  let n = Value.integer_to_z position in
  let offset = match counting with Syntax.Pos -> Z.pred n | Syntax.Offset -> n in
  if Z.lt offset Z.zero || Z.geq offset (Z.of_int length) then
    runtime_error
      ~what:(Printf.sprintf "%s %s is outside the list"
               (match counting with Syntax.Pos -> "position" | Syntax.Offset -> "offset") (Z.to_string n))
      ~when_:(Printf.sprintf "the list has %d item%s" length (if length = 1 then "" else "s"))
      span "a position outside the list is a check (D53, standard 7.2)";
  Z.to_int offset

(* trace: D130, D131 *)
let string_length kind _span = function
  | Value.String s :: _ -> (
      match kind with
      | `Bytes -> int (String.length s)
      | `Code_points -> int (Text.code_point_count s)
      | `Graphemes -> int (Text.grapheme_count s))
  | _ -> Value.Nothing

let length _span = function
  | Value.List l :: _ -> int (Dynarray.length l.items)
  | Value.Map m :: _ -> int (Dynarray.length m.entries)
  | _ -> Value.Nothing

(* trace: D136 *)
let add _span = function
  | list :: [ item ] -> Dynarray.add_last (items list) item; Value.Nothing
  | _ -> Value.Nothing

let add_at counting span = function
  | list :: [ item; position ] ->
      let xs = items list in
      let offset = offset_of span ~length:(Dynarray.length xs) counting position in
      let before = Dynarray.to_list xs in
      Dynarray.clear xs;
      List.iteri (fun i x -> if i = offset then Dynarray.add_last xs item; Dynarray.add_last xs x) before;
      Value.Nothing
  | _ -> Value.Nothing

let remove counting span = function
  | list :: [ position ] ->
      let xs = items list in
      let offset = offset_of span ~length:(Dynarray.length xs) counting position in
      let removed = Dynarray.get xs offset in
      let before = Dynarray.to_list xs in
      Dynarray.clear xs;
      List.iteri (fun i x -> if i <> offset then Dynarray.add_last xs x) before;
      removed
  | _ -> Value.Nothing

let clear _span = function list :: _ -> Dynarray.clear (items list); Value.Nothing | _ -> Value.Nothing

let contains _span = function
  | list :: [ item ] -> Value.Bool (Dynarray.exists (fun x -> Value.equal x item) (items list))
  | _ -> Value.Nothing

let first_or_last which span = function
  | list :: _ ->
      let xs = items list in
      if Dynarray.length xs = 0 then
        runtime_error
          ~what:(Printf.sprintf "`%s()` on an empty list" (match which with `First -> "first" | `Last -> "last"))
          span "`first()` and `last()` on an empty list are checks (D136, standard 13.3)";
      (match which with `First -> Dynarray.get xs 0 | `Last -> Dynarray.get xs (Dynarray.length xs - 1))
  | _ -> Value.Nothing

(* trace: D38 *)
let sum (item_type : Types.t) span = function
  | list :: _ -> (
      let values = Dynarray.to_list (items list) in
      match item_type with
      | Types.Integer t ->
          let total = List.fold_left (fun total v -> Z.add total (Value.integer_to_z v)) Z.zero values in
          if not (Types.integer_fits t total) then
            runtime_error ~what:(Printf.sprintf "the sum doesn't fit in `%s`" (Types.name item_type))
              ~when_:(Printf.sprintf "it would be %s" (Z.to_string total))
              span "a number too big for its type is a check (D54, standard 7.2)";
          Value.integer_of_z t total
      | Types.Float k -> Value.Float (Numbers.float_sum (List.map (function Value.Float (f, _) -> f | _ -> 0.0) values), k)
      | Types.Rational -> Value.Rational (List.fold_left (fun total v -> match v with Value.Rational q -> Q.add total q | _ -> total) Q.zero values)
      | _ -> Value.Nothing)
  | _ -> Value.Nothing

(* ---------- Maps (D138) ---------- *)

let entries = function Value.Map m -> m | _ -> invalid_arg "entries"

let find_key (m : Value.map_value) key =
  let rec go i = if i >= Dynarray.length m.entries then None else if Value.equal (fst (Dynarray.get m.entries i)) key then Some i else go (i + 1) in
  go 0

(* The order keys sort in: numbers by value, strings by code point (D138). *)
let compare_keys (a : Value.t) (b : Value.t) : int =
  match a, b with
  | (Value.Int64_integer _ | Value.Wide_integer _), _ -> Z.compare (Value.integer_to_z a) (Value.integer_to_z b)
  | Value.String x, Value.String y -> String.compare x y   (* UTF-8 bytes sort in code point order *)
  | Value.Float (x, _), Value.Float (y, _) -> Float.compare x y
  | Value.Rational x, Value.Rational y -> Q.compare x y
  | _ -> 0

let missing_key span =
  runtime_error ~what:"the map has no such key" span "a missing key is a check (D138, standard 13.3)"

(* Adds or replaces; a Map.sorted keeps its entries sorted by key. *)
let set_key (m : Value.map_value) key value =
  match find_key m key with
  | Some i -> Dynarray.set m.entries i (key, value)
  | None -> (
      match m.map_kind with
      | Types.Map_sorted ->
          let before = Dynarray.to_list m.entries in
          let smaller, larger = List.partition (fun (k, _) -> compare_keys k key < 0) before in
          Dynarray.clear m.entries;
          List.iter (Dynarray.add_last m.entries) (smaller @ [ (key, value) ] @ larger)
      | _ -> Dynarray.add_last m.entries (key, value))

let map_index span (map : Value.t) key =
  let m = entries map in
  match find_key m key with Some i -> snd (Dynarray.get m.entries i) | None -> missing_key span

let map_get span = function
  | map :: [ key ] -> (
      let m = entries map in
      match find_key m key with
      | Some i -> snd (Dynarray.get m.entries i)
      | None ->
          raise
            (C.Runtime_stop
               (Diagnostic.make ~span ~what:"the name of the failure `get` raises isn't decided yet"
                  Diagnostic.Not_designed_yet "not decided yet (D138, standard 12.1)")))
  | _ -> Value.Nothing

let map_contains _span = function
  | map :: [ key ] -> Value.Bool (find_key (entries map) key <> None)
  | _ -> Value.Nothing

let map_remove span = function
  | map :: [ key ] -> (
      let m = entries map in
      match find_key m key with
      | Some i ->
          let removed = snd (Dynarray.get m.entries i) in
          let before = Dynarray.to_list m.entries in
          Dynarray.clear m.entries;
          List.iteri (fun j e -> if j <> i then Dynarray.add_last m.entries e) before;
          removed
      | None -> missing_key span)
  | _ -> Value.Nothing

let map_keys_sorted _span = function
  | map :: _ ->
      let keys = List.map fst (Dynarray.to_list (entries map).entries) in
      Value.List { items = Dynarray.of_list (List.stable_sort compare_keys keys) }
  | _ -> Value.Nothing
