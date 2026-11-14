(* Runs a checked program. It never optimizes and never drops a check (D69, standard 10.2). *)

module C = Checked

exception Runtime_stop of Diagnostic.t
exception Return_signal of Value.t
exception Break_signal of int
exception Instead_signal of Value.t

let runtime_error ?what ?when_ span why =
  raise (Runtime_stop (Diagnostic.make ~span ?what ?when_ Diagnostic.Runtime_error why))

let runtime_not_designed ~what span why =
  raise (Runtime_stop (Diagnostic.make ~span ~what Diagnostic.Not_designed_yet why))

type frame = (int, Value.t ref) Hashtbl.t

let source_text (span : Span.t) =
  match Diagnostic.source_line span.file span.line with
  | Some line when span.end_line = span.line && span.end_column <= String.length line + 1 ->
      String.sub line (span.column - 1) (span.end_column - span.column)
  | _ -> ""

(* ---------- Text of values ---------- *)

(* The decimal text of an exact fraction whose denominator is a power of two, every digit. *)
let exact_decimal_of_q (q : Q.t) : string =
  let negative = Q.sign q < 0 in
  let q = Q.abs q in
  let numerator = Q.num q and denominator = Q.den q in
  let k = Z.log2 denominator in
  let scaled = Z.mul numerator (Z.pow (Z.of_int 5) k) in
  let digits = Z.to_string scaled in
  let digits = if String.length digits <= k then String.make (k - String.length digits + 1) '0' ^ digits else digits in
  let whole = String.sub digits 0 (String.length digits - k) in
  let fraction = String.sub digits (String.length digits - k) k in
  let rec trim s = if s <> "" && s.[String.length s - 1] = '0' then trim (String.sub s 0 (String.length s - 1)) else s in
  let fraction = trim fraction in
  (if negative then "-" else "") ^ whole ^ (if fraction = "" then "" else "." ^ fraction)

(* "1.2345e+02"-style text to plain digits with no exponent (D120). *)
let plain_of_scientific (text : string) : string =
  let negative = text.[0] = '-' in
  let text = if negative then String.sub text 1 (String.length text - 1) else text in
  let mantissa, exponent =
    match String.index_opt text 'e' with
    | Some i -> (String.sub text 0 i, int_of_string (String.sub text (i + 1) (String.length text - i - 1)))
    | None -> (text, 0)
  in
  let digits, point =
    match String.index_opt mantissa '.' with
    | Some i -> (String.sub mantissa 0 i ^ String.sub mantissa (i + 1) (String.length mantissa - i - 1), i)
    | None -> (mantissa, String.length mantissa)
  in
  let point = point + exponent in
  let digits, point =
    if point <= 0 then (String.make (1 - point) '0' ^ digits, 1)
    else if point > String.length digits then (digits ^ String.make (point - String.length digits) '0', point)
    else (digits, point)
  in
  let whole = String.sub digits 0 point and fraction = String.sub digits point (String.length digits - point) in
  let rec trim s = if s <> "" && s.[String.length s - 1] = '0' then trim (String.sub s 0 (String.length s - 1)) else s in
  let rec trim_front s = if String.length s > 1 && s.[0] = '0' then trim_front (String.sub s 1 (String.length s - 1)) else s in
  let fraction = trim fraction in
  (if negative then "-" else "") ^ trim_front whole ^ (if fraction = "" then "" else "." ^ fraction)

(* The shortest digits that read back as exactly the same float, with `~` when the float isn't
   exactly that decimal (D119, D120). *)
