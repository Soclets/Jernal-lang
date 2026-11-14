(* Decimal: IEEE 754 decimal128 (D82, D83). Each result is worked out exactly, then rounded once to
   34 significant digits, ties to even, within decimal128's exponents, as IEEE says. *)

type t =
  | Finite of Q.t            (* always a value decimal128 holds *)
  | Infinity of bool         (* true: negative *)
  | Not_a_number

let digits = 34
let max_exponent = 6144       (* of the leading digit *)
let min_quantum = -6176       (* of the last digit, the smallest subnormal's *)

let ten = Z.of_int 10
let power_of_ten n = Z.pow ten n

(* 10^n as a fraction, for any n. *)
let q_power_of_ten n = if n >= 0 then Q.of_bigint (power_of_ten n) else Q.make Z.one (power_of_ten (-n))

(* floor(log10 q) for q > 0 *)
let leading_exponent (q : Q.t) : int =
  let a = Q.num q and b = Q.den q in
  let estimate = String.length (Z.to_string a) - String.length (Z.to_string b) in
  let e = ref estimate in
  while Q.lt q (q_power_of_ten !e) do decr e done;
  while Q.geq q (q_power_of_ten (!e + 1)) do incr e done;
  !e

(* The decimal128 value nearest [q], ties to even. *)
let round (q : Q.t) : t =
  if Q.sign q = 0 then Finite Q.zero
  else begin
    let negative = Q.sign q < 0 in
    let a = Q.abs q in
    let e = leading_exponent a in
    if e > max_exponent then Infinity negative
    else begin
      let quantum = max (e - (digits - 1)) min_quantum in
      let scaled = Q.div a (q_power_of_ten quantum) in
      let m, r = Z.div_rem (Q.num scaled) (Q.den scaled) in
      let c = Z.compare (Z.shift_left r 1) (Q.den scaled) in
      let m = if c > 0 || (c = 0 && Z.is_odd m) then Z.succ m else m in
      let m, quantum = if Z.equal m (power_of_ten digits) then (Z.div m ten, quantum + 1) else (m, quantum) in
      let leading = quantum + String.length (Z.to_string m) - 1 in
      if leading > max_exponent then Infinity negative
      else
        let magnitude = Q.mul (Q.of_bigint m) (q_power_of_ten quantum) in
        Finite (if negative then Q.neg magnitude else magnitude)
    end
  end

let of_rational = round

let holds_exactly (q : Q.t) = match round q with Finite r -> Q.equal r q | _ -> false

let add a b =
  match a, b with
  | Not_a_number, _ | _, Not_a_number -> Not_a_number
  | Infinity x, Infinity y -> if x = y then Infinity x else Not_a_number
  | Infinity x, _ | _, Infinity x -> Infinity x
  | Finite x, Finite y -> round (Q.add x y)

let negate = function Finite x -> Finite (Q.neg x) | Infinity x -> Infinity (not x) | Not_a_number -> Not_a_number

let subtract a b = add a (negate b)

let sign_of = function Finite x -> Q.sign x | Infinity n -> if n then -1 else 1 | Not_a_number -> 0

let multiply a b =
  match a, b with
  | Not_a_number, _ | _, Not_a_number -> Not_a_number
  | Infinity _, _ | _, Infinity _ ->
      let s = sign_of a * sign_of b in
      if s = 0 then Not_a_number else Infinity (s < 0)
  | Finite x, Finite y -> round (Q.mul x y)

let divide a b =
  match a, b with
  | Not_a_number, _ | _, Not_a_number -> Not_a_number
  | Infinity _, Infinity _ -> Not_a_number
  | Infinity _, Finite y -> Infinity (sign_of a * (if Q.sign y < 0 then -1 else 1) < 0)
  | Finite _, Infinity _ -> Finite Q.zero
  | Finite x, Finite y ->
      if Q.sign y = 0 then (if Q.sign x = 0 then Not_a_number else Infinity (Q.sign x < 0))
      else round (Q.div x y)

let compare_values a b = match a, b with Finite x, Finite y -> Some (Q.compare x y) | _ -> None

let equal a b =
  match a, b with
  | Finite x, Finite y -> Q.equal x y
  | Infinity x, Infinity y -> x = y
  | _ -> false

(* Its exact digits, with no exponent: 0.1, -2.5, 100 (D139, D120). *)
let to_text = function
  | Not_a_number -> "NaN"
  | Infinity negative -> if negative then "-inf" else "inf"
  | Finite q ->
      let negative = Q.sign q < 0 in
      let q = Q.abs q in
      let numerator = Q.num q and denominator = Q.den q in
      let rec places k = if Z.equal (Z.rem (power_of_ten k) denominator) Z.zero then k else places (k + 1) in
      let k = places 0 in
      let scaled = Z.to_string (Z.div (Z.mul numerator (power_of_ten k)) denominator) in
      let scaled = if String.length scaled <= k then String.make (k - String.length scaled + 1) '0' ^ scaled else scaled in
      let whole = String.sub scaled 0 (String.length scaled - k) and fraction = String.sub scaled (String.length scaled - k) k in
      (if negative then "-" else "") ^ whole ^ (if fraction = "" then "" else "." ^ fraction)
