open Input
open Earley
open Asttypes
open Parsetree
open Pa_ast
open Pa_lexing
type entry =
  | FromExt 
  | Impl 
  | Intf 
let entry = (ref FromExt : entry ref) 
let fast = (ref false : bool ref) 
let file = (ref None : string option ref) 
let ascii = (ref false : bool ref) 
let print_location ch { Location.loc_start = s; Location.loc_end = e } =
  let open Lexing in
    Printf.fprintf ch "Position %d:%d to %d:%d%!" s.pos_lnum
      (s.pos_cnum - s.pos_bol) e.pos_lnum (e.pos_cnum - e.pos_bol)
  
let string_location { Location.loc_start = s; Location.loc_end = e } =
  let open Lexing in
    Printf.sprintf "Position %d:%d to %d:%d%!" s.pos_lnum
      (s.pos_cnum - s.pos_bol) e.pos_lnum (e.pos_cnum - e.pos_bol)
  
let lexing_position str pos =
  let loff = line_offset str  in
  let open Lexing in
    {
      pos_fname = (filename str);
      pos_lnum = (line_num str);
      pos_cnum = (loff + pos);
      pos_bol = loff
    }
  
let locate str pos str' pos' =
  let open Lexing in
    let s = lexing_position str pos  in
    let e = lexing_position str' pos'  in
    let open Location in { loc_start = s; loc_end = e; loc_ghost = false }
  
type entry_point =
  | Implementation of Parsetree.structure_item list grammar * blank 
  | Interface of Parsetree.signature_item list grammar * blank 