let float_text span (f : float) : string =
  if Float.is_nan f || Float.is_integer f = false && not (Float.is_finite f) then
    runtime_not_designed ~what:"what NaN and infinity look like as text isn't decided yet" span
      "not decided yet (D119, standard 12.1)"
  else if not (Float.is_finite f) then
    runtime_not_designed ~what:"what NaN and infinity look like as text isn't decided yet" span
      "not decided yet (D119, standard 12.1)"
  else begin
    let rec shortest precision =
      let text = Printf.sprintf "%.*e" (precision - 1) f in
      if precision >= 17 || Float.equal (float_of_string text) f then text else shortest (precision + 1)
    in
    let plain = plain_of_scientific (shortest 1) in
    let plain = if Float.sign_bit f && plain.[0] <> '-' then "-" ^ plain else plain in
    let decimal_value =
      let negative = plain.[0] = '-' in
      let body = if negative then String.sub plain 1 (String.length plain - 1) else plain in
      let q =
        match String.index_opt body '.' with
        | None -> Q.of_bigint (Z.of_string body)
        | Some i ->
            let fraction = String.length body - i - 1 in
            Q.make (Z.of_string (String.sub body 0 i ^ String.sub body (i + 1) fraction)) (Z.pow (Z.of_int 10) fraction)
      in
      if negative then Q.neg q else q
    in
    if Q.equal decimal_value (Q.of_float f) then plain else "~" ^ plain
  end

let rec to_text span (narrowings : string list) (value : Value.t) : string =
  match value, narrowings with
  | (Value.Int64_integer _ | Value.Wide_integer _), _ -> Z.to_string (Value.integer_to_z value)
  | Value.Bool b, _ -> if b then "true" else "false"     (* trace: D120 *)
  | Value.String s, _ -> s
  | Value.Float (f, _), [ "stored" ] ->
      if not (Float.is_finite f) then to_text span [] value else exact_decimal_of_q (Q.of_float f)
  | Value.Float (f, _), _ -> float_text span f
  | _ ->
      runtime_not_designed ~what:"what this value looks like as text isn't decided yet" span
        "not decided yet (D120, standard 12.1)"

(* ---------- Integers ---------- *)

let integer_type_of = function
  | Value.Int64_integer (_, t) | Value.Wide_integer (_, t) -> t
  | _ -> { Types.signed = true; width = 64 }

let wrap (t : Types.integer_type) (n : Z.t) : Z.t =
  let modulus = Z.shift_left Z.one t.width in
  let low = Z.erem n modulus in
  if t.signed && Z.geq low (Z.shift_left Z.one (t.width - 1)) then Z.sub low modulus else low

let saturate (t : Types.integer_type) (n : Z.t) : Z.t =
  if Z.lt n (Types.integer_minimum t) then Types.integer_minimum t
  else if Z.gt n (Types.integer_maximum t) then Types.integer_maximum t
  else n

(* ---------- Expressions ---------- *)

type context = { program : C.program; frame : frame }

let read context (v : C.variable) = !(Hashtbl.find context.frame v.variable_id)

let define context (v : C.variable) value = Hashtbl.replace context.frame v.variable_id (ref value)

let rec evaluate context (e : C.expression) : Value.t =
  match e.kind with
  | C.Call_function _ | C.Call_builtin _ -> (
      try evaluate_call context e
      with C.Failure_raised (failure, _) ->
        (* trace: D48, D137 *)
        let name =
          match e.kind with
          | C.Call_builtin { builtin; _ } -> builtin.builtin_name
          | C.Call_function { function_id; _ } -> (Hashtbl.find context.program.functions function_id).function_name
          | _ -> ""
        in
        flush stdout;
        runtime_error
          ~what:(Printf.sprintf "`%s` failed with `%s`, and nothing handled it" name failure.failure_name)
          e.span "a failure nobody handles crashes (D48, standard 6.3)")
  | _ -> evaluate_plain context e

(* A call whose failure is left for the caller to handle. *)
and evaluate_call context (e : C.expression) : Value.t =
  match e.kind with
  | C.Call_builtin { builtin; arguments } ->
      let values = List.map (evaluate context) arguments in
      builtin.run e.span values
  | C.Call_function { function_id; arguments } ->
      let values = List.map (evaluate context) arguments in
      call_function context.program e.span function_id values
  | _ -> evaluate context e

