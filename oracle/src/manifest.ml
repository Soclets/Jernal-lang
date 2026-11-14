(* Reads and checks Journey.siml (standard 9.1, D76, D113, D117), the oracle's own reader. *)

(* `use <path> as <name>` in a block for one file, or for `all` (D60, D114, D115). *)
type short_name = {
  block : string;                (* a file name, or "all" *)
  path : string list;            (* time.seconds is ["time"; "seconds"] *)
  short : string;
  quoted : bool;
  use_span : Span.t;
}

type t = {
  uses : short_name list;
  package_name : string option;
  kind : string option;          (* "tests" for a tests folder (D122) *)
  needs_std : bool;
}

let file_name = "Journey.siml"

(* The std dates the oracle implements (D128, D137). *)
let std_dates = [ "2026y-11m-14d" ]

let is_date (text : string) : bool =
  (* <year>y-<month>m-<day>d, biggest first (D110) *)
  match String.split_on_char '-' text with
  | [ year; month; day ] ->
      let part s suffix digits =
        let n = String.length s in
        n >= 2 && s.[n - 1] = suffix
        && (digits = 0 || n - 1 = digits)
        && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub s 0 (n - 1))
      in
      part year 'y' 0 && part month 'm' 2 && part day 'd' 2
      && (let m = int_of_string (String.sub month 0 2) and d = int_of_string (String.sub day 0 2) in
          m >= 1 && m <= 12 && d >= 1 && d <= 31)
  | _ -> false