module Initial =
  struct
    let spec =
      ([("--ascii", (Arg.Set ascii),
          "Output ASCII text instead of serialized AST.");
       ("--impl", (Arg.Unit ((fun ()  -> entry := Impl))),
         "Treat file as an implementation.");
       ("--intf", (Arg.Unit ((fun ()  -> entry := Intf))),
         "Treat file as an interface.");
       ("--unsafe", (Arg.Set fast),
         "Use unsafe functions for arrays (more efficient).");
       ("--position-from-parser", (Arg.Set Quote.quote_parser_position),
         "Report position from quotation in parser (usefull to debug quotation).");
       ("--debug", (Arg.Set_int Earley.debug_lvl),
         "Sets the value of \"Earley.debug_lvl\".")] : (Arg.key * Arg.spec *
                                                         Arg.doc) list)
      
    let before_parse_hook = (fun ()  -> () : unit -> unit) 
    let char_litteral = (declare_grammar "char_litteral" : char grammar) 
    let string_litteral =
      (declare_grammar "string_litteral" : string grammar) 
    let regexp_litteral =
      (declare_grammar "regexp_litteral" : string grammar) 
    type expression_prio =
      | Seq 
      | If 
      | Aff 
      | Tupl 
      | Disj 
      | Conj 
      | Eq 
      | Append 
      | Cons 
      | Sum 
      | Prod 
      | Pow 
      | Opp 
      | App 
      | Dash 
      | Dot 
      | Prefix 
      | Atom 
    let expression_prios =
      [Seq;
      Aff;
      Tupl;
      Disj;
      Conj;
      Eq;
      Append;
      Cons;
      Sum;
      Prod;
      Pow;
      Opp;
      App;
      Dash;
      Dot;
      Prefix;
      Atom] 
    let next_exp =
      function
      | Seq  -> If
      | If  -> Aff
      | Aff  -> Tupl
      | Tupl  -> Disj
      | Disj  -> Conj
      | Conj  -> Eq
      | Eq  -> Append
      | Append  -> Cons
      | Cons  -> Sum
      | Sum  -> Prod
      | Prod  -> Pow
      | Pow  -> Opp
      | Opp  -> App
      | App  -> Dash
      | Dash  -> Dot
      | Dot  -> Prefix
      | Prefix  -> Atom
      | Atom  -> Atom 
    type alm =
      | NoMatch 
      | Match 
      | MatchRight 
      | Let 
      | LetRight 
    let right_alm =
      function
      | Match |MatchRight  -> Match
      | Let |LetRight  -> Let
      | NoMatch  -> NoMatch 
    let left_alm =
      function
      | Match |MatchRight  -> MatchRight
      | Let |LetRight  -> LetRight
      | NoMatch  -> NoMatch 
    let allow_match = function | Match  -> true | _ -> false 
    let allow_let = function | Match |Let  -> true | _ -> false 
    let string_exp (b,lvl) =
      (match b with
       | NoMatch  -> ""
       | Match  -> "m_"
       | MatchRight  -> "mr_"
       | Let  -> "l_"
       | LetRight  -> "lr_") ^
        (match lvl with
         | Seq  -> "Seq"
         | If  -> "If"
         | Aff  -> "Aff"
         | Tupl  -> "Tupl"
         | Disj  -> "Disj"
         | Conj  -> "Conj"
         | Eq  -> "Eq"
         | Append  -> "Append"
         | Cons  -> "Cons"
         | Sum  -> "Sum"
         | Prod  -> "Prod"
         | Pow  -> "Pow"
         | Opp  -> "Opp"
         | App  -> "App"
         | Dash  -> "Dash"
         | Dot  -> "Dot"
         | Prefix  -> "Prefix"
         | Atom  -> "Atom")
      
    let ((expression_lvl : (alm * expression_prio) -> expression grammar),set_expression_lvl)
      = grammar_family ~param_to_string:string_exp "expression_lvl" 
    let expression = expression_lvl (Match, Seq) 
    let structure_item =
      (declare_grammar "structure_item" : structure_item list grammar) 
    let signature_item =
      (declare_grammar "signature_item" : signature_item list grammar) 
    let ((parameter :
           bool ->
             [ `Arg of (arg_label * expression option * pattern) 
             | `Type of string loc ] grammar),set_parameter)
      = grammar_family "parameter" 
    let structure = structure_item 
    let signature = Earley.declare_grammar "signature" 
    let _ =
      Earley.set_grammar signature
        (Earley.apply (fun l  -> List.flatten l)
           (Earley.apply List.rev
              (Earley.fixpoint []
                 (Earley.apply (fun x  -> fun y  -> x :: y) signature_item))))
      
    type type_prio =
      | TopType 
      | As 
      | Arr 
      | ProdType 
      | DashType 
      | AppType 
      | AtomType 
    let type_prios =
      [TopType; As; Arr; ProdType; DashType; AppType; AtomType] 
    let type_prio_to_string (_,lvl) =
      match lvl with
      | TopType  -> "TopType"
      | As  -> "As"
      | Arr  -> "Arr"
      | ProdType  -> "ProdType"
      | DashType  -> "DashType"
      | AppType  -> "AppType"
      | AtomType  -> "AtomType" 
    let next_type_prio =
      function
      | TopType  -> As
      | As  -> Arr
      | Arr  -> ProdType
      | ProdType  -> DashType
      | DashType  -> AppType
      | AppType  -> AtomType
      | AtomType  -> AtomType 
    let ((typexpr_lvl_raw : (bool * type_prio) -> core_type grammar),set_typexpr_lvl)
      = grammar_family ~param_to_string:type_prio_to_string "typexpr_lvl" 
    let typexpr_lvl lvl = typexpr_lvl_raw (true, lvl) 
    let typexpr_nopar = typexpr_lvl_raw (false, TopType) 
    let typexpr = typexpr_lvl TopType 
    type pattern_prio =
      | AltPat 
      | TupPat 
      | ConsPat 
      | ConstrPat 
      | AtomPat 
    let topPat = AltPat 
    let next_pat_prio =
      function
      | AltPat  -> TupPat
      | TupPat  -> ConsPat
      | ConsPat  -> ConstrPat
      | ConstrPat  -> AtomPat
      | AtomPat  -> assert false 
    let ((pattern_lvl : (bool * pattern_prio) -> pattern grammar),set_pattern_lvl)
      = grammar_family "pattern_lvl" 
    let pattern = pattern_lvl (true, topPat) 
    let let_binding =
      (declare_grammar "let_binding" : value_binding list grammar) 
    let class_body = (declare_grammar "class_body" : class_structure grammar) 
    let class_expr = (declare_grammar "class_expr" : class_expr grammar) 
    let value_path = (declare_grammar "value_path" : Longident.t grammar) 
    let extra_expressions =
      ([] : ((alm * expression_prio) -> expression grammar) list) 
    let extra_prefix_expressions = ([] : expression grammar list) 
    let extra_types = ([] : (type_prio -> core_type grammar) list) 
    let extra_patterns =
      ([] : ((bool * pattern_prio) -> pattern grammar) list) 
    let extra_structure = ([] : structure_item list grammar list) 
    let extra_signature = ([] : signature_item list grammar list) 
    type record_field = (Longident.t Asttypes.loc * Parsetree.expression)
    let constr_decl_list =
      (declare_grammar "constr_decl_list" : constructor_declaration list
                                              grammar)
      
    let field_decl_list =
      (declare_grammar "field_decl_list" : label_declaration list grammar) 
    let record_list =
      (declare_grammar "record_list" : record_field list grammar) 
    let match_cases = (declare_grammar "match_cases" : case list grammar) 
    let module_expr = (declare_grammar "module_expr" : module_expr grammar) 
    let module_type = (declare_grammar "module_type" : module_type grammar) 
    let parse_string' g e' =
      try parse_string g ocaml_blank e'
      with | e -> (Printf.eprintf "Error in quotation: %s\n%!" e'; raise e) 
    let mk_attrib loc s contents =
      ((id_loc s Location.none),
        (PStr [loc_str loc (Pstr_eval ((exp_string loc contents), []))]))
      
    let attach_attrib =
      let tbl_s = Hashtbl.create 31  in
      let tbl_e = Hashtbl.create 31  in
      fun ?(local= false)  ->
        fun loc  ->
          fun acc  ->
            let open Location in
              let open Lexing in
                let rec fn acc res =
                  function
                  | [] -> (ocamldoc_comments := (List.rev acc); res)
                  | ((start,end_,contents) as c)::rest ->
                      let start' = loc.loc_start  in
                      let loc =
                        locate (fst start) (snd start) (fst end_) (snd end_)
                         in
                      if
                        (start'.pos_lnum >= (line_num (fst end_))) &&
                          (((start'.pos_lnum - (line_num (fst end_))) <= 1)
                             &&
                             ((if local
                               then (snd start) > 0
                               else (snd start) = 0)))
                      then
                        fn acc ((mk_attrib loc "ocaml.doc" contents) :: res)
                          rest
                      else fn (c :: acc) res rest
                   in
                let rec gn acc res =
                  function
                  | [] -> (ocamldoc_comments := (List.rev acc); List.rev res)
                  | ((start,end_,contents) as c)::rest ->
                      let end' = loc.loc_end  in
                      let loc =
                        locate (fst start) (snd start) (fst end_) (snd end_)
                         in
                      if
                        ((line_num (fst start)) >= end'.pos_lnum) &&
                          ((((line_num (fst start)) - end'.pos_lnum) <= 1) &&
                             ((if local
                               then (snd start) > 0
                               else (snd start) = 0)))
                      then
                        gn acc ((mk_attrib loc "ocaml.doc" contents) :: res)
                          rest
                      else gn (c :: acc) res rest
                   in
                let l1 =
                  try Hashtbl.find tbl_s ((loc.loc_start), local)
                  with
                  | Not_found  ->
                      let res = fn [] [] (!ocamldoc_comments)  in
                      (Hashtbl.add tbl_s ((loc.loc_start), local) res; res)
                   in
                let l2 =
                  try Hashtbl.find tbl_e ((loc.loc_end), local)
                  with
                  | Not_found  ->
                      let res = gn [] [] (!ocamldoc_comments)  in
                      (Hashtbl.add tbl_e ((loc.loc_end), local) res; res)
                   in
                l1 @ (acc @ l2)
      
    let attach_gen build =
      let tbl = Hashtbl.create 31  in
      fun loc  ->
        let open Location in
          let open Lexing in
            let rec fn acc res =
              function
              | [] -> (ocamldoc_comments := (List.rev acc); res)
              | ((start,end_,contents) as c)::rest ->
                  let start' = loc.loc_start  in
                  let loc =
                    locate (fst start) (snd start) (fst end_) (snd end_)  in
                  if (line_num (fst end_)) < start'.pos_lnum
                  then
                    fn acc ((build loc (mk_attrib loc "ocaml.text" contents))
                      :: res) rest
                  else fn (c :: acc) res rest
               in
            try Hashtbl.find tbl loc.loc_start
            with
            | Not_found  ->
                let res = fn [] [] (!ocamldoc_comments)  in
                (Hashtbl.add tbl loc.loc_start res; res)
      
    let attach_sig =
      attach_gen (fun loc  -> fun a  -> loc_sig loc (Psig_attribute a)) 
    let attach_str =
      attach_gen (fun loc  -> fun a  -> loc_str loc (Pstr_attribute a)) 
    let union_re l =
      let l = List.map (fun s  -> "\\(" ^ (s ^ "\\)")) l  in
      String.concat "\\|" l 
    let arrow_re = Earley.declare_grammar "arrow_re" 
    let _ =
      Earley.set_grammar arrow_re
        (EarleyStr.regexp ~name:"\\\\(->\\\\)\\\\|\\\\(\\226\\134\\146\\\\)"
           "\\(->\\)\\|\\(\226\134\146\\)" (fun groupe  -> groupe 0))
      
    let infix_symb_re prio =
      match prio with
      | Prod  ->
          union_re
            ["[/%][!$%&*+./:<=>?@^|~-]*";
            "[*]\\([!$%&+./:<=>?@^|~-][!$%&*+./:<=>?@^|~-]*\\)?";
            "mod\\b";
            "land\\b";
            "lor\\b";
            "lxor\\b"]
      | Sum  -> "[+-][!$%&*+./:<=>?@^|~-]*"
      | Append  -> "[@^][!$%&*+./:<=>?@^|~-]*"
      | Cons  -> "::"
      | Aff  ->
          union_re [":=[!$%&*+./:<=>?@^|~-]*"; "<-[!$%&*+./:<=>?@^|~-]*"]
      | Eq  ->
          union_re
            ["[<][!$%&*+./:<=>?@^|~]?[!$%&*+./:<=>?@^|~-]*";
            "[&][!$%*+./:<=>?@^|~-][!$%&*+./:<=>?@^|~-]*";
            "|[!$%&*+./:<=>?@^~-][!$%&*+./:<=>?@^|~-]*";
            "[=>$][!$%&*+./:<=>?@^|~-]*";
            "!="]
      | Conj  -> union_re ["[&][&][!$%&*+./:<=>?@^|~-]*"; "[&]"]
      | Disj  -> union_re ["or\\b"; "||[!$%&*+./:<=>?@^|~-]*"]
      | Pow  ->
          union_re
            ["lsl\\b"; "lsr\\b"; "asr\\b"; "[*][*][!$%&*+./:<=>?@^|~-]*"]
      | _ -> assert false 
    let infix_prios = [Prod; Sum; Append; Cons; Aff; Eq; Conj; Disj; Pow] 
    let prefix_symb_re prio =
      match prio with
      | Opp  -> union_re ["-[.]?"; "+[.]?"]
      | Prefix  ->
          union_re ["[!][!$%&*+./:<=>?@^|~-]*"; "[~?][!$%&*+./:<=>?@^|~-]+"]
      | _ -> assert false 
    let prefix_prios = [Opp; Prefix] 
    let (infix_symbol,infix_symbol__set__grammar) =
      Earley.grammar_family "infix_symbol" 
    let _ =
      infix_symbol__set__grammar
        (fun prio  ->
           Earley.alternatives
             ((if prio <> Cons
               then
                 [Earley.sequence
                    (EarleyStr.regexp (infix_symb_re prio)
                       (fun groupe  -> groupe 0)) not_special
                    (fun sym  ->
                       fun _default_0  ->
                         if is_reserved_symb sym then give_up (); sym)]
               else []) @
                ((if prio = Cons
                  then
                    [Earley.apply (fun _  -> "::") (Earley.string "::" "::")]
                  else []) @ [])))
      
    let (prefix_symbol,prefix_symbol__set__grammar) =
      Earley.grammar_family "prefix_symbol" 
    let _ =
      prefix_symbol__set__grammar
        (fun prio  ->
           Earley.sequence
             (EarleyStr.regexp (prefix_symb_re prio)
                (fun groupe  -> groupe 0)) not_special
             (fun sym  ->
                fun _default_0  ->
                  if (is_reserved_symb sym) || (sym = "!=") then give_up ();
                  sym))
      
    let mutable_flag = Earley.declare_grammar "mutable_flag" 
    let _ =
      Earley.set_grammar mutable_flag
        (Earley.alternatives
           [Earley.apply (fun _  -> Immutable) (Earley.empty ());
           Earley.apply (fun _default_0  -> Mutable) mutable_kw])
      
    let private_flag = Earley.declare_grammar "private_flag" 
    let _ =
      Earley.set_grammar private_flag
        (Earley.alternatives
           [Earley.apply (fun _  -> Public) (Earley.empty ());
           Earley.apply (fun _default_0  -> Private) private_kw])
      
    let virtual_flag = Earley.declare_grammar "virtual_flag" 
    let _ =
      Earley.set_grammar virtual_flag
        (Earley.alternatives
           [Earley.apply (fun _  -> Concrete) (Earley.empty ());
           Earley.apply (fun _default_0  -> Virtual) virtual_kw])
      
    let rec_flag = Earley.declare_grammar "rec_flag" 
    let _ =
      Earley.set_grammar rec_flag
        (Earley.alternatives
           [Earley.apply (fun _  -> Nonrecursive) (Earley.empty ());
           Earley.apply (fun _default_0  -> Recursive) rec_kw])
      
    let downto_flag = Earley.declare_grammar "downto_flag" 
    let _ =
      Earley.set_grammar downto_flag
        (Earley.alternatives
           [Earley.apply (fun _default_0  -> Downto) downto_kw;
           Earley.apply (fun _default_0  -> Upto) to_kw])
      
    let entry_points =
      ([(".mli", (Interface (signature, ocaml_blank)));
       (".ml", (Implementation (structure, ocaml_blank)))] : (string *
                                                               entry_point)
                                                               list)
      
  end
module type Extension  = module type of Initial
module type FExt  = functor (E : Extension) -> Extension
include Initial
let start_pos loc = loc.Location.loc_start 
let end_pos loc = loc.Location.loc_end 