and evaluate_plain context (e : C.expression) : Value.t =
  match e.kind with
  | C.Constant v -> v
  | C.Read v -> read context v
  | C.Call_function _ | C.Call_builtin _ -> evaluate context e
  | C.Join items -> Value.String (String.concat "" (List.map (fun i -> match evaluate context i with Value.String s -> s | _ -> "") items))
  | C.Convert { value; narrowings; target } -> (
      let v = evaluate context value in
      match target with
      | Types.String -> Value.String (to_text e.span narrowings v)
      | _ -> v)
  | C.Arithmetic { operator; narrowings; left; right } ->
      let l = evaluate context left in
      let r = evaluate context right in
      arithmetic e operator narrowings l r
  | C.Negate inner -> (
      match evaluate context inner with
      | (Value.Int64_integer _ | Value.Wide_integer _) as v ->
          let t = integer_type_of v in
          let result = Z.neg (Value.integer_to_z v) in
          if not (Types.integer_fits t result) then
            runtime_error ~what:(Printf.sprintf "`%s` doesn't fit in `%s`" (source_text e.span) (Types.name (Types.Integer t)))
              ~when_:(Printf.sprintf "it would be %s" (Z.to_string result)) e.span
              "a number too big for its type is a check (D54, standard 7.2)";
          Value.integer_of_z t result
      | Value.Float (f, k) -> Value.Float (Float.neg f, k)
      | Value.Rational q -> Value.Rational (Q.neg q)
      | v -> v)
  | C.Compare { operator; left; right } ->
      let l = evaluate context left and r = evaluate context right in
      Value.Bool (compare_values operator l r)
  | C.Logic { operator; both; left; right } -> (
      let l = evaluate context left in
      (* trace: D28 *)
      match operator, l, both with
      | "and", Value.Bool false, false -> Value.Bool false
      | "or", Value.Bool true, false -> Value.Bool true
      | _ -> (
          let r = evaluate context right in
          match operator, l, r with
          | "and", Value.Bool a, Value.Bool b -> Value.Bool (a && b)
          | _, Value.Bool a, Value.Bool b -> Value.Bool (a || b)
          | _ -> Value.Bool false))
  | C.Not inner -> (match evaluate context inner with Value.Bool b -> Value.Bool (not b) | v -> v)
  | C.List_literal items -> Value.List { items = Dynarray.of_list (List.map (evaluate context) items) }
  | C.Map_literal (map_kind, entries) ->
      let m = { Value.map_kind; entries = Dynarray.create () } in
      List.iter (fun (k, v) -> map_set m (evaluate context k) (evaluate context v)) entries;
      Value.Map m
  | C.Build_struct { struct_name; fields } ->
      let defaults = Option.value (Hashtbl.find_opt context.program.struct_defaults struct_name) ~default:[] in
      let given = List.map (fun (n, x) -> (n, evaluate context x)) fields in
      let all =
        List.map
          (fun (n, default) ->
            match List.assoc_opt n given with
            | Some v -> (n, ref v)
            | None -> (n, ref (match default with Some d -> evaluate context d | None -> Value.Nothing)))
          defaults
      in
      Value.Struct { struct_name; fields = all }
  | C.Build_union { union_name; case_name; fields } ->
      Value.Union { union_name; case_name; case_fields = List.map (fun (n, x) -> (n, ref (evaluate context x))) fields }
  | C.Field (target, name) -> (
      match evaluate context target with
      | Value.Struct s -> !(List.assoc name s.fields)
      | Value.Union u -> !(List.assoc name u.case_fields)
      | v -> v)
  | C.Index { target; counting; position } -> (
      let list = evaluate context target in
      let p = evaluate context position in
      match list with
      | Value.List l -> Dynarray.get l.items (list_offset e.span counting l p)
      | v -> v)
  | C.Range { from; ending; inclusive; step_by } ->
      let from = Value.integer_to_z (evaluate context from) in
      let ending = Value.integer_to_z (evaluate context ending) in
      let step =
        match step_by with
        | None -> Z.one
        | Some s ->
            let step = Value.integer_to_z (evaluate context s) in
            (* trace: D37 *)
            if Z.equal step Z.zero then
              runtime_error ~what:"`step_by:` is 0, so the range never ends" s.span
                "a `step_by:` of 0 is a check (D37, standard 4.7)";
            step
      in
      let last = if inclusive then ending else if Z.gt step Z.zero then Z.pred ending else Z.succ ending in
      let reaches = if Z.gt step Z.zero then Z.leq from last else Z.geq from last in
      Value.Range { from; last = (if reaches then Some last else None); step }
  | C.Copy inner -> Value.deep_copy (evaluate context inner)
  | C.Fallback { value; instead } -> (
      try evaluate_call context value with C.Failure_raised _ -> evaluate context instead)
  | C.Ignore value -> (try ignore (evaluate_call context value); Value.Nothing with C.Failure_raised _ -> Value.Nothing)
  | C.Pass_up value -> evaluate_call context value
  | C.Otherwise { value; arms } -> (
      try evaluate_call context value
      with C.Failure_raised (failure, _) -> (
        match List.find_opt (fun (a : C.arm) -> a.arm_failure = failure.failure_name) arms with
        | Some arm -> (
            try
              execute_block context arm.arm_body;
              Value.Nothing
            with Instead_signal v -> v)
        | None -> raise (C.Failure_raised (failure, e.span))))

