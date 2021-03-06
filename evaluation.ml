(* 
                         CS 51 Final Project
                         MiniML -- Evaluation
*)

(* This module implements a small untyped ML-like language under
   various operational semantics.
 *)

open Expr ;;
  
(* Exception for evaluator runtime, generated by a runtime error in
   the interpreter *)
exception EvalError of string ;;
  
(* Exception for evaluator runtime, generated by an explicit `raise`
   construct in the object language *)
exception EvalException ;;

(*......................................................................
  Environments and values 
 *)

module type ENV = sig
    (* the type of environments *)
    type env
    (* the type of values stored in environments *)
    type value =
      | Val of expr
      | Closure of (expr * env)
   
    (* empty () -- Returns an empty environment *)
    val empty : unit -> env

    (* close expr env -- Returns a closure for `expr` and its `env` *)
    val close : expr -> env -> value

    (* lookup env varid -- Returns the value in the `env` for the
       `varid`, raising an `Eval_error` if not found *)
    val lookup : env -> varid -> value

    (* extend env varid loc -- Returns a new environment just like
       `env` except that it maps the variable `varid` to the `value`
       stored at `loc`. This allows later changing the value, an
       ability used in the evaluation of `letrec`. To make good on
       this, extending an environment needs to preserve the previous
       bindings in a physical, not just structural, way. *)
    val extend : env -> varid -> value ref -> env

    (* env_to_string env -- Returns a printable string representation
       of environment `env` *)
    val env_to_string : env -> string
                                 
    (* value_to_string ?printenvp value -- Returns a printable string
       representation of a value; the optional flag `printenvp`
       (default: `true`) determines whether to include the environment
       in the string representation when called on a closure *)
    val value_to_string : ?printenvp:bool -> value -> string
  end

