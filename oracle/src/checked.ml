(* A program after checking: names are resolved, types are known, and every literal has its
   value. This is what the interpreter runs. *)

type variable = { variable_id : int; variable_name : string }

type failure = { failure_name : string; failure_fields : (string * Value.t) list }

exception Failure_raised of failure * Span.t

(* A check that failed while running (chapter 7), or NotDesignedYet met while running. *)
exception Runtime_stop of Diagnostic.t

type expression = { kind : expression_kind; type_ : Types.t; span : Span.t }

and expression_kind =
  | Constant of Value.t
  | Read of variable
  | Call_function of { function_id : int; arguments : expression list }
  | Call_builtin of { builtin : builtin; arguments : expression list }
  | Join of expression list
  | Convert of { value : expression; narrowings : string list; target : Types.t }
  | Arithmetic of { operator : string; narrowings : string list; left : expression; right : expression }
  | Negate of expression
  | Compare of { operator : string; left : expression; right : expression }
  | Logic of { operator : string; both : bool; left : expression; right : expression }
  | Not of expression
  | List_literal of expression list
  | Map_literal of Types.map_kind * (expression * expression) list
  | Build_struct of { struct_name : string; fields : (string * expression) list }
  | Build_union of { union_name : string; case_name : string; fields : (string * expression) list }
  | Field of expression * string
  | Index of { target : expression; counting : Syntax.counting; position : expression }
  | Range of { from : expression; ending : expression; inclusive : bool; step_by : expression option }
  | Copy of expression
  | Fallback of { value : expression; instead : expression }
  | Ignore of expression
  | Otherwise of { value : expression; arms : arm list }
  | Pass_up of expression

and builtin = {
  builtin_name : string;
  run : Span.t -> Value.t list -> Value.t;
}

and arm = { arm_failure : string; arm_binding : variable option; arm_body : statement list }

and statement = { statement_kind : statement_kind; statement_span : Span.t }

and statement_kind =
  | Define of variable * expression
  | Set of variable * expression
  | Set_field of { target : expression; field : string; value : expression }
  | Set_index of { target : expression; counting : Syntax.counting; position : expression; value : expression }
  | Evaluate of expression
  | Return of expression option
  | If of (expression * statement list) list * statement list option
  | Case_test of { subject : expression; union_name : string; case_name : string; body : statement list; else_body : statement list option }
  | Match of { subject : expression; arms : (string * variable option * statement list) list }
  | While of { loop_id : int; condition : expression; body : statement list }
  | For of {
      loop_id : int;
      variable : variable;
      position : (Syntax.counting * variable) option;
      iterable : expression;
      handling : loop_handling;
      body : statement list;
    }
  | Break of int
  | Fail of failure_expression
  | Instead of expression
  | Check_contract of { condition : expression; text : string; why : string }

and failure_expression = { failure : string; fields : (string * expression) list }

and loop_handling = Loop_crash | Loop_pass_up | Loop_fallback of expression | Loop_arms of arm list

type function_ = {
  function_id : int;
  function_name : string;
  parameters : variable list;
  requires : (expression * string) list;
  body : statement list;
  returns_value : bool;
}

type program = {
  functions : (int, function_) Hashtbl.t;
  main : int;
  struct_defaults : (string, (string * expression option) list) Hashtbl.t;
}