let read ~(text : string) : t * Diagnostic.t list =
  Diagnostic.add_source ~file:file_name ~text;
  let diagnostics = ref [] in
  let report d = diagnostics := d :: !diagnostics in
  let lines = Text.lines_of text in
  let package_name = ref None and kind = ref None and needs_std = ref false in
  let needed = Hashtbl.create 8 in
  let in_block = ref None in
  let uses = ref [] in
  Array.iteri
    (fun index raw ->
      let line_number = index + 1 in
      let without_comment =
        match Text.find_substring raw "//" with Some i -> String.sub raw 0 i | None -> raw
      in
      (* words and where each starts *)
      let words =
        let result = ref [] and i = ref 0 and n = String.length without_comment in
        while !i < n do
          if without_comment.[!i] = ' ' || without_comment.[!i] = '\t' then incr i
          else begin
            let start = !i in
            while !i < n && without_comment.[!i] <> ' ' && without_comment.[!i] <> '\t' do incr i done;
            result := (String.sub without_comment start (!i - start), start) :: !result
          end
        done;
        List.rev !result
      in
      let span_of (word, start) =
        Span.make ~file:file_name ~line:line_number ~column:(start + 1) ~end_line:line_number
          ~end_column:(start + String.length word + 1)
      in
      let line_span () =
        match words with
        | [] -> Span.none
        | first :: _ ->
            let (last_word, last_start) = List.nth words (List.length words - 1) in
            Span.join (span_of first) (span_of (last_word, last_start))
      in
      let error ?what ?fix span why = report (Diagnostic.make ~span ?what ?fix Diagnostic.Compile_time_error why) in
      let not_built what span why = report (Diagnostic.make ~span ~what Diagnostic.Not_built_yet why) in
      match !in_block, words with
      | _, [] -> ()
      | Some block, ("end", _) :: rest ->
          let closer = String.concat " " (List.map fst rest) in
          if closer <> block then
            error ~fix:(Printf.sprintf "`end %s`" block) (line_span ())
              "a block closes with `end` and its name (D114, standard 9.3)";
          in_block := None
      | Some block, [ ("use", _); (path, path_start); ("as", _); (name, name_start) ] ->
          (* trace: D60, D114, D115 *)
          let why = "`use path as name` gives something a short name (D60, standard 9.3)" in
          let quoted = String.length name >= 2 && name.[0] = '"' && name.[String.length name - 1] = '"' in
          let short = if quoted then String.sub name 1 (String.length name - 2) else name in
          let words = String.split_on_char '.' path in
          let last = List.nth words (List.length words - 1) in
          let name_span = span_of (name, name_start) in
          if String.contains path '*' then
            error ~what:"`use` gives one name; there are no wildcards" (span_of (path, path_start)) why
          else if quoted && (short = "" || List.mem short Parser.keywords
                             || not (String.for_all (fun c -> Lexer.is_word_char c) short)
                             || not (Lexer.is_word_start short.[0])) then
            error ~what:(Printf.sprintf "nothing could call `%s`" name) name_span "a quoted name is one a call could use (D60, standard 9.3)"
          else if (not quoted) && short <> last then
            error ~fix:(Printf.sprintf "`%s`" last) name_span
              "an unquoted name matches the last word of its path, so it can't lie about what it is (D60, standard 9.3)"
          else if List.exists (fun u -> u.short = short && (u.block = block || u.block = "all" || block = "all")) !uses then
            error ~what:(Printf.sprintf "`%s` is given twice, in `all` and a file's block, or in one block" short) name_span
              "the same short name in `all` and a file's block is a clash (D115, standard 9.3)"
          else uses := !uses @ [ { block; path = words; short; quoted; use_span = line_span () } ]
      | Some _, _ ->
          error ~what:"a block in the manifest holds `use <path> as <name>` lines" (line_span ())
            "`use` lives in the manifest, in a block per file (D114, standard 9.3)"
      | None, [ (word, _) ] when String.length word > 1 && word.[String.length word - 1] = ':' ->
          let block = String.sub word 0 (String.length word - 1) in
          in_block := Some block
      | None, (first, first_start) :: rest -> (
          let scoped = String.contains first '.' in
          if scoped then
            not_built "scoped manifest lines aren't built in the oracle yet" (span_of (first, first_start))
              "a line that applies only in some situations starts with a scope (D111, standard 9.1)"
          else
            match first, rest with
            | "name", [ (n, _) ] -> package_name := Some n
            | "ver", [ (date, date_start); (word, word_start) ] ->
                if not (is_date date) then
                  error ~what:(Printf.sprintf "`%s` isn't a date such as `2026y-11m-14d`" date)
                    (span_of (date, date_start)) "a version is a labelled date, biggest first (D110, standard 9.1)";
                if word <> "breaks" && word <> "not_broken" then
                  error ~what:(Printf.sprintf "a version ends with `breaks` or `not_broken`, not `%s`" word)
                    (span_of (word, word_start)) "a version says whether it breaks anything (D110, standard 9.1)"
            | "need", [ (package, package_start); (date, date_start) ] ->
                if Hashtbl.mem needed package then
                  error ~what:(Printf.sprintf "`%s` is needed twice" package) (line_span ())
                    "one `need` per package (D112, standard 9.1)"
                else begin
                  Hashtbl.add needed package ();
                  if not (is_date date) then
                    error ~what:(Printf.sprintf "`%s` isn't a date such as `2026y-11m-14d`" date)
                      (span_of (date, date_start)) "a `need` always writes its version (D112, standard 9.1)"
                  else if package = "std" then begin
                    (* trace: D128, D137 *)
                    if List.mem date std_dates then needs_std := true
                    else
                      not_built (Printf.sprintf "std as of `%s` isn't built in the oracle" date)
                        (span_of (date, date_start))
                        "`need std <date>` means std as specified on that date (D128, standard 13)"
                  end
                  else
                    not_built "packages other than std aren't built in the oracle yet"
                      (span_of (package, package_start))
                      "every package the manifest lists is visible by short names (D59, standard 9.2)"
                end
            | "kind", [ ("tests", _) ] -> kind := Some "tests"
            | "rule", _ ->
                report (Diagnostic.make ~span:(span_of (first, first_start)) ~what:"which rules the manifest can set isn't decided yet"
                          Diagnostic.Not_designed_yet "not decided yet (D76, standard 9.1)")
            | ("name" | "ver" | "need" | "kind"), _ ->
                error ~what:(Printf.sprintf "this `%s` line doesn't have the shape the manifest expects" first)
                  (line_span ()) "siml is one fact per line: what the line is, then its values (D76, standard 9.1)"
            | _ ->
                error ~what:(Printf.sprintf "`%s` isn't a fact the manifest knows" first)
                  (span_of (first, first_start)) "siml is one fact per line: what the line is, then its values (D76, standard 9.1)"))
    lines;
  ({ uses = !uses; package_name = !package_name; kind = !kind; needs_std = !needs_std }, List.rev !diagnostics)
