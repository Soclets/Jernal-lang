(* Exact number helpers, written out so their rounding is obviously right. *)

(* An IEEE 754 binary format: [precision] significand bits, counting the hidden one, and the
   exponent range of normal numbers (D82, D93). *)
type format = { precision : int; min_exponent : int; max_exponent : int }

let format_of (kind : Types.float_kind) =
  match kind with
  | Types.F64 -> { precision = 53; min_exponent = -1022; max_exponent = 1023 }
  | Types.F32 -> { precision = 24; min_exponent = -126; max_exponent = 127 }
  | Types.F16 -> { precision = 11; min_exponent = -14; max_exponent = 15 }
  | Types.Bf16 -> { precision = 8; min_exponent = -126; max_exponent = 127 }

(* The value of [format] nearest the exact fraction [q], ties to even (IEEE round to nearest),
   held in an OCaml float, which holds every value of these formats exactly. *)
let round_rational (format : format) (q : Q.t) : float =
  if Q.sign q = 0 then 0.0
  else begin
    let negative = Q.sign q < 0 in
    let a = Z.abs (Q.num q) and b = Q.den q in
    (* e = floor(log2(a / b)) *)
    let e = ref (Z.numbits a - Z.numbits b) in
    let at_least_power p = if p >= 0 then Z.geq a (Z.shift_left b p) else Z.geq (Z.shift_left a (-p)) b in
    if not (at_least_power !e) then decr e;
    if at_least_power (!e + 1) then incr e;
    let infinity = if negative then Float.neg_infinity else Float.infinity in
    if !e > format.max_exponent then infinity
    else begin
      (* the scale k makes the significand a [precision]-bit integer, or fewer bits when subnormal *)
      let k = if !e < format.min_exponent then format.precision - 1 - format.min_exponent else format.precision - 1 - !e in
      let scaled_a, scaled_b = if k >= 0 then (Z.shift_left a k, b) else (a, Z.shift_left b (-k)) in
      let m, r = Z.div_rem scaled_a scaled_b in
      let c = Z.compare (Z.shift_left r 1) scaled_b in
      let m = if c > 0 || (c = 0 && Z.is_odd m) then Z.succ m else m in
      let magnitude = Float.ldexp (Z.to_float m) (-k) in
      let largest =
        Float.ldexp (Float.of_int ((1 lsl format.precision) - 1)) (format.max_exponent - format.precision + 1)
      in
      if magnitude > largest then infinity else if negative then Float.neg magnitude else magnitude
    end
  end

let float_of_rational (q : Q.t) : float = round_rational (format_of Types.F64) q

(* An f64 result rounded to a smaller format. Rounding twice is exact here, since binary64 has
   more than twice the bits of the others, plus two. *)
let round_float (kind : Types.float_kind) (f : float) : float =
  if kind = Types.F64 || not (Float.is_finite f) then f else round_rational (format_of kind) (Q.of_float f)

(* The exact sum of floats, rounded once (D38): like Python's math.fsum. *)
let float_sum ?(kind = Types.F64) (xs : float list) : float =
  if List.exists Float.is_nan xs then Float.nan
  else
    let positive_infinity = List.exists (fun x -> x = Float.infinity) xs in
    let negative_infinity = List.exists (fun x -> x = Float.neg_infinity) xs in
    if positive_infinity && negative_infinity then Float.nan
    else if positive_infinity then Float.infinity
    else if negative_infinity then Float.neg_infinity
    else round_rational (format_of kind) (List.fold_left (fun total x -> Q.add total (Q.of_float x)) Q.zero xs)
