(* Reads tokens into the syntax tree (standard chapters 1 to 6).

   Jernal is read a line at a time (D19). A line with an error is skipped and reading carries on
   with the next one (D13). A line that opens a block and has an error still has its body read,
   up to the named `end` that says where the block stops. *)

open Token
open Syntax

exception Line_error of Diagnostic.t

type state = {
  tokens : Token.t array;
  mutable position : int;
  mutable diagnostics : Diagnostic.t list;
  mutable open_blocks : string list;   (* the closers of the blocks being read, innermost first *)
}

(* ---------- Looking at tokens ---------- *)

let peek state = state.tokens.(state.position)
let peek_at state offset =
  let index = min (state.position + offset) (Array.length state.tokens - 1) in
  state.tokens.(index)
let peek_kind state = (peek state).kind
let advance state =
  let token = peek state in
  if state.position < Array.length state.tokens - 1 then state.position <- state.position + 1;
  token

let report state d = state.diagnostics <- d :: state.diagnostics

let error_diagnostic ?what ?fix span why = Diagnostic.make ~span ?what ?fix Diagnostic.Compile_time_error why

let fail_line ?what ?fix span why = raise (Line_error (error_diagnostic ?what ?fix span why))

let at_line_end state = match peek_kind state with Newline | End_of_file -> true | _ -> false

let is_word state text = match peek_kind state with Word w -> w = text | _ -> false
let is_word_at state offset text = match (peek_at state offset).kind with Word w -> w = text | _ -> false

let keywords =
  [ "let"; "mut"; "baked"; "decl"; "assign"; "shadow"; "change"; "give"; "copy"; "fn"; "end"; "if";
    "else"; "for"; "in"; "while"; "break"; "return"; "early"; "match"; "case"; "with";
    "otherwise"; "instead"; "fail"; "fails"; "ignore"; "struct"; "union"; "type"; "fam";
    "handler"; "failure"; "preset"; "versions"; "version"; "labels"; "defaults"; "requires";
    "ensures"; "as"; "and"; "or"; "not"; "at_least"; "at_most"; "div"; "mod"; "x"; "plus";
    "minus"; "times"; "true"; "false"; "at"; "interface"; "includes"; "op"; "type_set";
    "satisfies"; "pub"; "comment"; "shield"; "reason"; "pin"; "use"; "my" ]

let is_keyword word = List.mem word keywords

let quote_word w = "`" ^ w ^ "`"

(* The text of a token as written, for messages. *)
let token_text (t : Token.t) =
  match t.kind with
  | String_literal s -> "\"" ^ s ^ "\""
  | kind -> Token.describe kind

(* The rest of the line from [from], written back out with its spacing. *)
let render_tokens state from =
  let buffer = Buffer.create 32 in
  let rec go i first =
    let t = state.tokens.(i) in
    match t.kind with
    | Newline | End_of_file -> ()
    | _ ->
        if (not first) && t.space_before then Buffer.add_char buffer ' ';
        Buffer.add_string buffer (token_text t);
        go (i + 1) false
  in
  go from true;
  Buffer.contents buffer

let line_has_broken state =
  let rec go i =
    match state.tokens.(i).kind with
    | Newline | End_of_file -> false
    | Broken -> true
    | _ -> go (i + 1)
  in
  go state.position

(* Whether the current line ends with `:`, so opens a block. *)
let line_opens_block state =
  let rec go i last =
    match state.tokens.(i).kind with
    | Newline | End_of_file -> last = Some Colon
    | kind -> go (i + 1) (Some kind)
  in
  go state.position None

let skip_line state =
  while not (at_line_end state) do ignore (advance state) done;
  if peek_kind state = Newline then ignore (advance state)

let skip_blank_lines state = while peek_kind state = Newline do ignore (advance state) done

let unexpected state expected =
  let t = peek state in
  fail_line ~what:(Printf.sprintf "expected %s here, not %s" expected
                     (match t.kind with Newline -> "the end of the line" | _ -> "`" ^ token_text t ^ "`"))
    t.span "the shape of each statement is set out in the standard (D19, standard 1.1)"

let expect state kind expected =
  if peek_kind state = kind then advance state else unexpected state expected

let expect_word state word =
  if is_word state word then advance state else unexpected state ("`" ^ word ^ "`")

let end_of_line state =
  if peek_kind state = Newline then ignore (advance state)
  else if peek_kind state = End_of_file then ()
  else unexpected state "the end of the line"

let name_of (t : Token.t) text = { text; span = t.span }

let expect_name state expected =
  let t = peek state in
  match t.kind with
  | Word w -> ignore (advance state); name_of t w
  | _ -> unexpected state expected

let expect_variable state =
  let t = peek state in
  match t.kind with
  | Variable v -> ignore (advance state); name_of t v
  | _ -> unexpected state "a variable such as `$name`"

(* Narrowings after a dot: .pure.baked *)
let rec dotted_words state =
  if peek_kind state = Dot then begin
    match (peek_at state 1).kind with
    | Word w ->
        ignore (advance state);
        let t = advance state in
        name_of t w :: dotted_words state
    | _ -> []
  end
  else []

(* A name that may be written in full, such as `file_failed.not_found` (D140). *)
let expect_dotted_name state expected =
  let head = expect_name state expected in
  let rest = dotted_words state in
  match rest with
  | [] -> head
  | _ ->
      let last = List.nth rest (List.length rest - 1) in
      { text = String.concat "." (head.text :: List.map (fun n -> n.text) rest); span = Span.join head.span last.span }

and span_from (first : Span.t) state =
  let last = state.tokens.(max 0 (state.position - 1)) in
  Span.join first last.span

(* ---------- Types ---------- *)

