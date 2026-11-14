(* Jernal's types, as the checker knows them (standard chapter 2). *)

(* trace: D54, D93 *)
type integer_type = { signed : bool; width : int }

type float_kind = F16 | Bf16 | F32 | F64

type map_kind = Map_hash | Map_sorted | Map_insertion

type t =
  | Integer of integer_type
  | Float of float_kind
  | Decimal
  | Rational
  | Bool
  | String
  | List of t
  | Array of t * int
  | Map of map_kind * t * t
  | Range                       (* what range[...] gives: the Ints it goes through *)
  | Lines                       (* what lines() gives: a sequence of String *)
  | Struct of string
  | Union of string
  | Case of string * string      (* a union value known to be one case, inside a case test or arm (D97) *)
  | Failure of string * (string * t) list   (* a failure's data, named in an `otherwise` arm (D48) *)
  | New of string * t           (* type.new: a distinct type over the same data (D61) *)
  | Parameter of string         (* a type parameter, ?Item, inside its generic function (D103) *)
  | Bounded of t * bounds       (* a type with details in [ ]: Int[min: 0, max: 100], List<Int>[len.max: 3] (D135) *)
  | Unknown                     (* after an error: nothing is guessed about it (D13) *)
  | Nothing                     (* what a function that returns nothing gives *)

and bounds = {
  min : Q.t option;
  max : Q.t option;
  len_min : int option;
  len_max : int option;
}

let no_bounds = { min = None; max = None; len_min = None; len_max = None }

let int = Integer { signed = true; width = 64 }

(* A bound as written: 100, -2.5 *)
let bound_text (q : Q.t) =
  if Z.equal (Q.den q) Z.one then Z.to_string (Q.num q)
  else
    let negative = Q.sign q < 0 in
    let q = Q.abs q in
    let rec places k = if Z.equal (Z.rem (Z.pow (Z.of_int 10) k) (Q.den q)) Z.zero then k else places (k + 1) in
    let k = places 0 in
    let digits = Z.to_string (Z.div (Z.mul (Q.num q) (Z.pow (Z.of_int 10) k)) (Q.den q)) in
    let digits = if String.length digits <= k then String.make (k - String.length digits + 1) '0' ^ digits else digits in
    (if negative then "-" else "") ^ String.sub digits 0 (String.length digits - k) ^ "." ^ String.sub digits (String.length digits - k) k

let integer_name { signed; width } =
  (if signed then "i" else "u") ^ string_of_int width

let float_name = function F16 -> "f16" | Bf16 -> "bf16" | F32 -> "f32" | F64 -> "f64"

let rec name = function
  | Integer i -> if i = { signed = true; width = 64 } then "Int" else integer_name i
  | Float F64 -> "Float"
  | Float k -> float_name k
  | Decimal -> "Decimal"
  | Rational -> "Rational"
  | Bool -> "Bool"
  | String -> "String"
  | List item -> "List<" ^ name item ^ ">"
  | Array (item, length) -> Printf.sprintf "Array<%s>[len: %d]" (name item) length
  | Map (kind, key, value) ->
      let head = match kind with Map_hash -> "Map.hash" | Map_sorted -> "Map.sorted" | Map_insertion -> "Map" in
      Printf.sprintf "%s<key: %s, val: %s>" head (name key) (name value)
  | Range -> "range"
  | Lines -> "lines"
  | Struct n | Union n -> n
  | Case (u, c) -> u ^ "." ^ c
  | Failure (f, _) -> f
  | New (n, _) -> n
  | Parameter p -> "?" ^ p
  | Bounded (t, b) ->
      let parts =
        List.filter_map (fun x -> x)
          [ Option.map (fun n -> "len.min: " ^ string_of_int n) b.len_min;
            Option.map (fun n -> "len.max: " ^ string_of_int n) b.len_max;
            Option.map (fun q -> "min: " ^ bound_text q) b.min;
            Option.map (fun q -> "max: " ^ bound_text q) b.max ]
      in
      name t ^ "[" ^ String.concat ", " parts ^ "]"
  | Unknown -> "?"
  | Nothing -> "nothing"

(* Whether a value of the type can change inside, so handing it off needs `give` or `copy` (D7). *)
let rec has_inside_that_changes = function
  | List _ | Map _ | Array _ | Struct _ | Union _ | Case _ -> true
  | New (_, t) | Bounded (t, _) -> has_inside_that_changes t
  | _ -> false

let integer_minimum { signed; width } =
  if signed then Z.neg (Z.shift_left Z.one (width - 1)) else Z.zero

let integer_maximum { signed; width } =
  if signed then Z.pred (Z.shift_left Z.one (width - 1)) else Z.pred (Z.shift_left Z.one width)

let integer_fits integer_type value =
  Z.geq value (integer_minimum integer_type) && Z.leq value (integer_maximum integer_type)

(* Integers whose whole range fits an Int64 are held as Int64 (D73, rule 19); wider ones as Z. *)
let held_as_int64 integer_type =
  Z.geq (integer_minimum integer_type) (Z.of_int64 Int64.min_int)
  && Z.leq (integer_maximum integer_type) (Z.of_int64 Int64.max_int)

let is_number = function Integer _ | Float _ | Decimal | Rational -> true | _ -> false

(* Unknown fits anywhere, so an error never causes another one (D13). *)
let rec same a b =
  match a, b with
  | Unknown, _ | _, Unknown -> true
  | Bounded (x, _), y | y, Bounded (x, _) -> same x y   (* bounds are checked where a value is stored (D135) *)
  | List x, List y -> same x y
  | Array (x, n), Array (y, m) -> n = m && same x y
  | Map (k1, a1, b1), Map (k2, a2, b2) -> k1 = k2 && same a1 a2 && same b1 b2
  | Case (u, _), Union v | Union u, Case (v, _) -> u = v
  | _ -> a = b
