(* The source text of a span, for messages that quote the program. *)

let text_of (span : Span.t) : string =
  match Diagnostic.source_line span.file span.line with
  | Some line when span.end_line = span.line && span.end_column <= String.length line + 1 && span.column >= 1 ->
      String.sub line (span.column - 1) (span.end_column - span.column)
  | _ -> ""
