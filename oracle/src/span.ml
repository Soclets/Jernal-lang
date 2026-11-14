(* A place in a source file. Lines count from 1; columns are UTF-8 byte offsets counting from 1.
   [end_column] is the column just past the last byte. A span may run over several lines. *)

type t = {
  file : string;            (* relative to the package folder (D137) *)
  line : int;
  column : int;
  end_line : int;
  end_column : int;
}

let make ~file ~line ~column ~end_line ~end_column = { file; line; column; end_line; end_column }

let join (first : t) (last : t) : t =
  { first with end_line = last.end_line; end_column = last.end_column }

let compare (a : t) (b : t) : int =
  match compare a.file b.file with
  | 0 -> (match compare a.line b.line with 0 -> compare a.column b.column | c -> c)
  | c -> c

let none = { file = ""; line = 0; column = 0; end_line = 0; end_column = 0 }
