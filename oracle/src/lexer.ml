(* Turns a file's text into tokens (standard chapter 1).

   A line break ends a statement (D19), except inside ( ) and [ ] (D64). Comments are dropped,
   and a named comment block is skipped up to its own end line (D96). Spellings Jernal refuses
   are reported here; when they have one fix, the fixed token is used, so checking carries on
   as if the fix were applied (D13). *)

open Token

type state = {
  file : string;
  mutable tokens : Token.t list;          (* reversed *)
  mutable diagnostics : Diagnostic.t list;
  mutable bracket_depth : int;            (* ( and [ *)
  mutable bracket_opener : Span.t option; (* the outermost unclosed ( or [ *)
  mutable type_depth : int;               (* < > as type brackets, on this line *)
}

let error state ?what ?fix ?edit span why =
  state.diagnostics <- Diagnostic.make ~span ?what ?fix ?edit Diagnostic.Compile_time_error why :: state.diagnostics

let not_designed state ~what span why =
  state.diagnostics <- Diagnostic.make ~span ~what Diagnostic.Not_designed_yet why :: state.diagnostics

let is_word_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_word_char c = is_word_start c || (c >= '0' && c <= '9')
let is_digit c = c >= '0' && c <= '9'
let is_space c = c = ' ' || c = '\t'

(* Words that start a statement or a block. A line starting with one of these can't be an item
   continuing a bracket from the line before. *)
let statement_words =
  [ "let"; "decl"; "assign"; "shadow"; "change"; "return"; "if"; "else"; "for"; "while"; "break";
    "match"; "case"; "end"; "fail"; "fn"; "struct"; "union"; "fam"; "type"; "interface";
    "type_set"; "instead"; "labels"; "defaults"; "requires"; "ensures"; "pub"; "shield";
    "comment"; "versions"; "preset"; "handler"; "failure" ]

let first_word (line : string) : string =
  let length = String.length line in
  let rec skip i = if i < length && is_space line.[i] then skip (i + 1) else i in
  let start = skip 0 in
  let rec stop i = if i < length && is_word_char line.[i] then stop (i + 1) else i in
  let finish = stop start in
  String.sub line start (finish - start)

(* "comment name:" alone on a line opens a comment block (D96). *)
let comment_block_name (line : string) : string option =
  let trimmed = String.trim line in
  let words = String.split_on_char ' ' trimmed |> List.filter (fun w -> w <> "") in
  match words with
  | [ "comment"; name_colon ] when String.length name_colon > 1
                                   && name_colon.[String.length name_colon - 1] = ':' ->
      let name = String.sub name_colon 0 (String.length name_colon - 1) in
      if String.for_all is_word_char name then Some name else None
  | _ -> None

(* "inline.<name>:" alone on a line opens raw foreign code, which tools leave alone (D78). *)
let inline_block_name (line : string) : string option =
  let trimmed = String.trim line in
  let n = String.length trimmed in
  if n > 8 && String.sub trimmed 0 7 = "inline." && trimmed.[n - 1] = ':' then
    let name = String.sub trimmed 7 (n - 8) in
    if name <> "" && String.for_all is_word_char name then Some ("inline." ^ name) else None
  else None

(* The run of characters with no space in it, ending just before [index] / starting at [index]. *)
let stuck_run_before (line : string) (index : int) : string =
  let stops c = is_space c || c = '(' || c = '[' || c = ',' in
  let rec back i = if i > 0 && not (stops line.[i - 1]) then back (i - 1) else i in
  let start = back index in
  String.sub line start (index - start)

let stuck_run_after (line : string) (index : int) : string =
  let length = String.length line in
  let stops c = is_space c || c = ':' || c = ',' || c = ')' || c = ']' in
  let rec forward i = if i < length && not (stops line.[i]) then forward (i + 1) else i in
  let finish = forward index in
  String.sub line index (finish - index)

let spacing_why = "a comparison has a space on both sides, and type brackets stick to the name before them (D18, standard 1.5)"

let lex_line state (line : string) (line_number : int) =
  let length = String.length line in
  let file = state.file in
  let span_of start finish =
    Span.make ~file ~line:line_number ~column:(start + 1) ~end_line:line_number ~end_column:(finish + 1)
  in
  let previous_kind () = match state.tokens with t :: _ -> Some t.kind | [] -> None in
  let previous_on_this_line () =
    match state.tokens with
    | t :: _ when t.span.line = line_number && t.kind <> Newline -> Some t
    | _ -> None
  in
  let push kind start finish space_before =
    state.tokens <- { kind; span = span_of start finish; space_before } :: state.tokens
  in
  let broken start finish = push Broken start finish true in
  let rec go i space_before =
    if i >= length then ()
    else
      let c = line.[i] in
      if is_space c then go (i + 1) true
      else if c = '/' && i + 1 < length && line.[i + 1] = '/' then ()   (* a comment, // or /// *)
      else if c = '$' then begin
        let rec stop j = if j < length && is_word_char line.[j] then stop (j + 1) else j in
        let finish = stop (i + 1) in
        if finish = i + 1 then begin
          error state ~what:"`$` starts a variable's name, and no name follows it" (span_of i (i + 1))
            "a variable's name starts with `$` (D56, standard 1.3)";
          broken i (i + 1)
        end
        else push (Variable (String.sub line (i + 1) (finish - i - 1))) i finish space_before;
        go finish false
      end
      else if is_word_start c then begin
        let rec stop j = if j < length && is_word_char line.[j] then stop (j + 1) else j in
        let finish = stop i in
        push (Word (String.sub line i (finish - i))) i finish space_before;
        go finish false
      end
      else if is_digit c then begin
        let rec digits j = if j < length && is_digit line.[j] then digits (j + 1) else j in
        let integer_end = digits i in
        let finish, kind =
          if integer_end + 1 < length && line.[integer_end] = '.' && is_digit line.[integer_end + 1] then
            let fraction_end = digits (integer_end + 1) in
            (fraction_end, Decimal_literal (String.sub line i (fraction_end - i)))
          else (integer_end, Integer_literal (String.sub line i (integer_end - i)))
        in
        if finish < length && is_word_start line.[finish] then begin
          let rec stop j = if j < length && is_word_char line.[j] then stop (j + 1) else j in
          let word_end = stop finish in
          let tail = String.sub line finish (word_end - finish) in
          let is_exponent =
            (tail.[0] = 'e' || tail.[0] = 'E')
            && String.length tail > 1
            && String.for_all is_digit (String.sub tail 1 (String.length tail - 1))
          in
          if is_exponent then
            not_designed state ~what:"exponent literals aren't decided yet" (span_of i word_end)
              "not decided yet (D120, standard 12.1)"
          else
            error state
              ~what:(Printf.sprintf "`%s` runs a number into a name" (String.sub line i (word_end - i)))
              (span_of i word_end) "a number literal is digits, with an optional `.` and more digits (D84, standard 2.1a)";
          broken i word_end;
          go word_end false
        end
        else begin
          push kind i finish space_before;
          go finish false
        end
      end
      else if c = '"' then begin
        let buffer = Buffer.create 16 in
        let rec read j ok =
          if j >= length then (j, false, ok)
          else
            match line.[j] with
            | '"' -> (j + 1, true, ok)
            | '\\' ->
                if j + 1 < length && (line.[j + 1] = '"' || line.[j + 1] = '\\') then begin
                  Buffer.add_char buffer line.[j + 1];
                  read (j + 2) ok
                end
                else begin
                  (* trace: D95 *)
                  let escape_end =
                    if j + 1 < length then
                      j + 1 + Uchar.utf_decode_length (String.get_utf_8_uchar line (j + 1))
                    else j + 1
                  in
                  error state
                    ~what:(Printf.sprintf "`%s` isn't an escape: only `\\\"` and `\\\\` are"
                             (String.sub line j (escape_end - j)))
                    (span_of j escape_end) "`\\` is always special in a string (D95, standard 2.2)";
                  read escape_end false
                end
            | _ ->
                let decoded = String.get_utf_8_uchar line j in
                let width = Uchar.utf_decode_length decoded in
                let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
                (* trace: D95, D139 — every control character, and U+2028 and U+2029 *)
                if code < 0x20 || (code >= 0x7F && code <= 0x9F) || code = 0x2028 || code = 0x2029 then begin
                  error state ~what:(Printf.sprintf "a string can't hold U+%04X" code) (span_of j (j + width))
                    "plain strings hold no control characters, and no U+2028 or U+2029 (D95, D139, standard 2.2)";
                  read (j + width) false
                end
                else begin
                  Buffer.add_string buffer (String.sub line j width);
                  read (j + width) ok
                end
        in
        let finish, closed, ok = read (i + 1) true in
        if not closed then begin
          error state ~what:"this string has no closing `\"` on its line" (span_of i finish)
            "a string is written in double quotes on one line (D19, standard 2.2)";
          broken i finish
        end
        else if not ok then broken i finish
        else push (String_literal (Buffer.contents buffer)) i finish space_before;
        go finish false
      end
      else begin
        let next = if i + 1 < length then Some line.[i + 1] else None in
        let space_after_at j = j >= length || is_space line.[j] in
        let simple kind width =
          push kind i (i + width) space_before;
          go (i + width) false
        in
        (* A refused spelling with one fix: report it, then carry on with the fixed word. *)
        let refused_word ~fix_word ~why width =
          error state ~fix:(Printf.sprintf "`%s`" fix_word) ~edit:(span_of i (i + width), " " ^ fix_word ^ " ")
            (span_of i (i + width)) why;
          push (Word fix_word) i (i + width) true;
          go (i + width) true
        in
        match c, next with
        | '(', _ ->
            if state.bracket_depth = 0 then state.bracket_opener <- Some (span_of i (i + 1));
            state.bracket_depth <- state.bracket_depth + 1;
            simple Left_paren 1
        | '[', _ ->
            if state.bracket_depth = 0 then state.bracket_opener <- Some (span_of i (i + 1));
            state.bracket_depth <- state.bracket_depth + 1;
            simple Left_bracket 1
        | (')' | ']'), _ ->
            state.bracket_depth <- max 0 (state.bracket_depth - 1);
            simple (if c = ')' then Right_paren else Right_bracket) 1
        | ',', _ -> simple Comma 1
        | ':', Some ':' -> simple Double_colon 2
        | ':', _ -> simple Colon 1
        | '.', Some '.' ->
            error state ~what:"there's no `..`; a range is written `range[from: ..., to: ...]`"
              (span_of i (i + 2)) "a range is labelled (D37, standard 4.7)";
            broken i (i + 2);
            go (i + 2) false
        | '.', _ -> simple Dot 1
        | '=', Some '=' -> simple Equals_equals 2
        | '=', Some '>' -> simple Fat_arrow 2
        | '=', _ -> simple Equals 1
        | '!', Some '=' -> simple Bang_equals 2
        | '!', _ -> refused_word ~fix_word:"not" ~why:"logic is written in words (D28, standard 4.2)" 1
        | '&', Some '&' -> refused_word ~fix_word:"and" ~why:"logic is written in words (D28, standard 4.2)" 2
        | '|', Some '|' -> refused_word ~fix_word:"or" ~why:"logic is written in words (D28, standard 4.2)" 2
        | '>', Some '=' ->
            refused_word ~fix_word:"at_least" ~why:"comparisons that include the end are words (D27, standard 4.1)" 2
        | '<', Some '=' ->
            refused_word ~fix_word:"at_most" ~why:"comparisons that include the end are words (D27, standard 4.1)" 2
        | '-', Some '>' -> simple Arrow 2
        | ('+' | '-' | '*'), Some '=' ->
            error state
              ~what:(Printf.sprintf "there's no `%c=`; an update is written `change $x = $x %c ...`" c c)
              (span_of i (i + 2)) "every update starts with `change` and reads in order (D32, standard 3.5)";
            broken i (i + 2);
            go (i + 2) false
        | '+', Some '+' | '-', Some '-' ->
            error state
              ~what:(Printf.sprintf "there's no `%c%c`; an update is written `change $x = $x %c 1`" c c c)
              (span_of i (i + 2)) "every update starts with `change` and reads in order (D32, standard 3.5)";
            broken i (i + 2);
            go (i + 2) false
        | '+', _ -> simple Plus 1
        | '-', _ -> simple Minus 1
        | '*', _ -> simple Star 1
        | '~', _ -> simple Tilde 1
        | '?', Some '?' -> simple Double_question 2
        | '?', Some ch when ch >= 'A' && ch <= 'Z' ->
            let rec stop j = if j < length && is_word_char line.[j] then stop (j + 1) else j in
            let finish = stop (i + 1) in
            push (Type_parameter (String.sub line (i + 1) (finish - i - 1))) i finish space_before;
            go finish false
        | '?', _ -> simple Question 1
        | '/', _ ->
            error state ~what:"there's no `/`; dividing is `div`, and on integers it says which kind"
              (span_of i (i + 1)) "dividing is a word that says how it rounds (D87, D88, standard 2.1a)";
            broken i (i + 1);
            go (i + 1) false
        | ';', _ ->
            error state ~what:"there are no semicolons; a line break ends a statement" (span_of i (i + 1))
              "one statement, one line (D19, standard 1.1)";
            broken i (i + 1);
            go (i + 1) false
        | ('<' | '>'), _ when (match previous_on_this_line () with Some { kind = Word "op"; _ } -> true | _ -> false) ->
            (* `op <[...]` in an interface names the operator (D105) *)
            simple (if c = '<' then Less else Greater) 1
        | '<', _ ->
            (* trace: D18 *)
            let space_after = space_after_at (i + 1) in
            let previous_is_name =
              match previous_on_this_line () with
              | Some { kind = Word _ | Type_parameter _; _ } -> true
              | _ -> false
            in
            if previous_is_name && not space_before then begin
              state.type_depth <- state.type_depth + 1;
              simple Type_open 1
            end
            else if space_before && space_after then simple Less 1
            else if previous_is_name && space_before && not space_after then begin
              (* `List <Int>`: a type bracket with a space before it *)
              let rec matching j depth =
                if j >= length then length
                else if line.[j] = '<' then matching (j + 1) (depth + 1)
                else if line.[j] = '>' then (if depth = 1 then j + 1 else matching (j + 1) (depth - 1))
                else matching (j + 1) depth
              in
              let close = matching i 0 in
              let name = String.trim (stuck_run_before line (let rec b k = if k > 0 && is_space line.[k-1] then b (k-1) else k in b i)) in
              let fixed = name ^ String.sub line i (close - i) in
              let space_start = let rec b k = if k > 0 && is_space line.[k-1] then b (k-1) else k in b i in
              error state ~fix:(Printf.sprintf "`%s`" fixed) ~edit:(span_of space_start (i + 1), "<") (span_of i (i + 1)) spacing_why;
              state.type_depth <- state.type_depth + 1;
              push Type_open i (i + 1) false;
              go (i + 1) false
            end
            else begin
              let left = String.trim (stuck_run_before line (let rec b k = if k > 0 && is_space line.[k-1] then b (k-1) else k in b i)) in
              let rec skip k = if k < length && is_space line.[k] then skip (k + 1) else k in
              let right = stuck_run_after line (skip (i + 1)) in
              error state ~fix:(Printf.sprintf "`%s < %s`" left right) ~edit:(span_of i (i + 1), " < ") (span_of i (i + 1)) spacing_why;
              push Less i (i + 1) true;
              go (i + 1) true
            end
        | '>', _ ->
            (* trace: D18 *)
            let space_after = space_after_at (i + 1) in
            if state.type_depth > 0 && not space_before then begin
              state.type_depth <- state.type_depth - 1;
              simple Type_close 1
            end
            else if space_before && space_after then simple Greater 1
            else if state.type_depth > 0 then begin
              let space_start = let rec b k = if k > 0 && is_space line.[k-1] then b (k-1) else k in b i in
              error state ~fix:"`>` right after the type it closes" ~edit:(span_of space_start (i + 1), ">") (span_of i (i + 1)) spacing_why;
              state.type_depth <- state.type_depth - 1;
              push Type_close i (i + 1) false;
              go (i + 1) false
            end
            else begin
              let left = String.trim (stuck_run_before line (let rec b k = if k > 0 && is_space line.[k-1] then b (k-1) else k in b i)) in
              let rec skip k = if k < length && is_space line.[k] then skip (k + 1) else k in
              let right = stuck_run_after line (skip (i + 1)) in
              error state ~fix:(Printf.sprintf "`%s > %s`" left right) ~edit:(span_of i (i + 1), " > ") (span_of i (i + 1)) spacing_why;
              push Greater i (i + 1) true;
              go (i + 1) true
            end
        | _ ->
            let width = Uchar.utf_decode_length (String.get_utf_8_uchar line i) in
            error state
              ~what:(Printf.sprintf "`%s` isn't part of Jernal's syntax" (String.sub line i width))
              (span_of i (i + width)) "the characters Jernal's syntax uses are set out in chapter 1 (D15, standard 1.4)";
            broken i (i + width);
            go (i + width) false
      end
  in
  ignore previous_kind;
  go 0 true

let lex ~(file : string) (text : string) : Token.t array * Diagnostic.t list =
  let state =
    { file; tokens = []; diagnostics = []; bracket_depth = 0; bracket_opener = None; type_depth = 0 }
  in
  let lines = Text.lines_of text in
  let count = Array.length lines in
  let push_newline line_number column =
    match state.tokens with
    | { kind = Newline; _ } :: _ | [] -> ()
    | _ ->
        state.tokens <-
          { kind = Newline;
            span = Span.make ~file ~line:line_number ~column ~end_line:line_number ~end_column:column;
            space_before = true }
          :: state.tokens
  in
  let rec next_code_line index =
    if index >= count then None
    else
      let trimmed = String.trim lines.(index) in
      if trimmed = "" || (String.length trimmed >= 2 && String.sub trimmed 0 2 = "//") then next_code_line (index + 1)
      else Some lines.(index)
  in
  let rec go index =
    if index >= count then ()
    else
      let line = lines.(index) in
      let line_number = index + 1 in
      match (if state.bracket_depth = 0 then inline_block_name line else None) with
      | Some block ->
          (* trace: D78 — the opening and closing lines are Jernal; the raw code between is skipped *)
          lex_line state line line_number;
          push_newline line_number (String.length line + 1);
          let closer = "end " ^ block in
          let rec find j = if j >= count then None else if String.trim lines.(j) = closer then Some j else find (j + 1) in
          (match find (index + 1) with
           | Some j ->
               lex_line state lines.(j) (j + 1);
               push_newline (j + 1) (String.length lines.(j) + 1);
               go (j + 1)
           | None -> go count)
      | None ->
      match (if state.bracket_depth = 0 then comment_block_name line else None) with
      | Some name ->
          (* trace: D96 *)
          let closer = "end comment " ^ name in
          let rec find j = if j >= count then None else if String.trim lines.(j) = closer then Some j else find (j + 1) in
          (match find (index + 1) with
           | Some j -> go (j + 1)
           | None ->
               let start = String.length line - String.length (String.trim line |> fun s -> s) in
               let indent = let rec k i = if i < String.length line && is_space line.[i] then k (i + 1) else i in k 0 in
               ignore start;
               error state
                 ~what:(Printf.sprintf "`comment %s:` has no `%s` line" name closer)
                 (Span.make ~file ~line:line_number ~column:(indent + 1) ~end_line:line_number
                    ~end_column:(String.length (String.trim line) + indent + 1))
                 "a comment block runs until its own named `end` (D96, standard 1.7)";
               ())
      | None ->
          state.type_depth <- 0;
          lex_line state line line_number;
          if state.bracket_depth > 0 then begin
            (* Inside ( ) or [ ], a line break is allowed between items (D64), unless the next line
               starts a statement, which no item can. *)
            match next_code_line (index + 1) with
            | Some next when not (List.mem (first_word next) statement_words) -> ()
            | _ ->
                let opener = Option.get state.bracket_opener in
                error state ~what:(Printf.sprintf "this bracket isn't closed")
                  opener "a bracket closes before the statement ends (D19, D64, standard 1.1)";
                state.tokens <- { kind = Broken; span = opener; space_before = true } :: state.tokens;
                state.bracket_depth <- 0;
                push_newline line_number (String.length line + 1)
          end
          else push_newline line_number (String.length line + 1);
          go (index + 1)
  in
  go 0;
  let last_line = max 1 count in
  let eof =
    { kind = End_of_file;
      span = Span.make ~file ~line:last_line ~column:1 ~end_line:last_line ~end_column:1;
      space_before = true }
  in
  (Array.of_list (List.rev (eof :: state.tokens)), List.rev state.diagnostics)
