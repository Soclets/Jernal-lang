(* Checks a package and turns it into a checked program (standard chapters 2 to 7).

   Every error is collected, not just the first (D10, D13). A statement with an error is skipped
   and checking carries on; a skipped `let` or `decl` still creates its variable, with the type
   it wrote. Whatever is broken counts as unknown, and an error that only happens because
   something is unknown isn't shown. *)

open Syntax
module C = Checked

(* ---------- What the checker knows ---------- *)

type variable_info = {
  variable : C.variable;
  mutable variable_type : Types.t;
  mutable case_known_until : Span.t option;   (* the `change` that ended a case test's knowledge (D97) *)
  is_mutable : bool;
  mutable assigned : bool;          (* a `decl` gets its value later (D34) *)
  mutable given : bool;             (* retired by `give` (D7) *)
  mutable is_parameter : bool;      (* a parameter, or a frozen name for one: keeping it needs `copy` (D139) *)
  is_loop_variable : bool;
  declared_at : Span.t;
}

type function_info = {
  function_id : int;
  declaration : function_declaration;
  full_name : string;
  file : string;
  mutable parameter_types : Types.t list;
  mutable result_type : Types.t;
  pure : bool;                      (* fn.pure, or a member of fam.fn.pure (D41, D45) *)
  mutable failures : (string * (string * Types.t) list) list;   (* what it lists after `fails` (D48) *)
  baked : bool;                     (* fn.pure.baked: can run while compiling (D41) *)
}

type struct_info = {
  struct_declaration : struct_declaration;
  mutable resolved_fields : (string * Types.t * expression option) list;
  struct_file : string;
  struct_visibility : visibility;
}

type union_info = {
  union_declaration : union_declaration;
  mutable resolved_cases : (string * (string * Types.t) list) list;
  union_file : string;
  union_visibility : visibility;
}

type context = {
  mutable diagnostics : Diagnostic.t list;
  functions : (string, function_info) Hashtbl.t;     (* by full name *)
  structs : (string, struct_info) Hashtbl.t;
  unions : (string, union_info) Hashtbl.t;
  aliases : (string, type_expression) Hashtbl.t;     (* type.alias, resolved where it's used (D61) *)
  new_types : (string, type_expression) Hashtbl.t;   (* type.new *)
  mutable resolving : string list;                   (* aliases being resolved, to refuse a cycle *)
  std_visible : bool;
  mutable next_id : int;
  checked : (int, C.function_) Hashtbl.t;
  presets : (string, (name * expression) list) Hashtbl.t;   (* greet.loud -> its settings (D45) *)
  families : (string, Span.t) Hashtbl.t;
  file_scopes : (string, (string, variable_info) Hashtbl.t) Hashtbl.t;   (* each file's top-level `let`s (D139) *)
  function_by_id : (int, function_info) Hashtbl.t;
  failure_families : (string, failure_shape list) Hashtbl.t;
  handler_families : (string, handler_set list) Hashtbl.t;
  mutable globals : C.statement list;
  baked_variables : (int, unit) Hashtbl.t;                       (* the ids of `let baked` variables *)
  versions : (string, function_info list) Hashtbl.t;             (* a name with several parameter lists (D46) *)
  overlapping_versions : (string, unit) Hashtbl.t;               (* already refused where they're written *)
  interfaces : (string, name list * name list) Hashtbl.t;        (* includes, operations (D105) *)
  type_sets : (string, type_expression list) Hashtbl.t;
  mutable satisfied : (string * string) list;                    (* (type, interface) from `satisfies` lines *)
  mutable type_parameters : (string * name list) list;           (* the generic function being checked (D103) *)
  short_names : Manifest.short_name list;                        (* `use` lines from the manifest (D60, D114) *)
  mutable current_file : string;                                 (* the file being checked, for `pub` (D106) *)
  mutable baked_values : (C.variable * C.expression) list;       (* worked out when compiling, in order (D5) *)
}

type function_context = {
  context : context;
  info : function_info;
  mutable scopes : (string, variable_info) Hashtbl.t list;
  mutable loops : (string option * int) list;
  mutable arm_values : Types.t option list;   (* inside `otherwise` arms: the type `instead` gives, if any (D48) *)
}

(* Statements are checked after expressions are defined; an `otherwise` arm holds statements. *)
let check_statements_ref : (function_context -> statement list -> C.statement list) ref = ref (fun _ _ -> [])

exception Skip   (* the statement has an error that was already reported *)

let fresh_id context =
  context.next_id <- context.next_id + 1;
  context.next_id

let report context d = context.diagnostics <- d :: context.diagnostics

let error context ?what ?fix ?when_ span why =
  report context (Diagnostic.make ~span ?what ?fix ?when_ Diagnostic.Compile_time_error why)

let refuse context ?what ?fix ?when_ span why =
  error context ?what ?fix ?when_ span why;
  raise Skip

let not_built context ~what span why =
  report context (Diagnostic.make ~span ~what Diagnostic.Not_built_yet why);
  raise Skip

let not_designed context ~what span why =
  report context (Diagnostic.make ~span ~what Diagnostic.Not_designed_yet why);
  raise Skip

let quote text = "`" ^ text ^ "`"

(* The span of the keyword a statement starts with. *)
let keyword_span (s : Span.t) (word : string) : Span.t =
  { s with end_line = s.line; end_column = s.column + String.length word }
let type_text t = quote (Types.name t)

let integer_literal_value ~negative digits = let z = Z.of_string digits in if negative then Z.neg z else z

let decimal_literal_value ~negative digits =
  (* digits.digits as an exact fraction *)
  let dot = String.index digits '.' in
  let whole = String.sub digits 0 dot and fraction = String.sub digits (dot + 1) (String.length digits - dot - 1) in
  let numerator = Z.of_string (whole ^ fraction) in
  let denominator = Z.pow (Z.of_int 10) (String.length fraction) in
  let q = Q.make numerator denominator in
  if negative then Q.neg q else q


(* What a type.new is made of (D61). *)
let rec underlying = function Types.New (_, t) | Types.Bounded (t, _) -> underlying t | t -> t

(* ---------- Types ---------- *)

(* A type parameter's label: ?Left is `left:`, ?KeyType is `key_type:` (D103, D132). *)
let parameter_label (p : string) =
  let buffer = Buffer.create 16 in
  String.iteri
    (fun i c ->
      if c >= 'A' && c <= 'Z' then begin
        if i > 0 then Buffer.add_char buffer '_';
        Buffer.add_char buffer (Char.lowercase_ascii c)
      end
      else Buffer.add_char buffer c)
    p;
  Buffer.contents buffer

(* A type with its type parameters filled in. *)
let rec substitute_parameters (bindings : (string * Types.t) list) (t : Types.t) : Types.t =
  match t with
  | Types.Parameter p -> Option.value (List.assoc_opt p bindings) ~default:t
  | Types.List item -> Types.List (substitute_parameters bindings item)
  | Types.Map (k, a, b) -> Types.Map (k, substitute_parameters bindings a, substitute_parameters bindings b)
  | Types.Bounded (t, b) -> Types.Bounded (substitute_parameters bindings t, b)
  | Types.Array (t, n) -> Types.Array (substitute_parameters bindings t, n)
  | Types.Instance (n, xs) -> Types.Instance (n, List.map (fun (l, t) -> (l, substitute_parameters bindings t)) xs)
  | t -> t

let sized_integer word =
  let n = String.length word in
  if n >= 2 && (word.[0] = 'i' || word.[0] = 'u')
     && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub word 1 (n - 1))
     && word.[1] <> '0'
  then Some { Types.signed = word.[0] = 'i'; width = int_of_string (String.sub word 1 (n - 1)) }
  else None

let is_power_of_two n = n > 0 && n land (n - 1) = 0

(* Something without `pub` is seen only in its own file (D106); using it elsewhere is refused with no fix. *)
let seen_from context ~name ~file ~(visibility : visibility) (span : Span.t) =
  (* trace: D106 *)
  if visibility = File_only && context.current_file <> "" && context.current_file <> file then
    refuse context ~what:(Printf.sprintf "%s is seen only in %s, since it has no `pub`" (quote name) (quote file)) span
      "a declaration without `pub` is seen only in its own file (D106, standard 9.2a)"

let rec resolve_type context (t : type_expression) : Types.t =
  match t.type_kind with
  | Parameter_type p ->
      (* trace: D103 *)
      if List.mem_assoc p context.type_parameters then Types.Parameter p
      else
        refuse context ~what:(Printf.sprintf "`?%s` isn't a type parameter here" p) t.type_span
          "a type parameter is declared in `< >` after a function's name (D103, standard 5.8)"
  | Named_type { details = _ :: _; _ } -> resolve_details context t t.type_kind
  | Named_type { words = [ "Array" ]; my = false; _ } ->
      refuse context ~what:"an `Array` always says its length, as `Array<u8>[len: 4]`" t.type_span
        "an `Array` is a fixed-size array that always says `[len: N]` (D135, standard 2.3a)"
  | Named_type { words; arguments; my; _ } -> (
      let no_arguments result =
        if arguments <> [] then
          refuse context ~what:(Printf.sprintf "%s takes no types in `< >`" (quote (String.concat "." words))) t.type_span
            "`< >` fills in a type's type parameters (D18, standard 1.4)"
        else result
      in
      let one_argument make =
        match arguments with
        | [ { argument_label = None; argument_type } ] -> make (resolve_type context argument_type)
        | _ ->
            refuse context ~what:(Printf.sprintf "%s takes one type in `< >`, written bare" (quote (String.concat "." words)))
              t.type_span "a type with one type parameter writes it bare (D102, D132, standard 2.3)"
      in
      match my, words with
      | false, [ ("Int" | "i64") ] -> no_arguments Types.int
      | false, [ "Float" ] | false, [ "f64" ] -> no_arguments (Types.Float Types.F64)
      | false, [ "f32" ] -> no_arguments (Types.Float Types.F32)
      | false, [ "f16" ] -> no_arguments (Types.Float Types.F16)
      | false, [ "bf16" ] -> no_arguments (Types.Float Types.Bf16)
      | false, [ "Decimal" ] -> no_arguments Types.Decimal
      | false, [ "Rational" ] -> no_arguments Types.Rational
      | false, [ "Bool" ] -> no_arguments Types.Bool
      | false, ([ "String" ] | [ "String"; "utf8" ]) -> no_arguments Types.String
      | false, [ "List" ] -> one_argument (fun item -> Types.List item)
      | false, [ "Array" ] ->
          not_built context ~what:"`Array` isn't built in the oracle yet" t.type_span
            "an `Array` is a fixed-size list that lives inline (D135, standard 2.3a)"
      | false, ("Map" :: rest) -> (
          let kind =
            match rest with
            | [] | [ "insertion" ] -> Types.Map_insertion
            | [ "sorted" ] -> Types.Map_sorted
            | [ "hash" ] -> Types.Map_hash
            | _ ->
                refuse context ~what:(Printf.sprintf "%s isn't a kind of map" (quote (String.concat "." words)))
                  t.type_span "maps come in kinds: `Map.hash`, `Map.sorted` and `Map.insertion` (D64, standard 2.3)"
          in
          match arguments with
          | [ { argument_label = Some { text = "key"; _ }; argument_type = key };
              { argument_label = Some { text = "val"; _ }; argument_type = value } ] ->
              Types.Map (kind, resolve_type context key, resolve_type context value)
          | _ ->
              refuse context ~what:"a map's types are written `<key: ..., val: ...>`" t.type_span
                "two or more type parameters are each labelled with their name (D102, D132, standard 2.3)")
      | false, [ word ] when sized_integer word <> None ->
          let integer = Option.get (sized_integer word) in
          (* trace: D93 *)
          if not (is_power_of_two integer.width) then
            refuse context ~fix:(quote ("not_two_pow." ^ word)) t.type_span
              "an integer width that isn't a power of two needs the `not_two_pow.` gate (D93, standard 2.1)"
          else if integer.width > 8_388_607 then
            refuse context ~what:(Printf.sprintf "%s is wider than 8,388,607 bits" (quote word)) t.type_span
              "integers come in any width from 1 to 8,388,607 bits (D93, standard 2.1)"
          else no_arguments (Types.Integer integer)
      | false, [ "not_two_pow"; word ] when sized_integer word <> None ->
          let integer = Option.get (sized_integer word) in
          if is_power_of_two integer.width then
            refuse context ~fix:(quote word) t.type_span
              "only a width that isn't a power of two takes the `not_two_pow.` gate (D93, standard 2.1)"
          else if integer.width > 8_388_607 then
            refuse context ~what:(Printf.sprintf "%s is wider than 8,388,607 bits" (quote word)) t.type_span
              "integers come in any width from 1 to 8,388,607 bits (D93, standard 2.1)"
          else no_arguments (Types.Integer integer)
      | _, [ word ] when Hashtbl.mem context.structs word -> (
          let info = Hashtbl.find context.structs word in
          seen_from context ~name:word ~file:info.struct_file ~visibility:info.struct_visibility t.type_span;
          match info.struct_declaration.struct_type_parameters with
          | [] -> no_arguments (Types.Struct word)
          | parameters ->
              (* trace: D103, D132 — one type parameter is written bare; two or more are labelled by their names *)
              let labels = List.map (fun ((p : name), _) -> parameter_label p.text) parameters in
              let given =
                match parameters, arguments with
                | [ _ ], [ { argument_label = None; argument_type } ] -> [ (List.hd labels, argument_type) ]
                | _ :: _ :: _, _ when List.for_all (fun a -> a.argument_label <> None) arguments ->
                    List.map (fun a -> ((Option.get a.argument_label).text, a.argument_type)) arguments
                | _ -> []
              in
              if List.sort compare (List.map fst given) <> List.sort compare labels then
                refuse context
                  ~what:(Printf.sprintf "%s takes %s in `< >`" (quote word)
                           (match labels with [ _ ] -> "one type, written bare" | _ -> String.concat " and " (List.map (fun l -> quote (l ^ ":")) labels)))
                  t.type_span "a type with one type parameter writes it bare; with two or more, each is labelled (D102, D132, standard 2.3)";
              Types.Instance (word, List.map (fun l -> (l, resolve_type context (List.assoc l given))) labels))
      | _, [ word ] when Hashtbl.mem context.unions word ->
          let info = Hashtbl.find context.unions word in
          seen_from context ~name:word ~file:info.union_file ~visibility:info.union_visibility t.type_span;
          no_arguments (Types.Union word)
      | _, [ word ] when Hashtbl.mem context.aliases word || Hashtbl.mem context.new_types word ->
          if List.mem word context.resolving then
            refuse context ~what:(Printf.sprintf "%s is defined in terms of itself" (quote word)) t.type_span
              "a type name stands for a type (D61, standard 2.5)";
          context.resolving <- word :: context.resolving;
          let resolved =
            match
              (match Hashtbl.find_opt context.aliases word with
               | Some aliased -> resolve_type context aliased
               | None -> Types.New (word, resolve_type context (Hashtbl.find context.new_types word)))
            with
            | r -> context.resolving <- List.tl context.resolving; r
            | exception e -> context.resolving <- List.tl context.resolving; raise e
          in
          no_arguments resolved
      | _ ->
          refuse context ~what:(Printf.sprintf "there's no type called %s" (quote (String.concat "." words))) t.type_span
            "a type is a built-in type or one the program declares (D56, standard 2)")

(* A type's details in [ ] (D135): lengths for lists and arrays, min and max for numbers. *)
and resolve_details context (t : type_expression) named =
  let why = "a type's details go in `[ ]` after the type (D135, standard 2.3a)" in
  let details = match named with Named_type { details; _ } -> details | _ -> [] in
  let value_of (d : detail) : Q.t =
    let rec literal (e : expression) negate =
      match e.expression_kind with
      | Syntax.Integer_literal { digits; negative; tilde = false } ->
          Q.of_bigint (integer_literal_value ~negative:(negative <> negate) digits)
      | Syntax.Decimal_literal { digits; negative; tilde = false } -> decimal_literal_value ~negative:(negative <> negate) digits
      | Syntax.Negate inner -> literal inner (not negate)
      | _ ->
          not_built context ~what:"a bound that's worked out, rather than written as a number, isn't built in the oracle yet"
            d.detail_value.expression_span "all bounds are `baked` (D135, standard 2.3a)"
    in
    literal d.detail_value false
  in
  let whole (d : detail) =
    let q = value_of d in
    if not (Z.equal (Q.den q) Z.one) || Q.sign q < 0 then
      refuse context ~what:(Printf.sprintf "%s is a count of items, so it's a whole number from 0" (quote d.detail_label))
        d.detail_value.expression_span why;
    Z.to_int (Q.num q)
  in
  let allowed labels =
    List.iter
      (fun (d : detail) ->
        if not (List.mem d.detail_label labels) then
          refuse context
            ~what:(Printf.sprintf "%s isn't a detail this type takes; it takes %s" (quote d.detail_label)
                     (String.concat " and " (List.map (fun l -> quote (l ^ ":")) labels)))
            d.detail_label_span why)
      details
  in
  let find label = List.find_opt (fun (d : detail) -> d.detail_label = label) details in
  let base_expression = { t with type_kind = (match named with Named_type n -> Named_type { n with details = [] } | k -> k) } in
  match named with
  | Named_type { words = [ "Array" ]; my = false; arguments = [ { argument_label = None; argument_type } ]; _ } -> (
      allowed [ "len" ];
      let item = resolve_type context argument_type in
      match find "len" with
      | Some d -> Types.Array (item, whole d)
      | None -> refuse context ~what:"an `Array` always says its length, as `[len: 4]`" t.type_span why)
  | _ -> (
      let base = resolve_type context base_expression in
      let checked_order low high =
        match low, high with
        | Some l, Some h when Q.gt l h ->
            refuse context ~what:"the lower bound is above the upper one, so no value fits" t.type_span why
        | _ -> ()
      in
      match underlying base with
      | Types.List _ ->
          allowed [ "len.min"; "len.max" ];
          let len_min = Option.map whole (find "len.min") and len_max = Option.map whole (find "len.max") in
          checked_order (Option.map Q.of_int len_min) (Option.map Q.of_int len_max);
          Types.Bounded (base, { Types.no_bounds with len_min; len_max })
      | Types.Integer _ | Types.Float _ | Types.Decimal | Types.Rational ->
          allowed [ "min"; "max" ];
          let min = Option.map value_of (find "min") and max = Option.map value_of (find "max") in
          (match underlying base with
           | Types.Integer _ ->
               List.iter
                 (fun (d : detail) ->
                   if not (Z.equal (Q.den (value_of d)) Z.one) then
                     refuse context ~what:(Printf.sprintf "an integer's %s is a whole number" (quote d.detail_label))
                       d.detail_value.expression_span why)
                 details
           | _ -> ());
          checked_order min max;
          Types.Bounded (base, { Types.no_bounds with min; max })
      | Types.Unknown -> Types.Unknown
      | b ->
          not_designed context ~what:(Printf.sprintf "details on %s aren't decided yet" (type_text b)) t.type_span
            "not decided yet (D135, standard 12.1)")


(* ---------- Variables ---------- *)

let find_variable fctx name =
  let rec go = function
    | [] -> None
    | scope :: rest -> (match Hashtbl.find_opt scope name with Some v -> Some v | None -> go rest)
  in
  go fctx.scopes

let push_scope fctx = fctx.scopes <- Hashtbl.create 8 :: fctx.scopes
let pop_scope fctx = fctx.scopes <- List.tl fctx.scopes

let in_scope fctx f =
  push_scope fctx;
  match f () with
  | result -> pop_scope fctx; result
  | exception e -> pop_scope fctx; raise e

let add_variable fctx ?(is_loop_variable = false) ~(name : name) ~variable_type ~is_mutable ~assigned () =
  let variable = { C.variable_id = fresh_id fctx.context; variable_name = name.text } in
  let info =
    { variable; variable_type; case_known_until = None; is_mutable; assigned; given = false; is_parameter = false; is_loop_variable;
      declared_at = name.span }
  in
  Hashtbl.replace (List.hd fctx.scopes) name.text info;
  info

(* The program's own function [name] as seen from [file]: one without `pub` is seen only in its own
   file (D106), and two seen at once are a clash (D59). *)
let find_function context ~(from_file : string) ~(span : Span.t) (name : string) : function_info option =
  let all = Hashtbl.find_all context.functions name in
  let visible =
    List.filter (fun (f : function_info) -> f.declaration.function_visibility <> File_only || f.file = from_file || from_file = "") all
  in
  match visible, all with
  | [ f ], _ -> Some f
  | [], [] -> None
  | [], f :: _ ->
      (* trace: D106 — using what isn't visible is refused with no fix *)
      refuse context ~what:(Printf.sprintf "%s is seen only in %s, since it has no `pub`" (quote name) (quote f.file)) span
        "a declaration without `pub` is seen only in its own file (D106, standard 9.2a)"
  | _ :: _ :: _, _ ->
      refuse context
        ~what:(Printf.sprintf "%s is declared in %s" (quote name)
                 (String.concat " and " (List.map (fun (f : function_info) -> quote f.file) visible)))
        span "a short name that clashes is always refused (D59, standard 9.2)"

(* ---------- Literals (D84) ---------- *)

(* The float nearest an exact fraction, rounding to nearest, ties to even. *)
let float_of_rational (q : Q.t) : float = Numbers.float_of_rational q

let float_exactly (q : Q.t) : bool =
  let f = float_of_rational q in
  Float.is_finite f && Q.equal (Q.of_float f) q

(* ---------- Expressions ---------- *)

let constant ?(span = Span.none) value type_ = { C.kind = C.Constant value; type_; span }

(* A value stored into a type with details is checked there (D135): a literal now, anything else when running. *)
let fit context (target : Types.t) (c : C.expression) : C.expression =
  if not (Fits.has_details target) then c
  else
    let rec literal_value (x : C.expression) =
      match x.kind with
      | C.Constant v -> Some v
      | C.List_literal xs ->
          let values = List.map literal_value xs in
          if List.for_all Option.is_some values then Some (Value.List { items = Dynarray.of_list (List.map Option.get values) })
          else None
      | _ -> None
    in
    match literal_value c with
    | Some v -> (
        match Fits.problem target v with
        | Some p ->
            report context
              (Diagnostic.make ~span:c.span ~when_:p
                 ~what:(let text = Source.text_of c.span in
                        if text = "" then Printf.sprintf "this doesn't fit in `%s`" (Types.name target)
                        else Printf.sprintf "`%s` doesn't fit in `%s`" text (Types.name target))
                 Diagnostic.Compile_time_error "a literal that breaks a bound is refused (D135, standard 2.3a)");
            raise Skip
        | None -> c)
    | None -> { c with kind = C.Check_fits { value = c; target } }

(* The operations an interface gives, with those it includes (D105). *)
let rec interface_operations context (interface : string) : string list =
  match Hashtbl.find_opt context.interfaces interface with
  | None -> []
  | Some (includes, operations) ->
      List.map (fun (o : name) -> o.text) operations
      @ List.concat_map (fun (i : name) -> interface_operations context i.text) includes

(* Whether a type parameter's requirements give an operation: `==` gives `!=`, and `<` gives `>`,
   `at_least` and `at_most` (D105). *)
let parameter_gives context (p : string) (operator : string) =
  let requirements = Option.value (List.assoc_opt p context.type_parameters) ~default:[] in
  let given = List.concat_map (fun (r : name) -> interface_operations context r.text) requirements in
  let needed = match operator with "!=" -> "==" | ">" | "at_least" | "at_most" -> "<" | o -> o in
  List.mem needed given

(* Whether [t] meets a requirement: Any, a type set it's in, or an interface it satisfies (D105). *)
let rec meets context (t : Types.t) (requirement : string) =
  requirement = "Any"
  || (match Hashtbl.find_opt context.type_sets requirement with
      | Some members -> List.exists (fun m -> try Types.same (resolve_type context m) t with Skip -> false) members
      | None -> false)
  || List.mem (Types.name t, requirement) context.satisfied
  || (match Hashtbl.find_opt context.interfaces requirement with
      | Some _ ->
          (* satisfying an interface that includes this one counts *)
          List.exists
            (fun (type_name, other) -> type_name = Types.name t && other <> requirement && includes context other requirement)
            context.satisfied
      | None -> false)

and includes context (outer : string) (inner : string) =
  match Hashtbl.find_opt context.interfaces outer with
  | Some (included, _) -> List.exists (fun (i : name) -> i.text = inner || includes context i.text inner) included
  | None -> false

let literal_text = function
  | Syntax.Integer_literal { digits; negative; tilde } | Syntax.Decimal_literal { digits; negative; tilde } ->
      (if tilde then "~" else "") ^ (if negative then "-" else "") ^ digits
  | _ -> ""

let is_literal (e : expression) =
  match e.expression_kind with Syntax.Integer_literal _ | Syntax.Decimal_literal _ -> true | _ -> false

let tilde_why = "a number literal its type can't hold exactly is written with `~`, and one it can is written without (D84, standard 2.1a)"

let rec check_number_literal fctx ~(expected : Types.t option) (e : expression) : C.expression =
  let context = fctx.context in
  let span = e.expression_span in
  let text = literal_text e.expression_kind in
  match e.expression_kind, Option.map underlying expected with
  | Syntax.Integer_literal { digits; negative; tilde }, (None | Some (Types.Integer _ | Types.Unknown)) ->
      let integer_type = match expected with Some t -> (match underlying t with Types.Integer i -> i | _ -> { signed = true; width = 64 }) | None -> { signed = true; width = 64 } in
      let value = integer_literal_value ~negative digits in
      if tilde then
        refuse context ~fix:(quote (if negative then "-" ^ digits else digits)) span tilde_why;
      if not (Types.integer_fits integer_type value) then
        refuse context
          ~what:(Printf.sprintf "%s doesn't fit in %s" (quote text) (type_text (Types.Integer integer_type)))
          ~when_:(Printf.sprintf "%s holds %s to %s" (type_text (Types.Integer integer_type))
                    (Z.to_string (Types.integer_minimum integer_type)) (Z.to_string (Types.integer_maximum integer_type)))
          span "an integer literal that doesn't fit its type is refused (D84, standard 2.1a)";
      let type_ = match expected with Some (Types.New _ as t) -> t | _ -> Types.Integer integer_type in
      constant ~span (Value.integer_of_z integer_type value) type_
  | (Syntax.Integer_literal { digits; negative; tilde } | Syntax.Decimal_literal { digits; negative; tilde }),
    Some (Types.Float kind) ->
      let q =
        match e.expression_kind with
        | Syntax.Integer_literal _ -> Q.of_bigint (integer_literal_value ~negative digits)
        | _ -> decimal_literal_value ~negative digits
      in
      let f = Numbers.round_rational (Numbers.format_of kind) q in
      (* trace: D120 *)
      if not (Float.is_finite f) then
        refuse context ~what:(Printf.sprintf "%s is outside the range of %s" (quote text) (type_text (Types.Float kind)))
          span "a float literal outside its type's range is refused (D120, standard 2.1a)";
      let exact = Float.is_finite f && Q.equal (Q.of_float f) q in
      (* trace: D84 *)
      if exact && tilde then refuse context ~fix:(quote (if negative then "-" ^ digits else digits)) span tilde_why;
      if (not exact) && not tilde then refuse context ~fix:(quote ("~" ^ (if negative then "-" else "") ^ digits)) span tilde_why;
      constant ~span (Value.Float (f, kind)) (Option.get expected)
  | (Syntax.Integer_literal { digits; negative; tilde } | Syntax.Decimal_literal { digits; negative; tilde }),
    Some Types.Rational ->
      let q =
        match e.expression_kind with
        | Syntax.Integer_literal _ -> Q.of_bigint (integer_literal_value ~negative digits)
        | _ -> decimal_literal_value ~negative digits
      in
      if tilde then refuse context ~fix:(quote ((if negative then "-" else "") ^ digits)) span tilde_why;
      constant ~span (Value.Rational q) Types.Rational
  | (Syntax.Integer_literal { digits; negative; tilde } | Syntax.Decimal_literal { digits; negative; tilde }),
    Some Types.Decimal ->
      (* trace: D82, D83, D84 *)
      let q =
        match e.expression_kind with
        | Syntax.Integer_literal _ -> Q.of_bigint (integer_literal_value ~negative digits)
        | _ -> decimal_literal_value ~negative digits
      in
      let rounded = Decimal.round q in
      (match rounded with
       | Decimal.Infinity _ ->
           refuse context ~what:(Printf.sprintf "%s is outside the range of `Decimal`" (quote text)) span
             "a literal outside its type's range is refused (D120, standard 2.1a)"
       | _ -> ());
      let exact = Decimal.holds_exactly q in
      if exact && tilde then refuse context ~fix:(quote ((if negative then "-" else "") ^ digits)) span tilde_why;
      if (not exact) && not tilde then refuse context ~fix:(quote ("~" ^ (if negative then "-" else "") ^ digits)) span tilde_why;
      constant ~span (Value.Decimal rounded) (Option.get expected)
  | Syntax.Decimal_literal _, None ->
      refuse context ~what:(Printf.sprintf "%s needs a type to land in" (quote text)) span
        "a number literal takes the type of where it lands (D84, standard 2.1a)"
  | _, Some t ->
      refuse context ~what:(Printf.sprintf "%s is a number, and %s is expected here" (quote text) (type_text t)) span
        "a value has the type its place expects (D56, standard 2)"
  | _, None -> raise Skip

and check_expression fctx ~(expected : Types.t option) (e : expression) : C.expression =
  let context = fctx.context in
  let span = e.expression_span in
  let result =
    match e.expression_kind with
    | Syntax.Integer_literal _ | Syntax.Decimal_literal _ -> check_number_literal fctx ~expected e
    | Syntax.String_literal s -> constant ~span (Value.String s) Types.String
    | Syntax.Bool_literal b -> constant ~span (Value.Bool b) Types.Bool
    | Syntax.Variable name -> (
        match find_variable fctx name with
        | None ->
            refuse context ~what:(Printf.sprintf "there's no variable called `$%s` here" name) span
              "every new name says how it's made (D5, D34, standard 3.1)"
        | Some info ->
            (* trace: D7 *)
            if info.given then
              refuse context ~what:(Printf.sprintf "`$%s` was given away, so it can't be used here" name) span
                "`give` retires the name it gives (D7, standard 3.6)";
            (* trace: D34 *)
            if not info.assigned then
              refuse context
                ~what:(Printf.sprintf "`$%s` has no value yet on every path to here" name) span
                "a `decl` is read only after `assign` on every path (D34, standard 3.3)";
            { C.kind = C.Read info.variable; type_ = info.variable_type; span })
    | Syntax.Grouped inner -> check_expression fctx ~expected inner
    | Syntax.Join items -> check_join fctx e items
    | Syntax.Convert { value; narrowings; target } -> check_convert fctx e value narrowings target
    | Syntax.Binary { operator; left; right } -> check_binary fctx ~expected e operator left right
    | Syntax.Comparison_chain { operands; operators } ->
        (* each neighbouring pair is checked as its own comparison; a middle operand is checked twice,
           and the same error twice is printed once *)
        let rec pairs = function
          | a :: (b :: _ as rest), o :: os ->
              let c = check_binary fctx ~expected:None { e with expression_kind = Syntax.Binary { operator = o; left = a; right = b } } o a b in
              c :: pairs (rest, os)
          | _ -> []
        in
        let compared = pairs (operands, operators) in
        let checked =
          match compared with
          | { C.kind = C.Compare { left; _ }; _ } :: _ ->
              left :: List.map (function { C.kind = C.Compare { right; _ }; _ } -> right | c -> c) compared
          | _ -> raise Skip
        in
        { C.kind = C.Chain { operands = checked; operators = List.map (fun (o : operator) -> o.word) operators }; type_ = Types.Bool; span }
    | Syntax.Not inner ->
        let inner = check_expression fctx ~expected:(Some Types.Bool) inner in
        expect_type context Types.Bool inner;
        { C.kind = C.Not inner; type_ = Types.Bool; span }
    | Syntax.Negate inner ->
        let inner = check_expression fctx ~expected inner in
        if not (Types.is_number (underlying inner.type_)) && inner.type_ <> Types.Unknown then
          refuse context ~what:(Printf.sprintf "`-` needs a number, and this is %s" (type_text inner.type_)) span
            "unary `-` works on numbers (D90, standard 2.1a)";
        { C.kind = C.Negate inner; type_ = inner.type_; span }
    | Syntax.Call { callee; arguments } -> check_call fctx ~expected e callee arguments
    | Syntax.Name { word; _ } ->
        refuse context ~what:(Printf.sprintf "`%s` names a function or type, not a value; a call takes `( )`" word) span
          "`( )` runs something (D15, standard 1.4)"
    | Syntax.List_literal items -> check_list_literal fctx ~expected e items
    | Syntax.Map_literal entries -> check_map_literal fctx ~expected e entries
    | Syntax.Range { from; ending; step_by } ->
        let check_int x = let c = check_expression fctx ~expected:(Some Types.int) x in expect_type context Types.int c; c in
        let from = check_int from in
        let inclusive, ending = match ending with To x -> (true, check_int x) | Before x -> (false, check_int x) in
        let step_by = Option.map check_int step_by in
        { C.kind = C.Range { from; ending; inclusive; step_by }; type_ = Types.Range; span }
    | Syntax.Index { target; counting; position } ->
        let target = check_expression fctx ~expected:None target in
        let position = check_expression fctx ~expected:(Some Types.int) position in
        expect_type context Types.int position;
        let item_type =
          match underlying target.type_ with
          | Types.List item | Types.Array (item, _) -> item
          | Types.Unknown -> Types.Unknown
          | t ->
              refuse context ~what:(Printf.sprintf "%s can't be indexed" (type_text t)) span
                "indexing works on lists (D17, standard 4.4)"
        in
        { C.kind = C.Index { target; counting; position }; type_ = item_type; span }
    | Syntax.Key_index { target; key } -> (
        let target = check_expression fctx ~expected:None target in
        match underlying target.type_ with
        | Types.Map (_, key_type, value_type) ->
            let key = check_expression fctx ~expected:(Some key_type) key in
            expect_type context key_type key;
            { C.kind = C.Key_index { target; key }; type_ = value_type; span }
        | Types.Unknown -> raise Skip
        | t ->
            refuse context ~what:(Printf.sprintf "%s isn't a map, so it has no `key:`" (type_text t)) span
              "a map is read by key, labelled like indexing (D138, standard 13.3)")
    | Syntax.Bare_index _ ->
        (* trace: D17 *)
        refuse context ~what:"an index says how it counts: `pos:` from 1, or `offset:` from 0" span
          "an index always says how it counts (D17, standard 4.4)"
    | Syntax.Member (target, field) -> check_member fctx e target field
    | Syntax.Build { built; fields } -> check_build fctx ~expected e built fields
    | Syntax.Copy inner ->
        let inner = check_expression fctx ~expected inner in
        { C.kind = C.Copy inner; type_ = inner.type_; span }
    | Syntax.Give inner -> (
        let checked = check_expression fctx ~expected inner in
        match inner.expression_kind with
        | Syntax.Variable name ->
            let info = Option.get (find_variable fctx name) in
            if not info.is_mutable then
              () (* giving a frozen value is allowed and changes nothing *);
            info.given <- true;
            checked
        | _ ->
            refuse context ~what:"`give` hands off a whole variable, such as `give $list`" span
              "`give $a` moves it to the new name and retires `$a` (D7, standard 3.6)")
    | Syntax.Fallback { value; instead } ->
        let value = check_expression fctx ~expected value in
        require_can_fail context value;
        let instead = check_expression fctx ~expected:(Some value.type_) instead in
        expect_type context value.type_ instead;
        { C.kind = C.Fallback { value; instead }; type_ = value.type_; span }
    | Syntax.Ignore value ->
        let value = check_expression fctx ~expected:None value in
        require_can_fail context value;
        { C.kind = C.Ignore value; type_ = Types.Nothing; span }
    | Syntax.Pass_up inner ->
        (* trace: D48 — `?` passes a failure up, refused unless this function lists it *)
        let value = check_expression fctx ~expected inner in
        require_can_fail context value;
        List.iter
          (fun (name, fields) ->
            match List.assoc_opt name fctx.info.failures with
            | Some listed when Types.same (Types.Failure (name, listed)) (Types.Failure (name, fields)) -> ()
            | Some _ ->
                refuse context
                  ~what:(Printf.sprintf "%s here carries different data from the %s this function lists" (quote name) (quote name))
                  span "`?` passes a failure up as it is (D48, standard 6.3)"
            | None ->
                refuse context
                  ~what:(Printf.sprintf "this can fail with %s, and %s doesn't list it after `fails`" (quote name)
                           (quote (if fctx.info.full_name = "" then "this" else fctx.info.full_name)))
                  span "`?` passes a failure up, refused unless this function lists it (D48, standard 6.3)")
          (failures_of context value);
        { C.kind = C.Pass_up value; type_ = value.type_; span }
    | Syntax.Otherwise { value; handling } ->
        let value = check_expression fctx ~expected value in
        require_can_fail context value;
        let arms = check_handling fctx ~at:value.span ~possible:(failures_of context value) ~gives:value.type_ handling in
        { C.kind = C.Otherwise { value; arms }; type_ = value.type_; span }
    | Syntax.Narrowed_member _ ->
        not_built context ~what:"this isn't built in the oracle yet" span "handlers that jump are marked `*` (D100, standard 6.4)"
  in
  result

(* The failures a call can raise, with their data (D48). *)
and failures_of context (value : C.expression) : (string * (string * Types.t) list) list =
  match value.kind with
  | C.Call_builtin { builtin; _ } -> List.map (fun f -> (f, [])) builtin.fails
  | C.Call_function { function_id; _ } -> (
      match Hashtbl.find_opt context.function_by_id function_id with Some f -> f.failures | None -> [])
  | C.Arithmetic { operator = "div"; narrowings = [ "exact" ]; _ } -> [ ("not_exact", []) ]   (* trace: D139 *)
  | C.Convert { narrowings = [ "exact" ]; _ } -> [ ("not_exact", []) ]
  | _ -> []

and require_can_fail context (value : C.expression) =
  let fails = failures_of context value <> [] in
  if not fails && value.type_ <> Types.Unknown then
    refuse context ~what:"nothing here can fail, so there's nothing to handle" value.span
      "a caller handles the failures a call can raise (D48, standard 6.3)"

and expect_type context (expected : Types.t) (actual : C.expression) =
  if not (Types.same expected actual.type_) then
    refuse context
      ~what:(Printf.sprintf "this is %s, and %s is expected here" (type_text actual.type_) (type_text expected))
      actual.span "a value has the type its place expects (D56, standard 2)"

(* Arms after `otherwise`, or a handler's arms used there: every failure still possible is covered,
   and nothing else (D48, D49). [gives] is the call's type, which `instead` gives in an arm. *)
and check_handling fctx ~(at : Span.t) ~possible ~(gives : Types.t) (handling : handling) : C.arm list =
  let context = fctx.context in
  let arms =
    match handling with
    | Arms arms -> arms
    | Handler { family; handler; jumps } -> handler_arms fctx ~family ~handler ~jumps
  in
  let seen = Hashtbl.create 8 in
  let checked =
    List.filter_map
      (fun (arm : arm) ->
        let known =
          match List.assoc_opt arm.case_name.text possible with
          | None ->
              error context ~what:(Printf.sprintf "%s isn't a failure this call can raise" (quote arm.case_name.text))
                arm.case_name.span "arms cover the failures still possible there (D48, standard 6.3)";
              None
          | Some fields ->
              if Hashtbl.mem seen arm.case_name.text then begin
                error context ~what:(Printf.sprintf "%s is covered twice" (quote arm.case_name.text)) arm.case_name.span
                  "each failure still possible is covered once (D48, standard 6.3)";
                None
              end
              else (Hashtbl.add seen arm.case_name.text (); Some fields)
        in
        let needs_value = gives <> Types.Nothing in
        fctx.arm_values <- (if needs_value then Some gives else None) :: fctx.arm_values;
        let result =
          in_scope fctx (fun () ->
              let binding =
                Option.map
                  (fun (b : name) ->
                    let t = match known with Some fields -> Types.Failure (arm.case_name.text, fields) | None -> Types.Unknown in
                    (add_variable fctx ~name:b ~variable_type:t ~is_mutable:false ~assigned:true ()).variable)
                  arm.binding
              in
              (binding, !check_statements_ref fctx arm.arm_body))
        in
        fctx.arm_values <- List.tl fctx.arm_values;
        (* an arm in place of a value ends with `instead`, `return`, `break` or `fail` on every path *)
        if needs_value && not (ends_every_path arm.arm_body) then
          error context ~what:"this arm can reach its end without `instead`, `return`, `break` or `fail`" arm.case_name.span
            "`instead` gives the value used in place of the failed call (D48, standard 6.3)";
        match known with
        | Some _ -> let binding, body = result in Some { C.arm_failure = arm.case_name.text; arm_binding = binding; arm_body = body }
        | None -> None)
      arms
  in
  let missing = List.filter (fun (name, _) -> not (Hashtbl.mem seen name)) possible in
  if missing <> [] then
    refuse context
      ~what:(Printf.sprintf "%s %s still possible here and not covered"
               (String.concat ", " (List.map (fun (n, _) -> quote n) missing)) (if List.length missing = 1 then "is" else "are"))
      at "every failure still possible must be covered (D48, standard 6.3)";
  if List.length checked <> List.length arms then raise Skip;
  checked

(* A handler's arms, from its family; `*` marks one that can jump out (D48, D49). *)
and handler_arms fctx ~(family : name) ~(handler : name) ~(jumps : bool) : arm list =
  let context = fctx.context in
  match Hashtbl.find_opt context.handler_families family.text with
  | None ->
      refuse context ~what:(Printf.sprintf "there's no handler family called %s" (quote family.text)) family.span
        "a `fam.handler` holds named, reusable sets of arms (D48, standard 6.4)"
  | Some handlers -> (
      match List.find_opt (fun h -> h.handler_name.text = handler.text) handlers with
      | None ->
          refuse context ~what:(Printf.sprintf "%s has no handler called %s" (quote family.text) (quote handler.text))
            handler.span "a `fam.handler` holds named, reusable sets of arms (D48, standard 6.4)"
      | Some h ->
          let can_jump = List.exists (fun (a : arm) -> can_jump_out a.arm_body) h.handler_arms in
          let place = Span.join family.span handler.span in
          (* trace: D48, D49 *)
          if can_jump && not jumps then
            refuse context ~fix:(quote (family.text ^ ".*" ^ handler.text)) place
              "a handler that can `return` or `break` is marked `*` where it's used (D48, standard 6.4)"
          else if jumps && not can_jump then
            refuse context ~fix:(quote (family.text ^ "." ^ handler.text)) place
              "only a handler that can `return` or `break` is marked `*` (D48, standard 6.4)";
          h.handler_arms)

(* Whether statements always end with `instead`, `return`, `break` or `fail`. *)
and ends_every_path (statements : statement list) =
  List.exists
    (fun (s : statement) ->
      match s.statement_kind with
      | Instead _ | Return _ | Return_early | Break _ | Fail _ -> true
      | If { branches; else_body = Some e } -> List.for_all (fun b -> ends_every_path b.branch_body) branches && ends_every_path e
      | Match { match_arms = Match_arms arms; _ } -> arms <> [] && List.for_all (fun (a : arm) -> ends_every_path a.arm_body) arms
      | _ -> false)
    statements

(* Whether statements can `return`, or `break` out of a loop they're not inside. *)
and can_jump_out (statements : statement list) =
  let rec go loop_depth (statements : statement list) =
    List.exists
      (fun (s : statement) ->
        match s.statement_kind with
        | Return _ | Return_early -> true
        | Break _ -> loop_depth = 0
        | If { branches; else_body } ->
            List.exists (fun b -> go loop_depth b.branch_body) branches || (match else_body with Some e -> go loop_depth e | None -> false)
        | Match { match_arms = Match_arms arms; _ } -> List.exists (fun (a : arm) -> go loop_depth a.arm_body) arms
        | While { body; _ } | For { body; _ } -> go (loop_depth + 1) body
        | Broken_block { body; _ } -> go loop_depth body
        | _ -> false)
      statements
  in
  go 0 statements

(* A join holds only strings, variables, fields and `as` (D20, D23). *)
and check_join fctx (e : expression) items =
  let context = fctx.context in
  let checked =
    List.map
      (fun (item : expression) ->
        let rec allowed (x : expression) =
          match x.expression_kind with
          | Syntax.String_literal _ | Syntax.Variable _ -> true
          | Syntax.Member (inner, _) -> allowed inner
          (* an item or entry is read like a field: D138's own example joins `$ages[key: $name] as String` *)
          | Syntax.Index { target; _ } | Syntax.Key_index { target; _ } -> allowed target
          | Syntax.Convert { value; _ } -> allowed value
          | _ -> false
        in
        if not (allowed item) then
          refuse context ~what:"a join holds only strings, variables, fields and `as`; a value worked out here needs a named step first"
            item.expression_span "values side by side are joined, and a join holds only plain values (D20, D23, standard 4.3)";
        let c = check_expression fctx ~expected:(Some Types.String) item in
        if c.type_ <> Types.String && c.type_ <> Types.Unknown then begin
          (* trace: D21 *)
          let source = Option.value (Diagnostic.source_line item.expression_span.file item.expression_span.line) ~default:"" in
          let text =
            if item.expression_span.end_line = item.expression_span.line then
              String.sub source (item.expression_span.column - 1) (item.expression_span.end_column - item.expression_span.column)
            else ""
          in
          refuse context ~fix:(quote (text ^ " as String")) item.expression_span
            "anything that isn't a `String` is converted explicitly with `as String` (D21, standard 4.3)"
        end;
        c)
      items
  in
  { C.kind = C.Join checked; type_ = Types.String; span = e.expression_span }

and check_convert fctx (e : expression) value narrowings target =
  let context = fctx.context in
  let target_type = resolve_type context target in
  let value = check_expression fctx ~expected:None value in
  let narrowing_words = List.map (fun n -> n.text) narrowings in
  let span = e.expression_span in
  let from = underlying value.type_ in
  (match underlying target_type, from, narrowing_words with
   | _, Types.Unknown, _ -> ()
   (* trace: D61 — crossing between a new type and its data uses `as`, which can't fail *)
   | _, _, [] when (match target_type, value.type_ with
                    | Types.New (_, u), t | t, Types.New (_, u) -> Types.same (underlying u) (underlying t)
                    | _ -> false) -> ()
   | Types.String, (Types.Integer _ | Types.Bool | Types.String), [] -> ()
   | Types.String, Types.Float _, ([] | [ "stored" ]) -> ()
   | Types.String, (Types.Rational | Types.Decimal), [] -> ()   (* trace: D139 *)
   | Types.String, (Types.Struct _ | Types.Union _), _ ->
       not_designed context ~what:"what a struct looks like as text isn't decided yet" span
         "not decided yet (D120, standard 12.1)"
   | Types.String, (Types.List _ | Types.Map _), _ ->
       not_designed context ~what:(Printf.sprintf "what %s looks like as text isn't decided yet" (type_text from)) span
         "not decided yet (D120, standard 12.1)"
   (* trace: D91 *)
   | Types.Integer _, Types.Integer _, ([] | [ "wrap" ] | [ "saturate" ]) -> ()
   | Types.Integer _, Types.Integer _, _ ->
       refuse context
         ~what:(Printf.sprintf "%s isn't a conversion between integers: it's plain `as`, `as.wrap` or `as.saturate`"
                  (quote (String.concat "." ("as" :: narrowing_words))))
         span "conversions say what they do whenever there's a choice (D91, standard 2.1a)"
   | Types.Integer _, (Types.Float _ | Types.Rational | Types.Decimal),
     ([ "trunc" ] | [ "floor" ] | [ "ceil" ] | [ "round"; "even" ] | [ "round"; "away" ] | [ "exact" ]) -> ()
   | Types.Integer _, (Types.Float _ | Types.Rational | Types.Decimal), [] ->
       refuse context
         ~what:(Printf.sprintf "converting %s to an integer says how it rounds: `as.trunc`, `as.floor`, `as.ceil`, `as.round.even`, `as.round.away` or `as.exact`"
                  (type_text value.type_))
         span "there's no bare rounding, since ties are a real choice (D91, standard 2.1a)"
   | (Types.Float _ | Types.Rational), (Types.Integer _ | Types.Float _ | Types.Rational), [] -> ()
   | (Types.Float _ | Types.Rational), Types.Decimal, [] -> ()
   | Types.Decimal, Types.Decimal, [] -> ()
   | Types.Decimal, Types.Integer { width; _ }, [] when width <= 112 -> ()   (* 2^112 has fewer than 34 digits *)
   | Types.Decimal, (Types.Integer _ | Types.Float _ | Types.Rational), [] ->
       not_designed context ~what:(Printf.sprintf "how %s rounds into `Decimal` isn't decided yet" (type_text value.type_)) span
         "not decided yet (D91, standard 12.1)"
   | (Types.Integer _ | Types.Float _ | Types.Rational | Types.Decimal), (Types.Integer _ | Types.Float _ | Types.Rational | Types.Decimal), _ ->
       refuse context
         ~what:(Printf.sprintf "%s doesn't say anything this conversion needs" (quote (String.concat "." ("as" :: narrowing_words))))
         span "conversions say what they do whenever there's a choice (D91, standard 2.1a)"
   | (Types.Integer _ | Types.Float _ | Types.Rational | Types.Decimal), Types.String, _ ->
       not_designed context ~what:(Printf.sprintf "turning text into %s isn't decided yet" (type_text target_type)) span
         "not decided yet (D53, standard 12.1)"
   | _ ->
       refuse context
         ~what:(Printf.sprintf "%s can't be converted to %s" (type_text value.type_) (type_text target_type))
         span "converting between number types uses `as` (D91, standard 2.1a)");
  { C.kind = C.Convert { value; narrowings = narrowing_words; target = target_type }; type_ = target_type; span }

and check_binary fctx ~expected (e : expression) (operator : operator) left right =
  let context = fctx.context in
  let span = e.expression_span in
  let is_join (x : expression) = match x.expression_kind with Syntax.Join _ -> true | _ -> false in
  if (is_join left || is_join right) && operator.word <> "==" && operator.word <> "!=" then
    refuse context
      ~what:(Printf.sprintf "%s can't be used inside a join; the value it works out needs a named step first" (quote operator.word))
      operator.operator_span "a join holds only strings, variables, fields and `as` (D23, standard 4.3)";
  (* A literal takes the type of the other side. *)
  let check_pair expected_for_both =
    if is_literal left && not (is_literal right) then
      let r = check_expression fctx ~expected:expected_for_both right in
      let l = check_expression fctx ~expected:(Some r.type_) left in
      (l, r)
    else
      let l = check_expression fctx ~expected:expected_for_both left in
      let r = check_expression fctx ~expected:(Some l.type_) right in
      (l, r)
  in
  let operator_text = String.concat "." (operator.word :: operator.narrowings) in
  match operator.word with
  | "and" | "or" ->
      let both =
        match operator.narrowings with
        | [] -> false
        | [ "both" ] -> true
        | _ -> refuse context ~what:(Printf.sprintf "%s isn't a kind of %s" (quote operator_text) (quote operator.word))
                 operator.operator_span "`and.both` and `or.both` always run both sides (D28, standard 4.2)"
      in
      let l = check_expression fctx ~expected:(Some Types.Bool) left in
      let r = check_expression fctx ~expected:(Some Types.Bool) right in
      expect_type context Types.Bool l;
      expect_type context Types.Bool r;
      { C.kind = C.Logic { operator = operator.word; both; left = l; right = r }; type_ = Types.Bool; span }
  | "==" | "!=" | "<" | ">" | "at_least" | "at_most" ->
      let l, r = check_pair None in
      if not (Types.same l.type_ r.type_) then
        refuse context
          ~what:(Printf.sprintf "%s compares %s with %s" (quote operator_text) (type_text l.type_) (type_text r.type_))
          operator.operator_span "both sides of a comparison have the same type (D27, D61, standard 4.1)";
      let ordered = operator.word <> "==" && operator.word <> "!=" in
      (match underlying l.type_ with
       | Types.Integer _ | Types.Float _ | Types.Rational | Types.Decimal | Types.Unknown -> ()
       | Types.Parameter p ->
           (* trace: D103 — the body is checked once against the requirements *)
           if not (parameter_gives context p operator.word) then
             refuse context
               ~what:(Printf.sprintf "`?%s`'s requirements don't give %s" p (quote operator_text)) operator.operator_span
               "a generic body uses only what its requirements promise (D103, D105, standard 5.8)"
       | Types.String -> ()   (* trace: D138 — strings order by code point *)
       | Types.Bool when not ordered -> ()
       | Types.Bool ->
           (* trace: D139 *)
           refuse context ~what:"`Bool` has no order, so it can't be compared with `<`, `>`, `at_least` or `at_most`"
             operator.operator_span "`Bool` has no order (D139, standard 4.1)"
       | Types.Struct _ | Types.Union _ | Types.List _ | Types.Map _ when not ordered ->
           not_built context ~what:(Printf.sprintf "comparing %s values isn't built in the oracle yet" (type_text l.type_))
             operator.operator_span "a type defines `==` and `<` (D105, standard 5.8)"
       | t when ordered ->
           not_designed context ~what:(Printf.sprintf "ordering %s values isn't decided yet" (type_text t))
             operator.operator_span "not decided yet (D105, standard 12.1)"
       | t ->
           refuse context ~what:(Printf.sprintf "%s values can't be compared with %s" (type_text t) (quote operator_text))
             operator.operator_span "comparisons work on values of the same type (D27, standard 4.1)");
      { C.kind = C.Compare { operator = operator.word; left = l; right = r }; type_ = Types.Bool; span }
  | _ ->
      (* `div.rational` takes integers and gives a Rational, so its operands don't take the result's type *)
      let operand_expected = if operator.word = "div" && operator.narrowings = [ "rational" ] then None else expected in
      let l, r = check_pair operand_expected in
      if not (Types.same l.type_ r.type_) then
        refuse context
          ~what:(Printf.sprintf "%s works on two values of the same type, and these are %s and %s" (quote operator_text)
                   (type_text l.type_) (type_text r.type_))
          operator.operator_span "maths works on values of one type, converted with `as` (D91, standard 2.1a)";
      let t = underlying l.type_ in
      let is_integer = match t with Types.Integer _ -> true | _ -> false in
      (match t with
       | Types.Parameter p when not (parameter_gives context p operator.word) ->
           refuse context
             ~what:(Printf.sprintf "`?%s`'s requirements don't give %s" p (quote operator_text)) operator.operator_span
             "a generic body uses only what its requirements promise (D103, D105, standard 5.8)"
       | _ -> ());
      if not (Types.is_number t) && t <> Types.Unknown && (match t with Types.Parameter _ -> false | _ -> true) then
        refuse context ~what:(Printf.sprintf "%s works on numbers, and this is %s" (quote operator_text) (type_text l.type_))
          operator.operator_span "maths works on numbers (D90, standard 2.1a)";
      (* arithmetic gives back the plain type (D135) *)
      let rec plain = function Types.Bounded (t, _) -> plain t | t -> t in
      let result_type = ref (plain l.type_) in
      (match operator.word, operator.narrowings with
       | ("+" | "-" | "x"), [] -> ()
       | ("plus" | "minus" | "times"), [ ("wrap" | "saturate") as how ] ->
           (* trace: D92 *)
           if (not is_integer) && t <> Types.Unknown then begin
             if how = "wrap" then
               refuse context ~what:(Printf.sprintf "%s works on integers, not %s" (quote operator_text) (type_text l.type_))
                 operator.operator_span "on `Float`, `.wrap` is refused (D92, standard 2.1a)"
             else
               not_designed context ~what:(Printf.sprintf "%s on %s isn't decided yet" (quote operator_text) (type_text l.type_))
                 operator.operator_span "not decided yet (D92, standard 12.1)"
           end
       | ("plus" | "minus" | "times"), _ ->
           refuse context ~what:(Printf.sprintf "%s isn't an operator: overflow on purpose is `%s.wrap` or `%s.saturate`"
                                   (quote operator_text) operator.word operator.word)
             operator.operator_span "overflow on purpose is a narrowing of the operation's word (D92, standard 2.1a)"
       | "div", [] ->
           (* trace: D88 *)
           if is_integer then
             refuse context ~what:"dividing integers says which kind: `div.trunc`, `div.floor`, `div.exact` or `div.rational`"
               operator.operator_span "on integers, `div` says which kind (D88, standard 2.1a)"
       | "div", [ ("trunc" | "floor") ] when is_integer -> ()
       | "div", [ "exact" ] when is_integer -> ()
       | "div", [ "rational" ] when is_integer -> result_type := Types.Rational
       | "mod", ([ "trunc" ] | [ "floor" ]) when is_integer -> ()
       | "mod", [] when is_integer ->
           refuse context ~what:"the remainder says which kind: `mod.trunc` or `mod.floor`" operator.operator_span
             "the remainder matches its division (D85, standard 2.1a)"
       | ("div" | "mod"), _ when not is_integer && t <> Types.Unknown ->
           not_designed context ~what:(Printf.sprintf "%s on %s isn't decided yet" (quote operator_text) (type_text l.type_))
             operator.operator_span "not decided yet (D88, standard 12.1)"
       | _ ->
           refuse context ~what:(Printf.sprintf "%s isn't an operator" (quote operator_text)) operator.operator_span
             "dividing is `div`, and on integers it says which kind (D88, standard 2.1a)");
      (match t, operator.word, operator.narrowings with
       | (Types.Rational | Types.Decimal), ("x" | "+" | "-" | "div"), [] -> ()
       | (Types.Rational | Types.Decimal), _, _ ->
           not_designed context ~what:(Printf.sprintf "%s on %s isn't decided yet" (quote operator_text) (type_text l.type_))
             operator.operator_span "not decided yet (D92, standard 12.1)"
       | _ -> ());
      { C.kind = C.Arithmetic { operator = operator.word; narrowings = operator.narrowings; left = l; right = r };
        type_ = !result_type; span }

and check_list_literal fctx ~expected (e : expression) items =
  let context = fctx.context in
  let span = e.expression_span in
  match Option.map underlying expected with
  | Some (Types.List item_type) ->
      let checked = List.map (fun x -> let c = check_expression fctx ~expected:(Some item_type) x in expect_type context item_type c; c) items in
      { C.kind = C.List_literal checked; type_ = Option.get expected; span }
  | Some (Types.Array (item_type, _)) ->
      let checked = List.map (fun x -> let c = check_expression fctx ~expected:(Some item_type) x in expect_type context item_type c; c) items in
      { C.kind = C.List_literal checked; type_ = Option.get expected; span }
  | Some (Types.Map (kind, _, _)) when items = [] ->
      { C.kind = C.Map_literal (kind, []); type_ = Option.get expected; span }
  | Some Types.Unknown -> { C.kind = C.List_literal []; type_ = Types.Unknown; span }
  | Some t ->
      refuse context ~what:(Printf.sprintf "a list is written here, and %s is expected" (type_text t)) span
        "the declared type decides what a literal is (D64, standard 2.3)"
  | None ->
      refuse context ~what:"a list literal needs a declared type to land in" span
        "the declared type decides what a literal is (D64, standard 2.3)"

and check_map_literal fctx ~expected (e : expression) entries =
  let context = fctx.context in
  let span = e.expression_span in
  match Option.map underlying expected with
  | Some (Types.Map (kind, key_type, value_type)) ->
      let checked =
        List.map
          (fun (k, v) ->
            let k = check_expression fctx ~expected:(Some key_type) k in
            expect_type context key_type k;
            let v = check_expression fctx ~expected:(Some value_type) v in
            expect_type context value_type v;
            (k, v))
          entries
      in
      { C.kind = C.Map_literal (kind, checked); type_ = Option.get expected; span }
  | Some t ->
      refuse context ~what:(Printf.sprintf "a map is written here, and %s is expected" (type_text t)) span
        "the declared type decides what a literal is (D64, standard 2.3)"
  | None ->
      refuse context ~what:"a map literal needs a declared type to land in" span
        "the declared type decides what a literal is (D64, standard 2.3)"

and check_member fctx (e : expression) target field =
  let context = fctx.context in
  let span = e.expression_span in
  let target = check_expression fctx ~expected:None target in
  match underlying target.type_ with
  | Types.Struct struct_name | Types.Instance (struct_name, _) -> (
      let info = Hashtbl.find context.structs struct_name in
      let bindings =
        match underlying target.type_ with
        | Types.Instance (_, arguments) ->
            List.map2 (fun ((p : name), _) (_, t) -> (p.text, t)) info.struct_declaration.struct_type_parameters arguments
        | _ -> []
      in
      (match List.find_opt (fun (f : struct_field) -> f.field_name.text = field.text) info.struct_declaration.fields with
       | Some f -> seen_from context ~name:(struct_name ^ "." ^ field.text) ~file:info.struct_file ~visibility:f.field_visibility field.span
       | None -> ());
      match List.find_opt (fun (n, _, _) -> n = field.text) info.resolved_fields with
      | Some (_, t, _) -> { C.kind = C.Field (target, field.text); type_ = substitute_parameters bindings t; span }
      | None ->
          refuse context ~what:(Printf.sprintf "%s has no field called %s" (quote struct_name) (quote field.text)) field.span
            "fields are read with `.` (D56, standard 2.4)")
  | Types.Unknown -> { C.kind = C.Field (target, field.text); type_ = Types.Unknown; span }
  | Types.Failure (failure_name, fields) -> (
      match List.assoc_opt field.text fields with
      | Some t -> { C.kind = C.Field (target, field.text); type_ = t; span }
      | None ->
          refuse context ~what:(Printf.sprintf "the failure %s carries no %s" (quote failure_name) (quote field.text))
            field.span "a failure can carry data (D48, standard 6.2)")
  | Types.Case (union_name, case_name) -> (
      let info = Hashtbl.find context.unions union_name in
      match List.assoc_opt field.text (Option.value (List.assoc_opt case_name info.resolved_cases) ~default:[]) with
      | Some t -> { C.kind = C.Field (target, field.text); type_ = t; span }
      | None ->
          refuse context
            ~what:(Printf.sprintf "%s has no field called %s" (quote (union_name ^ "." ^ case_name)) (quote field.text))
            field.span "a case's data goes in `[ ]` with labelled fields (D97, standard 2.4a)")
  | Types.Union union_name ->
      (* trace: D97 *)
      let because =
        match target.kind with
        | C.Read v -> (
            match find_variable fctx v.variable_name with
            | Some { case_known_until = Some change_span; _ } ->
                [ Printf.sprintf "the `change` at line %d column %d ends what the case test knew" change_span.line
                    (Diagnostic.grapheme_column change_span) ]
            | _ -> [])
        | _ -> []
      in
      report context
        (Diagnostic.make ~span:field.span ~because
           ~what:(Printf.sprintf "which case of %s this is isn't known here, so its fields can't be read" (quote union_name))
           Diagnostic.Compile_time_error "a case's fields are read inside `if <value>: <type>.<case>:` or a `match` arm (D97, standard 4.5a)");
      raise Skip
  | t ->
      refuse context ~what:(Printf.sprintf "%s has no field called %s; a method call takes `( )`" (type_text t) (quote field.text))
        field.span "fields are read with `.`, and methods always take `( )` (D40, standard 13.3)"

and check_build fctx ~expected (e : expression) built fields =
  let context = fctx.context in
  let span = e.expression_span in
  match built.expression_kind with
  | Syntax.Name { word; _ } when Hashtbl.mem context.structs word ->
      let info = Hashtbl.find context.structs word in
      seen_from context ~name:word ~file:info.struct_file ~visibility:info.struct_visibility built.expression_span;
      let parameters = info.struct_declaration.struct_type_parameters in
      (* a generic struct's types come from where it goes, or from its fields (D103) *)
      let bindings =
        if parameters = [] then []
        else
          match Option.map underlying expected with
          | Some (Types.Instance (name, arguments)) when name = word ->
              List.map2 (fun ((p : name), _) (_, t) -> (p.text, t)) parameters arguments
          | _ ->
              let found = Hashtbl.create 4 in
              List.iter
                (fun { field; field_value } ->
                  match List.find_opt (fun (n, _, _) -> n = field.text) info.resolved_fields with
                  | Some (_, Types.Parameter p, _) when not (Hashtbl.mem found p) -> (
                      let saved = context.diagnostics in
                      match (check_expression fctx ~expected:None field_value).type_ with
                      | t -> context.diagnostics <- saved; if t <> Types.Unknown then Hashtbl.replace found p t
                      | exception Skip -> context.diagnostics <- saved)
                  | _ -> ())
                fields;
              List.map
                (fun ((p : name), _) ->
                  match Hashtbl.find_opt found p.text with
                  | Some t -> (p.text, t)
                  | None ->
                      refuse context ~what:(Printf.sprintf "nothing here says what `?%s` is" p.text) span
                        "a type parameter is worked out from the values or where the result goes (D103, standard 5.8)")
                parameters
      in
      let field_type t = substitute_parameters bindings t in
      let seen = Hashtbl.create 8 in
      let given =
        List.map
          (fun { field; field_value } ->
            match List.find_opt (fun (n, _, _) -> n = field.text) info.resolved_fields with
            | None ->
                refuse context ~what:(Printf.sprintf "%s has no field called %s" (quote word) (quote field.text)) field.span
                  "a struct is built with its own fields (D56, standard 2.4)"
            | Some (_, t, _) ->
                let t = field_type t in
                if Hashtbl.mem seen field.text then
                  refuse context ~what:(Printf.sprintf "%s is given twice" (quote field.text)) field.span
                    "a struct is built with each field once (D56, standard 2.4)";
                Hashtbl.add seen field.text ();
                let v = check_expression fctx ~expected:(Some t) field_value in
                expect_type context t v;
                check_hand_off ~escapes:true fctx v field_value;
                (field.text, fit context t v))
          fields
      in
      List.iter
        (fun (n, _, default) ->
          if default = None && not (Hashtbl.mem seen n) then
            refuse context ~what:(Printf.sprintf "%s has no default, so it must be given" (quote n)) span
              "a field without a default must be given (D57, standard 2.4)")
        info.resolved_fields;
      let type_ =
        if parameters = [] then Types.Struct word
        else Types.Instance (word, List.map (fun ((p : name), _) -> (parameter_label p.text, List.assoc p.text bindings)) parameters)
      in
      { C.kind = C.Build_struct { struct_name = word; fields = given }; type_; span }
  | Syntax.Member ({ expression_kind = Syntax.Name { word; _ }; _ }, case) when Hashtbl.mem context.unions word -> (
      let info = Hashtbl.find context.unions word in
      match List.assoc_opt case.text info.resolved_cases with
      | None ->
          refuse context ~what:(Printf.sprintf "%s has no case called %s" (quote word) (quote case.text)) case.span
            "a union's cases are its narrowings (D97, standard 2.4a)"
      | Some case_fields ->
          let seen = Hashtbl.create 8 in
          let given =
            List.map
              (fun { field; field_value } ->
                match List.assoc_opt field.text case_fields with
                | None ->
                    refuse context ~what:(Printf.sprintf "%s has no field called %s" (quote (word ^ "." ^ case.text)) (quote field.text))
                      field.span "a case's data goes in `[ ]` with labelled fields (D97, standard 2.4a)"
                | Some t ->
                    Hashtbl.add seen field.text ();
                    let v = check_expression fctx ~expected:(Some t) field_value in
                    expect_type context t v;
                    (field.text, v))
              fields
          in
          List.iter
            (fun (n, _) ->
              if not (Hashtbl.mem seen n) then
                refuse context ~what:(Printf.sprintf "%s must be given" (quote n)) span
                  "a case's fields are all given (D97, standard 2.4a)")
            case_fields;
          { C.kind = C.Build_union { union_name = word; case_name = case.text; fields = given }; type_ = Types.Union word; span })
  | _ ->
      refuse context ~what:"only a struct or a union's case is built with `[ ... = ... ]`" span
        "a struct is built with `[ ]` and `=` (D56, standard 2.4)"

(* Handing off something whose inside can change says `give` or `copy` (D7). *)
and check_hand_off ?(escapes = false) fctx (value : C.expression) (source : expression) =
  let context = fctx.context in
  let rec root (x : expression) =
    match x.expression_kind with
    | Syntax.Variable name -> Some name
    | Syntax.Member (inner, _) -> root inner
    | Syntax.Index { target; _ } | Syntax.Key_index { target; _ } -> root target
    | Syntax.Grouped inner -> root inner
    | _ -> None
  in
  match root source with
  | Some name when Types.has_inside_that_changes value.type_ -> (
      match find_variable fctx name with
      | Some info when info.is_mutable ->
          (* trace: D7 *)
          refuse context
            ~what:(Printf.sprintf "%s can change inside, so handing it off needs `give` or `copy`" (quote ("$" ^ name)))
            source.expression_span "a hand-off says what it does (D7, standard 3.6)"
      | Some info when info.is_parameter && escapes ->
          (* trace: D139 *)
          let text = Source.text_of source.expression_span in
          refuse context ~fix:(quote ("copy " ^ text)) source.expression_span
            "a function sees a parameter frozen for the call, and keeping it after returning needs `copy` (D139, standard 3.6)"
      | _ -> ())
  | _ -> ()

and check_call fctx ~expected (e : expression) callee arguments =
  let context = fctx.context in
  let span = e.expression_span in
  ignore expected;
  (* A chain of names after a base: geometry.area, greet.casual.loud, $r.warm_up, $s.len.bytes *)
  let rec flatten (x : expression) words =
    match x.expression_kind with
    | Syntax.Member (inner, n) -> flatten inner (n :: words)
    | _ -> (x, words)
  in
  match callee.expression_kind with
  | Syntax.Name { path = []; my = false; word }
    when List.exists (fun (u : Manifest.short_name) -> u.short = word && (u.block = "all" || u.block = fctx.info.file))
           context.short_names ->
      (* trace: D60, D114 — a short name from the manifest stands for its path *)
      let u =
        List.find (fun (u : Manifest.short_name) -> u.short = word && (u.block = "all" || u.block = fctx.info.file))
          context.short_names
      in
      let at = callee.expression_span in
      let head = { expression_kind = Syntax.Name { my = false; path = []; word = List.hd u.path }; expression_span = at } in
      let full =
        List.fold_left
          (fun inner w -> { expression_kind = Syntax.Member (inner, { text = w; span = at }); expression_span = at })
          head (List.tl u.path)
      in
      check_call fctx ~expected e full arguments
  | Syntax.Name { path = []; my = false; word } when Hashtbl.mem context.versions word ->
      check_versions_call fctx span word (Hashtbl.find context.versions word) arguments
  | Syntax.Name { my; path; word } -> (
      let user =
        if path = [] || path = [ "pkg" ] then find_function context ~from_file:fctx.info.file ~span:callee.expression_span word
        else None
      in
      let std =
        if (path = [] && not my) || (match path with "std" :: _ -> true | _ -> false) then
          match Std_library.find word with
          | Some s when path = [] || String.concat "::" path = s.path -> Some s
          | _ -> None
        else None
      in
      let std = if context.std_visible then std else None in
      (* trace: D63 *)
      let user = match user with Some f when f.declaration.function_my <> my -> (if my then Some f else None) | u -> u in
      match user, std with
      | Some _, Some s when path = [] ->
          (* trace: D59 *)
          refuse context
            ~what:(Printf.sprintf "%s is both `pkg::%s` and `%s::%s`" (quote word) word s.path word) callee.expression_span
            "a short name that clashes is always refused (D59, standard 9.2)"
      | Some f, _ -> check_user_call ?expected fctx span f [] None arguments
      | None, Some s -> check_std_call fctx span s arguments
      | None, None ->
          if word = "main" && not my then
            refuse context ~fix:"`my::main`" callee.expression_span
              "a name of the program's own that is also a built-in word is written with `my::` (D63, standard 9.4)"
          else if (not context.std_visible) && Std_library.find word <> None then
            refuse context
              ~what:(Printf.sprintf "%s is in std, and the manifest has no `need std` line" (quote word)) callee.expression_span
              "without a `need std` line, std's names aren't visible (D59, D128, standard 13)"
          else
            refuse context ~what:(Printf.sprintf "there's no function called %s" (quote word)) callee.expression_span
              "a name is visible when it's declared or comes from a package the manifest lists (D59, standard 9.2)")
  | Syntax.Member _ -> (
      let base, words = flatten callee [] in
      match base.expression_kind with
      | Syntax.Name { my = false; path = []; word } when not (is_variable_like base) ->
          check_path_call fctx span callee (word, base.expression_span) words arguments
      | _ -> check_method_call fctx span base words arguments)
  | _ ->
      refuse context ~what:"this can't be called" callee.expression_span "`( )` runs a function (D15, standard 1.4)"

and is_variable_like (_ : expression) = false

(* geometry.area(...), Reading.new(...), greet.casual.loud(...): a family member, maybe with presets (D45). *)
and check_path_call fctx span callee (head, head_span) (words : name list) arguments =
  let context = fctx.context in
  let all = head :: List.map (fun n -> n.text) words in
  let rec longest k =
    if k = 0 then None
    else
      let name = String.concat "." (List.filteri (fun i _ -> i < k) all) in
      match find_function context ~from_file:fctx.info.file ~span:callee.expression_span name with
      | Some f -> Some (f, List.filteri (fun i _ -> i >= k - 1) (List.map (fun n -> n) ({ text = head; span = head_span } :: words)) |> List.tl)
      | None -> longest (k - 1)
  in
  let full = String.concat "." all in
  if Hashtbl.mem context.versions full then check_versions_call fctx span full (Hashtbl.find context.versions full) arguments
  else
  match longest (List.length all) with
  | None ->
      refuse context ~what:(Printf.sprintf "there's no function called %s" (quote (String.concat "." all))) callee.expression_span
        "a family's members are written `<family>.<name>` (D45, standard 5.5)"
  | Some (f, presets) ->
      (* trace: D44, D45 *)
      let settings =
        List.fold_left
          (fun settings (preset : name) ->
            match Hashtbl.find_opt context.presets (f.full_name ^ "." ^ preset.text) with
            | None ->
                refuse context
                  ~what:(Printf.sprintf "%s has no preset called %s" (quote f.full_name) (quote preset.text)) preset.span
                  "`preset name [...]` fills in some of the family function's labelled arguments (D45, standard 5.6)"
            | Some preset_settings ->
                List.iter
                  (fun ((parameter : name), _) ->
                    if List.exists (fun ((p : name), _) -> p.text = parameter.text) settings then
                      refuse context
                        ~what:(Printf.sprintf "this chain of presets sets `$%s` twice" parameter.text) callee.expression_span
                        "presets stack, and a chain that sets one parameter twice is refused (D45, standard 5.6)")
                  preset_settings;
                settings @ preset_settings)
          [] presets
      in
      check_user_call fctx span f settings None arguments

(* A generic function's type parameters are worked out from the arguments, or from where the result
   goes; if nothing says, the call is refused (D103). Each must meet its requirements (D105). *)
and instantiate fctx span (f : function_info) (expected : Types.t option) arguments : function_info =
  let context = fctx.context in
  let saved_diagnostics = context.diagnostics in
  let variables = List.concat_map (fun scope -> Hashtbl.fold (fun _ info acc -> info :: acc) scope []) fctx.scopes in
  let saved_given = List.map (fun info -> (info, info.given)) variables in
  let argument_types =
    List.map
      (fun (a : argument) -> (a, try Some (check_expression fctx ~expected:None a.value).type_ with Skip -> None))
      arguments
  in
  context.diagnostics <- saved_diagnostics;
  List.iter (fun (info, given) -> info.given <- given) saved_given;
  let bindings : (string, Types.t) Hashtbl.t = Hashtbl.create 4 in
  let rec unify (declared : Types.t) (actual : Types.t) =
    match declared, actual with
    | Types.Parameter p, t when t <> Types.Unknown -> (
        let t = match t with Types.Bounded (t, _) -> t | t -> t in
        match Hashtbl.find_opt bindings p with
        | None -> Hashtbl.replace bindings p t
        | Some earlier when Types.same earlier t -> ()
        | Some earlier ->
            refuse context
              ~what:(Printf.sprintf "`?%s` would be both %s and %s in this call" p (type_text earlier) (type_text t)) span
              "a type parameter is worked out from the arguments (D103, standard 5.8)")
    | Types.List a, Types.List b -> unify a b
    | Types.Map (_, k1, v1), Types.Map (_, k2, v2) -> unify k1 k2; unify v1 v2
    | Types.Bounded (a, _), b | a, Types.Bounded (b, _) -> unify a b
    | _ -> ()
  in
  let labels = List.map (fun ((v : name), (l : name)) -> (v.text, l.text)) f.declaration.labels in
  let parameters = List.combine (List.map (fun p -> p.parameter.text) f.declaration.parameters) f.parameter_types in
  let positional_parameters = List.filter (fun (p, _) -> not (List.mem_assoc p labels)) parameters in
  let position = ref 0 in
  List.iter
    (fun ((a : argument), found) ->
      let parameter =
        match a.label with
        | None ->
            let p = List.nth_opt positional_parameters !position in
            incr position;
            Option.map snd p
        | Some l -> (
            match List.find_opt (fun (_, label) -> label = l.text) labels with
            | Some (p, _) -> List.assoc_opt p parameters
            | None -> None)
      in
      match parameter, found with Some declared, Some actual -> unify declared actual | _ -> ())
    argument_types;
  (match expected with Some e -> unify f.result_type e | None -> ());
  List.iter
    (fun ((p : name), (r : requirement)) ->
      match Hashtbl.find_opt bindings p.text with
      | None ->
          refuse context ~what:(Printf.sprintf "nothing in this call says what `?%s` is" p.text) span
            "a type parameter is worked out from the arguments or where the result goes, and if nothing says, it's refused (D103, standard 5.8)"
      | Some t ->
          List.iter
            (fun (requirement : name) ->
              if not (meets context t requirement.text) then
                refuse context
                  ~what:(Printf.sprintf "`?%s` is %s here, which doesn't meet %s" p.text (type_text t) (quote requirement.text))
                  span
                  "a type fits an interface only through a written `satisfies` line, and a type set only by being in it (D105, standard 5.8)")
            r.requirement_names)
    f.declaration.type_parameters;
  let rec substitute (t : Types.t) =
    match t with
    | Types.Parameter p -> Option.value (Hashtbl.find_opt bindings p) ~default:t
    | Types.List item -> Types.List (substitute item)
    | Types.Map (k, a, b) -> Types.Map (k, substitute a, substitute b)
    | Types.Bounded (t, b) -> Types.Bounded (substitute t, b)
    | Types.Array (t, n) -> Types.Array (substitute t, n)
    | t -> t
  in
  { f with parameter_types = List.map substitute f.parameter_types; result_type = substitute f.result_type }

(* A call of a name with versions picks the one whose parameters fit the arguments' number and exact
   types (D46). The arguments' types are found first without keeping anything that finding them did. *)
and check_versions_call fctx span call_name (infos : function_info list) arguments =
  let context = fctx.context in
  let saved_diagnostics = context.diagnostics in
  let variables = List.concat_map (fun scope -> Hashtbl.fold (fun _ info acc -> info :: acc) scope []) fctx.scopes in
  let saved_given = List.map (fun info -> (info, info.given)) variables in
  let argument_type (a : argument) =
    if is_literal a.value then None
    else Some (try (check_expression fctx ~expected:None a.value).type_ with Skip -> Types.Unknown)
  in
  let found = List.map (fun (a : argument) -> (a, argument_type a)) arguments in
  context.diagnostics <- saved_diagnostics;
  List.iter (fun (info, given) -> info.given <- given) saved_given;
  let fits (f : function_info) =
    let labels = List.map (fun ((v : name), (l : name)) -> (v.text, l.text)) f.declaration.labels in
    let defaults = List.map (fun ((v : name), _) -> v.text) f.declaration.defaults in
    let parameters = List.combine (List.map (fun p -> p.parameter.text) f.declaration.parameters) f.parameter_types in
    let positional_parameters = List.filter (fun (p, _) -> not (List.mem_assoc p labels)) parameters in
    let positional = List.filter (fun ((a : argument), _) -> a.label = None) found in
    let labelled = List.filter (fun ((a : argument), _) -> a.label <> None) found in
    let type_fits t (a, found_type) =
      match found_type with
      | Some actual -> Types.same t actual
      | None -> ( try ignore (check_number_literal { fctx with scopes = [ Hashtbl.create 1 ] } ~expected:(Some t) a.value); true with Skip -> false)
    in
    let given = ref [] in
    List.length positional <= List.length positional_parameters
    && List.for_all2 (fun (p, t) arg -> given := p :: !given; type_fits t arg)
         (List.filteri (fun i _ -> i < List.length positional) positional_parameters) positional
    && List.for_all
         (fun (((a : argument), _) as arg) ->
           match List.find_opt (fun (_, l) -> Some l = Option.map (fun (n : name) -> n.text) a.label) labels with
           | Some (p, _) -> given := p :: !given; type_fits (List.assoc p parameters) arg
           | None -> false)
         labelled
    && List.for_all (fun (p, _) -> List.mem p !given || List.mem p defaults) parameters
  in
  let candidates = List.filter fits infos in
  context.diagnostics <- saved_diagnostics;
  match candidates with
  | [ f ] -> check_user_call fctx span f [] None arguments
  | [] ->
      refuse context ~what:(Printf.sprintf "no version of %s takes these arguments" (quote call_name)) span
        "a version is picked by the number of arguments and their exact types (D46, standard 5.7)"
  | _ when Hashtbl.mem context.overlapping_versions call_name -> raise Skip
  | _ ->
      refuse context ~what:(Printf.sprintf "more than one version of %s takes these arguments" (quote call_name)) span
        "a version is picked by the number of arguments and their exact types (D46, standard 5.7)"

and check_arguments fctx span ~(function_name : string) ~(parameters : (string * Types.t) list)
    ~(labels : (string * string) list) ~(defaults : (string * expression) list) (arguments : argument list) =
  let context = fctx.context in
  let why = "unlabelled arguments come first, in order, then labelled ones (D42, standard 5.3)" in
  let unlabelled_parameters = List.filter (fun (p, _) -> not (List.mem_assoc p labels)) parameters in
  let rec split acc = function
    | ({ label = None; _ } as a) :: rest -> split (a :: acc) rest
    | rest -> (List.rev acc, rest)
  in
  let positional, labelled = split [] arguments in
  List.iter
    (fun (a : argument) ->
      if a.label = None then
        refuse context ~what:"an unlabelled argument comes after a labelled one" a.value.expression_span why)
    labelled;
  if List.length positional > List.length unlabelled_parameters then begin
    let extra = List.nth positional (List.length unlabelled_parameters) in
    let labelled_given = List.filter_map (fun (a : argument) -> Option.map (fun (l : name) -> l.text) a.label) labelled in
    let labels_left = List.filter (fun (_, l) -> not (List.mem l labelled_given)) labels in
    (* one extra argument and one label left: the one fix is to label it *)
    (match labels_left with
     | [ (_, label) ] when List.length positional = List.length unlabelled_parameters + 1 ->
         let at = extra.value.expression_span in
         let source = Option.value (Diagnostic.source_line at.file at.line) ~default:"" in
         let text =
           if at.end_line = at.line then String.sub source (at.column - 1) (at.end_column - at.column) else ""
         in
         if text <> "" then
           refuse context ~fix:(Printf.sprintf "`%s: %s`" label text) at
             "a labelled parameter is written with its label at the call (D42, standard 5.3)"
     | _ -> ());
    refuse context
      ~what:(Printf.sprintf "%s takes %d unlabelled argument%s" (quote function_name) (List.length unlabelled_parameters)
               (if List.length unlabelled_parameters = 1 then "" else "s"))
      extra.value.expression_span why
  end;
  let given = Hashtbl.create 8 in
  List.iteri (fun i (a : argument) -> Hashtbl.replace given (fst (List.nth unlabelled_parameters i)) a.value) positional;
  List.iter
    (fun (a : argument) ->
      let label = Option.get a.label in
      match List.find_opt (fun (_, l) -> l = label.text) labels with
      | None ->
          refuse context ~what:(Printf.sprintf "%s has no label %s" (quote function_name) (quote (label.text ^ ":"))) label.span why
      | Some (parameter, _) ->
          if Hashtbl.mem given parameter then
            refuse context ~what:(Printf.sprintf "%s is given twice" (quote (label.text ^ ":"))) label.span why;
          Hashtbl.replace given parameter a.value)
    labelled;
  List.map
    (fun (parameter, parameter_type) ->
      match Hashtbl.find_opt given parameter with
      | Some value ->
          let c = check_expression fctx ~expected:(Some parameter_type) value in
          expect_type context parameter_type c;
          `Given (fit context parameter_type c)
      | None -> (
          match List.assoc_opt parameter defaults with
          | Some default -> `Default (parameter, default, parameter_type)
          | None ->
              let what =
                match List.assoc_opt parameter labels with
                | Some l -> Printf.sprintf "%s needs %s" (quote function_name) (quote (l ^ ":"))
                | None -> Printf.sprintf "%s needs `$%s`" (quote function_name) parameter
              in
              refuse context ~what span "every parameter without a default is given (D42, standard 5.3)"))
    parameters

(* A call of the program's own function. [settings] are a preset chain's values; [receiver] is the
   value a method is called on, given as its first argument. *)
and check_user_call ?expected fctx span (f : function_info) (settings : (name * expression) list) (receiver : C.expression option) arguments =
  let context = fctx.context in
  let f = if f.declaration.type_parameters = [] then f else instantiate fctx span f expected arguments in
  let declaration = f.declaration in
  (* trace: D41 *)
  if fctx.info.baked && not f.baked then
    refuse context
      ~what:(Printf.sprintf "%s isn't `fn.pure.baked`, so a baked function can't call it" (quote f.full_name)) span
      "a `fn.pure.baked` function can run while compiling, so it calls only others that can (D41, standard 5.2)";
  if fctx.info.pure && not f.pure then
    refuse context
      ~what:(Printf.sprintf "%s isn't `fn.pure`, so a pure function can't call it" (quote f.full_name)) span
      "a pure function calls only pure functions (D41, standard 5.2)";
  let parameters = List.map2 (fun p t -> (p.parameter.text, t)) declaration.parameters f.parameter_types in
  let parameters, receiver_value =
    match receiver, parameters with
    | Some r, _ :: rest -> (rest, [ r ])
    | _ -> (parameters, [])
  in
  let labels = List.map (fun (v, l) -> (v.text, l.text)) declaration.labels in
  let defaults =
    List.map (fun ((v : name), e) -> (v.text, e)) settings
    @ List.filter_map
        (fun ((v : name), e) -> if List.exists (fun ((s : name), _) -> s.text = v.text) settings then None else Some (v.text, e))
        declaration.defaults
  in
  let checked = check_arguments fctx span ~function_name:f.full_name ~parameters ~labels ~defaults arguments in
  let arguments =
    List.map
      (function
        | `Given c -> c
        | `Default (_, default, parameter_type) ->
            (* A default or preset is a value written in the declaration, checked with no variables. *)
            let empty = { fctx with scopes = [ Hashtbl.create 1 ] } in
            check_expression empty ~expected:(Some parameter_type) default)
      checked
  in
  { C.kind = C.Call_function { function_id = f.function_id; arguments = receiver_value @ arguments }; type_ = f.result_type; span }

and check_std_call fctx span (s : Std_library.signature) arguments =
  let context = fctx.context in
  if fctx.info.pure then
    refuse context ~what:(Printf.sprintf "%s isn't pure, so a pure function can't call it" (quote s.std_name)) span
      "a pure function calls only pure functions; no I/O (D41, standard 5.2)";
  let parameters = List.mapi (fun i t -> ("p" ^ string_of_int i, t)) s.parameter_types in
  let checked = check_arguments fctx span ~function_name:s.std_name ~parameters ~labels:[] ~defaults:[] arguments in
  let arguments = List.map (function `Given c -> c | `Default _ -> assert false) checked in
  (* trace: D11 *)
  (if s.std_name = "exit" then
     match arguments with
     | [ { C.kind = C.Constant code; span = code_span; _ } ] ->
         let n = Value.integer_to_z code in
         (* trace: D11, D139 — exit takes Int[min: 0, max: 117] *)
         if Z.lt n Z.zero || Z.gt n (Z.of_int 117) then
           refuse context ~what:(Printf.sprintf "`exit` takes a code from 0 to 117, and this is %s" (Z.to_string n))
 code_span
             "programs use 0 to 117 for their own reasons (D11, D139, standard 13.2)"
     | _ -> ());
  { C.kind = C.Call_builtin { builtin = { C.builtin_name = s.std_name; fails = s.fails; run = s.run }; arguments }; type_ = s.result; span }

(* The variable at the root of a value, such as `$r` in `$r.items`. *)
and root_variable (x : expression) =
  match x.expression_kind with
  | Syntax.Variable name -> Some (name, x.expression_span)
  | Syntax.Member (inner, _) | Syntax.Index { target = inner; _ } | Syntax.Key_index { target = inner; _ }
  | Syntax.Grouped inner -> root_variable inner
  | _ -> None

(* A method that changes its value needs the value to be able to change (D43). *)
and require_changeable fctx (receiver : expression) ~(method_text : string) =
  let context = fctx.context in
  let why = "calling a method that changes its value on a value that can't change is refused (D43, standard 5.4)" in
  match root_variable receiver with
  | None ->
      refuse context ~what:(Printf.sprintf "%s changes its value, and this value can't change" (quote method_text))
        receiver.expression_span why
  | Some (name, name_span) -> (
      match find_variable fctx name with
      | Some info when info.is_loop_variable ->
          refuse context ~what:(Printf.sprintf "`$%s` is the loop's own variable, which can't be changed inside the loop" name)
            name_span "the loop's own variable can't be changed inside the loop (D37, standard 4.7)"
      | Some info when not info.is_mutable ->
          refuse context ~what:(Printf.sprintf "%s changes `$%s`, which isn't `mut`" (quote method_text) name) name_span why
      | _ -> ())

(* A list type's length bounds, if it has any (D135). *)
and list_bounds (t : Types.t) : Types.bounds option =
  match t with
  | Types.Bounded (_, b) when b.len_min <> None || b.len_max <> None -> Some b
  | Types.Bounded (t, _) | Types.New (_, t) -> list_bounds t
  | _ -> None

(* An Array's reading methods are a list's (D135). *)
and check_method_call_on_list fctx span (target : C.expression) receiver (as_list : Types.t) words arguments (_ : int option) =
  check_method_call_checked fctx span { target with type_ = as_list } receiver words arguments

(* $value.method(...), $value.len.bytes(), $r.items.len(): fields first, then a method and its narrowings. *)
and check_method_call fctx span (base : expression) (words : name list) arguments =
  let context = fctx.context in
  let base_checked = check_expression fctx ~expected:None base in
  (* walk through fields while more than one word is left *)
  let rec walk (value : C.expression) (source : expression) (words : name list) =
    match words with
    | field :: (_ :: _ as rest) -> (
        match underlying value.type_ with
        | Types.Struct struct_name
          when List.exists (fun (n, _, _) -> n = field.text) (Hashtbl.find context.structs struct_name).resolved_fields ->
            let _, t, _ = List.find (fun (n, _, _) -> n = field.text) (Hashtbl.find context.structs struct_name).resolved_fields in
            let source = { expression_kind = Syntax.Member (source, field); expression_span = Span.join source.expression_span field.span } in
            walk { C.kind = C.Field (value, field.text); type_ = t; span = source.expression_span } source rest
        | _ -> (value, source, words))
    | _ -> (value, source, words)
  in
  let target, receiver, words = walk base_checked base words in
  check_method_call_checked fctx span target receiver words arguments

and check_method_call_checked fctx span (target : C.expression) (receiver : expression) (words : name list) arguments =
  let context = fctx.context in
  let method_name = List.hd words in
  let narrowings = List.map (fun n -> n.text) (List.tl words) in
  let method_text = String.concat "." (List.map (fun n -> n.text) words) in
  let builtin ?(changes = false) ?(fails = []) name run result extra =
    if changes then require_changeable fctx receiver ~method_text;
    { C.kind = C.Call_builtin { builtin = { C.builtin_name = name; fails; run }; arguments = target :: extra }; type_ = result; span }
  in
  let positional count =
    if List.length arguments <> count || List.exists (fun (a : argument) -> a.label <> None) arguments then
      refuse context
        ~what:(Printf.sprintf "%s takes %s" (quote method_text)
                 (match count with 0 -> "no arguments" | 1 -> "one argument" | n -> string_of_int n ^ " arguments"))
        span "each built-in method's arguments are set out in std (D136, standard 13.3)";
    List.map (fun (a : argument) -> a.value) arguments
  in
  let position_argument (a : argument) =
    match a.label with
    | Some { text = "pos"; _ } -> Syntax.Pos
    | Some { text = "offset"; _ } -> Syntax.Offset
    | _ ->
        refuse context ~what:"a position says how it counts: `pos:` from 1, or `offset:` from 0" a.value.expression_span
          "positions say how they count (D17, D136, standard 13.3)"
  in
  let checked_item item_type (x : expression) =
    let c = check_expression fctx ~expected:(Some item_type) x in
    expect_type context item_type c;
    check_hand_off fctx c x;
    let c = fit context item_type c in
    { c with kind = C.Copy c }
  in
  let checked_int (x : expression) =
    let c = check_expression fctx ~expected:(Some Types.int) x in
    expect_type context Types.int c;
    c
  in
  let not_built_method t =
    not_built context ~what:(Printf.sprintf "the method %s on %s isn't built in the oracle yet" (quote method_text) (type_text t))
      method_name.span "values have methods, called with a dot (D40, standard 13.3)"
  in
  match underlying target.type_, method_name.text, narrowings with
  | Types.Unknown, _, _ -> raise Skip
  (* trace: D130, D131 *)
  | Types.String, "len", ([] | [ "graphemes" ]) ->
      ignore (positional 0); builtin "len" (Methods.string_length `Graphemes) Types.int []
  | Types.String, "len", [ "bytes" ] -> ignore (positional 0); builtin "len.bytes" (Methods.string_length `Bytes) Types.int []
  | Types.String, "len", [ "code_points" ] ->
      ignore (positional 0); builtin "len.code_points" (Methods.string_length `Code_points) Types.int []
  | (Types.List _ | Types.Map _ | Types.Array _), "len", [] -> ignore (positional 0); builtin "len" Methods.length Types.int []
  (* trace: D135 — an Array has nothing that changes its length *)
  | Types.Array _, ("add" | "remove" | "clear"), [] ->
      refuse context ~what:(Printf.sprintf "an `Array` has a fixed length, so it has no %s" (quote method_name.text))
        method_name.span "an `Array` has nothing that changes its length (D135, standard 13.3)"
  | Types.Array (item, n), _, _ -> check_method_call_on_list fctx span target receiver (Types.List item) words arguments (Some n)
  (* trace: D136 *)
  | Types.List item, "add", [] -> (
      let run f = Methods.within_length (list_bounds target.type_) f in
      match arguments with
      | [ { label = None; value } ] -> builtin ~changes:true "add" (run Methods.add) Types.Nothing [ checked_item item value ]
      | [ { label = None; value }; at ] ->
          let counting = position_argument at in
          builtin ~changes:true "add" (run (Methods.add_at counting)) Types.Nothing [ checked_item item value; checked_int at.value ]
      | _ ->
          refuse context ~what:"`add` takes an item, and maybe `pos:` or `offset:`" span
            "each built-in method's arguments are set out in std (D136, standard 13.3)")
  | Types.List item, "remove", [] -> (
      match arguments with
      | [ at ] ->
          let counting = position_argument at in
          builtin ~changes:true "remove" (Methods.within_length (list_bounds target.type_) (Methods.remove counting)) item [ checked_int at.value ]
      | _ ->
          refuse context ~what:"`remove` takes `pos:` or `offset:`" span
            "each built-in method's arguments are set out in std (D136, standard 13.3)")
  | Types.List _, "clear", [] ->
      ignore (positional 0);
      builtin ~changes:true "clear" (Methods.within_length (list_bounds target.type_) Methods.clear) Types.Nothing []
  | Types.List item, "contains", [] -> (
      match positional 1 with
      | [ x ] ->
          let c = check_expression fctx ~expected:(Some item) x in
          expect_type context item c;
          builtin "contains" Methods.contains Types.Bool [ c ]
      | _ -> raise Skip)
  | Types.List item, "first", [] -> ignore (positional 0); builtin "first" (Methods.first_or_last `First) item []
  | Types.List item, "last", [] -> ignore (positional 0); builtin "last" (Methods.first_or_last `Last) item []
  (* trace: D38 *)
  (* trace: D138 *)
  | Types.Map (_, key_type, value_type), ("get" | "contains" | "remove"), [] -> (
      match arguments with
      | [ { label = Some { text = "key"; _ }; value = key } ] -> (
          let k = check_expression fctx ~expected:(Some key_type) key in
          expect_type context key_type k;
          match method_name.text with
          | "get" -> builtin ~fails:[ "not_found" ] "get" Methods.map_get value_type [ k ]
          | "contains" -> builtin "contains" Methods.map_contains Types.Bool [ k ]
          | _ -> builtin ~changes:true "remove" Methods.map_remove value_type [ k ])
      | _ ->
          refuse context ~what:(Printf.sprintf "%s takes `key:`" (quote method_text)) span
            "a map is read and changed by key (D138, standard 13.3)")
  | Types.Map (_, key_type, _), "keys", [ "sorted" ] -> (
      ignore (positional 0);
      match underlying key_type with
      | Types.Integer _ | Types.String | Types.Float Types.F64 | Types.Rational ->
          builtin "keys.sorted" Methods.map_keys_sorted (Types.List key_type) []
      | t ->
          not_designed context ~what:(Printf.sprintf "how %s keys are ordered isn't decided yet" (type_text t))
            method_name.span "not decided yet (D138, standard 12.1)")
  | Types.List item, "sum", [] -> (
      ignore (positional 0);
      match underlying item with
      | Types.Integer _ | Types.Float _ | Types.Rational | Types.Decimal -> builtin "sum" (Methods.sum (underlying item)) item []
      | _ ->
          refuse context ~what:(Printf.sprintf "`sum` adds numbers, and these are %s" (type_text item)) method_name.span
            "`sum` is the exact sum of a list of numbers (D38, standard 13.3)")
  | (Types.Struct type_name | Types.Union type_name), _, _ -> (
      (* a method from the type's family: a function whose first parameter is `$self` (D43) *)
      match find_function context ~from_file:fctx.info.file ~span:method_name.span (type_name ^ "." ^ method_name.text) with
      | Some f when (match f.declaration.parameters with p :: _ -> p.parameter.text = "self" | [] -> false) ->
          if narrowings <> [] then not_built_method target.type_;
          let self = List.hd f.declaration.parameters in
          if self.self_mutable then require_changeable fctx receiver ~method_text;
          check_user_call fctx span f [] (Some target) arguments
      | _ -> (
          match family_function_on fctx span target receiver words arguments with
          | Some call -> call
          | None ->
              refuse context
                ~what:(Printf.sprintf "%s has no method called %s" (type_text target.type_) (quote method_name.text))
                method_name.span "a type's methods are the functions in its family with `$self` first (D43, standard 5.4)"))
  | t, _, _ -> (
      match family_function_on fctx span target receiver words arguments with
      | Some call -> call
      | None -> not_built_method t)

(* `$x.show()`, `$x.show.stored()`, `$x.show.hex()`: a family's function, its preset or its narrowing,
   called with a dot on a value that matches its first parameter (D40, D44, D45, standard 5.6). *)
and family_function_on fctx span (target : C.expression) receiver (words : name list) arguments : C.expression option =
  let context = fctx.context in
  let all = List.map (fun (n : name) -> n.text) words in
  let rec longest k =
    if k = 0 then None
    else
      let name = String.concat "." (List.filteri (fun i _ -> i < k) all) in
      match Hashtbl.find_all context.functions name with
      | _ :: _ -> (
          match find_function context ~from_file:fctx.info.file ~span name with
          | Some f -> Some (f, List.filteri (fun i _ -> i >= k) words)
          | None -> None)
      | [] -> longest (k - 1)
  in
  match longest (List.length all) with
  | Some (f, presets)
    when (match f.parameter_types with first :: _ -> Types.same first target.type_ | [] -> false)
         && f.declaration.type_parameters = [] ->
      ignore receiver;
      let settings =
        List.concat_map
          (fun (preset : name) ->
            match Hashtbl.find_opt context.presets (f.full_name ^ "." ^ preset.text) with
            | Some s -> s
            | None ->
                refuse context ~what:(Printf.sprintf "%s has no preset called %s" (quote f.full_name) (quote preset.text))
                  preset.span "`preset name [...]` fills in some of the family function's labelled arguments (D45, standard 5.6)")
          presets
      in
      Some (check_user_call fctx span f settings (Some target) arguments)
  | _ -> None

(* ---------- Statements ---------- *)

(* A value stored where it can change is its own copy, so nothing frozen changes through it (D6, D52). *)
let stored (c : C.expression) : C.expression = { c with kind = C.Copy c }

let rec check_block fctx (statements : statement list) : C.statement list =
  in_scope fctx (fun () -> check_statements fctx statements)

and check_statements fctx statements = List.concat_map (check_statement fctx) statements

and check_statement fctx (s : statement) : C.statement list =
  let context = fctx.context in
  let span = s.statement_span in
  let make kind = [ { C.statement_kind = kind; statement_span = span } ] in
  match s.statement_kind with
  | Let { is_mutable; baked; variable; declared_type; value } -> (
      if baked && is_mutable then begin
        report context (Diagnostic.make ~span ~what:"a `let mut baked` isn't decided yet" Diagnostic.Not_designed_yet
                          "not decided yet (D5, standard 3.1)");
        []
      end
      else
        let declared = try resolve_type context declared_type with Skip -> Types.Unknown in
        let existing = find_variable fctx variable.text in
        (* the variable exists from here on, even if its value has an error (D13) *)
        let checked_value = try Some (check_value fctx declared value) with Skip -> None in
        (* trace: D5 — a baked value is made only of what's known when compiling *)
        let checked_value =
          match checked_value with
          | Some v when baked -> (try require_baked fctx v; Some v with Skip -> None)
          | other -> other
        in
        (match existing with
         | Some _ ->
             (* trace: D36 *)
             error context ~fix:"`shadow`" (keyword_span span "let")
               "declaring an existing name is refused; `shadow` gives it a new value (D36, standard 3.4)"
         | None -> ());
        let info = add_variable fctx ~name:variable ~variable_type:declared ~is_mutable ~assigned:true () in
        if not is_mutable then info.is_parameter <- names_a_parameter fctx value declared;
        if baked then begin
          Hashtbl.replace context.baked_variables info.variable.variable_id ();
          Option.iter (fun v -> context.baked_values <- context.baked_values @ [ (info.variable, v) ]) checked_value
        end;
        match checked_value with
        | Some v -> make (C.Define (info.variable, if is_mutable then stored v else v))
        | None -> [])
  | Decl { is_mutable; variable; declared_type } ->
      let declared = try resolve_type context declared_type with Skip -> Types.Unknown in
      (match find_variable fctx variable.text with
       | Some _ ->
           error context ~fix:"`shadow`" (keyword_span span "decl")
             "declaring an existing name is refused; `shadow` gives it a new value (D36, standard 3.4)"
       | None -> ());
      ignore (add_variable fctx ~name:variable ~variable_type:declared ~is_mutable ~assigned:false ());
      []
  | Assign { variable; value } -> (
      match find_variable fctx variable.text with
      | None ->
          error context ~what:(Printf.sprintf "there's no variable called `$%s` here" variable.text) variable.span
            "`assign` gives a `decl` its first value (D34, standard 3.3)";
          []
      | Some info ->
          if info.assigned then begin
            (* trace: D34 *)
            error context ~fix:(quote "change") (keyword_span span "assign")
              "`assign` gives a `decl` its first value, exactly once on each path (D34, standard 3.3)";
            []
          end
          else
            match check_value fctx info.variable_type value with
            | v -> info.assigned <- true; make (C.Set (info.variable, if info.is_mutable then stored v else v))
            | exception Skip -> info.assigned <- true; [])
  | Shadow { is_mutable; variable; declared_type; value } -> (
      let declared = try resolve_type context declared_type with Skip -> Types.Unknown in
      let checked_value = try Some (check_value fctx declared value) with Skip -> None in
      (match find_variable fctx variable.text with
       | None ->
           (* trace: D36 *)
           error context ~fix:"`let`" (keyword_span span "shadow")
             "`shadow` gives an existing name a new value (D36, standard 3.4)"
       | Some _ -> ());
      let info = add_variable fctx ~name:variable ~variable_type:declared ~is_mutable ~assigned:true () in
      match checked_value with Some v -> make (C.Define (info.variable, if is_mutable then stored v else v)) | None -> [])
  | Change { target; value } -> (
      try check_change fctx span target value with Skip -> [])
  | Expression_statement e -> (
      try
        let c = check_expression fctx ~expected:None e in
        (match c.type_ with
         | Types.Nothing | Types.Unknown -> ()
         | t -> (
             match c.kind with
             | C.Call_function _ | C.Call_builtin _ ->
                 error context ~what:(Printf.sprintf "this call gives %s, and nothing uses it" (type_text t)) e.expression_span
                   "a value nobody uses is a mistake; `?? ignore` is only for failures (D48, standard 6.3)"
             | _ ->
                 error context ~what:"this value isn't used" e.expression_span
                   "a line does something: a call, a declaration or an update (D19, standard 1.1)"));
        make (C.Evaluate c)
      with Skip -> [])
  | Return_early -> (
      match fctx.info.result_type with
      | Types.Nothing -> make (C.Return None)
      | t ->
          error context ~what:(Printf.sprintf "this function returns %s, so it says `return` and a value" (type_text t)) span
            "a function with a result always uses `return $value` (D26, standard 5.1)";
          [])
  | Return value -> (
      match fctx.info.result_type with
      | Types.Nothing ->
          error context ~fix:"`return early`" span
            "a function that returns nothing leaves early with `return early` (D26, standard 5.1)";
          []
      | t -> (
          try
            let v = check_value ~escapes:true fctx t value in
            make (C.Return (Some v))
          with Skip -> []))
  | If { branches; else_body } -> check_if fctx span branches else_body
  | While { loop_name; condition; body } ->
      let condition = try Some (check_expression fctx ~expected:(Some Types.Bool) condition) with Skip -> None in
      Option.iter (fun c -> try expect_type context Types.Bool c with Skip -> ()) condition;
      let loop_id = fresh_id context in
      fctx.loops <- (Option.map (fun n -> n.text) loop_name, loop_id) :: fctx.loops;
      let body = check_block fctx body in
      fctx.loops <- List.tl fctx.loops;
      (match condition with Some condition -> make (C.While { loop_id; condition; body }) | None -> [])
  | For { loop_name; variable; iterable; at; handling; body } -> check_for fctx span loop_name variable iterable at handling body
  | Break name -> (
      match name, fctx.loops with
      | None, (_, id) :: _ -> make (C.Break id)
      | None, [] ->
          error context ~what:"`break` is outside any loop" span "`break` leaves the innermost loop (D30, standard 4.6)";
          []
      | Some n, loops -> (
          match List.find_opt (fun (name, _) -> name = Some n.text) loops with
          | Some (_, id) -> make (C.Break id)
          | None ->
              error context ~what:(Printf.sprintf "no loop around this is called %s" (quote n.text)) n.span
                "`break name` leaves that loop and every loop inside it (D31, standard 4.6)";
              []))
  | Broken_block { declares; body } ->
      in_scope fctx (fun () ->
          declare_recovered fctx declares;
          ignore (check_statements fctx body));
      []
  | Broken_statement declares ->
      declare_recovered fctx declares;
      []
  | Unfinished { what; why; designed } ->
      report context
        (Diagnostic.make ~span ~what (if designed then Diagnostic.Not_built_yet else Diagnostic.Not_designed_yet) why);
      []
  | Match { subject; match_arms } -> check_match fctx span subject match_arms
  | Fail { failure; fields } -> (
      (* trace: D48 — `fail` raises one of the function's listed failures, and leaves it *)
      let suffix = "." ^ failure.text in
      let in_full =
        List.filter
          (fun (n, _) -> String.length n > String.length suffix
                         && String.sub n (String.length n - String.length suffix) (String.length suffix) = suffix)
          fctx.info.failures
      in
      match List.assoc_opt failure.text fctx.info.failures, in_full with
      | None, [ (full, _) ] ->
          (* trace: D140 *)
          error context ~fix:(quote full) failure.span "a family's failure is written in full (D140, standard 6.2)";
          []
      | None, _ ->
          error context
            ~what:(Printf.sprintf "%s isn't listed after `fails` on %s" (quote failure.text)
                     (if fctx.info.full_name = "" then "this function" else quote fctx.info.full_name))
            failure.span "a function lists the failures it can raise on its opening line (D48, standard 6.2)";
          []
      | Some shape, _ -> (
          try
            let seen = Hashtbl.create 4 in
            let given =
              List.map
                (fun { field; field_value } ->
                  match List.assoc_opt field.text shape with
                  | None ->
                      refuse context ~what:(Printf.sprintf "%s carries no %s" (quote failure.text) (quote field.text)) field.span
                        "a failure can carry data (D48, standard 6.2)"
                  | Some t ->
                      Hashtbl.replace seen field.text ();
                      (field.text, check_value fctx t field_value))
                fields
            in
            List.iter
              (fun (n, _) ->
                if not (Hashtbl.mem seen n) then
                  refuse context ~what:(Printf.sprintf "%s needs %s" (quote failure.text) (quote n)) span
                    "a failure's data is all given (D48, standard 6.2)")
              shape;
            make (C.Fail { failure = failure.text; fields = given })
          with Skip -> []))
  | Instead value -> (
      match fctx.arm_values with
      | Some t :: _ -> (
          try make (C.Instead (check_value fctx t value)) with Skip -> [])
      | None :: _ ->
          error context ~what:"this call gives nothing, so there's nothing for `instead` to give" span
            "`instead` gives the value used in place of the failed call (D48, standard 6.3)";
          []
      | [] ->
          error context ~what:"`instead` is only used in an arm that handles a failure" span
            "`instead` gives the value used in place of the failed call (D48, standard 6.3)";
          [])

(* Variables a refused line still creates, so nothing that uses them is refused because of it (D13). *)
and declare_recovered fctx (declares : recovered list) =
  List.iter
    (fun r ->
      let t =
        match r.recovered_type with
        | Some t -> (try resolve_type fctx.context t with Skip -> Types.Unknown)
        | None -> Types.Unknown
      in
      ignore (add_variable fctx ~name:r.recovered_name ~variable_type:t ~is_mutable:r.recovered_mutable ~assigned:true ()))
    declares

(* What `let baked` may be made of: literals, baked values, and `fn.pure.baked` calls (D5, D41). *)
and require_baked fctx (value : C.expression) =
  let context = fctx.context in
  let why = "`let baked` declares a value known when compiling (D5, standard 3.1)" in
  let pure_methods = [ "len"; "len.bytes"; "len.code_points"; "contains"; "first"; "last"; "sum"; "keys.sorted"; "get" ] in
  let rec walk (x : C.expression) =
    match x.kind with
    | C.Constant _ -> ()
    | C.Read v ->
        if not (Hashtbl.mem context.baked_variables v.variable_id) then
          refuse context ~what:(Printf.sprintf "`$%s` isn't known when compiling" v.variable_name) x.span why
    | C.Call_function { function_id; arguments } ->
        (match Hashtbl.find_opt context.function_by_id function_id with
         | Some f when f.baked -> ()
         | Some f ->
             refuse context ~what:(Printf.sprintf "%s isn't `fn.pure.baked`, so it can't run while compiling" (quote f.full_name))
               x.span "only a `fn.pure.baked` function can run while compiling (D41, standard 5.2)"
         | None -> ());
        List.iter walk arguments
    | C.Call_builtin { builtin; arguments } ->
        if not (List.mem builtin.builtin_name pure_methods) then
          refuse context ~what:(Printf.sprintf "%s can't run while compiling" (quote builtin.builtin_name)) x.span
            "only a `fn.pure.baked` function can run while compiling (D41, standard 5.2)";
        List.iter walk arguments
    | C.Join xs | C.List_literal xs -> List.iter walk xs
    | C.Chain { operands; _ } -> List.iter walk operands
    | C.Map_literal (_, entries) -> List.iter (fun (k, v) -> walk k; walk v) entries
    | C.Build_struct { fields; _ } | C.Build_union { fields; _ } -> List.iter (fun (_, v) -> walk v) fields
    | C.Arithmetic { left; right; _ } | C.Compare { left; right; _ } | C.Logic { left; right; _ } -> walk left; walk right
    | C.Convert { value; _ } | C.Negate value | C.Not value | C.Field (value, _) | C.Copy value | C.Ignore value
    | C.Pass_up value | C.Check_fits { value; _ } | C.Fits_test { value; _ } | C.Is_case { value; _ } -> walk value
    | C.Index { target; position; _ } -> walk target; walk position
    | C.Key_index { target; key } -> walk target; walk key
    | C.Range { from; ending; step_by; _ } -> walk from; walk ending; Option.iter walk step_by
    | C.Fallback { value; instead } -> walk value; walk instead
    | C.Otherwise { value; _ } -> walk value
  in
  walk value

(* A value landing in a place of a known type. *)
and check_value ?(escapes = false) fctx (declared : Types.t) (value : expression) : C.expression =
  let v = check_expression fctx ~expected:(Some declared) value in
  expect_type fctx.context declared v;
  check_hand_off ~escapes fctx v value;
  fit fctx.context declared v

(* A frozen name for a parameter's inside is still the parameter's (D139). *)
and names_a_parameter fctx (value : expression) (t : Types.t) =
  Types.has_inside_that_changes t
  && (match root_variable value with
      | Some (name, _) -> (match find_variable fctx name with Some info -> info.is_parameter | None -> false)
      | None -> false)

and check_change fctx span target value =
  let context = fctx.context in
  let why = "`change` works on what can change (D33, D43, standard 3.5)" in
  let rec root (x : expression) =
    match x.expression_kind with
    | Syntax.Variable name -> Some (name, x.expression_span)
    | Syntax.Member (inner, _) | Syntax.Index { target = inner; _ } | Syntax.Key_index { target = inner; _ } -> root inner
    | _ -> None
  in
  match root target with
  | None -> refuse context ~what:"`change` updates a variable, one of its fields or one of its items" target.expression_span why
  | Some (name, name_span) -> (
      match find_variable fctx name with
      | None ->
          refuse context ~what:(Printf.sprintf "there's no variable called `$%s` here" name) name_span
            "every new name says how it's made (D5, D34, standard 3.1)"
      | Some info ->
          if info.is_loop_variable then
            refuse context ~what:(Printf.sprintf "`$%s` is the loop's own variable, which can't be changed inside the loop" name)
              name_span "the loop's own variable can't be changed inside the loop (D37, standard 4.7)";
          if not info.is_mutable then
            refuse context
              ~what:(Printf.sprintf "`$%s` can't change: it isn't `mut`" name) name_span why;
          if not info.assigned then
            refuse context ~fix:(quote "assign") (keyword_span span "change") "`assign` gives a `decl` its first value (D34, standard 3.3)";
          match target.expression_kind with
          | Syntax.Variable _ ->
              let declared = match info.variable_type with Types.Case (u, _) -> Types.Union u | t -> t in
              let v = check_value fctx declared value in
              (* trace: D97 — a change ends what a case test knew *)
              (match info.variable_type with
               | Types.Case _ -> info.variable_type <- declared; info.case_known_until <- Some (keyword_span span "change")
               | _ -> ());
              [ { C.statement_kind = C.Set (info.variable, stored v); statement_span = span } ]
          | Syntax.Member (inner, field) ->
              let t = check_expression fctx ~expected:None target in
              let inner = check_expression fctx ~expected:None inner in
              let v = check_value fctx t.type_ value in
              [ { C.statement_kind = C.Set_field { target = inner; field = field.text; value = stored v }; statement_span = span } ]
          | Syntax.Index { target = inner; counting; position } ->
              let t = check_expression fctx ~expected:None target in
              let inner = check_expression fctx ~expected:None inner in
              let position = check_expression fctx ~expected:(Some Types.int) position in
              let v = check_value fctx t.type_ value in
              [ { C.statement_kind = C.Set_index { target = inner; counting; position; value = stored v }; statement_span = span } ]
          | Syntax.Key_index { target = inner; key } ->
              let t = check_expression fctx ~expected:None target in
              let inner = check_expression fctx ~expected:None inner in
              let key_checked =
                match underlying inner.type_ with
                | Types.Map (_, key_type, _) ->
                    let k = check_expression fctx ~expected:(Some key_type) key in
                    expect_type context key_type k;
                    k
                | _ -> raise Skip
              in
              let v = check_value fctx t.type_ value in
              (* trace: D138 *)
              [ { C.statement_kind = C.Set_key { target = inner; key = key_checked; value = stored v }; statement_span = span } ]
          | _ -> refuse context ~what:"`change` updates a variable, one of its fields or one of its items" target.expression_span why)

and check_if fctx span branches else_body =
  let context = fctx.context in
  (* Which `decl`s get assigned on every path (D34). *)
  let unassigned () =
    List.concat_map (fun scope -> Hashtbl.fold (fun _ info acc -> if info.assigned then acc else info :: acc) scope []) fctx.scopes
  in
  let before = unassigned () in
  let assigned_in_all = ref None in
  let record () =
    let now = List.filter (fun info -> info.assigned) before in
    (match !assigned_in_all with
     | None -> assigned_in_all := Some now
     | Some previous -> assigned_in_all := Some (List.filter (fun i -> List.memq i now) previous));
    List.iter (fun info -> info.assigned <- false) before
  in
  let checked_branches =
    List.filter_map
      (fun { condition; branch_body } ->
        match condition with
        | Plain c ->
            let c = try Some (check_expression fctx ~expected:(Some Types.Bool) c) with Skip -> None in
            Option.iter (fun c -> try expect_type context Types.Bool c with Skip -> ()) c;
            let body = check_block fctx branch_body in
            record ();
            Option.map (fun c -> (c, body)) c
        | Case_test (value, tested) -> (
            let checked = try Some (check_case_test fctx value tested) with Skip -> None in
            match checked with
            | None ->
                ignore (check_block fctx branch_body);
                record ();
                None
            | Some (condition, narrowed) ->
                let body =
                  in_scope fctx (fun () ->
                      (* inside, the value is known to be that case (D97) *)
                      (match value.expression_kind, narrowed with
                       | Syntax.Variable name, Some case_type -> (
                           match find_variable fctx name with
                           | Some info ->
                               Hashtbl.replace (List.hd fctx.scopes) name { info with variable_type = case_type; case_known_until = None }
                           | None -> ())
                       | _ -> ());
                      check_statements fctx branch_body)
                in
                (* what the inner copy learnt about assignment goes back to the variable *)
                record ();
                Some (condition, body)))
      branches
  in
  let else_checked = Option.map (fun body -> let b = check_block fctx body in record (); b) else_body in
  (* Without an `else`, the path that skips every branch assigns nothing. *)
  if else_body = None then assigned_in_all := Some [];
  List.iter (fun info -> info.assigned <- List.memq info (Option.value !assigned_in_all ~default:[])) before;
  if List.length checked_branches <> List.length branches then []
  else [ { C.statement_kind = C.If (checked_branches, else_checked); statement_span = span } ]

(* `if <value>: <type>.<case>:` (D97): the condition, and the type the value has inside. *)
and check_case_test fctx (value : expression) (tested : type_expression) : C.expression * Types.t option =
  let context = fctx.context in
  let checked = check_expression fctx ~expected:None value in
  match tested.type_kind with
  | Named_type { words = [ union_name; case_name ]; arguments = []; details = []; my = false } -> (
      match underlying checked.type_ with
      | Types.Unknown -> raise Skip
      | Types.Union u | Types.Case (u, _) when u = union_name -> (
          let info = Hashtbl.find context.unions u in
          match List.assoc_opt case_name info.resolved_cases with
          | None ->
              refuse context ~what:(Printf.sprintf "%s has no case called %s" (quote u) (quote case_name)) tested.type_span
                "a union's cases are its narrowings (D97, standard 2.4a)"
          | Some _ ->
              ( { C.kind = C.Is_case { value = checked; case_name }; type_ = Types.Bool; span = tested.type_span },
                Some (Types.Case (u, case_name)) ))
      | t ->
          refuse context ~what:(Printf.sprintf "this is %s, and the test asks about %s" (type_text t) (quote (union_name ^ "." ^ case_name)))
            tested.type_span "the case test asks which case a value is (D97, standard 4.5a)")
  | Named_type { details = _ :: _; _ } ->
      (* trace: D135 — the case test works on bounds *)
      let target = resolve_type context tested in
      if not (Types.same target checked.type_) then
        refuse context ~what:(Printf.sprintf "this is %s, and the test asks about %s" (type_text checked.type_) (type_text target))
          tested.type_span "the case test asks whether a value fits a type (D97, D135, standard 2.3a)";
      ({ C.kind = C.Fits_test { value = checked; target }; type_ = Types.Bool; span = tested.type_span }, Some target)
  | _ ->
      refuse context ~what:"the case test names a union's case, such as `Status.failed`" tested.type_span
        "`if <value>: <type>.<case>:` tests which case a value is (D97, standard 4.5a)"

(* `match` (D97, D98, D101): every case is covered once, with no catch-all. *)
and check_match fctx span subject (match_arms : match_arms) : C.statement list =
  let context = fctx.context in
  let arms_of = function
    | Match_arms arms -> Some arms
    | Match_with { family; handler; jumps } -> (
        (* trace: D100 *)
        try Some (handler_arms fctx ~family ~handler ~jumps) with Skip -> None)
  in
  match arms_of match_arms with
  | None -> []
  | Some arms -> (
      let checked = try Some (check_expression fctx ~expected:None subject) with Skip -> None in
      let cases =
        match Option.map (fun (c : C.expression) -> underlying c.type_) checked with
        | Some (Types.Union u | Types.Case (u, _)) ->
            Some (u, List.map (fun (name, _) -> name) (Hashtbl.find context.unions u).resolved_cases)
        | Some Types.Bool -> Some ("Bool", [ "true"; "false" ])
        | Some Types.Unknown | None -> None
        | Some t ->
            error context ~what:(Printf.sprintf "`match` works on tagged unions and `Bool`, and this is %s" (type_text t))
              subject.expression_span "integers, strings and ranges use `if` and `else if` (D101, standard 4.5a)";
            None
      in
      let seen = Hashtbl.create 8 in
      let unassigned =
        List.concat_map (fun scope -> Hashtbl.fold (fun _ info acc -> if info.assigned then acc else info :: acc) scope []) fctx.scopes
      in
      let assigned_in_all = ref None in
      let checked_arms =
        List.filter_map
          (fun arm ->
            let arm_ok =
              match cases with
              | None -> false
              | Some (type_name, names) ->
                  if not (List.mem arm.case_name.text names) then begin
                    error context ~what:(Printf.sprintf "%s has no case called %s" (quote type_name) (quote arm.case_name.text))
                      arm.case_name.span "arms use the case's short name (D97, standard 4.5a)";
                    false
                  end
                  else if Hashtbl.mem seen arm.case_name.text then begin
                    error context ~what:(Printf.sprintf "%s is covered twice" (quote arm.case_name.text)) arm.case_name.span
                      "`match` covers every case once (D97, standard 4.5a)";
                    false
                  end
                  else (Hashtbl.add seen arm.case_name.text (); true)
            in
            let binding, body =
              in_scope fctx (fun () ->
                  let binding =
                    Option.map
                      (fun (b : name) ->
                        let t =
                          match cases with
                          | Some ("Bool", _) -> Types.Bool
                          | Some (u, _) when arm_ok -> Types.Case (u, arm.case_name.text)
                          | _ -> Types.Unknown
                        in
                        (add_variable fctx ~name:b ~variable_type:t ~is_mutable:false ~assigned:true ()).variable)
                      arm.binding
                  in
                  (binding, check_statements fctx arm.arm_body))
            in
            let now = List.filter (fun info -> info.assigned) unassigned in
            (match !assigned_in_all with
             | None -> assigned_in_all := Some now
             | Some previous -> assigned_in_all := Some (List.filter (fun i -> List.memq i now) previous));
            List.iter (fun info -> info.assigned <- false) unassigned;
            if arm_ok then Some (arm.case_name.text, binding, body) else None)
          arms
      in
      List.iter (fun info -> info.assigned <- List.memq info (Option.value !assigned_in_all ~default:[])) unassigned;
      match checked, cases with
      | Some subject, Some (_, names) ->
          let missing = List.filter (fun n -> not (Hashtbl.mem seen n)) names in
          if missing <> [] then begin
            (* trace: D97, D99 *)
            error context
              ~what:(Printf.sprintf "this `match` doesn't cover %s" (String.concat ", " (List.map quote missing)))
              (keyword_span span "match") "`match` must cover every case, with no catch-all (D97, D99, standard 4.5a)";
            []
          end
          else if List.length checked_arms <> List.length arms then []
          else [ { C.statement_kind = C.Match { subject; arms = checked_arms }; statement_span = span } ]
      | _ -> [])

and check_for fctx span loop_name (variable : name) iterable at handling body =
  let context = fctx.context in
  let iterable_checked = try Some (check_expression fctx ~expected:None iterable) with Skip -> None in
  let item_type =
    match Option.map (fun (c : C.expression) -> underlying c.type_) iterable_checked with
    | Some Types.Range -> Types.int
    | Some (Types.List item | Types.Array (item, _)) -> item
    | Some (Types.Map (Types.Map_hash, _, _)) ->
        (* trace: D138 *)
        error context ~what:"a `Map.hash` has no order to rely on, so it can't be looped over; `.keys.sorted()` gives an order"
          iterable.expression_span "looping over a `Map.hash` is refused (D138, standard 13.3)";
        Types.Unknown
    | Some (Types.Map _) ->
        report context
          (Diagnostic.make ~span:iterable.expression_span ~what:"what a `for` over a map gives each time isn't decided yet"
             Diagnostic.Not_designed_yet "not decided yet (D138, standard 12.1)");
        Types.Unknown
    | Some Types.Lines -> Types.String
    | Some Types.Unknown | None -> Types.Unknown
    | Some t ->
        error context ~what:(Printf.sprintf "%s can't be gone through with `for`" (type_text t)) iterable.expression_span
          "`for ... in` goes through something (D30, standard 4.6)";
        Types.Unknown
  in
  let can_fail = match iterable_checked with Some { C.type_ = Types.Lines; _ } -> true | _ -> false in
  let checked_handling =
    match handling with
    | None -> Some C.Loop_crash
    | Some h when not can_fail ->
        ignore h;
        error context ~what:"getting this loop's next item can't fail, so there's nothing to handle" iterable.expression_span
          "a failure while a `for` gets its next item is handled on the `for` line (D134, standard 4.6)";
        None
    | Some (Loop_fallback e) -> (
        try
          let c = check_expression fctx ~expected:(Some item_type) e in
          expect_type context item_type c;
          Some (C.Loop_fallback c)
        with Skip -> None)
    | Some Loop_pass_up -> (
        try
          List.iter
            (fun name ->
              if not (List.mem_assoc name fctx.info.failures) then
                refuse context
                  ~what:(Printf.sprintf "getting the next line can fail with %s, and this function doesn't list it" (quote name))
                  iterable.expression_span "`?` passes a failure up, refused unless this function lists it (D48, D134, standard 4.6)")
            [ "not_text" ];
          Some C.Loop_pass_up
        with Skip -> None)
    | Some (Loop_handler { family; handler; jumps }) -> (
        try
          Some (C.Loop_arms (check_handling fctx ~at:iterable.expression_span ~possible:[ ("not_text", []) ] ~gives:item_type
                               (Handler { family; handler; jumps })))
        with Skip -> None)
  in
  let loop_id = fresh_id context in
  fctx.loops <- (Option.map (fun n -> n.text) loop_name, loop_id) :: fctx.loops;
  let result =
    in_scope fctx (fun () ->
        if find_variable fctx variable.text <> None then
          error context ~what:(Printf.sprintf "`$%s` already exists here" variable.text) variable.span
            "declaring an existing name is refused (D36, standard 3.4)";
        let v = add_variable fctx ~is_loop_variable:true ~name:variable ~variable_type:item_type ~is_mutable:false ~assigned:true () in
        let position =
          Option.map
            (fun (counting, (n : name)) ->
              let p = add_variable fctx ~is_loop_variable:true ~name:n ~variable_type:Types.int ~is_mutable:false ~assigned:true () in
              (counting, p.variable))
            at
        in
        let body = check_block fctx body in
        (v, position, body))
  in
  fctx.loops <- List.tl fctx.loops;
  match iterable_checked, checked_handling, result with
  | Some iterable, Some handling, (v, position, body) ->
      [ { C.statement_kind = C.For { loop_id; variable = v.variable; position; iterable; handling; body }; statement_span = span } ]
  | _ -> []

let () = check_statements_ref := check_statements

(* ---------- Declarations ---------- *)

let dummy_declaration =
  { narrowings = []; function_name = { text = ""; span = Span.none }; function_my = false; type_parameters = [];
    parameters = []; result = None; fails = []; labels = []; defaults = []; requires = []; ensures = []; body = [];
    function_span = Span.none; function_visibility = File_only }

(* A generic function's type parameters, each with requirements that exist (D103, D105). *)
let type_parameters_of context (d : function_declaration) =
  List.map
    (fun ((n : name), (r : requirement)) ->
      List.iter
        (fun (requirement : name) ->
          if requirement.text <> "Any" && not (Hashtbl.mem context.interfaces requirement.text)
             && not (Hashtbl.mem context.type_sets requirement.text)
          then
            error context ~what:(Printf.sprintf "%s isn't `Any`, an interface or a type set" (quote requirement.text))
              requirement.span "a type parameter always writes its requirement, even `Any` for none (D103, D105, standard 5.8)")
        r.requirement_names;
      (n.text, r.requirement_names))
    d.type_parameters

let file_scope context file =
  match Hashtbl.find_opt context.file_scopes file with
  | Some scope -> scope
  | None -> let scope = Hashtbl.create 8 in Hashtbl.replace context.file_scopes file scope; scope

let check_function context (info : function_info) =
  let declaration = info.declaration in
  context.current_file <- info.file;
  context.type_parameters <- List.map (fun ((n : name), (r : requirement)) -> (n.text, r.requirement_names)) declaration.type_parameters;
  let fctx = { context; info; scopes = [ Hashtbl.create 8; file_scope context info.file ]; loops = []; arm_values = [] } in
  let parameters =
    List.map2
      (fun p t ->
        let info = add_variable fctx ~name:p.parameter ~variable_type:t ~is_mutable:p.self_mutable ~assigned:true () in
        info.is_parameter <- not p.self_mutable;
        info.variable)
      declaration.parameters info.parameter_types
  in
  let requires =
    List.filter_map
      (fun (r : expression) ->
        try
          let c = check_expression fctx ~expected:(Some Types.Bool) r in
          expect_type context Types.Bool c;
          let text =
            match Diagnostic.source_line r.expression_span.file r.expression_span.line with
            | Some line when r.expression_span.end_line = r.expression_span.line ->
                String.sub line (r.expression_span.column - 1) (r.expression_span.end_column - r.expression_span.column)
            | _ -> ""
          in
          Some (c, text)
        with Skip -> None)
      declaration.requires
  in
  if declaration.ensures <> [] then
    report context
      (Diagnostic.make ~span:(List.hd declaration.ensures).expression_span ~what:"how `ensures` names the result isn't decided yet"
         Diagnostic.Not_designed_yet "not decided yet (D42, standard 12.2)");
  let body = check_statements fctx declaration.body in
  (* A function with a result returns on every path (D26). *)
  let rec always_returns (statements : statement list) =
    List.exists
      (fun (s : statement) ->
        match s.statement_kind with
        | Return _ -> true
        | If { branches; else_body = Some e } ->
            List.for_all (fun b -> always_returns b.branch_body) branches && always_returns e
        | _ -> false)
      statements
  in
  if info.result_type <> Types.Nothing && info.result_type <> Types.Unknown && not (always_returns declaration.body) then
    error context
      ~what:(Printf.sprintf "%s can reach its `end` without returning %s" (quote info.full_name) (type_text info.result_type))
      declaration.function_name.span "a function with a result always uses `return $value` (D26, standard 5.1)";
  context.type_parameters <- [];
  Hashtbl.replace context.checked info.function_id
    { C.function_id = info.function_id; function_name = info.full_name; parameters; requires; body;
      returns_value = info.result_type <> Types.Nothing }

let check_package ?(uses = []) ~(std_visible : bool) (files : Syntax.file list) : (C.program option * Diagnostic.t list) =
  let context =
    { diagnostics = []; functions = Hashtbl.create 32; structs = Hashtbl.create 16; unions = Hashtbl.create 16;
      aliases = Hashtbl.create 8; new_types = Hashtbl.create 8; std_visible; next_id = 0; checked = Hashtbl.create 32; resolving = [];
      presets = Hashtbl.create 8; families = Hashtbl.create 8; file_scopes = Hashtbl.create 8; globals = []; baked_variables = Hashtbl.create 8; baked_values = []; versions = Hashtbl.create 8; overlapping_versions = Hashtbl.create 4;
      interfaces = Hashtbl.create 4; type_sets = Hashtbl.create 4; satisfied = []; type_parameters = [];
      short_names = uses; current_file = "";
      function_by_id = Hashtbl.create 32; failure_families = Hashtbl.create 8; handler_families = Hashtbl.create 8 }
  in
  let mains = ref [] in
  let globals = ref [] in
  let declare_function ?(family_pure = false) file (declaration : function_declaration) full_name =
    let is_main = List.map (fun n -> n.text) declaration.narrowings = [ "main" ] in
    if is_main then mains := (declaration, file) :: !mains
    else if
      List.exists
        (fun (other : function_info) ->
          other.file = file || (other.declaration.function_visibility <> File_only && declaration.function_visibility <> File_only))
        (Hashtbl.find_all context.functions full_name)
    then
      error context ~what:(Printf.sprintf "%s is declared twice" (quote full_name)) declaration.function_name.span
        "one name means one thing; several parameter lists go in a `versions` block (D46, standard 5.7)"
    else begin
      (* trace: D63 *)
      let short = declaration.function_name.text in
      if (not declaration.function_my) && (List.mem short Parser.keywords || short = "main") then
        error context ~fix:(quote ("my::" ^ full_name)) declaration.function_name.span
          "a name of the program's own that is also a built-in word is written with `my::` (D63, standard 9.4)";
      let id = fresh_id context in
      let info =
        { function_id = id; declaration; full_name; file; parameter_types = []; result_type = Types.Nothing;
          pure = family_pure || List.exists (fun n -> n.text = "pure") declaration.narrowings; failures = [];
          baked = List.exists (fun n -> n.text = "baked") declaration.narrowings }
      in
      Hashtbl.add context.functions full_name info;
      Hashtbl.replace context.function_by_id id info
    end
  in
  (* First the names, so declarations can mention each other in any order. *)
  List.iter
    (fun (file : Syntax.file) ->
      List.iter
        (fun d ->
          match d.declaration_kind with
          | Function f -> declare_function file.file_name f f.function_name.text
          | Struct s ->
              if Hashtbl.mem context.structs s.struct_name.text then
                error context ~what:(Printf.sprintf "%s is declared twice" (quote s.struct_name.text)) s.struct_name.span
                  "one name means one thing (D47, standard 5.5)"
              else
                Hashtbl.replace context.structs s.struct_name.text
                  { struct_declaration = s; resolved_fields = []; struct_file = file.file_name; struct_visibility = d.visibility }
          | Union u ->
              Hashtbl.replace context.unions u.union_name.text
                { union_declaration = u; resolved_cases = []; union_file = file.file_name; union_visibility = d.visibility }
          | Family_function { family_narrowings; family_name; members } ->
              (* trace: D45, D47 *)
              if Hashtbl.mem context.families family_name.text then
                error context ~what:(Printf.sprintf "there's already a family called %s" (quote family_name.text))
                  family_name.span "a type has exactly one family; a second `fam.fn` with the same name is refused (D47, standard 5.5)"
              else begin
                Hashtbl.replace context.families family_name.text family_name.span;
                let family_pure = List.exists (fun n -> n.text = "pure") family_narrowings in
                if List.exists (fun n -> n.text <> "pure") family_narrowings then
                  report context
                    (Diagnostic.make ~span:d.declaration_span ~what:"this narrowing on `fam.fn` isn't built in the oracle yet"
                       Diagnostic.Not_built_yet "a narrowing on `fam.fn` applies to every member (D45, standard 5.5)");
                List.iter
                  (function
                    | Member_function f ->
                        let full_name =
                          if f.function_name.text = family_name.text then family_name.text
                          else family_name.text ^ "." ^ f.function_name.text
                        in
                        declare_function ~family_pure file.file_name f full_name
                    | Member_preset { preset_name; settings } ->
                        Hashtbl.replace context.presets (family_name.text ^ "." ^ preset_name.text) settings
                    | Member_versions { versions_name; versions } ->
                        (* trace: D46 *)
                        let call_name =
                          if versions_name.text = family_name.text then family_name.text
                          else family_name.text ^ "." ^ versions_name.text
                        in
                        let infos =
                          List.mapi
                            (fun i (v : function_declaration) ->
                              let hidden = Printf.sprintf "%s (version %d)" call_name (i + 1) in
                              declare_function ~family_pure file.file_name v hidden;
                              let info = Hashtbl.find context.functions hidden in
                              Hashtbl.remove context.functions hidden;
                              { info with full_name = call_name })
                            versions
                        in
                        List.iter (fun (info : function_info) -> Hashtbl.replace context.function_by_id info.function_id info) infos;
                        Hashtbl.replace context.versions call_name infos)
                  members
              end
          | Type_alias { alias_name; aliased } -> Hashtbl.replace context.aliases alias_name.text aliased
          | Type_new { new_name; underlying } -> Hashtbl.replace context.new_types new_name.text underlying
          | Family_failure { failure_family; failures } -> Hashtbl.replace context.failure_families failure_family.text failures
          | Family_handler { handler_family; handlers } ->
              if Hashtbl.mem context.handler_families handler_family.text then
                error context ~what:(Printf.sprintf "there's already a handler family called %s" (quote handler_family.text))
                  handler_family.span "one name means one thing (D47, standard 5.5)"
              else Hashtbl.replace context.handler_families handler_family.text handlers
          | Global statement -> globals := (file.file_name, statement) :: !globals
          | Interface { interface_name; includes; operations } ->
              Hashtbl.replace context.interfaces interface_name.text (includes, operations)
          | Type_set { set_name; members } -> Hashtbl.replace context.type_sets set_name.text members
          | Satisfies _ -> ()
          | Unfinished_declaration { what; why; designed } ->
              report context
                (Diagnostic.make ~span:d.declaration_span ~what
                   (if designed then Diagnostic.Not_built_yet else Diagnostic.Not_designed_yet) why))
        file.declarations)
    files;
  (* Then each struct's fields, union's cases and function's signature. *)
  Hashtbl.iter
    (fun _ info ->
      (match info.struct_declaration.struct_type_parameters with
       | _ :: _ ->
           context.type_parameters <- List.map (fun ((n : name), (r : requirement)) -> (n.text, r.requirement_names)) info.struct_declaration.struct_type_parameters
       | [] -> ());
      context.current_file <- info.struct_file;
      info.resolved_fields <-
        List.map
          (fun f -> (f.field_name.text, (try resolve_type context f.field_type with Skip -> Types.Unknown), f.field_default))
          info.struct_declaration.fields;
      context.type_parameters <- [])
    context.structs;
  Hashtbl.iter
    (fun _ info ->
      context.current_file <- info.union_file;
      info.resolved_cases <-
        List.map
          (fun c ->
            (c.union_case.text, List.map (fun (n, t) -> (n.text, try resolve_type context t with Skip -> Types.Unknown)) c.case_fields))
          info.union_declaration.cases)
    context.unions;
  let resolve_signature info =
    let d = info.declaration in
    context.current_file <- info.file;
    context.type_parameters <- type_parameters_of context d;
    (* trace: D140 — a family listed whole or by member, written in full; inline failures stay short *)
    let fields_of (shape : failure_shape) =
      List.map (fun ((n : name), t) -> (n.text, try resolve_type context t with Skip -> Types.Unknown)) shape.failure_fields
    in
    info.failures <-
      List.concat_map
        (fun (shape : failure_shape) ->
          let name = shape.failure_name.text in
          match Hashtbl.find_opt context.failure_families name, String.index_opt name '.' with
          | Some members, _ ->
              List.map (fun (m : failure_shape) -> (name ^ "." ^ m.failure_name.text, fields_of m)) members
          | None, Some dot -> (
              let family = String.sub name 0 dot and member = String.sub name (dot + 1) (String.length name - dot - 1) in
              match Hashtbl.find_opt context.failure_families family with
              | None ->
                  error context ~what:(Printf.sprintf "there's no failure family called %s" (quote family)) shape.failure_name.span
                    "a named set of failures is a family (D49, D140, standard 6.2)";
                  []
              | Some members -> (
                  match List.find_opt (fun (m : failure_shape) -> m.failure_name.text = member) members with
                  | Some m -> [ (name, fields_of m) ]
                  | None ->
                      error context ~what:(Printf.sprintf "%s has no failure called %s" (quote family) (quote member))
                        shape.failure_name.span "a family's members are written after the keyword `failure` (D49, standard 6.2)";
                      []))
          | None, None -> [ (name, fields_of shape) ])
        d.fails;
    info.parameter_types <- List.map (fun p -> try resolve_type context p.parameter_type with Skip -> Types.Unknown) d.parameters;
    info.result_type <- (match d.result with None -> Types.Nothing | Some t -> try resolve_type context t with Skip -> Types.Unknown);
    (* trace: D106 — a `pub.…` signature can't mention a less visible type *)
    if d.function_visibility <> File_only then begin
      let rec less_visible (t : Types.t) =
        match t with
        | Types.Struct n | Types.Instance (n, _) -> (
            match Hashtbl.find_opt context.structs n with
            | Some s when s.struct_visibility = File_only -> Some n
            | Some s when s.struct_visibility = Package && d.function_visibility = Everyone -> Some n
            | _ -> (match t with Types.Instance (_, xs) -> List.find_map (fun (_, x) -> less_visible x) xs | _ -> None))
        | Types.Union n -> (
            match Hashtbl.find_opt context.unions n with
            | Some u when u.union_visibility = File_only -> Some n
            | Some u when u.union_visibility = Package && d.function_visibility = Everyone -> Some n
            | _ -> None)
        | Types.List x | Types.Array (x, _) | Types.Bounded (x, _) | Types.New (_, x) -> less_visible x
        | Types.Map (_, a, b) -> (match less_visible a with Some n -> Some n | None -> less_visible b)
        | _ -> None
      in
      match List.find_map less_visible (info.result_type :: info.parameter_types) with
      | Some n ->
          error context
            ~what:(Printf.sprintf "this signature is seen further than %s, which it mentions" (quote n))
            d.function_name.span "a `pub.…` signature that mentions a less visible type is refused (D106, standard 9.2a)"
      | None -> ()
    end;
    context.type_parameters <- []
  in
  (* `Type satisfies Interface` lines (D105) *)
  List.iter
    (fun (file : Syntax.file) ->
      List.iter
        (fun d ->
          match d.declaration_kind with
          | Satisfies { satisfying; interface } -> (
              match resolve_type context satisfying with
              | t ->
                  if not (Hashtbl.mem context.interfaces interface.text) then
                    error context ~what:(Printf.sprintf "there's no interface called %s" (quote interface.text)) interface.span
                      "a type fits an interface through a written `satisfies` line (D105, standard 5.8)"
                  else context.satisfied <- (Types.name t, interface.text) :: context.satisfied
              | exception Skip -> ())
          | _ -> ())
        file.declarations)
    files;
  (* A `use` can't make a function's narrowing look like its own action (D60), nor clash with a name (D59). *)
  List.iter
    (fun (u : Manifest.short_name) ->
      let before = List.filteri (fun i _ -> i < List.length u.path - 1) u.path in
      if (not u.quoted) && before <> [] && Hashtbl.mem context.functions (String.concat "." before) then
        error context
          ~what:(Printf.sprintf "%s is a function, so `%s` alone would read like a different action; a quoted name is allowed"
                   (quote (String.concat "." before)) u.short)
          u.use_span "if the part before the last dot is a function, the unquoted short name can't be the narrowing alone (D60, standard 9.3)";
      if Hashtbl.mem context.functions u.short then
        error context
          ~what:(Printf.sprintf "%s is both this short name and the program's own function" (quote u.short))
          u.use_span "a short name that clashes is always refused (D59, standard 9.2)")
    context.short_names;
  Hashtbl.iter (fun _ info -> resolve_signature info) context.functions;
  Hashtbl.iter (fun _ infos -> List.iter resolve_signature infos) context.versions;
  (* Two versions that could take the same call are refused where they're written (D46). *)
  Hashtbl.iter
    (fun call_name (infos : function_info list) ->
      let shape (f : function_info) =
        let labelled = List.map (fun ((v : name), _) -> v.text) f.declaration.labels in
        let defaulted = List.map (fun ((v : name), _) -> v.text) f.declaration.defaults in
        let positional =
          List.filter_map
            (fun ((p : parameter), t) -> if List.mem p.parameter.text labelled then None else Some (p.parameter.text, t))
            (List.combine f.declaration.parameters f.parameter_types)
        in
        let required = List.length (List.filter (fun (n, _) -> not (List.mem n defaulted)) positional) in
        (positional, required)
      in
      let rec pairs = function
        | [] -> ()
        | f :: rest ->
            List.iter
              (fun (g : function_info) ->
                let pf, rf = shape f and pg, rg = shape g in
                let overlap =
                  List.exists
                    (fun n ->
                      n >= rf && n <= List.length pf && n >= rg && n <= List.length pg
                      && List.for_all2 (fun (_, a) (_, b) -> Types.same a b)
                           (List.filteri (fun i _ -> i < n) pf) (List.filteri (fun i _ -> i < n) pg))
                    (List.init (max (List.length pf) (List.length pg) + 1) (fun n -> n))
                in
                if overlap then Hashtbl.replace context.overlapping_versions call_name ();
                if overlap then
                  error context
                    ~what:(Printf.sprintf "this version of %s could take the same call as the one on line %d" (quote call_name)
                             f.declaration.function_span.line)
                    g.declaration.function_span "two versions that could take the same call are refused (D46, standard 5.7)")
              rest;
            pairs rest
      in
      pairs infos)
    context.versions;
  (* Top-level `let`s, in the order they're written, each seen in its own file (D139, D106). *)
  List.iter
    (fun (file, statement) ->
      let fake = { function_id = 0; declaration = dummy_declaration; full_name = ""; file; parameter_types = [];
                   result_type = Types.Nothing; pure = false; failures = []; baked = false } in
      context.current_file <- file;
      let fctx = { context; info = fake; scopes = [ file_scope context file ]; loops = []; arm_values = [] } in
      context.globals <- context.globals @ check_statement fctx statement)
    (List.rev !globals);
  (* trace: D62 *)
  let main_id = fresh_id context in
  (match List.rev !mains with
   | [] ->
       report context (Diagnostic.make ~what:"the program has no `fn.main`" Diagnostic.Compile_time_error
                         "a program starts at its one `fn.main` (D62, standard 5.9)")
   | [ (declaration, file) ] ->
       let why = "`fn.main` takes no parameters and returns nothing (D62, standard 5.9)" in
       if declaration.parameters <> [] then
         error context ~what:"`fn.main` takes no parameters" (List.hd declaration.parameters).parameter.span why;
       (match declaration.result with
        | Some t -> error context ~what:"`fn.main` returns nothing" t.type_span why
        | None -> ());
       let info =
         { function_id = main_id; declaration; full_name = "fn.main"; file; parameter_types = []; result_type = Types.Nothing; pure = false; failures = []; baked = false }
       in
       info.parameter_types <- List.map (fun _ -> Types.Unknown) declaration.parameters;
       check_function context info
   | _ :: (second, _) :: _ ->
       error context ~what:"the program has more than one `fn.main`" second.function_name.span
         "a program starts at its one `fn.main` (D62, standard 5.9)");
  Hashtbl.iter (fun _ info -> check_function context info) context.functions;
  Hashtbl.iter (fun _ infos -> List.iter (check_function context) infos) context.versions;
  let diagnostics = List.rev context.diagnostics in
  let program =
    { C.functions = context.checked; main = main_id; struct_defaults = Hashtbl.create 1; globals = context.globals }
  in
  (* Struct defaults, checked once, with no variables. *)
  Hashtbl.iter
    (fun name info ->
      let fake = { function_id = 0; declaration = dummy_declaration; full_name = ""; file = "";
                   parameter_types = []; result_type = Types.Nothing; pure = false; failures = []; baked = false } in
      let fctx = { context; info = fake; scopes = [ Hashtbl.create 1 ]; loops = []; arm_values = [] } in
      let defaults =
        List.map
          (fun (n, t, default) ->
            (n, Option.bind default (fun e -> try Some (check_value fctx t e) with Skip -> None)))
          info.resolved_fields
      in
      Hashtbl.replace program.struct_defaults name defaults)
    context.structs;
  (* Baked values are worked out now; a check that fails here fails when compiling (D5, D8). *)
  let frame = Hashtbl.create 16 in
  List.iter
    (fun ((variable : C.variable), (value : C.expression)) ->
      match Interpreter.evaluate_with program frame value with
      | v -> Hashtbl.replace frame variable.variable_id (ref v)
      | exception Interpreter.Runtime_stop d ->
          let because =
            if d.span = Some value.span then d.because
            else
              d.because
              @ [ Printf.sprintf "working out `$%s` at line %d column %d, when compiling" variable.variable_name value.span.line
                    (Diagnostic.grapheme_column value.span) ]
          in
          report context
            { d with kind = (if d.kind = Diagnostic.Runtime_error then Diagnostic.Compile_time_error else d.kind); because }
      | exception Std_library.Exit_program _ -> ()
      | exception Not_found ->
          (* it calls a function that was refused, so it's unknown, and nothing more is said (D13) *)
          ())
    context.baked_values;
  let diagnostics = diagnostics @ List.rev (List.filter (fun d -> not (List.memq d diagnostics)) context.diagnostics) in
  (Some program, diagnostics)
