(* Errors and warnings, printed in the layout of standard 7.3 (D10, D137). *)

type kind =
  | Compile_time_error
  | Runtime_error
  | Warning
  | Not_designed_yet
  | Not_built_yet
  | Compiler_bug

(* An earlier line that led to an error (7.3's `because:`): its place, and a note on it. *)
type step = { at : Span.t; note : string }

type t = {
  kind : kind;
  span : Span.t option;      (* [None]: no code line caused it *)
  what : string option;      (* replaced by [fix] when there's exactly one fix *)
  fix : string option;
  why : string;
  when_ : string option;
  because : step list;
  edit : (Span.t * string) option;
      (* the fix as a text edit, applied in memory to find knock-on errors (D13) *)
}

let unquote text =
  let n = String.length text in
  if n >= 2 && text.[0] = '`' && text.[n - 1] = '`' then String.sub text 1 (n - 2) else text

let make ?span ?what ?fix ?when_ ?(because = []) ?edit kind why =
  let edit =
    match edit, fix, span with
    | Some e, _, _ -> Some e
    | None, Some f, Some s when s.Span.line = s.Span.end_line -> Some (s, unquote f)
    | _ -> None
  in
  { kind; span; what; fix; why; when_; because; edit }

let kind_word = function
  | Compile_time_error -> "CompileTimeError"
  | Runtime_error -> "RuntimeError"
  | Warning -> "warning"
  | Not_designed_yet -> "NotDesignedYet"
  | Not_built_yet -> "NotBuiltYet"
  | Compiler_bug -> "CompilerBug"

(* trace: D11 *)
let exit_code = function
  | Runtime_error -> 122
  | Compile_time_error -> 121
  | Not_designed_yet -> 120
  | Not_built_yet -> 119
  | Compiler_bug -> 118
  | Warning -> 0

let stops_the_program d = d.kind <> Warning

(* Where each file's text is, so a message can quote its line. *)
let sources : (string, string array) Hashtbl.t = Hashtbl.create 16

let add_source ~file ~text = Hashtbl.replace sources file (Text.lines_of text)

let source_line file line =
  match Hashtbl.find_opt sources file with
  | Some lines when line >= 1 && line <= Array.length lines -> Some lines.(line - 1)
  | _ -> None

let safe_sub text start length =
  let start = max 0 (min start (String.length text)) in
  let length = max 0 (min length (String.length text - start)) in
  String.sub text start length

let grapheme_column (span : Span.t) =
  let line_text = Option.value (source_line span.file span.line) ~default:"" in
  Text.grapheme_count (safe_sub line_text 0 (span.column - 1)) + 1

(* trace: D10 *)
let render (d : t) : string =
  let buffer = Buffer.create 256 in
  let add = Buffer.add_string buffer in
  add (kind_word d.kind);
  add ":";
  (* the place twice, then the code line and the `^` run under the part in question (7.3) *)
  let place (span : Span.t) =
    let line_text = Option.value (source_line span.file span.line) ~default:"" in
    let grapheme_column = Text.grapheme_count (safe_sub line_text 0 (span.column - 1)) + 1 in
    let number = string_of_int span.line in
    let gutter = String.make (String.length number) ' ' in
    let end_column = if span.end_line > span.line then String.length line_text + 1 else span.end_column in
    let marked = safe_sub line_text (span.column - 1) (end_column - span.column) in
    let width = max 1 (Text.grapheme_count marked) in
    ( Printf.sprintf "%s:%d:%d, line %d column %d" span.file span.line span.column span.line grapheme_column,
      Printf.sprintf " %s | %s\n %s | %s%s\n" number line_text gutter (String.make (grapheme_column - 1) ' ') (String.make width '^'),
      String.length number )
  in
  (match d.span with
   | None -> (
       match d.kind with
       | Compiler_bug -> add " the compiler itself failed\n"
       | _ -> add "\n")
   | Some span ->
       let header, code, _ = place span in
       add (" " ^ header ^ "\n");
       add code);
  let label name text =
    let padded = if String.length name < 5 then name ^ String.make (5 - String.length name) ' ' else name in
    add (Printf.sprintf " %s %s\n" padded text)
  in
  (match d.kind with
   | Compiler_bug ->
       (* trace: D12 *)
       label "what:" (Option.value d.what ~default:"");
       label "why:" "this is a bug in the compiler, not in the program";
       label "fix:"
         "report it at https://github.com/Soclets/Jernal-lang/issues with the program that caused it"
   | _ ->
       (match d.fix, d.what with
        | Some fix, _ -> label "fix:" fix
        | None, Some what -> label "what:" what
        | None, None -> ());
       label "why:" d.why;
       Option.iter (label "when:") d.when_;
       (* trace: D10 — an earlier line is shown in the same shape, with its note under it *)
       List.iter
         (fun step ->
           let header, code, digits = place step.at in
           label "because:" header;
           add code;
           add (Printf.sprintf "%s%s\n" (String.make (digits + 4) ' ') step.note))
         d.because);
  Buffer.contents buffer

(* By place, with errors that have no place last. *)
let sort (ds : t list) : t list =
  List.stable_sort
    (fun a b ->
      match a.span, b.span with
      | Some x, Some y -> Span.compare x y
      | Some _, None -> -1
      | None, Some _ -> 1
      | None, None -> 0)
    ds

exception Stop of t
