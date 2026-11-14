(* Values while a program runs. *)

type t =
  | Int64_integer of int64 * Types.integer_type    (* trace: D73 — integers are Int64, never OCaml's int *)
  | Wide_integer of Z.t * Types.integer_type       (* widths whose range doesn't fit an Int64 *)
  | Float of float * Types.float_kind
  | Rational of Q.t
  | Bool of bool
  | String of string
  | List of list_value
  | Map of map_value
  | Struct of struct_value
  | Union of union_value
  | Range of { from : Z.t; last : Z.t option; step : Z.t }   (* [last = None]: runs zero times *)
  | Lines
  | Nothing

and list_value = { items : t Dynarray.t }

and map_value = { map_kind : Types.map_kind; entries : (t * t) Dynarray.t }

and struct_value = { struct_name : string; fields : (string * t ref) list }

and union_value = { union_name : string; case_name : string; case_fields : (string * t ref) list }

let integer_to_z = function
  | Int64_integer (n, _) -> Z.of_int64 n
  | Wide_integer (n, _) -> n
  | _ -> invalid_arg "integer_to_z"

(* The caller has checked that [value] fits [integer_type]. *)
let integer_of_z integer_type value =
  if Types.held_as_int64 integer_type then Int64_integer (Z.to_int64 value, integer_type)
  else Wide_integer (value, integer_type)

let int_of_int64 n = Int64_integer (n, { Types.signed = true; width = 64 })

let rec equal a b =
  match a, b with
  | (Int64_integer _ | Wide_integer _), (Int64_integer _ | Wide_integer _) -> Z.equal (integer_to_z a) (integer_to_z b)
  | Float (x, _), Float (y, _) -> Float.equal x y && not (Float.is_nan x)
  | Rational x, Rational y -> Q.equal x y
  | Bool x, Bool y -> x = y
  | String x, String y -> String.equal x y
  | List x, List y ->
      Dynarray.length x.items = Dynarray.length y.items
      && (let same = ref true in
          Dynarray.iteri (fun i item -> if not (equal item (Dynarray.get y.items i)) then same := false) x.items;
          !same)
  | Struct x, Struct y ->
      x.struct_name = y.struct_name
      && List.for_all2 (fun (_, a) (_, b) -> equal !a !b) x.fields y.fields
  | Union x, Union y ->
      x.union_name = y.union_name && x.case_name = y.case_name
      && List.for_all2 (fun (_, a) (_, b) -> equal !a !b) x.case_fields y.case_fields
  | _ -> false

(* A deep copy: everything that can change is duplicated, all the way down (D52). *)
let rec deep_copy = function
  | List l -> List { items = Dynarray.map deep_copy l.items }
  | Map m -> Map { m with entries = Dynarray.map (fun (k, v) -> (deep_copy k, deep_copy v)) m.entries }
  | Struct s -> Struct { s with fields = List.map (fun (n, v) -> (n, ref (deep_copy !v))) s.fields }
  | Union u -> Union { u with case_fields = List.map (fun (n, v) -> (n, ref (deep_copy !v))) u.case_fields }
  | other -> other
