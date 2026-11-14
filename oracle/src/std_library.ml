(* std, built into the oracle in OCaml straight from standard chapter 13 (D127). std's own Jernal
   code is never run here. *)

open Checked

exception Exit_program of int

(* A stop the interpreter reports as it is, such as NotDesignedYet while running. *)
exception Interpreter_stop of Diagnostic.t

(* What `jern run --Interp -- ...` passed after `--` (D108, D121). *)
let program_arguments : string list ref = ref []
let program_path_text : string ref = ref ""

type signature = {
  std_name : string;
  path : string;                         (* where it lives in std, such as std::io::stdio *)
  parameter_types : Types.t list;
  result : Types.t;
  fails : string list;
  run : Span.t -> Value.t list -> Value.t;
}

let raise_failure span name = raise (Failure_raised ({ failure_name = name; failure_fields = [] }, span))

(* Standard input, read a byte at a time so nothing is read ahead of what the program asked for. *)
let at_end_of_input = ref false

let read_raw_line () : string option =
  if !at_end_of_input then None
  else begin
    let buffer = Buffer.create 80 in
    let rec go () =
      match input_char stdin with
      | '\n' -> Some (Buffer.contents buffer)
      | c -> Buffer.add_char buffer c; go ()
      | exception End_of_file ->
          at_end_of_input := true;
          if Buffer.length buffer = 0 then None else Some (Buffer.contents buffer)
    in
    match go () with
    | Some line ->
        let length = String.length line in
        Some (if length > 0 && line.[length - 1] = '\r' then String.sub line 0 (length - 1) else line)
    | None -> None
  end

(* trace: D133 *)
let read_line span =
  match read_raw_line () with
  | None -> raise_failure span "end_of_input"
  | Some line -> if Text.is_valid_utf_8 line then Value.String line else raise_failure span "not_text"

let read_all span =
  let buffer = Buffer.create 256 in
  if not !at_end_of_input then begin
    (try
       while true do Buffer.add_channel buffer stdin 1 done
     with End_of_file -> ());
    at_end_of_input := true
  end;
  let text = Buffer.contents buffer in
  if Text.is_valid_utf_8 text then Value.String text else raise_failure span "not_text"

let functions : signature list =
  [ (* trace: D20, D21 *)
    { std_name = "println"; path = "std::io::stdio"; parameter_types = [ Types.String ]; result = Types.Nothing;
      fails = [];
      run = (fun _ arguments ->
          (match arguments with [ Value.String text ] -> print_string text; print_char '\n' | _ -> ());
          Value.Nothing) };
    { std_name = "read_line"; path = "std::io::stdio"; parameter_types = []; result = Types.String;
      fails = [ "end_of_input"; "not_text" ]; run = (fun span _ -> read_line span) };
    { std_name = "read_all"; path = "std::io::stdio"; parameter_types = []; result = Types.String;
      fails = [ "not_text" ]; run = (fun span _ -> read_all span) };
    { std_name = "lines"; path = "std::io::stdio"; parameter_types = []; result = Types.Lines;
      fails = []; run = (fun _ _ -> Value.Lines) };
    (* trace: D108 *)
    { std_name = "args"; path = "std::env"; parameter_types = []; result = Types.List Types.String;
      fails = [ "not_text" ];
      run = (fun span _ ->
          if List.for_all Text.is_valid_utf_8 !program_arguments then
            Value.List { items = Dynarray.of_list (List.map (fun a -> Value.String a) !program_arguments) }
          else raise_failure span "not_text") };
    { std_name = "program_path"; path = "std::env"; parameter_types = []; result = Types.String; fails = [];
      (* trace: D139 — under --Interp, the package folder's path *)
      run = (fun _ _ -> Value.String !program_path_text) };
    (* trace: D11 *)
    { std_name = "exit"; path = "std::env"; parameter_types = [ Types.int ]; result = Types.Nothing; fails = [];
      run = (fun span arguments ->
          match arguments with
          | [ code ] ->
              let n = Value.integer_to_z code in
              (* trace: D139 *)
              if Z.lt n Z.zero || Z.gt n (Z.of_int 117) then
                raise (Runtime_stop (Diagnostic.make ~span
                         ~what:(Printf.sprintf "`exit` takes a code from 0 to 117, and this is %s" (Z.to_string n))
                         Diagnostic.Runtime_error "programs use 0 to 117 for their own reasons (D11, D139, standard 13.2)"));
              raise (Exit_program (Z.to_int n))
          | _ -> Value.Nothing) } ]

let find name = List.find_opt (fun s -> s.std_name = name) functions

(* The next line for `for $line in lines()`; [None] at the end of input. *)
let next_line span : Value.t option =
  match read_raw_line () with
  | None -> None
  | Some line -> if Text.is_valid_utf_8 line then Some (Value.String line) else raise_failure span "not_text"
