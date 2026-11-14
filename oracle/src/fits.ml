(* Whether a value fits a type's details: bounds and array lengths (D135). *)

let rec has_details (t : Types.t) =
  match t with
  | Types.Bounded _ | Types.Array _ -> true
  | Types.List item -> has_details item
  | Types.Map (_, k, v) -> has_details k || has_details v
  | Types.New (_, t) -> has_details t
  | _ -> false

let number_of (v : Value.t) : Q.t option =
  match v with
  | Value.Int64_integer _ | Value.Wide_integer _ -> Some (Q.of_bigint (Value.integer_to_z v))
  | Value.Float (f, _) -> if Float.is_finite f then Some (Q.of_float f) else None
  | Value.Rational q -> Some q
  | Value.Decimal (Decimal.Finite q) -> Some q
  | _ -> None

let shown (v : Value.t) =
  match v with
  | Value.Int64_integer _ | Value.Wide_integer _ -> Z.to_string (Value.integer_to_z v)
  | _ -> ( match number_of v with Some q -> Types.bound_text q | None -> "not a number")

let items_text n = Printf.sprintf "%d item%s" n (if n = 1 then "" else "s")

(* [None] if [v] fits [t]; otherwise what's wrong, as `when:` text. *)
let rec problem (t : Types.t) (v : Value.t) : string option =
  match t, v with
  | Types.Bounded (base, b), _ -> (
      let own =
        match v with
        | Value.List l ->
            let n = Dynarray.length l.items in
            if (match b.len_min with Some m -> n < m | None -> false) || (match b.len_max with Some m -> n > m | None -> false)
            then Some (Printf.sprintf "it has %s" (items_text n))
            else None
        | Value.Float (f, _) when Float.is_integer f = false && not (Float.is_finite f) ->
            (* infinities are ordered as IEEE says; NaN is unordered, so it never fits a bound *)
            let breaks =
              Float.is_nan f && (b.min <> None || b.max <> None)
              || (f = Float.infinity && b.max <> None)
              || (f = Float.neg_infinity && b.min <> None)
            in
            if breaks then Some (Printf.sprintf "it is %s" (if Float.is_nan f then "NaN" else if f > 0.0 then "inf" else "-inf"))
            else None
        | Value.Decimal ((Decimal.Infinity _ | Decimal.Not_a_number) as d) ->
            let breaks =
              (d = Decimal.Not_a_number && (b.min <> None || b.max <> None))
              || (d = Decimal.Infinity false && b.max <> None)
              || (d = Decimal.Infinity true && b.min <> None)
            in
            if breaks then Some (Printf.sprintf "it is %s" (Decimal.to_text d)) else None
        | _ -> (
            match number_of v with
            | None -> if b.min <> None || b.max <> None then Some (Printf.sprintf "it is %s" (shown v)) else None
            | Some q ->
                if (match b.min with Some m -> Q.lt q m | None -> false) || (match b.max with Some m -> Q.gt q m | None -> false)
                then Some (Printf.sprintf "it is %s" (shown v))
                else None)
      in
      match own with Some p -> Some p | None -> problem base v)
  | Types.Array (item, n), Value.List l ->
      let length = Dynarray.length l.items in
      if length <> n then Some (Printf.sprintf "it has %s" (items_text length)) else items item l
  | Types.List item, Value.List l -> items item l
  | Types.Map (_, k, value), Value.Map m ->
      Dynarray.fold_left
        (fun found (key, x) -> match found with Some _ -> found | None -> (match problem k key with Some p -> Some p | None -> problem value x))
        None m.entries
  | Types.New (_, t), _ -> problem t v
  | _ -> None

and items item (l : Value.list_value) =
  if not (has_details item) then None
  else
    let found = ref None in
    Dynarray.iteri
      (fun i x ->
        if !found = None then
          match problem item x with
          | Some p -> found := Some (Printf.sprintf "item %d doesn't fit: %s" (i + 1) p)
          | None -> ())
      l.items;
    !found
