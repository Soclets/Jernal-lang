(* Loads a package, checks it and runs it: what `jern run --Interp` calls (standard 9.1, 10.1). *)

let read_file path =
  let channel = open_in_bin path in
  let text = really_input_string channel (in_channel_length channel) in
  close_in channel;
  text

(* The folder whose Journey.siml is in [start] or the nearest folder above it (D121). *)
let rec find_package (start : string) : string option =
  if Sys.file_exists (Filename.concat start Manifest.file_name) then Some start
  else
    let parent = Filename.dirname start in
    if parent = start then None else find_package parent

let jern_files folder =
  Sys.readdir folder |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".jern" && not (Sys.is_directory (Filename.concat folder f)))
  |> List.sort compare

let print_diagnostics diagnostics =
  (* the same error found twice, such as in a chain's middle operand, is printed once *)
  let rec unique seen = function
    | [] -> []
    | (d : Diagnostic.t) :: rest ->
        let key = (d.kind, d.span, d.what, d.fix, d.why) in
        if List.mem key seen then unique seen rest else d :: unique (key :: seen) rest
  in
  let sorted = Diagnostic.sort (unique [] diagnostics) in
  List.iteri
    (fun i d ->
      if i > 0 then prerr_string "\n";
      prerr_string (Diagnostic.render d))
    sorted;
  flush stderr;
  sorted

let compiler_bug what =
  flush stdout;
  prerr_string (Diagnostic.render (Diagnostic.make ~what Diagnostic.Compiler_bug ""));
  flush stderr;
  118

(* Reads, checks and gives the program made of [texts] (file name, text), with every error. *)
let check_texts ~(manifest_text : string) (texts : (string * string) list) =
  let manifest, manifest_diagnostics = Manifest.read ~text:manifest_text in
  let parsed, file_diagnostics =
    List.fold_left
      (fun (parsed, diagnostics) (file, text) ->
        if not (Text.is_valid_utf_8 text) then
          ( parsed,
            diagnostics
            @ [ Diagnostic.make ~what:(Printf.sprintf "`%s` isn't valid UTF-8" file) Diagnostic.Compile_time_error
                  "Jernal files are UTF-8 text (D74, standard 10.1)" ] )
        else begin
          Diagnostic.add_source ~file ~text;
          let tokens, lex_diagnostics = Lexer.lex ~file text in
          let syntax, parse_diagnostics = Parser.parse_file ~file tokens in
          (parsed @ [ syntax ], diagnostics @ lex_diagnostics @ parse_diagnostics)
        end)
      ([], []) texts
  in
  let program, check_diagnostics = Checker.check_package ~uses:manifest.uses ~std_visible:manifest.needs_std parsed in
  (program, manifest_diagnostics @ file_diagnostics @ check_diagnostics)

let apply_edit (texts : (string * string) list) ~(manifest_text : string) ((span : Span.t), replacement) =
  let edit text =
    let lines = Text.lines_of text in
    if span.line < 1 || span.line > Array.length lines then text
    else begin
      let line = lines.(span.line - 1) in
      let start = min (span.column - 1) (String.length line) and finish = min (span.end_column - 1) (String.length line) in
      lines.(span.line - 1) <- String.sub line 0 start ^ replacement ^ String.sub line finish (String.length line - finish);
      String.concat "\n" (Array.to_list lines)
    end
  in
  if span.file = Manifest.file_name then (texts, edit manifest_text)
  else (List.map (fun (file, text) -> if file = span.file then (file, edit text) else (file, text)) texts, manifest_text)

(* Knock-on errors: apply each single fix in memory and check again; an error that goes away gets a
   `because:` pointing back at the fix (D13, standard 7.4). *)
let add_knock_ons ~(manifest_text : string) (texts : (string * string) list) (diagnostics : Diagnostic.t list) =
  let key (d : Diagnostic.t) = (d.kind, d.what, d.fix, d.why) in
  let moved (edit_span : Span.t) replacement (d : Diagnostic.t) =
    match d.span with
    | Some s when s.file = edit_span.file && s.line = edit_span.line && s.column >= edit_span.end_column ->
        let delta = String.length replacement - (edit_span.end_column - edit_span.column) in
        Some { s with column = s.column + delta; end_column = s.end_column + delta }
    | other -> other
  in
  let result = Array.of_list diagnostics in
  Array.iteri
    (fun i (d : Diagnostic.t) ->
      match d.edit, d.span with
      | Some ((edit_span, replacement) as edit), Some fix_span when result.(i).because = [] ->
          let edited_texts, edited_manifest = apply_edit texts ~manifest_text edit in
          let _, again = check_texts ~manifest_text:edited_manifest edited_texts in
          let still_there (other : Diagnostic.t) =
            let place = moved edit_span replacement other in
            List.exists
              (fun (x : Diagnostic.t) ->
                key x = key other
                && (match x.span, place with
                    | Some a, Some b -> a.file = b.file && a.line = b.line && a.column = b.column
                    | None, None -> true
                    | _ -> false))
              again
          in
          let line_text = Option.value (Diagnostic.source_line fix_span.file fix_span.line) ~default:"" in
          ignore line_text;
          Array.iteri
            (fun j (other : Diagnostic.t) ->
              if j <> i && other.because = [] && other.kind <> Diagnostic.Warning && not (still_there other) then
                result.(j) <-
                  { other with
                    because =
                      [ Printf.sprintf "with %s at line %d column %d, this error goes away"
                          (Option.value d.fix ~default:"") fix_span.line (Diagnostic.grapheme_column fix_span) ] })
            result
      | _ -> ())
    result;
  (* the sources the messages quote are the program as written *)
  Diagnostic.add_source ~file:Manifest.file_name ~text:manifest_text;
  List.iter (fun (file, text) -> if Text.is_valid_utf_8 text then Diagnostic.add_source ~file ~text) texts;
  Array.to_list result

(* Checks and runs the program made of [files] in [folder]; gives the exit code. *)
let run ~(folder : string) ~(files : string list) : int =
  Std_library.program_path_text := folder;
  try
    let manifest_text = read_file (Filename.concat folder Manifest.file_name) in
    let texts = List.map (fun file -> (file, read_file (Filename.concat folder file))) files in
    let program, diagnostics = check_texts ~manifest_text texts in
    let diagnostics = add_knock_ons ~manifest_text texts diagnostics in
    let sorted = print_diagnostics diagnostics in
    match List.find_opt Diagnostic.stops_the_program sorted, program with
    | Some d, _ -> Diagnostic.exit_code d.kind
    | None, None -> 0
    | None, Some program -> (
        try
          Interpreter.run program;
          flush stdout;
          0
        with
        | Std_library.Exit_program code -> flush stdout; code
        | Interpreter.Runtime_stop d | Std_library.Interpreter_stop d ->
            flush stdout;
            prerr_string (Diagnostic.render d);
            flush stderr;
            Diagnostic.exit_code d.kind
        | Stack_overflow | Out_of_memory ->
            flush stdout;
            prerr_string
              (Diagnostic.render
                 (Diagnostic.make ~what:"the program ran out of memory" Diagnostic.Runtime_error
                    "running out of memory is a check (D53, standard 7.2)"));
            flush stderr;
            122)
  with
  | Checked.Impossible what -> compiler_bug ("the oracle reached a state the checker should rule out: " ^ what)
  | Sys_error message -> compiler_bug message
  | e -> compiler_bug (Printexc.to_string e)