and list_offset span counting (l : Value.list_value) (p : Value.t) : int =
  let n = Value.integer_to_z p in
  let length = Dynarray.length l.items in
  let offset = match counting with Syntax.Pos -> Z.pred n | Syntax.Offset -> n in
  (* trace: D17, D53 *)
  if Z.lt offset Z.zero || Z.geq offset (Z.of_int length) then
    runtime_error
      ~what:(Printf.sprintf "%s %s is outside the list" (match counting with Syntax.Pos -> "position" | Syntax.Offset -> "offset") (Z.to_string n))
      ~when_:(Printf.sprintf "the list has %d item%s" length (if length = 1 then "" else "s"))
      span "a position outside the list is a check (D53, standard 7.2)";
  Z.to_int offset

and map_set (m : Value.map_value) key value =
  let rec find i = if i >= Dynarray.length m.entries then None else if Value.equal (fst (Dynarray.get m.entries i)) key then Some i else find (i + 1) in
  match find 0 with
  | Some i -> Dynarray.set m.entries i (key, value)
  | None -> Dynarray.add_last m.entries (key, value)

and compare_values operator l r =
  let order () =
    match l, r with
    | (Value.Int64_integer _ | Value.Wide_integer _), _ -> Some (Z.compare (Value.integer_to_z l) (Value.integer_to_z r))
    | Value.Float (a, _), Value.Float (b, _) -> if Float.is_nan a || Float.is_nan b then None else Some (Float.compare a b)
    | Value.Rational a, Value.Rational b -> Some (Q.compare a b)
    | _ -> None
  in
  match operator with
  | "==" -> Value.equal l r
  | "!=" -> not (Value.equal l r)
  | _ -> (
      match order () with
      | None -> false
      | Some c -> (
          match operator with
          | "<" -> c < 0
          | ">" -> c > 0
          | "at_least" -> c >= 0
          | "at_most" -> c <= 0
          | _ -> false))

