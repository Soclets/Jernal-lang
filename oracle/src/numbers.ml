(* Exact number helpers, written out so their rounding is obviously right. *)

(* The binary64 float nearest the exact fraction [q], ties to even (IEEE 754 round to nearest). *)
let float_of_rational (q : Q.t) : float =
  if Q.sign q = 0 then 0.0
  else begin
    let negative = Q.sign q < 0 in
    let a = Z.abs (Q.num q) and b = Q.den q in
    (* e = floor(log2(a / b)) *)
    let e = ref (Z.numbits a - Z.numbits b) in
    let at_least_power p =
      (* a / b >= 2^p *)
      if p >= 0 then Z.geq a (Z.shift_left b p) else Z.geq (Z.shift_left a (-p)) b
    in
    if not (at_least_power !e) then decr e;
    if at_least_power (!e + 1) then incr e;
    if !e > 1023 then (if negative then Float.neg_infinity else Float.infinity)
    else begin
      (* the scale k makes the significand a 53-bit integer, or fewer bits for subnormals *)
      let k = if !e < -1022 then 1074 else 52 - !e in
      let scaled_a, scaled_b = if k >= 0 then (Z.shift_left a k, b) else (a, Z.shift_left b (-k)) in
      let m, r = Z.div_rem scaled_a scaled_b in
      let twice_r = Z.shift_left r 1 in
      let m =
        let c = Z.compare twice_r scaled_b in
        if c > 0 || (c = 0 && Z.is_odd m) then Z.succ m else m
      in
      (* m < 2^54 here, so it converts to a float exactly *)
      let magnitude = Float.ldexp (Z.to_float m) (-k) in
      if negative then Float.neg magnitude else magnitude
    end
  end

(* The exact sum of floats, rounded once (D38): like Python's math.fsum. *)
let float_sum (xs : float list) : float =
  if List.exists Float.is_nan xs then Float.nan
  else
    let positive_infinity = List.exists (fun x -> x = Float.infinity) xs in
    let negative_infinity = List.exists (fun x -> x = Float.neg_infinity) xs in
    if positive_infinity && negative_infinity then Float.nan
    else if positive_infinity then Float.infinity
    else if negative_infinity then Float.neg_infinity
    else float_of_rational (List.fold_left (fun total x -> Q.add total (Q.of_float x)) Q.zero xs)
