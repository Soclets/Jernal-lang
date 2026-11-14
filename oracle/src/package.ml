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
  let sorted = Diagnostic.sort diagnostics in
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

(* Checks and runs the program made of [files] in [folder]; gives the exit code. *)
let run ~(folder : string) ~(files : string list) : int =
  try
    let manifest_text = read_file (Filename.concat folder Manifest.file_name) in
    let manifest, manifest_diagnostics = Manifest.read ~text:manifest_text in
    let parsed, file_diagnostics =
      List.fold_left
        (fun (parsed, diagnostics) file ->
          let text = read_file (Filename.concat folder file) in
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
        ([], []) files
    in
    let program, check_diagnostics = Checker.check_package ~std_visible:manifest.needs_std parsed in
    let all = manifest_diagnostics @ file_diagnostics @ check_diagnostics in
    let sorted = print_diagnostics all in
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
  | Sys_error message -> compiler_bug message
  | e -> compiler_bug (Printexc.to_string e)
