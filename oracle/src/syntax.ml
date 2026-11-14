(* The syntax tree of a Jernal file, as the parser reads it (standard chapters 1 to 6). *)

type name = { text : string; span : Span.t }

type counting = Pos | Offset   (* trace: D17 *)

type type_expression = { type_kind : type_kind; type_span : Span.t }

and type_kind =
  | Named_type of {
      my : bool;                          (* written with my:: (D63) *)
      words : string list;                (* Map.hash is ["Map"; "hash"] *)
      arguments : type_argument list;     (* inside < > *)
      details : detail list;              (* inside [ ] after the type (D135) *)
    }
  | Parameter_type of string              (* ?Item *)

and type_argument = { argument_label : name option; argument_type : type_expression }

and detail = { detail_label : string; detail_label_span : Span.t; detail_value : expression }

and expression = { expression_kind : expression_kind; expression_span : Span.t }

and expression_kind =
  | Integer_literal of { digits : string; negative : bool; tilde : bool }
  | Decimal_literal of { digits : string; negative : bool; tilde : bool }
  | String_literal of string
  | Bool_literal of bool
  | Variable of string
  | Name of { my : bool; path : string list; word : string }   (* println, my::main, http::get *)
  | Member of expression * name                                 (* .name *)
  | Narrowed_member of expression * name                        (* .*name, a jumping handler *)
  | Call of { callee : expression; arguments : argument list }
  | Index of { target : expression; counting : counting; position : expression }
  | Bare_index of { target : expression; position : expression }
  | Build of { built : expression; fields : field_value list }  (* Reading[celsius = 22] *)
  | List_literal of expression list
  | Map_literal of (expression * expression) list
  | Range of range
  | Binary of { operator : operator; left : expression; right : expression }
  | Negate of expression
  | Not of expression
  | Join of expression list
  | Convert of { value : expression; narrowings : name list; target : type_expression }
  | Give of expression
  | Copy of expression
  | Pass_up of expression                                      (* ? *)
  | Fallback of { value : expression; instead : expression }  (* ?? value *)
  | Ignore of expression                                       (* ?? ignore *)
  | Otherwise of { value : expression; handling : handling }
  | Grouped of expression                                      (* ( ) in maths *)

and argument = { label : name option; value : expression }

and field_value = { field : name; field_value : expression }

and range = {
  from : expression;
  ending : range_end;
  step_by : expression option;
}

and range_end = To of expression | Before of expression

and operator = { word : string; narrowings : string list; operator_span : Span.t }
(* word is one of: + - x div mod plus minus times == != < > at_least at_most and or *)

and handling =
  | Arms of arm list
  | Handler of { family : name; handler : name; jumps : bool }   (* otherwise word_failed.*bail *)

and arm = {
  case_name : name;
  binding : name option;           (* case no_words $f *)
  arm_body : statement list;
  arm_span : Span.t;
}

and statement = { statement_kind : statement_kind; statement_span : Span.t }

and statement_kind =
  | Let of { is_mutable : bool; baked : bool; variable : name; declared_type : type_expression; value : expression }
  | Decl of { is_mutable : bool; variable : name; declared_type : type_expression }
  | Assign of { variable : name; value : expression }
  | Shadow of { is_mutable : bool; variable : name; declared_type : type_expression; value : expression }
  | Change of { target : expression; value : expression }
  | Expression_statement of expression
  | Return of expression
  | Return_early
  | If of { branches : branch list; else_body : statement list option }
  | Match of { subject : expression; match_arms : match_arms }
  | For of {
      loop_name : name option;
      variable : name;
      iterable : expression;
      at : (counting * name) option;
      handling : loop_handling option;
      body : statement list;
    }
  | While of { loop_name : name option; condition : expression; body : statement list }
  | Break of name option
  | Fail of { failure : name; fields : field_value list }
  | Instead of expression
  | Broken_block of statement list          (* an opening line that was refused; its body is still checked (D13) *)
  | Unfinished of { what : string; why : string; designed : bool }   (* NotBuiltYet / NotDesignedYet *)

and branch = { condition : condition; branch_body : statement list }

and condition =
  | Plain of expression
  | Case_test of expression * type_expression   (* if $s: Status.failed: *)

and match_arms = Match_arms of arm list | Match_with of { family : name; handler : name; jumps : bool }

and loop_handling =
  | Loop_pass_up
  | Loop_fallback of expression
  | Loop_handler of { family : name; handler : name; jumps : bool }

type parameter = {
  self_mutable : bool;              (* mut $self *)
  parameter : name;
  parameter_type : type_expression;
}

type failure_shape = { failure_name : name; failure_fields : (name * type_expression) list }

type requirement = { requirement_names : name list }   (* Ordered and Whole, or Any *)

type function_declaration = {
  narrowings : name list;           (* fn.pure.baked: [pure; baked] *)
  function_name : name;
  function_my : bool;
  type_parameters : (name * requirement) list;
  parameters : parameter list;
  result : type_expression option;
  fails : failure_shape list;
  labels : (name * name) list;      (* labels [$limit as limit] *)
  defaults : (name * expression) list;
  requires : expression list;
  ensures : expression list;
  body : statement list;
  function_span : Span.t;
}

type struct_field = { field_name : name; field_type : type_expression; field_default : expression option; field_visibility : visibility }

and visibility = File_only | Package | Everyone

type struct_declaration = {
  struct_narrowings : name list;
  struct_name : name;
  struct_type_parameters : (name * requirement) list;
  fields : struct_field list;
}

type union_case = { union_case : name; case_fields : (name * type_expression) list }

type union_declaration = { union_name : name; cases : union_case list }

type family_member =
  | Member_function of function_declaration
  | Member_preset of { preset_name : name; settings : (name * expression) list }
  | Member_versions of { versions_name : name; versions : function_declaration list }

type handler_set = { handler_name : name; handler_arms : arm list }

type declaration_kind =
  | Function of function_declaration
  | Struct of struct_declaration
  | Union of union_declaration
  | Type_alias of { alias_name : name; aliased : type_expression }
  | Type_new of { new_name : name; underlying : type_expression }
  | Family_function of { family_narrowings : name list; family_name : name; members : family_member list }
  | Family_failure of { failure_family : name; failures : failure_shape list }
  | Family_handler of { handler_family : name; handlers : handler_set list }
  | Unfinished_declaration of { what : string; why : string; designed : bool }

type declaration = { declaration_kind : declaration_kind; visibility : visibility; declaration_span : Span.t }

type file = { file_name : string; declarations : declaration list }
