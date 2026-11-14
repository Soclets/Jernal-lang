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