module Env : ENV =
  struct
    type env = (varid * value ref) list
     and value =
       | Val of expr
       | Closure of (expr * env)

    (* empty environment *)
    let empty () : env = []

    (* Create a closure from an expr and its native environment. *)
    let close (exp : expr) (env : env) : value =
      Closure (exp, env) ;;

    (* Looks up a variable's value in an environment. *)
    let lookup (env : env) (varname : varid) : value =
      try 
        !(List.assoc varname env)
      with 
        | Not_found -> raise (EvalError ("Unbound variable " ^ varname)) 

    (* Returns an environemnt with every property as <env> in addition
      to the property that it maps the <varid> variable to <loc>. *)
    let rec extend (env : env) (varname : varid) (loc : value ref) : env =
      match env with 
      | [] -> [(varname, loc)] (* varid not found || end -> insert mapping *)
      | (varid, ref) :: tl -> if varid = varname 
                                then (varid, loc) :: tl (* varid map changed *)
                              else (varid, ref) :: (extend tl varname loc)

    (* Take a value v and return its string representation *)
    (* Note: ?printenvp should be an indicator whether to print the 
      env in addition to the output when encountered with a closure *)
    let rec value_to_string ?(printenvp : bool = true) (v : value) : string =
      match v with 
      | Val exp -> exp_to_concrete_string exp (* dont include env *)
      | Closure (exp, env) -> if printenvp (* include env *)
                              then "Closure(" ^
                                    exp_to_concrete_string exp ^ 
                                    ", " ^
                                    env_to_string env ^
                                    ")"
                              else exp_to_concrete_string exp (* dont *)

    (* Take an environment env and return its string representation *)
    and env_to_string (env : env) : string =
      match env with 
      | [] -> "[]"
      | (varid, ref) :: tl -> varid ^ " -> " ^ 
                              value_to_string !ref ^ ", " ^ 
                              env_to_string tl 
  end
;;


(*......................................................................
  Evaluation functions

  Each of the evaluation functions below evaluates an expression `exp`
  in an environment `env` returning a result of type `value`. We've
  provided an initial implementation for a trivial evaluator, which
  just converts the expression unchanged to a `value` and returns it,
  along with "stub code" for three more evaluators: a substitution
  model evaluator and dynamic and lexical environment model versions.

  Each evaluator is of type `expr -> Env.env -> Env.value` for
  consistency, though some of the evaluators don't need an
  environment, and some will only return values that are "bare
  values" (that is, not closures). 

  DO NOT CHANGE THE TYPE SIGNATURES OF THESE FUNCTIONS. Compilation
  against our unit tests relies on their having these signatures. If
  you want to implement an extension whose evaluator has a different
  signature, implement it as `eval_e` below.  *)

open Env ;;

(* The TRIVIAL EVALUATOR, which leaves the expression to be evaluated
   essentially unchanged, just converted to a value for consistency
   with the signature of the evaluators. *)
let eval_t (exp : expr) (_env : env) : value =
  (* coerce the expr, unchanged, into a value *)
  Val exp ;;

(* overarching evaluator for every subsequent eval_ *)
let rec evaluator (sub : bool)
                  (dyna: bool)
                  (lexi: bool) (exp : expr) (env : env) : value = 

  (* shorthand for rec call that ignores environment *)
  let eval_ignore (exp': expr) : value =  
    evaluator sub dyna lexi exp' env in 

  (* shorthand for rec call that includes environment *)
  let eval_include (exp': expr) (env': env) : value =
    evaluator sub dyna lexi exp' env' in
  
  (* first seen in expr.ml; see note there about pattern-match redundancy *)
  let unop_matcher (unop: unop) (expr : expr) : value = 
    match unop, expr with 
    | Negate_i, Num n -> Val(Num(~-n))
    | Negate_f, Float n -> Val(Float(~-.n))
    | Not, Bool b -> Val(Bool(not b))
    | _ -> raise (EvalError "(unop, expr type) combination not supported") 
    (* new unops and expressions go here *) in

  let binop_matcher (binop : binop) (e1 : expr) (e2: expr): value = 
    match eval_ignore e1, eval_ignore e2 with 
    | Val (Num n1), Val (Num n2) ->
      (match binop, n1, n2 with 
      | Plus_i, n1, n2 -> Val(Num (n1 + n2))
      | Minus_i, n1, n2 -> Val(Num (n1 - n2))
      | Times_i, n1, n2 -> Val(Num (n1 * n2))
      | Divide_i, n1, n2 -> Val(Num (n1 / n2))
      | Power_i, n1, n2 -> Val(Float (float_of_int n1 ** float_of_int n2))
      | Equals, n1, n2 -> Val(Bool (n1 = n2))
      | LessThan, n1, n2 -> Val(Bool (n1 < n2))
      | GreaterThan, n1, n2 -> Val(Bool (n1 > n2)) 
      | LessOrEqual, n1, n2 -> Val(Bool (n1 <= n2))
      | GreaterOrEqual, n1, n2 -> Val(Bool (n1 >= n2))
      | Unequal, n1, n2 -> Val(Bool (n1 <> n2))
      | _ -> raise (EvalError "type float should be type int")) 
    | Val (Float n1), Val (Float n2) -> 
      (match binop, n1, n2 with
      | Plus_f, n1, n2 -> Val(Float (n1 +. n2))
      | Minus_f, n1, n2 -> Val(Float (n1 -. n2))
      | Times_f, n1, n2 -> Val(Float (n1 *. n2))
      | Divide_f, n1, n2 -> Val(Float (n1 /. n2))
      | Power_f, n1, n2 -> Val(Float (n1 ** n2))
      | Equals, n1, n2 -> Val(Bool (n1 = n2))
      | LessThan, n1, n2 -> Val(Bool (n1 < n2))
      | GreaterThan, n1, n2 -> Val(Bool (n1 > n2)) 
      | LessOrEqual, n1, n2 -> Val(Bool (n1 <= n2))
      | GreaterOrEqual, n1, n2 -> Val(Bool (n1 >= n2))
      | Unequal, n1, n2 -> Val(Bool (n1 <> n2))
      | _ -> raise (EvalError "type int should be type float"))
    | Val (Bool n1), Val (Bool n2) -> 
      (match binop, n1, n2 with 
      | Equals, n1, n2 -> Val(Bool (n1 = n2))
      | LessThan, n1, n2 -> Val(Bool (n1 < n2))
      | GreaterThan, n1, n2 -> Val(Bool (n1 > n2))
      | LessOrEqual, n1, n2 -> Val(Bool (n1 <= n2))
      | GreaterOrEqual, n1, n2 -> Val(Bool (n1 >= n2))
      | Unequal, n1, n2 -> Val(Bool (n1 <> n2))
      | _ -> raise (EvalError "arguments not bools OR unsupported binop"))
    | _ -> raise (EvalError "unsupported binop expression type(s)") in

  (* outputs the expression inside a value *)
  let extract_expr (v : value) : expr = 
    match v with 
      | Val x -> x 
      | _ -> raise (EvalError "closure type not supported") in 
    
  (* takes an expression, calls evaluator on said expression while IGNORING 
  env, and then transformes the resulting value into an expression *)
  let extract_expr' (expression : expr) : expr =
    extract_expr (eval_ignore expression) in

    match exp with 
    | Var varid -> lookup env varid
    | Num _ | Float _ | Bool _ -> Val exp
    | Unop (unop, expr) -> unop_matcher unop expr
    | Binop (binop, expr1, expr2) -> binop_matcher binop expr1 expr2
    | Conditional (cond, expr1, expr2) -> 
        (match eval_ignore cond with 
        | Val (Bool true) -> eval_ignore expr1
        | Val (Bool false) -> eval_ignore expr2  
        | _ -> raise (EvalError "Condition of type bool expected"))
    | Fun (_name, _def) -> if not lexi then Val exp 
                           else close exp env
    | Let (name, def, body) -> 
        if sub then eval_ignore (subst name (extract_expr' def) body)
        else eval_include body (extend env name (ref (eval_ignore def)))
    | Letrec (name, def, body) -> 
        if sub then 
          (let def' = subst name (Letrec(name, def, Var name)) def in 
          eval_ignore (subst name (extract_expr (eval_ignore def')) body))
        else let name' = ref (Val Unassigned) in 
               let env' = extend env name name' in 
                 name' := eval_include def env';
                 eval_include body env'
    | Raise -> raise EvalException 
    | Unassigned -> raise (EvalError "Unassigned")
    | App (expr1, expr2) -> 
        if not lexi 
          then eval_ignore (match extract_expr' expr1 with 
                            | Fun (name, def) -> 
                              extract_expr' (subst name 
                                                  (extract_expr' expr2) 
                                                  def)
                            | _ -> raise (EvalError "not a function"))
        else (match eval_ignore expr1 with
              | Closure (Fun (name, def), env') ->
                eval_include def (extend env' name (ref (eval_ignore expr2)))
              | _ -> raise (EvalError "Not a function")) ;;
      

(* The SUBSTITUTION MODEL evaluator -- to be completed *)
let eval_s (exp : expr) (env : env) : value =
  evaluator true false false exp env ;;

(* The DYNAMICALLY-SCOPED ENVIRONMENT MODEL evaluator -- to be
   completed *) 
let eval_d (exp : expr) (env : env) : value =
  evaluator false true false exp env ;;
       
(* The LEXICALLY-SCOPED ENVIRONMENT MODEL evaluator -- optionally
   completed as (part of) your extension *)
let eval_l (exp : expr) (env : env) : value =
  evaluator false false true exp env ;;

(* The EXTENDED evaluator -- if you want, you can provide your
   extension as a separate evaluator, or if it is type- and
   correctness-compatible with one of the above, you can incorporate
   your extensions within `eval_s`, `eval_d`, or `eval_l`. *)
let eval_e _ =
  failwith "eval_e not implemented" ;;
  
(* Connecting the evaluators to the external world. The REPL in
   `miniml.ml` uses a call to the single function `evaluate` defined
   here. Initially, `evaluate` is the trivial evaluator `eval_t`. But
   you can define it to use any of the other evaluators as you proceed
   to implement them. (We will directly unit test the four evaluators
   above, not the `evaluate` function, so it doesn't matter how it's
   set when you submit your solution.) *)
   
let evaluate = eval_l ;;