(* Type names as other languages write them, and Jernal's own spelling (D56). *)
let lowercase_types =
  [ ("list", "List"); ("map", "Map"); ("int", "Int"); ("string", "String"); ("str", "String"); ("float", "Float");
    ("bool", "Bool"); ("array", "Array"); ("decimal", "Decimal"); ("rational", "Rational"); ("dict", "Map") ]

(* A type as Jernal writes it, for a fix. *)
let rec type_text (t : type_expression) =
  match t.type_kind with
  | Parameter_type p -> "?" ^ p
  | Named_type { my; words; arguments; _ } ->
      (if my then "my::" else "")
      ^ String.concat "." words
      ^
      match arguments with
      | [] -> ""
      | _ ->
          "<"
          ^ String.concat ", "
              (List.map
                 (fun a -> (match a.argument_label with Some l -> l.text ^ ": " | None -> "") ^ type_text a.argument_type)
                 arguments)
          ^ ">"

let rec parse_type state : type_expression =
  let first = peek state in
  match first.kind with
  | Token.Type_parameter p ->
      ignore (advance state);
      { type_kind = Parameter_type p; type_span = first.span }
  | Word _ ->
      let my =
        if is_word state "my" && (peek_at state 1).kind = Double_colon then (ignore (advance state); ignore (advance state); true)
        else false
      in
      let head = expect_name state "a type" in
      let rest = dotted_words state in
      let words = head.text :: List.map (fun n -> n.text) rest in
      (match List.assoc_opt head.text lowercase_types with
      | Some capitalized when (not my) && rest = [] -> lowercase_type state first head capitalized
      | _ -> (
      let arguments =
        if peek_kind state = Type_open then begin
          ignore (advance state);
          let rec items acc =
            let label =
              match peek_kind state, (peek_at state 1).kind with
              | Word w, Colon -> let t = advance state in ignore (advance state); Some (name_of t w)
              | _ -> None
            in
            let argument = parse_type state in
            let acc = { argument_label = label; argument_type = argument } :: acc in
            if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
          in
          let result = items [] in
          ignore (expect state Type_close "`>`");
          result
        end
        else []
      in
      let details =
        if peek_kind state = Left_bracket && not (peek state).space_before then parse_details state else []
      in
      { type_kind = Named_type { my; words; arguments; details }; type_span = span_from first.span state }))
  | _ -> unexpected state "a type"

(* `list[Int]` or `int` where a type goes: one fix, Jernal's spelling, and reading carries on as if it were
   written so (D56, D102). *)
and lowercase_type state (first : Token.t) (head : name) (capitalized : string) : type_expression =
  let bracketed = peek_kind state = Left_bracket && not (peek state).space_before in
  let items =
    if bracketed then begin
      ignore (advance state);
      let rec go acc =
        if peek_kind state = Right_bracket then List.rev acc
        else
          let t = parse_type state in
          if peek_kind state = Comma then (ignore (advance state); go (t :: acc)) else List.rev (t :: acc)
      in
      let result = go [] in
      ignore (expect state Right_bracket "`]`");
      result
    end
    else []
  in
  let arguments =
    match capitalized, items with
    | "Map", [ key; value ] ->
        [ { argument_label = Some { head with text = "key" }; argument_type = key };
          { argument_label = Some { head with text = "val" }; argument_type = value } ]
    | _ -> List.map (fun t -> { argument_label = None; argument_type = t }) items
  in
  let fixed = { type_kind = Named_type { my = false; words = [ capitalized ]; arguments; details = [] }; type_span = span_from first.span state } in
  (* trace: D56, D102 *)
  report state
    (error_diagnostic ~fix:("`" ^ type_text fixed ^ "`") fixed.type_span
       (if bracketed then "types are capitalized, and a type's parameters go in `< >` (D56, D102, standard 2.3)"
        else "types are capitalized (D56, standard 1.3)"));
  fixed

(* [min: 0, max: 100], [len.min: 1] (D135) *)
and parse_details state =
  ignore (advance state);
  let rec items acc =
    if peek_kind state = Right_bracket then List.rev acc
    else begin
      let label_token = peek state in
      let head = expect_name state "a detail such as `min:`" in
      let rest = dotted_words state in
      let label = String.concat "." (head.text :: List.map (fun n -> n.text) rest) in
      ignore (expect state Colon "`:`");
      let value = parse_expression state in
      let acc = { detail_label = label; detail_label_span = span_from label_token.span state; detail_value = value } :: acc in
      if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
    end
  in
  let result = items [] in
  ignore (expect state Right_bracket "`]`");
  result

(* ---------- Expressions ---------- *)

and make kind first state = { expression_kind = kind; expression_span = span_from first state }

and parse_expression state : expression =
  let first = (peek state).span in
  let value = parse_or state in
  let value =
    if peek_kind state = Double_question then begin
      ignore (advance state);
      if is_word state "ignore" then (ignore (advance state); make (Ignore value) first state)
      else
        let instead = parse_or state in
        make (Fallback { value; instead }) first state
    end
    else value
  in
  if is_word state "otherwise" then begin
    ignore (advance state);
    let handling = parse_handling state in
    make (Otherwise { value; handling }) first state
  end
  else value

(* After `otherwise`: either `:` and arms up to `end otherwise`, or `family.handler`. *)
and parse_handling state : handling =
  if peek_kind state = Colon && (peek_at state 1).kind = Newline then begin
    ignore (advance state);
    ignore (advance state);
    let arms = parse_arms state in
    expect_closer state ~opener:(peek state).span ~expected:"otherwise";
    (* the closer's newline is left for the statement to end on *)
    Arms arms
  end
  else
    let family, handler, jumps = parse_handler_reference state in
    Handler { family; handler; jumps }

and parse_handler_reference state =
  let family = expect_name state "a handler family" in
  ignore (expect state Dot "`.`");
  let jumps = if peek_kind state = Star then (ignore (advance state); true) else false in
  let handler = expect_name state "a handler" in
  (family, handler, jumps)

and binary_loop state first next_level matches =
  let left = ref (next_level state) in
  let continue = ref true in
  while !continue do
    match matches state with
    | Some operator ->
        let right = next_level state in
        left := make (Binary { operator; left = !left; right }) first state
    | None -> continue := false
  done;
  !left

and word_operator state words =
  match peek_kind state with
  | Word w when List.mem w words ->
      let t = advance state in
      let narrowings = List.map (fun n -> n.text) (dotted_words state) in
      Some { word = w; narrowings; operator_span = span_from t.span state }
  | _ -> None

and parse_or state =
  let first = (peek state).span in
  binary_loop state first parse_and (fun s -> word_operator s [ "or" ])

and parse_and state =
  let first = (peek state).span in
  binary_loop state first parse_not (fun s -> word_operator s [ "and" ])

and parse_not state =
  if is_word state "not" then begin
    let first = (advance state).span in
    let inner = parse_not state in
    make (Not inner) first state
  end
  else parse_comparison state

and comparison_operator state =
  let t = peek state in
  let simple word = ignore (advance state); Some { word; narrowings = []; operator_span = t.span } in
  match t.kind with
  | Equals_equals -> simple "=="
  | Bang_equals -> simple "!="
  | Less -> simple "<"
  | Greater -> simple ">"
  | Word ("at_least" | "at_most") -> word_operator state [ "at_least"; "at_most" ]
  | Equals ->
      (* trace: D27 *)
      raise (Line_error (error_diagnostic ~fix:"`==`" t.span "`=` gives a value, and `==` compares (D27, standard 4.1)"))
  | _ -> None

and parse_comparison state =
  let first = (peek state).span in
  let left = parse_additive state in
  match comparison_operator state with
  | None -> left
  | Some operator ->
      let right = parse_additive state in
      (* trace: D139 — a chain reads as maths when every comparison points the same way *)
      let rec more operands operators =
        match comparison_operator state with
        | Some next -> more (parse_additive state :: operands) (next :: operators)
        | None -> (List.rev operands, List.rev operators)
      in
      let operands, operators = more [ right; left ] [ operator ] in
      if List.length operators = 1 then make (Binary { operator; left; right }) first state
      else begin
        let direction (o : operator) =
          match o.word with "<" | "at_most" -> `Up | ">" | "at_least" -> `Down | _ -> `Equal
        in
        let why = "comparisons chain only when they all point the same way, and `==` and `!=` never chain (D139, standard 4.1)" in
        List.iter
          (fun (o : operator) ->
            if direction o = `Equal then
              fail_line ~what:(Printf.sprintf "%s can't be part of a chain of comparisons; group with `( )`" (quote_word o.word))
                o.operator_span why)
          operators;
        let first_direction = direction (List.hd operators) in
        List.iter
          (fun (o : operator) ->
            if direction o <> first_direction then
              fail_line ~what:"this chain of comparisons points both ways; group with `( )`" o.operator_span why)
          operators;
        make (Comparison_chain { operands; operators }) first state
      end

and parse_additive state =
  let first = (peek state).span in
  binary_loop state first parse_multiplicative (fun s ->
      let t = peek s in
      match t.kind with
      | Plus -> ignore (advance s); Some { word = "+"; narrowings = []; operator_span = t.span }
      | Minus -> ignore (advance s); Some { word = "-"; narrowings = []; operator_span = t.span }
      | _ -> word_operator s [ "plus"; "minus" ])

and parse_multiplicative state =
  let first = (peek state).span in
  binary_loop state first parse_unary (fun s -> word_operator s [ "x"; "div"; "mod"; "times" ])

and parse_unary state =
  let t = peek state in
  if t.kind = Minus then begin
    ignore (advance state);
    match peek_kind state with
    | Token.Integer_literal digits when not (peek state).space_before ->
        ignore (advance state);
        let literal = make (Integer_literal { digits; negative = true; tilde = false }) t.span state in
        parse_postfix_on state t.span literal |> parse_as_on state t.span
    | Token.Decimal_literal digits when not (peek state).space_before ->
        ignore (advance state);
        let literal = make (Decimal_literal { digits; negative = true; tilde = false }) t.span state in
        parse_postfix_on state t.span literal |> parse_as_on state t.span
    | _ ->
        let inner = parse_unary state in
        make (Negate inner) t.span state
  end
  else parse_join state

(* Values side by side are joined (D20). *)
and starts_join_item state =
  match peek_kind state with
  | Token.String_literal _ | Token.Variable _ | Token.Integer_literal _ | Token.Decimal_literal _ | Tilde -> true
  | Word w -> not (is_keyword w) || w = "true" || w = "false"
  | _ -> false

and parse_join state =
  let first = (peek state).span in
  let item = parse_as state in
  if starts_join_item state then begin
    let items = ref [ item ] in
    while starts_join_item state do
      items := parse_as state :: !items
    done;
    make (Join (List.rev !items)) first state
  end
  else item

and parse_as state =
  let first = (peek state).span in
  let value = parse_postfix state in
  parse_as_on state first value

and parse_as_on state first value =
  if is_word state "as" then begin
    ignore (advance state);
    let narrowings = dotted_words state in
    let target = parse_type state in
    parse_as_on state first (make (Convert { value; narrowings; target }) first state)
  end
  else value

and parse_postfix state =
  let first = (peek state).span in
  let primary = parse_primary state in
  parse_postfix_on state first primary

and parse_postfix_on state first value =
  let t = peek state in
  match t.kind with
  | Dot -> (
      ignore (advance state);
      match peek_kind state with
      | Star ->
          ignore (advance state);
          let member = expect_name state "a name" in
          parse_postfix_on state first (make (Narrowed_member (value, member)) first state)
      | Word w ->
          let n = advance state in
          parse_postfix_on state first (make (Member (value, name_of n w)) first state)
      | _ -> unexpected state "a name after `.`")
  | Left_paren when not t.space_before ->
      ignore (advance state);
      let arguments = parse_arguments state in
      parse_postfix_on state first (make (Call { callee = value; arguments }) first state)
  | Left_bracket when not t.space_before ->
      let builds =
        match (peek_at state 1).kind, (peek_at state 2).kind with
        | Word _, Equals -> true
        | Right_bracket, _ -> (
            match value.expression_kind with
            | Name { word; _ } -> word <> "" && Char.uppercase_ascii word.[0] = word.[0]
            | Member _ -> true
            | _ -> false)
        | _ -> false
      in
      if builds then begin
        ignore (advance state);
        let fields = parse_field_values state in
        ignore (expect state Right_bracket "`]`");
        parse_postfix_on state first (make (Build { built = value; fields }) first state)
      end
      else if (match (peek_at state 1).kind, (peek_at state 2).kind with Word "key", Colon -> true | _ -> false) then begin
        ignore (advance state); ignore (advance state); ignore (advance state);
        let key = parse_expression state in
        ignore (expect state Right_bracket "`]`");
        parse_postfix_on state first (make (Key_index { target = value; key }) first state)
      end
      else begin
        ignore (advance state);
        let counting =
          match peek_kind state, (peek_at state 1).kind with
          | Word "pos", Colon -> ignore (advance state); ignore (advance state); Some Pos
          | Word "offset", Colon -> ignore (advance state); ignore (advance state); Some Offset
          | _ -> None
        in
        let position = parse_expression state in
        ignore (expect state Right_bracket "`]`");
        let kind =
          match counting with
          | Some counting -> Index { target = value; counting; position }
          | None -> Bare_index { target = value; position }
        in
        parse_postfix_on state first (make kind first state)
      end
  | Question ->
      ignore (advance state);
      parse_postfix_on state first (make (Pass_up value) first state)
  | Type_open ->
      (* trace: D103 *)
      raise (Line_error (Diagnostic.make ~span:t.span ~what:"naming a type at a call isn't decided yet"
                           Diagnostic.Not_designed_yet "not decided yet (D103, standard 12.1)"))
  | _ -> value

and parse_field_values state =
  let rec items acc =
    if peek_kind state = Right_bracket then List.rev acc
    else begin
      let field = expect_name state "a field name" in
      ignore (expect state Equals "`=`");
      let value = parse_expression state in
      let acc = { field; field_value = value } :: acc in
      if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
    end
  in
  items []

and parse_arguments state =
  let rec items acc =
    if peek_kind state = Right_paren then (ignore (advance state); List.rev acc)
    else begin
      let label =
        match peek_kind state, (peek_at state 1).kind with
        | Word w, Colon -> let t = advance state in ignore (advance state); Some (name_of t w)
        | _ -> None
      in
      let value = parse_expression state in
      let acc = { label; value } :: acc in
      match peek_kind state with
      | Comma -> ignore (advance state); items acc
      | Right_paren -> ignore (advance state); List.rev acc
      | _ -> unexpected state "`,` or `)`"
    end
  in
  items []

and parse_primary state : expression =
  let t = peek state in
  let literal kind = ignore (advance state); make kind t.span state in
  match t.kind with
  | Token.Integer_literal digits -> literal (Integer_literal { digits; negative = false; tilde = false })
  | Token.Decimal_literal digits -> literal (Decimal_literal { digits; negative = false; tilde = false })
  | Tilde -> (
      ignore (advance state);
      let negative = if peek_kind state = Minus then (ignore (advance state); true) else false in
      match peek_kind state with
      | Token.Integer_literal digits -> literal (Integer_literal { digits; negative; tilde = true })
      | Token.Decimal_literal digits -> literal (Decimal_literal { digits; negative; tilde = true })
      | _ -> unexpected state "a number after `~`")
  | Token.String_literal s -> literal (String_literal s)
  | Token.Variable v -> literal (Variable v)
  | Word "true" -> literal (Bool_literal true)
  | Word "false" -> literal (Bool_literal false)
  | Word "give" ->
      ignore (advance state);
      let inner = parse_postfix state in
      make (Give inner) t.span state
  | Word "copy" ->
      ignore (advance state);
      let inner = parse_postfix state in
      make (Copy inner) t.span state
  | Word "range" when (peek_at state 1).kind = Left_bracket && not (peek_at state 1).space_before ->
      ignore (advance state);
      parse_range state t.span
  | Word "my" when (peek_at state 1).kind = Double_colon ->
      ignore (advance state);
      ignore (advance state);
      let n = expect_name state "a name after `my::`" in
      make (Name { my = true; path = []; word = n.text }) t.span state
  | Word w when (peek_at state 1).kind = Double_colon ->
      let rec path acc =
        match peek_kind state, (peek_at state 1).kind with
        | Word w, Double_colon -> ignore (advance state); ignore (advance state); path (w :: acc)
        | _ -> List.rev acc
      in
      ignore w;
      let words = path [] in
      let n = expect_name state "a name" in
      make (Name { my = false; path = words; word = n.text }) t.span state
  | Word w when not (is_keyword w) -> literal (Name { my = false; path = []; word = w })
  | Left_paren ->
      ignore (advance state);
      let inner = parse_expression state in
      ignore (expect state Right_paren "`)`");
      make (Grouped inner) t.span state
  | Left_bracket ->
      ignore (advance state);
      if peek_kind state = Right_bracket then literal (List_literal [])
      else begin
        let first_item = parse_expression state in
        if peek_kind state = Fat_arrow then begin
          ignore (advance state);
          let first_value = parse_expression state in
          let rec entries acc =
            if peek_kind state = Comma then begin
              ignore (advance state);
              if peek_kind state = Right_bracket then List.rev acc
              else
                let key = parse_expression state in
                ignore (expect state Fat_arrow "`=>`");
                let value = parse_expression state in
                entries ((key, value) :: acc)
            end
            else List.rev acc
          in
          let all = entries [ (first_item, first_value) ] in
          ignore (expect state Right_bracket "`]`");
          make (Map_literal all) t.span state
        end
        else begin
          let rec items acc =
            if peek_kind state = Comma then begin
              ignore (advance state);
              if peek_kind state = Right_bracket then List.rev acc
              else items (parse_expression state :: acc)
            end
            else List.rev acc
          in
          let all = items [ first_item ] in
          ignore (expect state Right_bracket "`]`");
          make (List_literal all) t.span state
        end
      end
  | _ -> unexpected state "a value"

(* range[from: ..., to: ... | before: ..., step_by: ...] (D37) *)
and parse_range state first =
  ignore (advance state);
  let why = "a range is labelled `from:`, then `to:` or `before:`, then `step_by:`, in that order (D37, standard 4.7)" in
  let label expected =
    let t = peek state in
    match t.kind, (peek_at state 1).kind with
    | Word w, Colon when List.mem w expected -> ignore (advance state); ignore (advance state); w
    | _ ->
        fail_line ~what:(Printf.sprintf "expected %s here"
                           (String.concat " or " (List.map (fun w -> "`" ^ w ^ ":`") expected)))
          t.span why
  in
  ignore (label [ "from" ]);
  let from = parse_expression state in
  ignore (expect state Comma "`,`");
  let ending_word = label [ "to"; "before" ] in
  let ending_value = parse_expression state in
  let ending = if ending_word = "to" then To ending_value else Before ending_value in
  let step_by =
    if peek_kind state = Comma && (peek_at state 1).kind <> Right_bracket then begin
      ignore (advance state);
      ignore (label [ "step_by" ]);
      Some (parse_expression state)
    end
    else (if peek_kind state = Comma then ignore (advance state); None)
  in
  ignore (expect state Right_bracket "`]`");
  make (Range { from; ending; step_by }) first state

(* ---------- Blocks and closers ---------- *)

(* After the body of a block: the line must be `end <expected>` (D24). *)
and expect_closer state ~(opener : Span.t) ~(expected : string) =
  skip_blank_lines state;
  let t = peek state in
  let why = "a block closes with `end` and everything its opening line said (D24, standard 1.2)" in
  match t.kind with
  | Word "end" ->
      let actual = render_tokens state (state.position + 1) in
      if actual = expected then begin
        ignore (advance state);
        while not (at_line_end state) do ignore (advance state) done
      end
      else if List.mem actual state.open_blocks then
        (* this `end` belongs to a block further out: this block was never closed *)
        report state
          (error_diagnostic ~what:(Printf.sprintf "this block has no `end %s`" expected) opener why)
      else begin
        let start = t.span in
        ignore (advance state);
        while not (at_line_end state) do ignore (advance state) done;
        let last = state.tokens.(state.position - 1) in
        report state (error_diagnostic ~fix:(Printf.sprintf "`end %s`" expected) (Span.join start last.span) why)
      end
  | _ ->
      report state (error_diagnostic ~what:(Printf.sprintf "this block has no `end %s`" expected) opener why)

(* `case name $binding:` arms, up to the closer (D48, D97). *)
and parse_arms state : arm list =
  let rec go acc =
    skip_blank_lines state;
    if is_word state "case" then begin
      let start = peek state in
      let arm_line () =
        ignore (advance state);
        let case_name = expect_dotted_name state "a case name" in
        let binding = match peek_kind state with Token.Variable _ -> Some (expect_variable state) | _ -> None in
        ignore (expect state Colon "`:`");
        end_of_line state;
        (case_name, binding)
      in
      match arm_line () with
      | case_name, binding ->
          let body = with_block state "case" (fun () -> parse_statements state) in
          go ({ case_name; binding; arm_body = body; arm_span = start.span } :: acc)
      | exception Line_error d ->
          report state d;
          skip_line state;
          let _ = parse_statements state in
          go acc
    end
    else List.rev acc
  in
  go []

and with_block : 'a. state -> string -> (unit -> 'a) -> 'a =
  fun state closer f ->
  state.open_blocks <- closer :: state.open_blocks;
  let result = f () in
  state.open_blocks <- List.tl state.open_blocks;
  result