and arithmetic (e : C.expression) operator narrowings l r : Value.t =
  let span = e.span in
  match l, r with
  | (Value.Int64_integer _ | Value.Wide_integer _), _ -> (
      let t = integer_type_of l in
      let a = Value.integer_to_z l and b = Value.integer_to_z r in
      let check_zero () =
        if Z.equal b Z.zero then
          runtime_error ~what:(Printf.sprintf "`%s` divides by zero" (source_text span)) span
            "dividing by zero is a check (D53, standard 7.2)"
      in
      let fits result =
        (* trace: D54 *)
        if not (Types.integer_fits t result) then
          runtime_error
            ~what:(Printf.sprintf "`%s` doesn't fit in `%s`" (source_text span) (Types.name (Types.Integer t)))
            ~when_:(Printf.sprintf "it would be %s" (Z.to_string result))
            span "a number too big for its type is a check (D54, standard 7.2)";
        Value.integer_of_z t result
      in
      match operator, narrowings with
      | "+", _ -> fits (Z.add a b)
      | "-", _ -> fits (Z.sub a b)
      | "x", _ -> fits (Z.mul a b)
      (* trace: D92 *)
      | "plus", [ "wrap" ] -> Value.integer_of_z t (wrap t (Z.add a b))
      | "minus", [ "wrap" ] -> Value.integer_of_z t (wrap t (Z.sub a b))
      | "times", [ "wrap" ] -> Value.integer_of_z t (wrap t (Z.mul a b))
      | "plus", [ "saturate" ] -> Value.integer_of_z t (saturate t (Z.add a b))
      | "minus", [ "saturate" ] -> Value.integer_of_z t (saturate t (Z.sub a b))
      | "times", [ "saturate" ] -> Value.integer_of_z t (saturate t (Z.mul a b))
      (* trace: D88 *)
      | "div", [ "trunc" ] -> check_zero (); fits (Z.div a b)
      | "div", [ "floor" ] -> check_zero (); fits (Z.fdiv a b)
      | "div", [ "rational" ] -> check_zero (); Value.Rational (Q.make a b)
      | "div", [ "exact" ] ->
          check_zero ();
          if not (Z.equal (Z.rem a b) Z.zero) then
            runtime_not_designed ~what:"which failure `div.exact` raises isn't decided yet" span
              "not decided yet (D94, standard 12.1)";
          fits (Z.div a b)
      (* trace: D85 *)
      | "mod", [ "trunc" ] -> check_zero (); fits (Z.rem a b)
      | "mod", [ "floor" ] -> check_zero (); fits (Z.sub a (Z.mul (Z.fdiv a b) b))
      | _ -> l)
  | Value.Float (a, k), Value.Float (b, _) -> (
      match operator with
      | "+" -> Value.Float (a +. b, k)
      | "-" -> Value.Float (a -. b, k)
      | "x" -> Value.Float (a *. b, k)
      | "div" -> Value.Float (a /. b, k)
      | _ -> l)
  | Value.Rational a, Value.Rational b -> (
      match operator with
      | "+" -> Value.Rational (Q.add a b)
      | "-" -> Value.Rational (Q.sub a b)
      | "x" -> Value.Rational (Q.mul a b)
      | "div" ->
          if Q.equal b Q.zero then
            runtime_error ~what:(Printf.sprintf "`%s` divides by zero" (source_text span)) span
              "dividing by zero is a check (D53, standard 7.2)";
          Value.Rational (Q.div a b)
      | _ -> l)
  | _ -> l

(* ---------- Statements ---------- *)

and execute_block context (statements : C.statement list) = List.iter (execute context) statements

