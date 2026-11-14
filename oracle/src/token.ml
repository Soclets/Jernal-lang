(* Tokens of a Jernal file. *)

type kind =
  | Variable of string            (* $name, without the $ *)
  | Word of string                (* a name or keyword: fn, Int, println, i32 *)
  | Type_parameter of string      (* ?Item, without the ? *)
  | Integer_literal of string     (* digits *)
  | Decimal_literal of string     (* digits.digits *)
  | String_literal of string      (* the text, with escapes already read *)
  | Tilde
  | Left_paren
  | Right_paren
  | Left_bracket
  | Right_bracket
  | Type_open                     (* < sticking to a type name (1.5) *)
  | Type_close
  | Less                          (* < with a space on both sides *)
  | Greater
  | Comma
  | Colon
  | Dot
  | Double_colon
  | Equals
  | Equals_equals
  | Bang_equals
  | Plus
  | Minus
  | Arrow                         (* -> *)
  | Fat_arrow                     (* => *)
  | Question
  | Double_question
  | Star
  | Broken                      (* a statement the lexer already refused: skip it quietly *)
  | Newline
  | End_of_file

type t = {
  kind : kind;
  span : Span.t;
  space_before : bool;
}

let describe = function
  | Variable name -> "$" ^ name
  | Word word -> word
  | Type_parameter name -> "?" ^ name
  | Integer_literal digits | Decimal_literal digits -> digits
  | String_literal _ -> "a string"
  | Tilde -> "~"
  | Left_paren -> "("
  | Right_paren -> ")"
  | Left_bracket -> "["
  | Right_bracket -> "]"
  | Type_open | Less -> "<"
  | Type_close | Greater -> ">"
  | Comma -> ","
  | Colon -> ":"
  | Dot -> "."
  | Double_colon -> "::"
  | Equals -> "="
  | Equals_equals -> "=="
  | Bang_equals -> "!="
  | Plus -> "+"
  | Minus -> "-"
  | Arrow -> "->"
  | Fat_arrow -> "=>"
  | Question -> "?"
  | Double_question -> "??"
  | Star -> "*"
  | Broken -> "?"
  | Newline -> "the end of the line"
  | End_of_file -> "the end of the file"