(* Statements up to a line starting with `end`, `else` or `case`, or the end of the file. *)
and parse_statements state : statement list =
  let rec go acc =
    skip_blank_lines state;
    match peek_kind state with
    | End_of_file | Word ("end" | "else" | "case") -> List.rev acc
    | _ -> (
        match parse_statement state with
        | Some s -> go (s :: acc)
        | None -> go acc)
  in
  go []

(* The word an opening line's closer starts with, for a line that can't be read. *)
and closer_word_of_line state =
  let rec last_before_colon i previous =
    match state.tokens.(i).kind with
    | Colon when (match state.tokens.(i + 1).kind with Newline | End_of_file -> true | _ -> false) -> previous
    | Newline | End_of_file -> previous
    | kind -> last_before_colon (i + 1) (Some kind)
  in
  match last_before_colon state.position None with
  | Some (Word "otherwise") -> "otherwise"
  | _ -> (match peek_kind state with Word w -> w | _ -> "")

(* The names a refused line still declares (D13): a `let`, `decl` or `shadow` declares its variable,
   with its type if that part can be read; a `for` declares its loop variable and position. *)
and recover_declarations state : recovered list =
  let saved = state.position in
  let first = peek state in
  let result =
    match first.kind with
    | Word ("let" | "decl" | "shadow") -> (
        ignore (advance state);
        let is_mutable = if is_word state "mut" then (ignore (advance state); true) else false in
        if is_word state "baked" then ignore (advance state);
        match peek_kind state with
        | Token.Variable v ->
            let n = name_of (advance state) v in
            let recovered_type =
              if peek_kind state = Colon && not (line_has_broken_before_end state) then begin
                ignore (advance state);
                match parse_type state with t -> Some t | exception Line_error _ -> None
              end
              else None
            in
            [ { recovered_name = n; recovered_type; recovered_mutable = is_mutable } ]
        | _ -> [])
    | Word "for" ->
        ignore (advance state);
        let rec variables acc =
          match peek_kind state with
          | Newline | End_of_file -> List.rev acc
          | Word "in" ->
              (* skip to `at pos $p`, if any *)
              let rec find_at () =
                match peek_kind state with
                | Newline | End_of_file -> None
                | Word "at" -> (
                    ignore (advance state);
                    ignore (advance state);
                    match peek_kind state with Token.Variable p -> Some (name_of (advance state) p) | _ -> None)
                | _ -> ignore (advance state); find_at ()
              in
              (match find_at () with
               | Some p -> List.rev ({ recovered_name = p; recovered_type = Some { type_kind = Named_type { my = false; words = [ "Int" ]; arguments = []; details = [] }; type_span = p.span }; recovered_mutable = false } :: acc)
               | None -> List.rev acc)
          | Token.Variable v when acc = [] ->
              let n = name_of (advance state) v in
              variables ({ recovered_name = n; recovered_type = None; recovered_mutable = false } :: acc)
          | _ -> ignore (advance state); variables acc
        in
        variables []
    | _ -> []
  in
  state.position <- saved;
  result

