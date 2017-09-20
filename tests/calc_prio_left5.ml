open Generate_calc
open Earley

type calc_prio = Sum | Prod | Pow | Atom

let prio_to_string = function
  | Sum  -> "Sum"
  | Prod -> "Prod"
  | Pow -> "Pow"
  | Atom -> "Atom"

let float_re = ''[0-9]+\([.][0-9]+\)?\([eE][-+]?[0-9]+\)?''
let float_num = parser
  f:RE(float_re) -> float_of_string f

let prod_sym = parser
  | '*' -> ( *. )
  | '/' -> ( /. )

let sum_sym = parser
  | '+' -> ( +. )
  | '-' -> ( -. )

let (expr, set_expr) = grammar_family ~param_to_string:prio_to_string "expr"

let _ = set_expr (fun prio -> parser
  | f:float_num                             when prio = Atom -> f
  | '(' e:(expr Sum) ')'                    when prio = Atom -> e
  | '-' e:(expr Pow)                        when prio = Pow  -> -. e
  | '+' e:(expr Pow)                        when prio = Pow  -> e
  | e:(expr Atom) "**" e':(expr Pow)        when prio = Pow  -> e ** e'
  | e:(expr Atom)                           when prio = Pow  -> e
  | e:(expr Prod) fn:prod_sym e':(expr Pow) when prio = Prod -> fn e e'
  | e:(expr Sum) fn:sum_sym e':(expr Prod)  when prio = Sum  -> fn e e'

  | e:(expr Pow)			    when prio = Prod ->	e
  | e:(expr Prod)                           when prio = Sum  -> e)

(* The main loop *)
let _ = run (expr Sum)