and execute context (s : C.statement) =
  match s.statement_kind with
  | C.Define (v, value) -> define context v (evaluate context value)
  | C.Set (v, value) -> (
      let x = evaluate context value in
      match Hashtbl.find_opt context.frame v.variable_id with
      | Some cell -> cell := x
      | None -> define context v x)
  | C.Set_field { target; field; value } -> (
      let x = evaluate context value in
      match evaluate context target with
      | Value.Struct st -> (List.assoc field st.fields) := x
      | _ -> ())
  | C.Set_index { target; counting; position; value } -> (
      let list = evaluate context target in
      let p = evaluate context position in
      let x = evaluate context value in
      match list with
      | Value.List l -> Dynarray.set l.items (list_offset s.statement_span counting l p) x
      | _ -> ())
  | C.Evaluate e -> ignore (evaluate context e)
  | C.Return None -> raise (Return_signal Value.Nothing)
  | C.Return (Some e) -> raise (Return_signal (evaluate context e))
  | C.If (branches, else_body) -> (
      let rec go = function
        | [] -> Option.iter (execute_block context) else_body
        | (condition, body) :: rest -> (
            match evaluate context condition with Value.Bool true -> execute_block context body | _ -> go rest)
      in
      go branches)
  | C.While { loop_id; condition; body } -> (
      try
        while (match evaluate context condition with Value.Bool b -> b | _ -> false) do
          execute_block context body
        done
      with Break_signal id when id = loop_id -> ())
  | C.For { loop_id; variable; position; iterable; handling; body } -> (
      let count = ref 0 in
      let run_item item =
        define context variable item;
        (match position with
         | Some (Syntax.Pos, p) -> define context p (Value.int_of_int64 (Int64.of_int (!count + 1)))
         | Some (Syntax.Offset, p) -> define context p (Value.int_of_int64 (Int64.of_int !count))
         | None -> ());
        incr count;
        execute_block context body
      in
      try
        match evaluate context iterable with
        | Value.Range { from; last = Some last; step } ->
            let i = ref from in
            let continues () = if Z.gt step Z.zero then Z.leq !i last else Z.geq !i last in
            while continues () do
              run_item (Value.int_of_int64 (Z.to_int64 !i));
              i := Z.add !i step
            done
        | Value.Range { last = None; _ } -> ()
        | Value.List l ->
            (* the loop goes through the items the list had when it started *)
            let items = Dynarray.to_list l.items in
            List.iter run_item items
        | Value.Lines ->
            let finished = ref false in
            while not !finished do
              (* trace: D134 *)
              match Std_library.next_line iterable.span with
              | Some line -> run_item line
              | None -> finished := true
              | exception C.Failure_raised (failure, _) -> (
                  match handling with
                  | C.Loop_fallback stand_in -> run_item (evaluate context stand_in)
                  | _ ->
                      flush stdout;
                      runtime_error
                        ~what:(Printf.sprintf "`lines` failed with `%s`, and nothing handled it" failure.failure_name)
                        iterable.span "a failure nobody handles crashes (D48, D134, standard 6.3)")
            done
        | _ -> ()
      with Break_signal id when id = loop_id -> ())
  | C.Break id -> raise (Break_signal id)
  | C.Instead e -> raise (Instead_signal (evaluate context e))
  | C.Fail { failure; fields } ->
      raise (C.Failure_raised ({ failure_name = failure; failure_fields = List.map (fun (n, x) -> (n, evaluate context x)) fields }, s.statement_span))
  | C.Check_contract { condition; text; why } -> (
      match evaluate context condition with
      | Value.Bool true -> ()
      | _ -> runtime_error ~what:(Printf.sprintf "`%s` is false" text) condition.span why)
  | C.Case_test _ | C.Match _ -> ()

and call_function (program : C.program) span function_id (arguments : Value.t list) : Value.t =
  let f = Hashtbl.find program.functions function_id in
  let context = { program; frame = Hashtbl.create 16 } in
  List.iter2 (fun v a -> define context v a) f.parameters arguments;
  (* trace: D42 *)
  List.iter
    (fun ((condition : C.expression), text) ->
      match evaluate context condition with
      | Value.Bool true -> ()
      | _ ->
          flush stdout;
          runtime_error ~what:(Printf.sprintf "`requires %s` is false" text) span
            ~when_:(Printf.sprintf "calling `%s`" f.function_name)
            "contracts are checked at runtime (D42, D8, standard 7.1)")
    f.requires;
  try
    execute_block context f.body;
    Value.Nothing
  with Return_signal v -> v

let run (program : C.program) : unit = ignore (call_function program Span.none program.main [])