(* Whether a Broken token comes before the line's `=`, so the type can't be read. *)
and line_has_broken_before_end state =
  let rec go i =
    match state.tokens.(i).kind with
    | Newline | End_of_file | Equals -> false
    | Broken -> true
    | _ -> go (i + 1)
  in
  go state.position

(* An opening line that can't be read: its body is still read, up to its `end` (D13). *)
and parse_broken_block state (d : Diagnostic.t option) : statement =
  let start = peek state in
  let declares = recover_declarations state in
  let closer = closer_word_of_line state in
  Option.iter (report state) d;
  skip_line state;
  let body =
    with_block state closer (fun () ->
        let rec sections acc =
          let body = parse_statements state in
          let acc = acc @ body in
          if is_word state "else" || is_word state "case" then (skip_line state; sections acc) else acc
        in
        sections [])
  in
  skip_blank_lines state;
  if is_word state "end" && is_word_at state 1 closer then skip_line state;
  { statement_kind = Broken_block { declares; body }; statement_span = start.span }

and parse_statement state : statement option =
  let start = peek state in
  let broken_statement () =
    let declares = recover_declarations state in
    skip_line state;
    if declares = [] then None else Some { statement_kind = Broken_statement declares; statement_span = start.span }
  in
  if line_has_broken state then
    if line_opens_block state then Some (parse_broken_block state None)
    else broken_statement ()
  else
    let opens = line_opens_block state in
    let saved = state.position in
    match parse_statement_line state with
    | s -> Some s
    | exception Line_error d ->
        if opens then begin
          state.position <- saved;
          Some (parse_broken_block state (Some d))
        end
        else begin
          report state d;
          state.position <- saved;
          broken_statement ()
        end

and statement_of kind (start : Token.t) state = { statement_kind = kind; statement_span = span_from start.span state }

and parse_statement_line state : statement =
  let start = peek state in
  let finish kind =
    let s = statement_of kind start state in
    end_of_line state;
    s
  in
  match start.kind with
  | Word "let" ->
      ignore (advance state);
      let is_mutable = if is_word state "mut" then (ignore (advance state); true) else false in
      let baked = if is_word state "baked" then (ignore (advance state); true) else false in
      let variable = expect_variable state in
      if peek_kind state <> Colon then
        fail_line ~what:(Printf.sprintf "`let $%s` doesn't write its type" variable.text) variable.span
          "a `let` always writes its type (D34, standard 3.1)";
      ignore (advance state);
      let declared_type = parse_type state in
      ignore (expect state Equals "`=`");
      let value = parse_expression state in
      finish (Let { is_mutable; baked; variable; declared_type; value })
  | Word "decl" ->
      ignore (advance state);
      let is_mutable = if is_word state "mut" then (ignore (advance state); true) else false in
      let variable = expect_variable state in
      ignore (expect state Colon "`:` and the type");
      let declared_type = parse_type state in
      finish (Decl { is_mutable; variable; declared_type })
  | Word "assign" ->
      ignore (advance state);
      let variable = expect_variable state in
      ignore (expect state Equals "`=`");
      let value = parse_expression state in
      finish (Assign { variable; value })
  | Word "shadow" ->
      ignore (advance state);
      let is_mutable = if is_word state "mut" then (ignore (advance state); true) else false in
      let variable = expect_variable state in
      ignore (expect state Colon "`:` and the type");
      let declared_type = parse_type state in
      ignore (expect state Equals "`=`");
      let value = parse_expression state in
      finish (Shadow { is_mutable; variable; declared_type; value })
  | Word "change" ->
      ignore (advance state);
      let target = parse_postfix state in
      ignore (expect state Equals "`=`");
      let value = parse_expression state in
      finish (Change { target; value })
  | Word "return" ->
      ignore (advance state);
      if is_word state "early" then (ignore (advance state); finish Return_early)
      else if at_line_end state then
        fail_line ~what:"`return` needs a value, or `early` in a function that returns nothing" start.span
          "a result is given with `return $value`, and leaving early says `return early` (D26, standard 5.1)"
      else
        let value = parse_expression state in
        finish (Return value)
  | Word "break" ->
      ignore (advance state);
      let name = if at_line_end state then None else Some (expect_name state "a loop's name") in
      finish (Break name)
  | Word "instead" ->
      ignore (advance state);
      let value = parse_expression state in
      finish (Instead value)
  | Word "fail" ->
      ignore (advance state);
      let failure = expect_dotted_name state "a failure's name" in
      let fields =
        if peek_kind state = Left_bracket && not (peek state).space_before then begin
          ignore (advance state);
          let fields = parse_field_values state in
          ignore (expect state Right_bracket "`]`");
          fields
        end
        else []
      in
      finish (Fail { failure; fields })
  | Word (("labels" | "defaults" | "requires" | "ensures") as word) ->
      (* trace: D42 *)
      fail_line ~what:(Printf.sprintf "`%s` goes at the top of a body, before any code" word) start.span
        "the top of a body says `labels`, `defaults`, `requires` and `ensures`, before any code (D42, standard 5.3)"
  | Word "if" -> parse_if state
  | Word "while" -> parse_while state
  | Word "for" -> parse_for state
  | Word "match" -> parse_match state
  | Word "shield" ->
      let s = unfinished_block state ~what:"shields aren't built yet" ~why:"shields hold unchecked code (D79, D80, standard 11.2)" ~designed:true in
      s
  | Word "inline" when (peek_at state 1).kind = Dot ->
      unfinished_block state ~what:"inline foreign code needs a quill, and quills aren't built yet"
        ~why:"raw code in another language goes inside an `inline.something:` block (D78, standard 11.3)" ~designed:true
  | Token.Variable _ when (
      (* $x = ... with no `change` (D33) *)
      let rec find i depth =
        match state.tokens.(i).kind with
        | Newline | End_of_file -> false
        | Left_paren | Left_bracket -> find (i + 1) (depth + 1)
        | Right_paren | Right_bracket -> find (i + 1) (depth - 1)
        | Equals when depth = 0 -> true
        | _ -> find (i + 1) depth
      in
      find state.position 0) ->
      (* trace: D33 *)
      let text = render_tokens state state.position in
      let line_end =
        let rec go i = match state.tokens.(i).kind with Newline | End_of_file -> i | _ -> go (i + 1) in
        go state.position
      in
      let last = state.tokens.(line_end - 1) in
      let at_start = { start.span with end_line = start.span.line; end_column = start.span.column } in
      raise (Line_error (Diagnostic.make ~span:(Span.join start.span last.span) ~fix:(Printf.sprintf "`change %s`" text)
                           ~edit:(at_start, "change ") Diagnostic.Compile_time_error
                           "every update starts with `change` (D33, standard 3.5)"))
  | _ ->
      let value = parse_expression state in
      finish (Expression_statement value)

(* A block the oracle doesn't build yet: one error at its opening line, and its body skipped. *)
and unfinished_block state ~what ~why ~designed : statement =
  let start = peek state in
  let closer = closer_word_of_line state in
  skip_line state;
  let depth = ref 1 in
  while !depth > 0 && peek_kind state <> End_of_file do
    if line_opens_block state && not (is_word state "case") && not (is_word state "else") then incr depth;
    if is_word state "end" then decr depth;
    skip_line state
  done;
  ignore closer;
  { statement_kind = Unfinished { what; why; designed }; statement_span = start.span }

and parse_condition state : condition =
  let value = parse_expression state in
  (* `if $s: Status.failed:` tests a case (D97) *)
  if peek_kind state = Colon && not ((peek_at state 1).kind = Newline || (peek_at state 1).kind = End_of_file) then begin
    ignore (advance state);
    let tested = parse_type state in
    Case_test (value, tested)
  end
  else Plain value

and parse_if state : statement =
  let start = advance state in
  let opener = start.span in
  let condition = parse_condition state in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let body = with_block state "if" (fun () -> parse_statements state) in
  let branches = ref [ { condition; branch_body = body } ] in
  let else_body = ref None in
  let continue = ref true in
  while !continue do
    skip_blank_lines state;
    if is_word state "else" && !else_body = None then begin
      let else_token = advance state in
      if is_word state "if" then begin
        ignore (advance state);
        match
          let c = parse_condition state in
          ignore (expect state Colon "`:`");
          end_of_line state;
          c
        with
        | c ->
            let body = with_block state "if" (fun () -> parse_statements state) in
            branches := { condition = c; branch_body = body } :: !branches
        | exception Line_error d ->
            report state d;
            skip_line state;
            let body = with_block state "if" (fun () -> parse_statements state) in
            branches := { condition = Plain { expression_kind = Bool_literal true; expression_span = else_token.span }; branch_body = body } :: !branches
      end
      else begin
        (match
           ignore (expect state Colon "`:`");
           end_of_line state
         with
         | () -> ()
         | exception Line_error d -> report state d; skip_line state);
        else_body := Some (with_block state "if" (fun () -> parse_statements state))
      end
    end
    else continue := false
  done;
  expect_closer state ~opener ~expected:"if";
  let s = statement_of (If { branches = List.rev !branches; else_body = !else_body }) start state in
  end_of_line state;
  s

and loop_name state =
  match peek_kind state with
  | Word w when not (is_keyword w) -> Some (name_of (advance state) w)
  | _ -> None

and parse_while state : statement =
  let start = advance state in
  let loop_name = loop_name state in
  let condition = parse_expression state in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer = match loop_name with Some n -> "while " ^ n.text | None -> "while" in
  let body = with_block state closer (fun () -> parse_statements state) in
  expect_closer state ~opener:start.span ~expected:closer;
  let s = statement_of (While { loop_name; condition; body }) start state in
  end_of_line state;
  s

and parse_for state : statement =
  let start = advance state in
  let loop_name = loop_name state in
  let variable = expect_variable state in
  ignore (expect_word state "in");
  let iterable = parse_or state in
  let at =
    if is_word state "at" then begin
      ignore (advance state);
      let counting =
        if is_word state "pos" then (ignore (advance state); Pos)
        else if is_word state "offset" then (ignore (advance state); Offset)
        else unexpected state "`pos` or `offset`"
      in
      Some (counting, expect_variable state)
    end
    else None
  in
  (* trace: D134 — `?` right after the list is the for line's own handling *)
  let iterable, written_pass_up =
    match iterable.expression_kind with
    | Pass_up inner when at_line_end_after_colon state -> (inner, true)
    | _ -> (iterable, false)
  in
  let handling =
    if written_pass_up then Some Loop_pass_up
    else
    match peek_kind state with
    | Question -> ignore (advance state); Some Loop_pass_up
    | Double_question -> ignore (advance state); Some (Loop_fallback (parse_or state))
    | Word "otherwise" ->
        ignore (advance state);
        let family, handler, jumps = parse_handler_reference state in
        Some (Loop_handler { family; handler; jumps })
    | _ -> None
  in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer = match loop_name with Some n -> "for " ^ n.text | None -> "for" in
  let body = with_block state closer (fun () -> parse_statements state) in
  expect_closer state ~opener:start.span ~expected:closer;
  let s = statement_of (For { loop_name; variable; iterable; at; handling; body }) start state in
  end_of_line state;
  s

and at_line_end_after_colon state =
  peek_kind state = Colon && (match (peek_at state 1).kind with Newline | End_of_file -> true | _ -> false)

and parse_match state : statement =
  let start = advance state in
  let subject = parse_or state in
  let with_handler =
    if is_word state "with" then begin
      ignore (advance state);
      Some (parse_handler_reference state)
    end
    else None
  in
  match with_handler with
  | Some (family, handler, jumps) ->
      (* trace: D100 — `match $x with family.handler` is a one-line match *)
      let s = statement_of (Match { subject; match_arms = Match_with { family; handler; jumps } }) start state in
      end_of_line state;
      s
  | None ->
      ignore (expect state Colon "`:`");
      end_of_line state;
      let match_arms = Match_arms (with_block state "match" (fun () -> parse_arms state)) in
      expect_closer state ~opener:start.span ~expected:"match";
      let s = statement_of (Match { subject; match_arms }) start state in
      end_of_line state;
      s

(* ---------- Declarations ---------- *)

let peek_kind_at_next_is_not_colon state = (peek_at state 1).kind <> Colon

let parse_type_parameters ?(requirement_optional = false) state : (name * requirement) list =
  if peek_kind state = Type_open then begin
    ignore (advance state);
    let rec items acc =
      let t = peek state in
      match t.kind with
      | Token.Type_parameter p when requirement_optional && peek_kind_at_next_is_not_colon state ->
          (* an interface's own `?Self` names the type that satisfies it, with no requirement (D104) *)
          ignore (advance state);
          let item = ({ text = p; span = t.span }, { requirement_names = [] }) in
          if peek_kind state = Comma then (ignore (advance state); items (item :: acc)) else List.rev (item :: acc)
      | Token.Type_parameter p ->
          ignore (advance state);
          ignore (expect state Colon "`:` and its requirement");
          let rec requirements acc =
            let n = expect_name state "a requirement such as `Any`" in
            if is_word state "and" then (ignore (advance state); requirements (n :: acc)) else List.rev (n :: acc)
          in
          let item = ({ text = p; span = t.span }, { requirement_names = requirements [] }) in
          if peek_kind state = Comma then (ignore (advance state); items (item :: acc)) else List.rev (item :: acc)
      | _ -> unexpected state "a type parameter such as `?Item`"
    in
    let result = items [] in
    ignore (expect state Type_close "`>`");
    result
  end
  else []

let parse_parameters state : parameter list =
  ignore (expect state Left_bracket "`[`");
  let rec items acc =
    if peek_kind state = Right_bracket then (ignore (advance state); List.rev acc)
    else begin
      let self_mutable = if is_word state "mut" then (ignore (advance state); true) else false in
      let parameter = expect_variable state in
      ignore (expect state Colon "`:` and the parameter's type");
      let parameter_type = parse_type state in
      let acc = { self_mutable; parameter; parameter_type } :: acc in
      match peek_kind state with
      | Comma -> ignore (advance state); items acc
      | Right_bracket -> ignore (advance state); List.rev acc
      | _ -> unexpected state "`,` or `]`"
    end
  in
  items []

let parse_failure_shape state : failure_shape =
  let failure_name = expect_dotted_name state "a failure's name" in
  let failure_fields =
    if peek_kind state = Left_bracket && not (peek state).space_before then begin
      ignore (advance state);
      let rec items acc =
        if peek_kind state = Right_bracket then List.rev acc
        else begin
          let n = expect_name state "a field name" in
          ignore (expect state Colon "`:`");
          let t = parse_type state in
          let acc = (n, t) :: acc in
          if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
        end
      in
      let result = items [] in
      ignore (expect state Right_bracket "`]`");
      result
    end
    else []
  in
  { failure_name; failure_fields }

let parse_fails state : failure_shape list =
  if is_word state "fails" then begin
    ignore (advance state);
    ignore (expect state Left_bracket "`[`");
    let rec items acc =
      if peek_kind state = Right_bracket then List.rev acc
      else
        let shape = parse_failure_shape state in
        if peek_kind state = Comma then (ignore (advance state); items (shape :: acc)) else List.rev (shape :: acc)
    in
    let result = items [] in
    ignore (expect state Right_bracket "`]`");
    result
  end
  else []

(* The top of a body: labels, defaults, requires, ensures, in that order (D42). *)
let parse_body_top state =
  let labels = ref [] and defaults = ref [] and requires = ref [] and ensures = ref [] in
  let stage = ref 0 in
  let order_why = "the top of a body says `labels`, `defaults`, `requires` and `ensures`, in that order (D42, standard 5.3)" in
  let rec go () =
    skip_blank_lines state;
    let t = peek state in
    let at_stage n word =
      if !stage > n then
        report state (error_diagnostic ~what:(Printf.sprintf "`%s` comes earlier in the top of the body" word) t.span order_why);
      stage := max !stage n
    in
    let attempt f =
      (match f () with () -> () | exception Line_error d -> report state d; skip_line state);
      go ()
    in
    match t.kind with
    | Word "labels" ->
        at_stage 1 "labels";
        attempt (fun () ->
            ignore (advance state);
            ignore (expect state Left_bracket "`[`");
            let rec items acc =
              if peek_kind state = Right_bracket then List.rev acc
              else begin
                let v = expect_variable state in
                ignore (expect_word state "as");
                let l = expect_name state "a label" in
                let acc = (v, l) :: acc in
                if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
              end
            in
            labels := !labels @ items [];
            ignore (expect state Right_bracket "`]`");
            end_of_line state)
    | Word "defaults" ->
        at_stage 2 "defaults";
        attempt (fun () ->
            ignore (advance state);
            ignore (expect state Left_bracket "`[`");
            let rec items acc =
              if peek_kind state = Right_bracket then List.rev acc
              else begin
                let v = expect_variable state in
                ignore (expect state Equals "`=`");
                let e = parse_expression state in
                let acc = (v, e) :: acc in
                if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
              end
            in
            defaults := !defaults @ items [];
            ignore (expect state Right_bracket "`]`");
            end_of_line state)
    | Word "requires" ->
        at_stage 3 "requires";
        attempt (fun () ->
            ignore (advance state);
            requires := !requires @ [ parse_expression state ];
            end_of_line state)
    | Word "ensures" ->
        at_stage 4 "ensures";
        attempt (fun () ->
            ignore (advance state);
            ensures := !ensures @ [ parse_expression state ];
            end_of_line state)
    | _ -> ()
  in
  go ();
  (!labels, !defaults, !requires, !ensures)

(* `fn.pure.baked name<...>[...] -> Type fails [...]:` and its body, up to `end fn... name`. *)
let parse_function state ~(keyword : string) : function_declaration =
  let start = expect_word state keyword in
  let narrowings = dotted_words state in
  let narrowing_words = List.map (fun n -> n.text) narrowings in
  (* trace: D41 *)
  let valid_orders = [ []; [ "pure" ]; [ "pure"; "baked" ]; [ "main" ] ] in
  if not (List.mem narrowing_words valid_orders) then begin
    let sorted = List.sort compare narrowing_words in
    let span = match narrowings with [] -> start.span | n :: _ -> Span.join start.span (List.nth narrowings (List.length narrowings - 1)).span |> fun s -> ignore n; s in
    if sorted = List.sort compare [ "pure"; "baked" ] then
      report state (error_diagnostic ~fix:(Printf.sprintf "`%s.pure.baked`" keyword) span
                      "narrowings go strongest first (D41, standard 5.2)")
    else
      report state (error_diagnostic
                      ~what:(Printf.sprintf "`%s.%s` isn't a kind of function" keyword (String.concat "." narrowing_words))
                      span "what kind of function it is goes on `fn` after a dot (D41, standard 5.2)")
  end;
  let is_main = narrowing_words = [ "main" ] in
  let function_my, function_name =
    if is_main then (false, { text = "main"; span = Span.join start.span (List.hd narrowings).span })
    else if is_word state "my" && (peek_at state 1).kind = Double_colon then begin
      ignore (advance state);
      ignore (advance state);
      (true, expect_name state "the function's name")
    end
    else (false, expect_name state "the function's name")
  in
  (* trace: D13 — a broken header still creates the function, and whatever is broken counts as unknown *)
  let type_parameters = ref [] and parameters = ref [] and result = ref None and fails = ref [] in
  let header_broken =
    match
      type_parameters := parse_type_parameters state;
      parameters := parse_parameters state;
      result := (if peek_kind state = Arrow then (ignore (advance state); Some (parse_type state)) else None);
      fails := parse_fails state;
      ignore (expect state Colon "`:`");
      end_of_line state
    with
    | () -> false
    | exception Line_error d ->
        report state d;
        skip_line state;
        true
  in
  let type_parameters = !type_parameters and parameters = !parameters and result = !result and fails = !fails in
  let closer =
    let head = String.concat "." (keyword :: narrowing_words) in
    if is_main then head else head ^ " " ^ (if function_my then "my::" else "") ^ function_name.text
  in
  let labels, defaults, requires, ensures, body =
    with_block state closer (fun () ->
        let labels, defaults, requires, ensures = parse_body_top state in
        let body = parse_statements state in
        (labels, defaults, requires, ensures, body))
  in
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  { narrowings; function_name; function_my; type_parameters; parameters; result; fails; labels;
    defaults; requires; ensures; body; function_span = start.span; function_visibility = File_only; header_broken }

let parse_visibility state : visibility * Token.t option =
  if is_word state "pub" then begin
    let t = advance state in
    match dotted_words state with
    | [ { text = "pkg"; _ } ] -> (Package, Some t)
    | [ { text = "all"; _ } ] -> (Everyone, Some t)
    | [] ->
        (* trace: D106 — the declaration is still read, seen only in its file, so nothing else is refused (D13) *)
        report state (error_diagnostic ~what:"a bare `pub` doesn't say how far: `pub.pkg` or `pub.all`" t.span
                        "`pub` always says how far (D106, standard 9.2a)");
        (File_only, Some t)
    | _ -> unexpected state "`pub.pkg` or `pub.all`"
  end
  else (File_only, None)


(* Skips a block the oracle doesn't build yet, up to its matching `end`. *)
let skip_block state =
  skip_line state;
  let depth = ref 1 in
  while !depth > 0 && peek_kind state <> End_of_file do
    skip_blank_lines state;
    if peek_kind state <> End_of_file then begin
      if is_word state "end" then decr depth
      else if line_opens_block state && not (is_word state "case") && not (is_word state "else") then incr depth;
      skip_line state
    end
  done

(* `versions name:`, then each version as its parameter list and body, `end version`, up to
   `end versions name` (D46). *)
let parse_versions state : family_member =
  let start = expect_word state "versions" in
  let versions_name = expect_name state "the name the versions share" in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer = "versions " ^ versions_name.text in
  let versions =
    with_block state closer (fun () ->
        let rec go acc =
          skip_blank_lines state;
          if is_word state "end" || peek_kind state = End_of_file then List.rev acc
          else
            match
              let opener = peek state in
              let parameters = parse_parameters state in
              let result = if peek_kind state = Arrow then (ignore (advance state); Some (parse_type state)) else None in
              let fails = parse_fails state in
              ignore (expect state Colon "`:`");
              end_of_line state;
              let labels, defaults, requires, ensures, body =
                with_block state "version" (fun () ->
                    let labels, defaults, requires, ensures = parse_body_top state in
                    (labels, defaults, requires, ensures, parse_statements state))
              in
              expect_closer state ~opener:opener.span ~expected:"version";
              end_of_line state;
              { narrowings = []; function_name = { versions_name with span = opener.span }; function_my = false;
                type_parameters = []; parameters; result; fails; labels; defaults; requires; ensures; body;
                function_span = opener.span; function_visibility = File_only; header_broken = false }
            with
            | v -> go (v :: acc)
            | exception Line_error d -> report state d; skip_block state; go acc
        in
        go [])
  in
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  Member_versions { versions_name; versions }

(* `interface Name<?Self>:` with `includes` and `op` lines (D104, D105). *)
let parse_interface state : declaration_kind =
  let start = expect_word state "interface" in
  let interface_name = expect_name state "the interface's name" in
  ignore (parse_type_parameters ~requirement_optional:true state);
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer = "interface " ^ interface_name.text in
  let includes = ref [] and operations = ref [] in
  with_block state closer (fun () ->
      let rec go () =
        skip_blank_lines state;
        if is_word state "end" || peek_kind state = End_of_file then ()
        else begin
          (match
             if is_word state "includes" then begin
               ignore (advance state);
               includes := !includes @ [ expect_name state "an interface" ];
               end_of_line state
             end
             else if is_word state "op" then begin
               ignore (advance state);
               let t = advance state in
               let symbol =
                 match t.kind with
                 | Less -> "<" | Greater -> ">" | Equals_equals -> "==" | Bang_equals -> "!=" | Plus -> "+" | Minus -> "-"
                 | Word w -> w
                 | _ -> unexpected state "an operator"
               in
               operations := !operations @ [ { text = symbol; span = t.span } ];
               ignore (parse_parameters state);
               if peek_kind state = Arrow then (ignore (advance state); ignore (parse_type state));
               end_of_line state
             end
             else unexpected state "`includes` or `op`"
           with
           | () -> ()
           | exception Line_error d -> report state d; skip_line state);
          go ()
        end
      in
      go ());
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  Interface { interface_name; includes = !includes; operations = !operations }

let parse_type_set state : declaration_kind =
  let start = expect_word state "type_set" in
  let set_name = expect_name state "the type set's name" in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer = "type_set " ^ set_name.text in
  let members =
    with_block state closer (fun () ->
        let rec go acc =
          skip_blank_lines state;
          if is_word state "end" || peek_kind state = End_of_file then List.rev acc
          else
            match let t = parse_type state in end_of_line state; t with
            | t -> go (t :: acc)
            | exception Line_error d -> report state d; skip_line state; go acc
        in
        go [])
  in
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  Type_set { set_name; members }

let unfinished_declaration state ~what ~why ~designed : declaration_kind =
  if line_opens_block state then skip_block state else skip_line state;
  Unfinished_declaration { what; why; designed }

(* A type of the program's own named like a built-in type is written with `my::` (D63). *)
let check_built_in_type_name state ~my (n : name) =
  let built_in =
    List.mem n.text [ "Int"; "Float"; "Decimal"; "Rational"; "Bool"; "String"; "List"; "Array"; "Map"; "Any" ]
    || (match n.text.[0] with 'i' | 'u' | 'f' -> String.length n.text > 1 && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub n.text 1 (String.length n.text - 1)) | _ -> false)
  in
  (* trace: D63 *)
  if built_in && not my then
    report state (error_diagnostic ~fix:(Printf.sprintf "`my::%s`" n.text) n.span
                    "a name of the program's own that is also a built-in word is written with `my::` (D63, standard 9.4)")

let parse_struct state : declaration_kind =
  let start = expect_word state "struct" in
  let struct_narrowings = dotted_words state in
  (* trace: D51, D56 — a struct's narrowings are its properties; `must_give` is the one decided *)
  List.iter
    (fun (n : name) ->
      if n.text <> "must_give" then
        report state
          (error_diagnostic ~what:(Printf.sprintf "`struct.%s` isn't a property a struct can have" n.text) n.span
             "properties of a type are narrowings on `struct` (D56, standard 2.4)"))
    struct_narrowings;
  let struct_my = if is_word state "my" && (peek_at state 1).kind = Double_colon then (ignore (advance state); ignore (advance state); true) else false in
  let struct_name = expect_name state "the struct's name" in
  check_built_in_type_name state ~my:struct_my struct_name;
  let struct_type_parameters = parse_type_parameters state in
  ignore (expect state Colon "`:`");
  end_of_line state;
  let closer =
    String.concat "." ("struct" :: List.map (fun n -> n.text) struct_narrowings) ^ " " ^ (if struct_my then "my::" else "")
    ^ struct_name.text
  in
  let fields =
    with_block state closer (fun () ->
        let rec go acc =
          skip_blank_lines state;
          if is_word state "end" || peek_kind state = End_of_file then List.rev acc
          else
            match
              let field_visibility, _ = parse_visibility state in
              let field_name = expect_name state "a field's name" in
              ignore (expect state Colon "`:` and the field's type");
              let field_type = parse_type state in
              let field_default =
                if peek_kind state = Equals then (ignore (advance state); Some (parse_expression state)) else None
              in
              end_of_line state;
              { field_name; field_type; field_default; field_visibility }
            with
            | field -> go (field :: acc)
            | exception Line_error d -> report state d; skip_line state; go acc
        in
        go [])
  in
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  Struct { struct_narrowings; struct_name; struct_type_parameters; fields }

let parse_union state : declaration_kind =
  let start = expect_word state "union" in
  let narrowings = dotted_words state in
  (* trace: D97 *)
  (match narrowings with
   | [ { text = "tagged"; _ } ] -> ()
   | [] -> report state (error_diagnostic ~fix:"`union.tagged`" start.span "a union is always written `union.tagged` (D97, standard 2.4a)")
   | _ -> unexpected state "`union.tagged`");
  let union_my = if is_word state "my" && (peek_at state 1).kind = Double_colon then (ignore (advance state); ignore (advance state); true) else false in
  let union_name = expect_name state "the union's name" in
  check_built_in_type_name state ~my:union_my union_name;
  let union_type_parameters = parse_type_parameters state in
  ignore (expect state Colon "`:`");
  end_of_line state;
  (* the closer repeats what the opening line said (D24) *)
  let closer = (if narrowings = [] then "union " else "union.tagged ") ^ (if union_my then "my::" else "") ^ union_name.text in
  let cases =
    with_block state closer (fun () ->
        let rec go acc =
          skip_blank_lines state;
          if is_word state "end" || peek_kind state = End_of_file then List.rev acc
          else
            match
              let shape = parse_failure_shape state in
              end_of_line state;
              { union_case = shape.failure_name; case_fields = shape.failure_fields }
            with
            | c -> go (c :: acc)
            | exception Line_error d -> report state d; skip_line state; go acc
        in
        go [])
  in
  expect_closer state ~opener:start.span ~expected:closer;
  end_of_line state;
  Union { union_name; union_type_parameters; cases }

let parse_family state : declaration_kind =
  let start = expect_word state "fam" in
  let narrowings = dotted_words state in
  match narrowings with
  | { text = "fn"; _ } :: family_narrowings ->
      let family_name = expect_name state "the family's name" in
      ignore (expect state Colon "`:`");
      end_of_line state;
      let closer =
        String.concat "." ("fam" :: List.map (fun n -> n.text) narrowings) ^ " " ^ family_name.text
      in
      let members =
        with_block state closer (fun () ->
            let rec go acc =
              skip_blank_lines state;
              if is_word state "end" || peek_kind state = End_of_file then List.rev acc
              else if is_word state "fn" || (is_word state "pub" && is_word_at state 3 "fn") then
                match
                  let visibility, _ = parse_visibility state in
                  { (parse_function state ~keyword:"fn") with function_visibility = visibility }
                with
                | f -> go (Member_function f :: acc)
                | exception Line_error d -> report state d; skip_block state; go acc
              else if is_word state "preset" then
                match
                  ignore (advance state);
                  let preset_name = expect_name state "the preset's name" in
                  ignore (expect state Left_bracket "`[`");
                  let rec items acc =
                    if peek_kind state = Right_bracket then List.rev acc
                    else begin
                      let v = expect_variable state in
                      ignore (expect state Equals "`=`");
                      let e = parse_expression state in
                      let acc = (v, e) :: acc in
                      if peek_kind state = Comma then (ignore (advance state); items acc) else List.rev acc
                    end
                  in
                  let settings = items [] in
                  ignore (expect state Right_bracket "`]`");
                  end_of_line state;
                  Member_preset { preset_name; settings }
                with
                | m -> go (m :: acc)
                | exception Line_error d -> report state d; skip_line state; go acc
              else if is_word state "versions" then
                match parse_versions state with
                | m -> go (m :: acc)
                | exception Line_error d -> report state d; skip_block state; go acc
              else
                match unexpected state "`fn`, `preset` or `versions`" with
                | _ -> go acc
                | exception Line_error d -> report state d; skip_line state; go acc
            in
            go [])
      in
      expect_closer state ~opener:start.span ~expected:closer;
      end_of_line state;
      Family_function { family_narrowings; family_name; members }
  | [ { text = "failure"; _ } ] ->
      let failure_family = expect_name state "the family's name" in
      ignore (expect state Colon "`:`");
      end_of_line state;
      let closer = "fam.failure " ^ failure_family.text in
      let failures =
        with_block state closer (fun () ->
            let rec go acc =
              skip_blank_lines state;
              if is_word state "end" || peek_kind state = End_of_file then List.rev acc
              else
                match
                  ignore (expect_word state "failure");
                  let shape = parse_failure_shape state in
                  end_of_line state;
                  shape
                with
                | f -> go (f :: acc)
                | exception Line_error d -> report state d; skip_line state; go acc
            in
            go [])
      in
      expect_closer state ~opener:start.span ~expected:closer;
      end_of_line state;
      Family_failure { failure_family; failures }
  | [ { text = "handler"; _ } ] ->
      let handler_family = expect_name state "the family's name" in
      ignore (expect state Colon "`:`");
      end_of_line state;
      let closer = "fam.handler " ^ handler_family.text in
      let handlers =
        with_block state closer (fun () ->
            let rec go acc =
              skip_blank_lines state;
              if is_word state "end" || peek_kind state = End_of_file then List.rev acc
              else
                match
                  let t = expect_word state "handler" in
                  let handler_name = expect_name state "the handler's name" in
                  if peek_kind state = Left_bracket then
                    raise (Line_error (Diagnostic.make ~span:(peek state).span ~what:"handlers taking arguments aren't decided yet"
                                         Diagnostic.Not_designed_yet "not decided yet (D49, standard 12.2)"));
                  ignore (expect state Colon "`:`");
                  end_of_line state;
                  let inner = "handler " ^ handler_name.text in
                  let handler_arms = with_block state inner (fun () -> parse_arms state) in
                  expect_closer state ~opener:t.span ~expected:inner;
                  end_of_line state;
                  { handler_name; handler_arms }
                with
                | h -> go (h :: acc)
                | exception Line_error d ->
                    report state d;
                    (* a refused `handler` line skips its whole block, up to its `end` *)
                    if line_opens_block state then skip_block state else skip_line state;
                    go acc
            in
            go [])
      in
      expect_closer state ~opener:start.span ~expected:closer;
      end_of_line state;
      Family_handler { handler_family; handlers }
  | [ { text = "type"; _ }; { text = "new"; _ } ] ->
      (* trace: D61 *)
      let type_family = expect_name state "the family's name" in
      ignore (expect state Colon "`:`");
      end_of_line state;
      let closer = "fam.type.new " ^ type_family.text in
      let new_types =
        with_block state closer (fun () ->
            let rec go acc =
              skip_blank_lines state;
              if is_word state "end" || peek_kind state = End_of_file then List.rev acc
              else
                match
                  ignore (expect_word state "type");
                  let n = expect_name state "the type's name" in
                  ignore (expect state Equals "`=`");
                  let t = parse_type state in
                  end_of_line state;
                  (n, t)
                with
                | m -> go (m :: acc)
                | exception Line_error d -> report state d; skip_line state; go acc
            in
            go [])
      in
      expect_closer state ~opener:start.span ~expected:closer;
      end_of_line state;
      Family_type_new { type_family; new_types }
  | { text = "unit"; _ } :: _ ->
      unfinished_declaration state ~what:"units aren't built yet: they come after v1"
        ~why:"units are designed now and built after v1 (D58, standard 2.6)" ~designed:true
  | _ ->
      fail_line
        ~what:(Printf.sprintf "`fam.%s` isn't a kind of family: they're `fam.fn`, `fam.failure`, `fam.handler`, `fam.type.new` and `fam.unit`"
                 (String.concat "." (List.map (fun n -> n.text) narrowings)))
        start.span "every family writes its members short, with a keyword (D45, D49, standard 5.5)"

let parse_type_declaration state : declaration_kind =
  let start = expect_word state "type" in
  match dotted_words state with
  | [ { text = "alias"; _ } ] ->
      let alias_name = expect_name state "the type's name" in
      ignore (expect state Equals "`=`");
      let aliased = parse_type state in
      end_of_line state;
      Type_alias { alias_name; aliased }
  | [ { text = "new"; _ } ] ->
      let new_name = expect_name state "the type's name" in
      ignore (expect state Equals "`=`");
      let underlying = parse_type state in
      end_of_line state;
      Type_new { new_name; underlying }
  | _ ->
      (* trace: D61 *)
      fail_line ~what:"a bare `type` doesn't say which: `type.alias` or `type.new`" start.span
        "there's no bare `type` (D61, standard 2.5)"

let parse_declaration state : declaration option =
  skip_blank_lines state;
  let start = peek state in
  if start.kind = End_of_file then None
  else
    let attempt () =
      let visibility, _ = parse_visibility state in
      let kind =
        match peek_kind state with
        | Word "fn" ->
            (* trace: D62 *)
            if is_word_at state 1 "main" && (peek_at state 2).kind = Left_bracket then begin
              let t = peek_at state 1 in
              report state (error_diagnostic ~fix:"`fn.main`" (Span.join start.span t.span)
                              "a program starts at its one `fn.main` (D62, standard 5.9)")
            end;
            let f = parse_function state ~keyword:"fn" in
            (* trace: D106 *)
            if List.map (fun n -> n.text) f.narrowings = [ "main" ] && visibility <> File_only then
              report state
                (error_diagnostic ~what:"`fn.main` is where the program starts, so it takes no `pub`" start.span
                   "`pub.…` on `fn.main` is refused (D106, standard 9.2a)");
            Function { f with function_visibility = visibility }
        | Word "struct" -> parse_struct state
        | Word "union" -> parse_union state
        | Word "fam" -> parse_family state
        | Word "type" -> parse_type_declaration state
        | Word "interface" -> parse_interface state
        | Word "type_set" -> parse_type_set state
        | Word "shield" ->
            unfinished_declaration state ~what:"shields aren't built yet"
              ~why:"shields hold unchecked code (D79, D80, standard 11.2)" ~designed:true
        | _ when (let rec find i = match state.tokens.(i).kind with
                    | Word "satisfies" -> true | Newline | End_of_file -> false | _ -> find (i + 1) in find state.position) ->
            (* trace: D105 *)
            let satisfying = parse_type state in
            ignore (expect_word state "satisfies");
            let interface = expect_name state "an interface" in
            end_of_line state;
            Satisfies { satisfying; interface }
        | Word "let" ->
            (* trace: D139 *)
            if is_word_at state 1 "mut" then begin
              let let_token = peek state and mut_token = peek_at state 1 in
              report state
                (Diagnostic.make ~span:(Span.join let_token.span mut_token.span) ~fix:"`let`"
                   Diagnostic.Compile_time_error "a `let` at the top of a file can't be `mut` (D139, standard 3.1)")
            end;
            Global (parse_statement_line state)
        | Word ("decl" | "shadow") ->
            unfinished_declaration state ~what:"a `decl` or `shadow` outside a function isn't decided yet"
              ~why:"not decided yet (D139, standard 3.1)" ~designed:false
        | _ ->
            fail_line ~what:(Printf.sprintf "`%s` can't start a declaration" (token_text (peek state)))
              (peek state).span "a file holds declarations: functions, types and families (D45, standard 5.5)"
      in
      { declaration_kind = kind; visibility; declaration_span = start.span }
    in
    match attempt () with
    | d -> Some d
    | exception Line_error d ->
        report state d;
        if line_opens_block state then skip_block state else skip_line state;
        Some { declaration_kind = Unfinished_declaration { what = ""; why = ""; designed = true };
               visibility = File_only; declaration_span = start.span }

let parse_file ~(file : string) (tokens : Token.t array) : Syntax.file * Diagnostic.t list =
  let state = { tokens; position = 0; diagnostics = []; open_blocks = [] } in
  let rec go acc =
    match parse_declaration state with
    | None -> List.rev acc
    | Some { declaration_kind = Unfinished_declaration { what = ""; _ }; _ } -> go acc
    | Some d -> go (d :: acc)
  in
  let declarations = go [] in
  ({ file_name = file; declarations }, List.rev state.diagnostics)
