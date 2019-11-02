open Earley_core
open Earley_helpers
open Earley
open Astextra
open Asttypes
open Parsetree
open Longident
open Pa_lexing
open Helper

(** [lexing_position str pos] transforms an [Input.buffer] and position into a
    lexing position (used in the OCaml parse tree). *)
let lexing_position : Input.buffer -> int -> Lexing.position = fun buf pos ->
  let pos_fname = Input.filename buf in
  let pos_lnum  = Input.line_num buf in
  let pos_bol   = Input.line_offset buf in
  let pos_cnum  = pos_bol + pos in
  Lexing.{pos_fname; pos_lnum; pos_cnum; pos_bol}

(** [locate] is an Earley location function. *)
let locate : Input.buffer -> int -> Input.buffer -> int -> Location.t =
    fun buf1 pos1 buf2 pos2 ->
  let loc_start = lexing_position buf1 pos1 in
  let loc_end   = lexing_position buf2 pos2 in
  Location.{loc_start; loc_end; loc_ghost = false}

#define LOCATE locate

(** Type representing the parsing mode. *)
type entry =
  | FromExt (** Proceed according to the extension.        *)
  | Impl    (** Treat the input file as an implementation. *)
  | Intf    (** Treat the input file as an interface.      *)

(** [entry] is the current parsing mode. *)
let entry : entry ref = ref FromExt

(** [file] is the name of the file being parsed (not set in this file). *)
let file  : string option ref = ref None

(** [ascii] if true, parsing is ASCII, and binary otherwise. *)
let ascii : bool ref = ref false

(** [debug_attributes] enables debuging mode for attribute attachement. *)
let debug_attributes = ref false

(** [initial_spec] is the default (minimal) command line argument config. *)
let initial_spec : (Arg.key * Arg.spec * Arg.doc) list =
  [ ( "--ascii"
    , Arg.Set ascii
    , "Output ASCII text instead of serialized AST." )
  ; ( "--impl"
    , Arg.Unit (fun () -> entry := Impl)
    , "Treat file as an implementation." )
  ; ( "--intf"
    , Arg.Unit (fun () -> entry := Intf)
    , "Treat file as an interface." )
  ; ( "--debug"
    , Arg.Set_int Earley.debug_lvl
    , "Sets the value of \"Earley.debug_lvl\"." )
  ; ( "--debug-quotations"
    , Arg.Set Quote.quote_parser_position
    , "Report position from quotation in parser (for debugging quotations)." )
  ; ( "--debug-attributes"
    , Arg.Set debug_attributes
    , "Debug ocamldoc comments attachment." ) ]

(** Priority levels for expressions. *)
module ExpPrio = struct
  type t =
    | Seq | If | Aff | Tupl | Disj | Conj | Eq | Append | Cons | Sum | Prod
    | Pow | Opp | App | Dash | Dot | Prefix | Atom

  let to_string : t -> string = fun p ->
    match p with
    | Seq    -> "Seq"    | If   -> "If"   | Aff  -> "Aff"  | Tupl   -> "Tupl"
    | Disj   -> "Disj"   | Conj -> "Conj" | Eq   -> "Eq"   | Append -> "Append"
    | Cons   -> "Cons"   | Sum  -> "Sum"  | Prod -> "Prod" | Pow    -> "Pow"
    | Opp    -> "Opp"    | App  -> "App"  | Dash -> "Dash" | Dot    -> "Dot"
    | Prefix -> "Prefix" | Atom -> "Atom"

  let next : t -> t = fun p ->
    match p with
    | Seq    -> If   | If   -> Aff  | Aff  -> Tupl   | Tupl   -> Disj
    | Disj   -> Conj | Conj -> Eq   | Eq   -> Append | Append -> Cons
    | Cons   -> Sum  | Sum  -> Prod | Prod -> Pow    | Pow    -> Opp
    | Opp    -> App  | App  -> Dash | Dash -> Dot    | Dot    -> Prefix
    | Prefix -> Atom | Atom -> Atom
end

module TypPrio = struct
  type t = TopType | As | Arr | ProdType | DashType | AppType | AtomType

  let to_string : t -> string = fun p ->
    match p with
    | TopType  -> "TopType"  | As       -> "As"       | Arr     -> "Arr"
    | ProdType -> "ProdType" | DashType -> "DashType" | AppType -> "AppType"
    | AtomType -> "AtomType"

  let next : t -> t = fun p ->
    match p with
    | TopType  -> As       | As       -> Arr     | Arr     -> ProdType
    | ProdType -> DashType | DashType -> AppType | AppType -> AtomType
    | AtomType -> AtomType
end

module PatPrio = struct
  type t = AltPat | TupPat | ConsPat | ConstrPat | AtomPat

  let top : t = AltPat

  let to_string : t -> string = fun p ->
    match p with
    | AltPat    -> "AltPat"    | TupPat  -> "TupPat"  | ConsPat -> "ConsPat"
    | ConstrPat -> "ConstrPat" | AtomPat -> "AtomPat"

  let next : t -> t = fun p ->
    match p with
    | AltPat    -> TupPat  | TupPat  -> ConsPat | ConsPat -> ConstrPat
    | ConstrPat -> AtomPat | AtomPat -> assert false (* ??? *)
end

open ExpPrio
open TypPrio
open PatPrio

(****************************************************************************
 * Gestion of attachment of ocamldoc comments                               *
 ****************************************************************************)

let mk_attrib loc txt contents =
  let str = Const.string contents in
  ({txt; loc = Location.none}, PStr [Str.eval ~loc (Exp.constant ~loc str)])


let attach_attrib =
  let tbl_s = Hashtbl.create 31 in
  let tbl_e = Hashtbl.create 31 in
  fun loc acc ->
    let open Location in
    let open Lexing in
    if !debug_attributes then Printf.eprintf "enter attach\n%!";
    let rec fn acc res = function
      | [] -> res

      | (start,end_,contents,_ as c)::rest ->
         let start' = loc.loc_start in
         let lend = Input.line_num (fst end_) in
         let loc = locate (fst start) (snd start) (fst end_) (snd end_) in
         if !debug_attributes then Printf.eprintf "start [%d,%d] [%d,...]\n%!"
                        (Input.line_num (fst start)) lend start'.pos_lnum;
         (** Attach comments before only if on the previous line*)
         if start'.pos_lnum > lend && start'.pos_lnum - lend <= 1
         then (
           if !debug_attributes then Printf.eprintf "attach backward %s\n%!" contents;
           ocamldoc_comments := List.rev_append acc rest;
           if contents <> "" then mk_attrib loc "ocaml.doc" contents::res else res)
         else
           fn (c::acc) res rest
    in
    let rec gn acc res = function
      | [] -> List.rev res

      | (start,end_,contents,lstart as c)::rest ->
         let end' = loc.loc_end in
         let loc = locate (fst start) (snd start) (fst end_) (snd end_) in
         if !debug_attributes then Printf.eprintf "end[%d,%d] [...,%d]\n%!"
           lstart (Input.line_num (fst end_)) end'.pos_lnum;
         if lstart >= end'.pos_lnum && lstart - end'.pos_lnum  <= 1
         then (
           if !debug_attributes then Printf.eprintf "attach forward %s\n%!" contents;
           ocamldoc_comments := List.rev_append rest acc;
           if contents <> "" then mk_attrib loc "ocaml.doc" contents :: res else res)
         else
           gn (c::acc) res rest
    in
    (*    Printf.eprintf "attach_attrib [%d,%d]\n%!" loc.loc_start.pos_lnum  loc.loc_end.pos_lnum;*)
    let l2 =
      try Hashtbl.find tbl_e (loc.loc_start, loc.loc_end)
      with Not_found ->
        let res = gn [] [] (List.rev !ocamldoc_comments) in
        Hashtbl.add tbl_e (loc.loc_start, loc.loc_end) res;
        res
    in
    let l1 =
      try Hashtbl.find tbl_s loc.loc_start
      with Not_found ->
        let res = fn [] [] !ocamldoc_comments in
        Hashtbl.add tbl_s loc.loc_start res;
        res
    in
    l1 @ acc @ l2

let attach_gen build =
  let tbl = Hashtbl.create 31 in
  fun loc ->
    let open Location in
    let open Lexing in
    let rec fn acc res = function
      | [] -> ocamldoc_comments := List.rev acc; res

      | (start,end_,contents,_ as c)::rest ->
         let start' = loc.loc_start in
         let loc = locate (fst start) (snd start) (fst end_) (snd end_) in
         if !debug_attributes then Printf.eprintf "sig/str [%d,%d] [%d,...]\n%!"
           (Input.line_num (fst start)) (Input.line_num (fst end_)) start'.pos_lnum;
           if Input.line_num (fst end_) < start'.pos_lnum - 1 then
             begin
               if !debug_attributes then
                 Printf.eprintf "attach ocaml.text %s\n%!" contents;
               fn acc (build loc (mk_attrib loc "ocaml.text" contents)
                       :: res) rest
             end
         else
           fn (c::acc) res rest
    in
    if !debug_attributes then Printf.eprintf "enter attach sig/str [%d,...] %d\n%!"
                     loc.loc_start.pos_lnum (List.length !ocamldoc_comments);
    try Hashtbl.find tbl loc.loc_start
    with Not_found ->
      let res = fn [] [] !ocamldoc_comments in
      Hashtbl.add tbl loc.loc_start res;
      res

let attach_sig = attach_gen (fun loc a  -> Sig.attribute ~loc a)
let attach_str = attach_gen (fun loc a  -> Str.attribute ~loc a)

(****** START OF OLD PA_OCAML_PRELUDE ******)

let print_location ch {Location.loc_start = s ; Location.loc_end = e} =
  let open Lexing in
  Printf.fprintf ch "Position %d:%d to %d:%d%!"
    s.pos_lnum (s.pos_cnum - s.pos_bol)
    e.pos_lnum (e.pos_cnum - e.pos_bol)

let string_location {Location.loc_start = s ; Location.loc_end = e} =
  let open Lexing in
  Printf.sprintf "Position %d:%d to %d:%d%!"
    s.pos_lnum (s.pos_cnum - s.pos_bol)
    e.pos_lnum (e.pos_cnum - e.pos_bol)

(* OCaml grammar entry points. *)
type entry_point =
  | Implementation of Parsetree.structure_item list grammar * blank
  | Interface      of Parsetree.signature_item list grammar * blank

(* Initial parser module, starting point of the functorial interface. *)
module Initial = struct

(* Default command line arguments. *)
let spec : (Arg.key * Arg.spec * Arg.doc) list = initial_spec

(* Function to be run before parsing. *)
let before_parse_hook : unit -> unit = fun () -> ()

type alm = NoMatch | Match | Let
let allow_match : alm -> bool = fun alm -> alm = Match
let allow_let   : alm -> bool = fun alm -> alm <> NoMatch

let ((expression_lvl : alm * ExpPrio.t -> expression grammar), set_expression_lvl) =
  let param_to_string (b, p) =
    let base = match b with NoMatch -> "" | Match -> "m_" | Let -> "l_" in
    base ^ ExpPrio.to_string p
  in
  grammar_family ~param_to_string "expression_lvl"
let expression = expression_lvl (Match, Seq)
let structure_item : structure_item list grammar =
  declare_grammar "structure_item"
let signature_item : signature_item list grammar =
  declare_grammar "signature_item"
let (parameter : bool -> [`Arg of arg_label * expression option * pattern
                           | `Type of string Location.loc ]
                             grammar), set_parameter =
  grammar_family "parameter"

let structure = structure_item

let parser signature = l:signature_item* -> List.flatten l

let (typexpr_lvl_raw : (bool * TypPrio.t) -> core_type grammar), set_typexpr_lvl =
  let param_to_string (_, p) = TypPrio.to_string p in
  grammar_prio ~param_to_string "typexpr_lvl"
let typexpr_lvl lvl = typexpr_lvl_raw (true, lvl)
let typexpr_nopar = typexpr_lvl_raw (false, TopType)
let typexpr = typexpr_lvl TopType
let (pattern_lvl : bool * PatPrio.t -> pattern grammar), set_pattern_lvl =
  let param_to_string (_, p) = PatPrio.to_string p in
  grammar_prio ~param_to_string "pattern_lvl"
let pattern : pattern grammar = pattern_lvl (true, PatPrio.top)

let let_binding : value_binding list grammar = declare_grammar "let_binding"
let class_body : class_structure grammar = declare_grammar "class_body"
let class_expr : class_expr grammar = declare_grammar "class_expr"
let value_path : Longident.t grammar = declare_grammar "value_path"
let extra_expressions = ([] : (alm * ExpPrio.t -> expression grammar) list)
let extra_prefix_expressions = ([] : (expression grammar) list)
let extra_types = ([] : (TypPrio.t -> core_type grammar) list)
let extra_patterns = ([] : (bool * PatPrio.t -> pattern grammar) list)
let extra_structure = ([] : structure_item list grammar list)
let extra_signature = ([] : signature_item list grammar list)

type record_field = Longident.t Asttypes.loc * Parsetree.expression

let constr_decl_list : constructor_declaration list grammar = declare_grammar "constr_decl_list"
let field_decl_list : label_declaration list grammar = declare_grammar "field_decl_list"
let record_list : record_field list grammar = declare_grammar "record_list"
let match_cases : case list grammar = declare_grammar "match_cases"
let module_expr : module_expr grammar = declare_grammar "module_expr"
let module_type : module_type grammar = declare_grammar "module_type"

let parse_string' g e' =
  try parse_string g ocaml_blank e' with e ->
    Printf.eprintf "Error in quotation: %s\n%!" e'; raise e

(****************************************************************************
 * Basic syntactic elements (identifiers and litterals)                      *
 ****************************************************************************)
let union_re l = String.concat "\\|" (List.map (Printf.sprintf "\\(%s\\)") l)

let infix_symb_re prio =
  match prio with
  | Prod -> union_re ["[/%][!$%&*+./:<=>?@^|~-]*";
                      "[*]\\([!$%&+./:<=>?@^|~-][!$%&*+./:<=>?@^|~-]*\\)?";
                        "mod\\b"; "land\\b"; "lor\\b"; "lxor\\b"]
  | Sum -> "[+-][!$%&*+./:<=>?@^|~-]*"
  | Append -> "[@^][!$%&*+./:<=>?@^|~-]*"
  | Cons -> "::"
  | Aff -> union_re [":=[!$%&*+./:<=>?@^|~-]*";
                     "<-[!$%&*+./:<=>?@^|~-]*"]
  | Eq -> union_re ["[<][!$%&*+./:<=>?@^|~]?[!$%&*+./:<=>?@^|~-]*";
                    "[&][!$%*+./:<=>?@^|~-][!$%&*+./:<=>?@^|~-]*";
                    "|[!$%&*+./:<=>?@^~-][!$%&*+./:<=>?@^|~-]*";
                    "[=>$][!$%&*+./:<=>?@^|~-]*"; "!="]
  | Conj -> union_re ["[&][&][!$%&*+./:<=>?@^|~-]*"; "[&]"]
  | Disj -> union_re ["or\\b"; "||[!$%&*+./:<=>?@^|~-]*"]
  | Pow -> union_re ["lsl\\b"; "lsr\\b"; "asr\\b"; "[*][*][!$%&*+./:<=>?@^|~-]*"]
  | _ -> assert false

let infix_prios = [ Prod; Sum; Append; Cons; Aff; Eq; Conj; Disj; Pow]

let prefix_symb_re prio =
  match prio with
  | Opp    -> union_re ["-[.]?"; "+[.]?"]
  | Prefix -> union_re ["[!][!$%&*+./:<=>?@^|~-]*"; "[~?][!$%&*+./:<=>?@^|~-]+"]
  | _      -> assert false

let parser infix_symbol prio =
  | "::"                                   when prio =  Cons -> "::"
  | sym:RE(infix_symb_re prio) not_special when prio <> Cons ->
      if is_reserved_symb sym then give_up (); sym

let parser prefix_symbol prio = sym:RE(prefix_symb_re prio) not_special ->
  if is_reserved_symb sym || sym = "!=" then give_up (); sym

(****************************************************************************
 * Several flags                                                            *
 ****************************************************************************)

let entry_points : (string * entry_point) list =
   [ ".mli", Interface      (signature, ocaml_blank)
   ;  ".ml", Implementation (structure, ocaml_blank) ]
end

module type Extension = module type of Initial

(****** END OF OLD PA_OCAML_PRELUDE ******)

let merge2 l1 l2 =
  let loc_start = l1.Location.loc_start and loc_end = l2.Location.loc_end in
  Location.({loc_start; loc_end; loc_ghost = l1.loc_ghost && l2.loc_ghost})

let ghost : Location.t -> Location.t = fun loc ->
  Location.{loc with loc_ghost = true}

let de_ghost : expression -> expression = fun e ->
  Helper.Exp.mk ~loc:Location.{e.pexp_loc with loc_ghost = false} e.pexp_desc

module Make(Initial : Extension) = struct

include Initial

let ouident = uident
let parser uident   =
  | ouident
  | "$uid:" e:expression - '$' -> Quote.string_antiquotation _loc e

let olident = lident
let parser lident   =
  | olident
  | "$lid:" e:expression - '$' -> Quote.string_antiquotation _loc e

let oident = ident
let parser ident   =
  | oident
  | "$ident:" e:expression - '$' -> Quote.string_antiquotation _loc e

let mk_unary_op loc name loc_name arg =
  match name, arg.pexp_desc with
  | "-", Pexp_constant(Pconst_integer(n,o)) ->
     Exp.constant ~loc (Const.integer ?suffix:o ("-"^n))
  | ("-" | "-."), Pexp_constant(Pconst_float(f,o)) ->
     Exp.constant ~loc (Const.float ?suffix:o ("-" ^ f))
  | "+", Pexp_constant(Pconst_integer _)
  | ("+" | "+."), Pexp_constant(Pconst_float _) ->
     Exp.mk ~loc arg.pexp_desc
  | ("-" | "-." | "+" | "+."), _ ->
     let lid = Location.mkloc (Lident ("~" ^ name)) loc_name in
     let fn = Exp.ident ~loc:loc_name lid in
     Exp.apply ~loc fn [Nolabel, arg]
  | _ ->
     let lid = Location.mkloc (Lident name) loc_name in
     let fn = Exp.ident ~loc:loc_name lid in
     Exp.apply ~loc fn [Nolabel, arg]

let mk_binary_op loc e' op loc_op e =
  if op = "::" then
    let lid = Location.mkloc (Lident "::") loc_op in
    let arg = Exp.tuple ~loc:(ghost loc) [e';e] in
    Exp.construct ~loc lid (Some arg)
  else
    let id = Exp.ident ~loc:loc_op (Location.mkloc (Lident op) loc_op) in
    Exp.apply ~loc id [(Nolabel, e') ; (Nolabel, e)]

let wrap_type_annotation loc types core_type body =
  let exp = Exp.constraint_ ~loc body core_type in
  let exp =
    List.fold_right (fun ty exp -> Exp.newtype ~loc ty exp) types exp
  in
  (exp, Typ.poly ~loc:(ghost loc) types (Typ.varify_constructors types core_type))

(* Naming labels *)
let label_name = lident

let parser ty_label =
  | '~' - s:lident ':' -> Labelled s

let parser ty_opt_label =
  | '?' - s:lident ':' -> Optional s

let parser maybe_opt_label =
  | o:STR("?")? ln:label_name ->
      (if o = None then Labelled ln else (Optional ln))

(****************************************************************************
 * Antiquotation                                                            *
 ****************************************************************************)

let list_antiquotation loc e =
  let e = Quote.generic_antiquote Quote.Quote_loc loc e in
  Quote.make_list_antiquotation loc Quote.Quote_loc e

(****************************************************************************
 * Names                                                                    *
 ****************************************************************************)

(* FIXME: add antiquotations for all as done for field_name *)

let operator_name =
  alternatives (prefix_symbol Prefix :: List.map infix_symbol infix_prios)

let parser value_name =
  | id:lident -> id
  | '(' op:operator_name ')' -> op

let constr_name     = uident
let parser tag_name = STR("`") c:ident -> c

let typeconstr_name = lident
let field_name      = lident

let smodule_name       = uident
let parser module_name = u:uident -> Location.mkloc u _loc

let modtype_name       = ident
let class_name         = lident
let inst_var_name      = lident
let parser method_name = id:lident -> Location.mkloc id _loc

let module_path_gen, set_module_path_gen  = grammar_family "module_path_gen"
let module_path_suit, set_module_path_suit  = grammar_family "module_path_suit"

let parser module_path_suit_aux allow_app =
  | STR("(") m':(module_path_gen true) STR(")") when allow_app ->
      (fun a -> Lapply(a, m'))
  | STR(".") m:smodule_name ->
      (fun acc -> Ldot(acc, m))

let _ = set_module_path_suit (fun allow_app ->
    parser
      f:(module_path_suit_aux allow_app) g:(module_path_suit allow_app) -> (fun acc -> g (f acc))
    | EMPTY -> (fun acc -> acc)
    )

let _ = set_module_path_gen (fun allow_app ->
  parser
  | m:smodule_name s:(module_path_suit allow_app) -> s (Lident m)
  )

let module_path = module_path_gen false
let extended_module_path = module_path_gen true

let _ = set_grammar value_path (
  parser
  | mp:{m:module_path STR(".")}? vn:value_name ->
      (match mp with
       | None   -> Lident vn
       | Some p -> Ldot(p, vn)))

let parser constr =
  | mp:{m:module_path STR(".")}? cn:constr_name ->
      (match mp with
       | None   -> Lident cn
       | Some p -> Ldot(p, cn))

let parser typeconstr =
  | mp:{m:extended_module_path STR(".")}? tcn:typeconstr_name ->
      (match mp with
       | None   -> Lident tcn
       | Some p -> Ldot(p, tcn))

let parser field =
  | mp:{m:module_path STR(".")}? fn:field_name ->
      (match mp with
       | None   -> Lident fn
       | Some p -> Ldot(p, fn))

let parser class_path =
  | mp:{m:module_path STR(".")}? cn:class_name ->
      (match mp with
       | None   -> Lident cn
       | Some p -> Ldot(p, cn))

let parser modtype_path =
  | mp:{m:extended_module_path STR(".")}? mtn:modtype_name ->
      (match mp with
       | None   -> Lident mtn
       | Some p -> Ldot(p, mtn))

let parser classtype_path =
  | mp:{m:extended_module_path STR(".")}? cn:class_name ->
      (match mp with
       | None   -> Lident cn
       | Some p -> Ldot(p, cn))

let parser opt_variance =
  | v:RE("[+-]")? ->
      (match v with
       | None     -> Invariant
       | Some "+" -> Covariant
       | Some "-" -> Contravariant
       | _        -> assert false)

let parser override_flag =
    o:STR("!")? -> (if o <> None then Override else Fresh)

let parser attr_id =
  | id:ident l:{ '.' id:ident}* ->
      Location.mkloc (String.concat "." (id::l)) _loc

let parser payload =
  | s:structure -> PStr(s)
  | ':' t:typexpr -> PTyp(t)
  | '?' p:pattern e:{_:when_kw e:expression}? -> PPat(p,e)

let parser attribute =
  | "[@" id:attr_id p:payload ']'

let parser attributes =
  | {a:attribute}*

let parser ext_attributes =
  | a:{'%' a:attribute}? l:attributes -> a, l

let parser post_item_attributes =
  | l:{"[@@" id:attr_id p:payload ']'}*

let parser floating_attribute =
  | l:{"[@@@" id:attr_id p:payload ']'}

let parser extension =
  | "[%" id:attr_id p:payload ']'

let parser floating_extension =
  | "[%%" id:attr_id p:payload ']'

(****************************************************************************
 * Type expressions                                                         *
 ****************************************************************************)
let parser only_poly_typexpr =
  | ids:{'\'' id:ident -> Location.mkloc id _loc}+ '.' te:typexpr ->
      Typ.poly ~loc:_loc ids te

let parser poly_typexpr =
  | ids:{'\'' id:ident -> Location.mkloc id _loc}+ '.' te:typexpr ->
      Typ.poly ~loc:_loc ids te
  | te:typexpr ->
       te

let parser poly_syntax_typexpr =
  | _:type_kw ids:{id:typeconstr_name -> Location.mkloc id _loc_id}+
    '.' te:typexpr

let parser method_type =
  | mn:method_name ':' pte:poly_typexpr      -> Otag(mn, [], pte)
  | ty:(typexpr_lvl (TypPrio.next DashType)) -> Oinherit(ty)

let parser tag_spec =
  | tn:tag_name te:{_:of_kw '&'? typexpr}? ->
      let amp,t = match te with
              | None   -> true, []
              | Some (amp,l) -> amp<>None, [l]
      in
      let tn = Location.mkloc tn _loc_tn in
      Rtag (tn, [], amp, t)

  | te:typexpr ->
      Rinherit te

let parser tag_spec_first =
  | tn:tag_name te:{_:of_kw '&'? typexpr}? ->
      let amp,t = match te with
              | None   -> true,[]
              | Some (amp,l) -> amp<>None, [l]
      in
      let tn = Location.mkloc tn _loc_tn in
      [Rtag (tn, [], amp, t)]
  | te:typexpr? '|' ts:tag_spec ->
      match te with
      | None    -> [ts]
      | Some te -> [Rinherit te; ts]

let parser tag_spec_full =
  | tn:tag_name (amp,tes):{of_kw amp:'&'? te:typexpr
    tes:{'&' te:typexpr}* -> (amp<>None,(te::tes))}?[true,[]] ->
      let tn = Location.mkloc tn _loc_tn in
      Rtag (tn, [], amp, tes)
  | te:typexpr ->
      Rinherit te

let parser polymorphic_variant_type : core_type grammar =
  | '[' tsf:tag_spec_first tss:{'|' ts:tag_spec}* ']' ->
      Typ.variant ~loc:_loc (tsf @ tss) Closed None
  | "[>" ts:tag_spec? tss:{'|' ts:tag_spec}* ']' ->
      let tss = match ts with
                | None    -> tss
                | Some ts -> ts :: tss
      in
      Typ.variant ~loc:_loc tss Open None
  | "[<" '|'? tfs:tag_spec_full tfss:{'|' tsf:tag_spec_full}*
         tns:{'>' tns:tag_name+}?[[]] ']' ->
      Typ.variant ~loc:_loc (tfs :: tfss) Closed (Some tns)

let parser package_constraint =
  | type_kw tc:typeconstr '=' te:typexpr ->
      let tc = Location.mkloc tc _loc_tc in
      (tc, te)

let parser package_type =
  | mtp:modtype_path
          cs:{with_kw pc:package_constraint
                      pcs:{_:and_kw package_constraint}* -> (pc::pcs)}?[[]]
    -> Typ.package ~loc:_loc (Location.mkloc mtp _loc_mtp) cs

let parser opt_present =
  | STR("[>") l:tag_name+ STR("]") -> l
  | EMPTY -> []

let mkoption loc d =
  let loc = ghost loc in
  Typ.constr ~loc (Location.mkloc (Ldot (Lident "*predef*", "option")) loc) [d]

let extra_types_grammar lvl =
  (alternatives (List.map (fun g -> g lvl) extra_types))

let op_cl = parser d:".." -> Open | EMPTY -> Closed

let _ = set_typexpr_lvl (fun @(allow_par, lvl) ->
  parser
  | [@unshared] e:(extra_types_grammar lvl)
                         -> e
  | "'" id:ident
    -> Typ.var ~loc:_loc id

  | joker_kw
    -> Typ.any ~loc:_loc ()

  | '(' module_kw pt:package_type ')'
    -> Typ.mk ~loc:_loc pt.ptyp_desc

  | '(' te:typexpr at:attribute* ')'
       when allow_par
    -> { te with ptyp_attributes = at }

  | ln:ty_opt_label te:(typexpr_lvl ProdType) "->" te':(typexpr_lvl Arr)
       when lvl <= Arr
    -> Typ.arrow ~loc:_loc ln te te'

  | ln:label_name ':' te:(typexpr_lvl ProdType) "->" te':(typexpr_lvl Arr)
       when lvl <= Arr
    -> Typ.arrow ~loc:_loc (Labelled ln) te te'

  | te:(typexpr_lvl ProdType) "->" te':(typexpr_lvl Arr)
       when lvl <= Arr
    -> Typ.arrow ~loc:_loc Nolabel te te'

  | tc:typeconstr
    -> Typ.constr ~loc:_loc (Location.mkloc tc _loc_tc) []

  | '(' te:typexpr tes:{',' te:typexpr}+ ')' tc:typeconstr
       when lvl <= AppType
    -> Typ.constr ~loc:_loc (Location.mkloc tc _loc_tc) (te::tes)

  | t:(typexpr_lvl AppType) tc:typeconstr
       when lvl <= AppType
    -> Typ.constr ~loc:_loc (Location.mkloc tc _loc_tc) [t]

  | pvt:polymorphic_variant_type
    -> pvt

  | '<' rv:op_cl '>'
    -> Typ.object_ ~loc:_loc [] rv

  | '<' mts:(Earley.list1 method_type semi_col) rv:{_:semi_col op_cl}?[Closed] '>'
    -> Typ.object_ ~loc:_loc mts rv

  | '#' cp:class_path
    -> Typ.class_ ~loc:_loc (Location.mkloc cp _loc_cp) []

  | te:(typexpr_lvl DashType) '#' cp:class_path
       when lvl <= DashType
    -> Typ.class_ ~loc:_loc (Location.mkloc cp _loc_cp) [te]

  | '(' te:typexpr tes:{',' te:typexpr}* ')' '#' cp:class_path
    -> Typ.class_ ~loc:_loc (Location.mkloc cp _loc_cp) (te::tes)

  | tes:(Earley.list2 (typexpr_lvl DashType) (parser {'*' | "×"}))
       when lvl <= ProdType
    -> Typ.tuple ~loc:_loc tes

  | te:(typexpr_lvl As) as_kw '\'' id:ident
       when lvl <= As
    -> Typ.alias ~loc:_loc te id

  | '$' - aq:{''[a-z]+'' - ':'}?["type"] e:expression - '$'
    -> let e_loc_lid = Location.mkloc (Lident "_loc") _loc in
       let e_loc = Exp.ident ~loc:_loc e_loc_lid in
       let f =
         let open Quote in
         match aq with
            | "type"  -> generic_antiquote Quote_ptyp _loc e
            | "tuple" -> generic_antiquote Quote_ptyp _loc
                           <:expr<Earley_helpers.Helper.Typ.tuple
                              ~loc:$quote_location_t e_loc _loc _loc$ $e$>>
            | _       -> give_up ()
       in
       Quote.ptyp_antiquotation _loc f
)

(****************************************************************************
 * Type and exception definitions                                           *
 ****************************************************************************)

(* Type definition *)
let parser type_param =
  | var:opt_variance id:{_:'\'' ident} -> (Typ.var ~loc:_loc_id id, var)
  | var:opt_variance j:'_'             -> (Typ.any ~loc:_loc_j () , var)

let parser type_params =
  | EMPTY -> []
  | tp:type_param -> [tp]
  | '(' tp:type_param tps:{',' tp:type_param -> tp}* ')' ->
      tp::tps

let parser type_equation =
  | '=' p:private_flag te:typexpr -> (p,te)

let parser constr_name2 =
  | cn:constr_name    -> cn
  | '(' ')' -> "()"

let parser bar with_bar =
  | EMPTY when not with_bar
  | '|'

(** FIXME OCAML: the bar is included in position *)
let parser constr_decl with_bar =
  | (bar with_bar) cn:constr_name2
    (args,res):{ te:{_:of_kw { _:'(' te:typexpr _:')' -> (te,true)
                   | te:typexpr_nopar -> (te,false) }}? ->
               let tes =
                 match te with
                 | None   -> []
                 | Some ({ ptyp_desc = Ptyp_tuple tes }, false) -> tes
                 | Some (t,_) -> [t]
               in
               (Pcstr_tuple tes, None)
             | of_kw '{' fds:field_decl_list '}' -> (Pcstr_record fds, None)
             | ':' tes:{te:(typexpr_lvl (TypPrio.next ProdType))
                        tes:{_:'*' (typexpr_lvl (TypPrio.next ProdType))}*
                        "->" -> (te::tes)}?[[]]
                   te:(typexpr_lvl (TypPrio.next Arr)) ->
                (Pcstr_tuple tes, Some te)
             | ':' '{' fds:field_decl_list '}' "->"
                   te:(typexpr_lvl (TypPrio.next Arr)) ->
                (Pcstr_record fds, Some te)
             } a:post_item_attributes
        -> let name = Location.mkloc cn _loc_cn in
           (name,args,res,a)

let parser type_constr_decl with_bar =
  (name,args,res,a):(constr_decl with_bar) ->
     Type.constructor ~attrs:(attach_attrib _loc a) ~loc:_loc ~args ?res name

let parser type_constr_extn with_bar =
  | (name,args,res,a):(constr_decl with_bar) ->
     Te.decl ~attrs:(attach_attrib _loc a) ~loc:_loc ~args ?res name
  | li:lident '=' cn:constr a:post_item_attributes ->
     Te.rebind ~attrs:(attach_attrib _loc a) ~loc:_loc (Location.mkloc li _loc_li)
                                                       (Location.mkloc cn _loc_cn)

let _ = set_grammar constr_decl_list (
  parser
  | cd:(type_constr_decl false) cds:(type_constr_decl true)* -> cd::cds
  | dol:'$' - e:(expression_lvl (NoMatch, App)) - '$' cds:constr_decl_list ->
        list_antiquotation _loc e @ cds
  | EMPTY -> []
  )

let parser constr_extn_list =
  | cd:(type_constr_extn false) cds:(type_constr_extn true)* -> cd::cds
  | dol:'$' - e:(expression_lvl (NoMatch, App)) - '$' cds:constr_extn_list ->
        list_antiquotation _loc e @ cds
  | EMPTY -> []

(* NOTE: OCaml includes the semi column in the position *)
let parser field_decl_semi =
  | mut:mutable_flag fn:field_name STR(":") pte:poly_typexpr semi_col ->
     Type.field ~loc:_loc ~mut (Location.mkloc fn _loc_fn) pte

let parser field_decl =
  | mut:mutable_flag fn:field_name STR(":") pte:poly_typexpr ->
     Type.field ~loc:_loc ~mut (Location.mkloc fn _loc_fn) pte

let parser field_decl_aux =
  | EMPTY -> []
  | fs:field_decl_aux fd:field_decl_semi -> fd::fs
  | dol:'$' - e:(expression_lvl (NoMatch,App)) - '$' ';'? ls:field_decl_list
                                     -> list_antiquotation _loc e

let _ = set_grammar field_decl_list (
  parser
    | fs:field_decl_aux -> List.rev fs
    | fs:field_decl_aux fd:field_decl -> List.rev (fd::fs)
  )

let parser type_repr =
  | STR("{") fds:field_decl_list STR("}") -> Ptype_record fds
  | cds:constr_decl_list -> if cds = [] then give_up (); Ptype_variant (cds)
  | ".." -> Ptype_open

let parser type_constraint_body = id:{_:'\'' ident} '=' te:typexpr ->
  (Typ.var ~loc:_loc_id id, te, _loc)

let parser type_constraint = _:constraint_kw type_constraint_body

let parser type_information =
  | te:type_equation?
    (pri,tkind):{'=' pri:private_flag tr:type_repr}?[(Public, Ptype_abstract)]
    cstrs:type_constraint* ->
      (pri, te, tkind, cstrs)

(* FIXME remove *)
let merge2 l1 l2 =
  Location.(
    {loc_start = l1.loc_start; loc_end = l2.loc_end; loc_ghost = l1.loc_ghost && l2.loc_ghost})

let typedef_gen att constr filter =
  parser
  | params:type_params tcn:constr ti:type_information
    a:{post_item_attributes when att | EMPTY when not att -> []} ->
    (fun prev_loc ->
      let _loc =
        match prev_loc with
        | None   -> _loc
        | Some l -> merge2 l _loc
      in
      let (pri, te, kind, cstrs) = ti in
      let (priv, manifest) =
        match te with
        | None              -> (pri, None)
        | Some(Private, te) ->
            (* ty = private ty' = private A | B is not legal *)
            if pri = Private then give_up ();
            (Private, Some te)
        | Some(_, te)       -> (pri, Some te)
      in
      let attrs = if att then attach_attrib _loc a else [] in
      let ltcn = Location.mkloc tcn _loc_tcn in
      (ltcn, Type.mk ~loc:_loc ~attrs ~params ~cstrs ~kind ~priv ?manifest
        (Location.mkloc (filter tcn) _loc_tcn)))

let parser type_extension =
  type_kw params:type_params tcn:typeconstr "+=" priv:private_flag
     cds:constr_extn_list attrs:post_item_attributes ->
        let tcn = Location.mkloc tcn _loc_tcn in
        Te.mk ~attrs ~params ~priv tcn cds

let parser typedef = (typedef_gen true typeconstr_name (fun x -> x))
let parser typedef_in_constraint = (typedef_gen false typeconstr Longident.last)

let parser type_definition =
  | l:type_kw td:typedef tds:{l:and_kw td:typedef -> snd (td (Some _loc_l))}* ->
                             snd (td (Some _loc_l))::tds

(* Exception definition *)
let parser exception_definition =
  | exception_kw cn:constr_name CHR('=') c:constr ->
      (let name = Location.mkloc cn _loc_cn in
      let ex = Location.mkloc c _loc_c in
      let ex =
        { ptyexn_constructor = Te.rebind ~loc:_loc name ex
        ; ptyexn_loc = _loc; ptyexn_attributes = [] }
      in
      (Str.exception_ ~loc:_loc ex)).pstr_desc
  | exception_kw (name,args,res,a):(constr_decl false) ->
       let cd = Te.decl ~attrs:(attach_attrib _loc a) ~loc:_loc ~args ?res name in
       let cd = {ptyexn_constructor = cd; ptyexn_loc = _loc; ptyexn_attributes = []} in 
       (Str.exception_ ~loc:_loc cd).pstr_desc

(****************************************************************************
 * Classes                                                                  *
 ****************************************************************************)
(* Class types *)
let class_field_spec = declare_grammar "class_field_spec"
let class_body_type = declare_grammar "class_body_type"

let parser virt_mut =
  | v:virtual_flag m:mutable_flag -> (v, m)
  | mutable_kw virtual_kw -> (Virtual, Mutable)

let parser virt_priv =
  | v:virtual_flag p:private_flag -> (v, p)
  | private_kw virtual_kw -> (Virtual, Private)

let _ = set_grammar class_field_spec (
  parser
  | inherit_kw cbt:class_body_type ->
      Ctf.inherit_ ~loc:_loc cbt
  | val_kw (vir,mut):virt_mut ivn:inst_var_name STR(":") te:typexpr ->
      let ivn = Location.mkloc ivn _loc_ivn in
      Ctf.val_ ~loc:_loc ivn mut vir te
  | method_kw (v,pri):virt_priv mn:method_name STR(":") te:poly_typexpr ->
      Ctf.method_ ~loc:_loc mn pri v te
  | constraint_kw te:typexpr '=' te':typexpr ->
      Ctf.constraint_ ~loc:_loc te te'
  | attr:floating_attribute ->
      Ctf.attribute ~loc:_loc attr
  | ext:floating_extension ->
      Ctf.extension ~loc:_loc ext
  )

let _ = set_grammar class_body_type (
  parser
  | object_kw te:{'(' te:typexpr ')'}? cfs:class_field_spec* end_kw ->
      let self =
        match te with
        | None   -> Typ.any ~loc:_loc_te ()
        | Some t -> t
      in
      Cty.signature ~loc:_loc (Csig.mk self cfs)
  | tes:{'[' te:typexpr tes:{',' te:typexpr}* ']' -> (te::tes)}?[[]]
    ctp:classtype_path ->
      let ctp = Location.mkloc ctp _loc_ctp in
      Cty.constr ~loc:_loc ctp tes
  )

let parser class_type =
  | tes:{l:maybe_opt_label? STR(":") te:typexpr -> (l, te)}* cbt:class_body_type ->
      let app acc (lab, te) =
        match lab with
        | None   -> Cty.arrow ~loc:_loc Nolabel te acc
        | Some l -> Cty.arrow ~loc:_loc l (match l with Optional _ -> te | _ -> te) acc
      in
      List.fold_left app cbt (List.rev tes)

let parser type_parameters =
  | i1:type_param l:{ STR(",") i2:type_param }* -> i1::l

(* Class specification *)
let parser class_spec =
  | virt:virtual_flag params:{'[' params:type_parameters ']'}?[[]]
    cn:class_name ':' ct:class_type ->
      Ci.mk ~loc:_loc ~attrs:(attach_attrib _loc []) ~virt ~params
        (Location.mkloc cn _loc_cn) ct

let parser class_specification =
  | class_kw cs:class_spec css:{_:and_kw class_spec}* -> (cs::css)

(* Class type definition *)
let parser classtype_def =
  | virt:virtual_flag params:{'[' tp:type_parameters ']'}?[[]] cn:class_name
    '=' cbt:class_body_type ->
      (fun _l -> Ci.mk ~loc:_l ~attrs:(attach_attrib _l []) ~virt ~params
                   (Location.mkloc cn _loc_cn) cbt)

let parser classtype_definition =
  | k:class_kw type_kw cd:classtype_def cds:{_:and_kw cd:classtype_def -> cd _loc}* ->
      cd (merge2 _loc_k _loc_cd) ::cds

(****************************************************************************
 * Constants and Patterns                                                   *
 ****************************************************************************)

(* Constants *)
let parser constant =
  | (f,suffix):float_litteral -> Const.float ?suffix f
  | c:char_litteral           -> Const.char c
  | (s,delim):string_litteral -> Const.string ?quotation_delimiter:delim s
  | s:regexp_litteral         -> Const.string s
  | s:new_regexp_litteral     -> Const.string s
  | (i,suffix):int_litteral   -> Const.integer ?suffix i

(* we do like parser.mly from ocaml: neg_constant for pattern only *)
let parser neg_constant =
  | '-' - '.'? (f,suffix):float_litteral -> Const.float   ?suffix ("-" ^ f)
  | '-' (i,suffix):int_litteral          -> Const.integer ?suffix ("-" ^ i)

(* Patterns *)

let parser extra_patterns_grammar lvl =
  (alternatives (List.map (fun g -> g lvl) extra_patterns))

let _ = set_pattern_lvl (fun @(as_ok,lvl) -> parser
  | [@unshared] e:(extra_patterns_grammar (as_ok, lvl)) -> e

  | [@unshared] p:(pattern_lvl (as_ok, lvl)) as_kw vn:value_name when as_ok ->
      Pat.alias ~loc:_loc p (Location.mkloc vn _loc_vn)

  | vn:value_name ->
      Pat.var ~loc:_loc (Location.mkloc vn _loc_vn)

  | joker_kw ->
      Pat.any ~loc:_loc ()

  | c1:char_litteral ".." c2:char_litteral ->
      Pat.interval ~loc:_loc (Const.char c1) (Const.char c2)

  | c:{c:constant | c:neg_constant} when lvl <= AtomPat ->
      Pat.constant ~loc:_loc c

  | '(' p:pattern  ty:{_:':' typexpr}? ')' ->
      begin
        match ty with
        | None    -> Pat.mk ~loc:_loc p.ppat_desc
        | Some ty -> Pat.constraint_ ~loc:_loc p ty
      end

  | lazy_kw p:(pattern_lvl (false,ConstrPat)) when lvl <= ConstrPat ->
      Pat.lazy_ ~loc:_loc p

  | exception_kw p:(pattern_lvl (false,ConstrPat)) when lvl <= ConstrPat ->
      Pat.exception_ ~loc:_loc p

  | c:constr p:(pattern_lvl (false, ConstrPat)) when lvl <= ConstrPat ->
      Pat.construct ~loc:_loc (Location.mkloc c _loc_c) (Some p)

  | c:constr ->
      Pat.construct ~loc:_loc (Location.mkloc c _loc_c) None

  | b:bool_lit ->
      Pat.construct ~loc:_loc (Location.mkloc (Lident b) _loc) None

  | c:tag_name p:(pattern_lvl (false, ConstrPat)) when lvl <= ConstrPat ->
      Pat.variant ~loc:_loc c (Some p)

  | c:tag_name ->
      Pat.variant ~loc:_loc c None

  | s:'#' t:typeconstr ->
      Pat.type_ ~loc:_loc (Location.mkloc t _loc_t)

  | s:'{' f:field p:{'=' p:pattern}? fps:{semi_col f:field
                  p:{'=' p:pattern}? -> (Location.mkloc f _loc_f, p)}*
          clsd:{semi_col joker_kw -> ()}? semi_col? '}' ->
      let all = (Location.mkloc f _loc_f, p)::fps in
      let f (lab, pat) =
        match pat with
        | Some p -> (lab, p)
        | None   ->
           let slab =
             match lab.txt with
             | Lident s -> Location.mkloc s lab.loc
             | _        -> give_up ()
           in
           (lab, Pat.var ~loc:lab.loc slab)
      in
      let all = List.map f all in
      let cl = match clsd with None   -> Closed | Some _ -> Open in
      Pat.record ~loc:_loc all cl

  | '[' l:(list1 pattern semi_col) semi_col? c:']' ->
      let nil = Location.mkloc (Lident "[]") (ghost _loc_c) in
      let hd = match l with [] -> assert false | x::_ -> x in
      let cons x xs =
        let cloc = ghost (merge2 x.ppat_loc _loc) in
        let c = Location.mkloc (Lident "::") cloc in
        let loc = if x == hd then _loc else cloc in
        Pat.construct ~loc c (Some (Pat.tuple ~loc:cloc [x;xs]))
      in
      List.fold_right cons l (Pat.construct ~loc:(ghost _loc_c) nil None)

  | '[' ']' ->
      Pat.construct ~loc:_loc (Location.mkloc (Lident "[]") _loc) None

  | "[|" ps:(list0 pattern semi_col) semi_col? "|]" ->
      Pat.array ~loc:_loc ps

  | '(' ')' ->
      Pat.construct ~loc:_loc (Location.mkloc (Lident "()") _loc) None

  | begin_kw end_kw ->
      Pat.construct ~loc:_loc (Location.mkloc (Lident "()") _loc) None

  | '(' module_kw mn:module_name pt:{STR(":") pt:package_type}? ')' when lvl <= AtomPat ->
      begin
        let unpack = Pat.unpack ~loc:_loc mn in
        match pt with
        | None    -> unpack
        | Some pt -> let ty = Typ.mk ~loc:(ghost _loc) pt.ptyp_desc in
                     (* FIXME OCAML: why enlarge and ghost ?*)
                     Pat.constraint_ ~loc:_loc unpack ty
      end

  | p :(pattern_lvl (true , AltPat)) '|'
    p':(pattern_lvl (false, PatPrio.next AltPat)) when lvl <= AltPat ->
      Pat.or_ ~loc:_loc p p'

  | ps:{ (pattern_lvl (true , PatPrio.next TupPat)) _:','}+
       p:(pattern_lvl (false, PatPrio.next TupPat)) when lvl <= TupPat ->
      Pat.tuple ~loc:_loc (ps @ [p])

  | p :(pattern_lvl (true , PatPrio.next ConsPat)) c:"::"
    p':(pattern_lvl (false, ConsPat)) when lvl <= ConsPat ->
      let cons = Location.mkloc (Lident "::") _loc_c in
      let args = Pat.tuple ~loc:(ghost _loc) [p; p'] in
      Pat.construct ~loc:_loc cons (Some args)

  | '$' - c:uident when lvl <= AtomPat ->
     (try let str = Sys.getenv c in
          parse_string ~filename:("ENV:"^c) pattern ocaml_blank str
      with Not_found -> give_up ())

  | '$' - aq:{''[a-z]+'' - ':'}?["pat"] e:expression - '$' when lvl <= AtomPat ->
     begin
       let open Quote in
       let e_loc =
         Exp.ident ~loc:_loc (Location.mkloc (Lident "_loc") _loc)
       in
       let f =
         match aq with
         | "pat"    -> generic_antiquote Quote_ppat _loc e
         | "bool"   -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let id = if $e$ then "true" else "false" in
                         let id = Location.mkloc (Longident.Lident id) loc in
                         Earley_helpers.Helper.Pat.construct ~loc id None
                       >>
         | "int"    -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let i = Earley_helpers.Helper.Const.int $e$ in
                         Earley_helpers.Helper.Pat.constant ~loc i
                       >>
         | "string" -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let s = Earley_helpers.Helper.Const.string $e$ in
                         Earley_helpers.Helper.Pat.constant ~loc s
                       >>
         | "list"   -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let n = Location.mkloc (Longident.Lident "[]") loc in
                         let n =
                           Earley_helpers.Helper.Pat.construct ~loc n None
                         in
                         let c x xs =
                           let open Earley_helpers.Helper in
                           let c = Location.mkloc (Longident.Lident "::") loc in
                           let a = Pat.tuple ~loc [x;xs] in
                           Pat.construct ~loc c (Some a)
                         in
                         List.fold_right c $e$ n
                       >>
         | "tuple"  -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         Earley_helpers.Helper.Pat.tuple ~loc $e$
                       >>
         | "array"  -> generic_antiquote Quote_ppat _loc <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         Earley_helpers.Helper.Pat.array ~loc $e$
                       >>
         | _        -> give_up ()
      in
      Quote.ppat_antiquotation _loc f
    end)

(****************************************************************************
 * Expressions                                                              *
 ****************************************************************************)

let let_re = "\\(let\\)\\|\\(val\\)\\b"

type assoc = NoAssoc | Left | Right

let assoc = function
  Prefix | Dot | Dash | Opp -> NoAssoc
| Prod | Sum | Eq -> Left
| _ -> Right

let infix_prio s =
  match s.[0] with
  | '*' -> if String.length s > 1 && s.[1] = '*' then Pow else Prod
  | '/' | '%' -> Prod
  | '+' | '-' -> Sum
  | ':' -> if String.length s > 1 && s.[1] = '=' then Aff else Cons
  | '<' -> if String.length s > 1 && s.[1] = '-' then Aff else Eq
  | '@' | '^' -> Append
  | '&' -> if String.length s = 1 ||
                (String.length s = 2 && s.[1] = '&') then Conj else Eq
  | '|' -> if String.length s = 2 && s.[1] = '|' then Disj else Eq
  | '=' | '>' | '$' | '!' -> Eq
  | 'o' -> Disj
  | 'm' -> Prod
  | 'a' -> Pow
  | 'l' -> (match s.[1] with 's' -> Pow | _ -> Prod)
  | _ -> Printf.printf "%s\n%!" s; assert false

let prefix_prio s =
  if s = "-" || s = "-." || s = "+" || s = "+." then Opp else Prefix

let array_function loc str name =
  Exp.ident ~loc (Location.mkloc (Ldot(Lident str, name)) loc)

let bigarray_function loc str name =
  let lid = Ldot(Ldot(Lident "Bigarray", str), name) in
  Exp.ident ~loc (Location.mkloc lid loc)

let untuplify exp =
  match exp.pexp_desc with
  | Pexp_tuple es -> es
  | _             -> [exp]

let bigarray_get _loc arr arg =
  match untuplify arg with
  | [c1] ->
      <:expr<Bigarray.Array1.$lid:"get"$ $arr$ $c1$ >>
  | [c1;c2] ->
      <:expr<Bigarray.Array2.$lid:"get"$ $arr$ $c1$ $c2$ >>
  | [c1;c2;c3] ->
      <:expr<Bigarray.Array3.$lid:"get"$ $arr$ $c1$ $c2$ $c3$ >>
  | coords ->
      <:expr<Bigarray.Genarray.$lid:"get"$ $arr$ $array:coords$ >>

let bigarray_set _loc arr arg newval =
  match untuplify arg with
  | [c1] ->
      <:expr<Bigarray.Array1.$lid:"set"$ $arr$ $c1$ $newval$>>
  | [c1;c2] ->
      <:expr<Bigarray.Array2.$lid:"set"$ $arr$ $c1$ $c2$ $newval$>>
  | [c1;c2;c3] ->
      <:expr<Bigarray.Array3.$lid:"set"$ $arr$ $c1$ $c2$ $c3$ $newval$>>
  | coords ->
      <:expr<Bigarray.Genarray.$lid:"set"$ $arr$ $array:coords$ $newval$ >>

let parser constructor =
  | m:{ m:module_path STR"." }? id:{id:uident -> id | b:bool_lit -> b } ->
      match m with
      | None   -> Lident id
      | Some m -> Ldot(m, id)

let parser argument =
  | '~' id:lident no_colon ->
        (Labelled id, Exp.ident ~loc:_loc_id (Location.mkloc (Lident id) _loc_id))
  | id:ty_label e:(expression_lvl (NoMatch ,ExpPrio.next App)) ->
       (id, e)
  | '?' id:lident ->
       (Optional id, Exp.ident ~loc:_loc_id (Location.mkloc (Lident id) _loc_id))
  | id:ty_opt_label e:(expression_lvl (NoMatch, ExpPrio.next App)) ->
       (id, e)
  | e:(expression_lvl (NoMatch, ExpPrio.next App)) ->
       (Nolabel, e)

let _ = set_parameter (fun allow_new_type ->
  parser
  | pat:(pattern_lvl (false,AtomPat)) -> `Arg (Nolabel, None, pat)
  | '~' '(' id:lident t:{ STR":" t:typexpr }? STR")" -> (
      let pat =  Pat.var ~loc:_loc_id (Location.mkloc id _loc_id) in
      let pat =
        match t with
        | None   -> pat
        | Some t -> Pat.constraint_ ~loc:_loc pat t
      in
      `Arg (Labelled id, None, pat))
  | id:ty_label pat:pattern -> `Arg (id, None, pat)
  | '~' id:lident no_colon -> `Arg (Labelled id, None, Pat.var ~loc:_loc_id (Location.mkloc id _loc_id))
  | '?' '(' id:lident t:{ ':' t:typexpr -> t }? e:{'=' e:expression -> e}? ')' -> (
      let pat = Pat.var ~loc:_loc_id (Location.mkloc id _loc_id) in
      let pat =
        match t with
        | None   -> pat
        | Some t -> Pat.constraint_ ~loc:(merge2 _loc_id _loc_t) pat t
      in
      `Arg (Optional id, e, pat))
  | id:ty_opt_label STR"(" pat:pattern t:{':' t:typexpr}? e:{'=' e:expression}? ')' -> (
      let pat =
        match t with
        | None   -> pat
        | Some t -> Pat.constraint_ ~loc:(merge2 _loc_pat _loc_t) pat t
      in
      `Arg (id, e, pat))
  | id:ty_opt_label pat:pattern -> `Arg (id, None, pat)
  | '?' id:lident ->
       (* FIXME OCAML: why is ? treated differently in label position *)
      `Arg (Optional id, None, Pat.var ~loc:_loc_id (Location.mkloc id _loc_id))
  | '(' type_kw name:typeconstr_name ')' when allow_new_type ->
      `Type(Location.mkloc name _loc_name)
  )

let apply_params ?(gh=false) _loc params e =
  let f acc = function
    | `Arg (lbl,opt,pat), _loc' ->
       Exp.fun_ ~loc:(ghost (merge2 _loc' _loc)) lbl opt pat acc
    | `Type name, _loc' ->
       (** FIXME OCAML: should be ghost, or above should not be ghost *)
       Exp.newtype ~loc:(merge2 _loc' _loc) name acc
  in
  let e = List.fold_left f e (List.rev params) in
  if gh then e else de_ghost e

let apply_params_cls ?(gh=false) _loc params e =
  let ghost _loc' = if gh then merge2 _loc' _loc else _loc in
  let f acc = function
    (** FIXME OCAML: shoud be ghost as above ? *)
    | `Arg (lbl,opt,pat), _loc' -> Cl.fun_ ~loc:(ghost _loc') lbl opt pat acc
    | `Type name        , _     -> assert false
  in
  List.fold_left f e (List.rev params)

let parser right_member =
  | l:{lb:(parameter true) -> lb, _loc_lb}+ ty:{':' t:typexpr}?
    '=' e:expression ->
      let e =
        match ty with
        | None    -> e
        | Some ty -> Exp.constraint_ ~loc:(ghost (merge2 _loc_ty _loc)) e ty
      in
      apply_params ~gh:true _loc_e l e

let parser eright_member = ty:{':' t:typexpr}? '=' e:expression

let _ = set_grammar let_binding (
  parser
  | pat:pattern erm:eright_member a:post_item_attributes
    l:{_:and_kw let_binding}?[[]] ->
      let (_ty, e) = erm in
      let loc = merge2 _loc_pat _loc_erm in
      let (pat, e) =
        match _ty with
        | None -> (pat, e)
        | Some ty ->
           (* FIXME OCAML: crisper position are possible!*)
           let loc = ghost _loc in
           let poly_ty = Typ.poly ~loc:(ghost _loc(*_ty*)) [] ty in
           (Pat.constraint_ ~loc pat poly_ty, Exp.constraint_ ~loc e ty)
      in
      Vb.mk ~loc ~attrs:(attach_attrib loc a) pat e :: l
  | vn:value_name e:right_member a:post_item_attributes l:{_:and_kw let_binding}?[[]] ->
      let loc = merge2 _loc_vn _loc_e in
      let pat = Pat.var ~loc:_loc_vn (Location.mkloc vn _loc_vn) in
      Vb.mk ~loc ~attrs:(attach_attrib loc a) pat e :: l
  | vn:value_name ':' ty:only_poly_typexpr '=' e:expression a:post_item_attributes l:{_:and_kw let_binding}?[[]] ->
      let pat =
        Pat.constraint_ ~loc:(ghost _loc)
          (Pat.var ~loc:_loc_vn (Location.mkloc vn _loc_vn))
          (** FIXME OCAML: shoud not change the position below *)
          (Typ.mk ~loc:(ghost _loc) ty.ptyp_desc)
      in
      let loc = merge2 _loc_vn _loc_e in
      Vb.mk ~loc ~attrs:(attach_attrib loc a) pat e :: l
  | vn:value_name ':' (ids,ty):poly_syntax_typexpr '=' e:expression
    a:post_item_attributes l:{_:and_kw let_binding}?[[]] ->
      let loc = merge2 _loc_vn _loc_e in
      let (e, ty) = wrap_type_annotation loc ids ty e in
      let pat =
        Pat.constraint_ ~loc:(ghost loc)
          (Pat.var ~loc:_loc_vn (Location.mkloc vn _loc_vn)) ty
      in
      Vb.mk ~loc ~attrs:(attach_attrib loc a) pat e :: l
  | dol:CHR('$') - aq:{c:"bindings" ":" -> c}?["bindings"] e:(expression_lvl (NoMatch, App)) - CHR('$') l:{_:and_kw let_binding}?[[]] ->
     begin
       let open Quote in
       let f =
         match aq with
         | "bindings" -> generic_antiquote Quote_loc _loc e
         | _          -> give_up ()
       in
       make_list_antiquotation _loc Quote_loc f
    end
  )

let parser match_case alm lvl =
  | pat:pattern  guard:{_:when_kw expression}? "->"
      e:{(expression_lvl (alm, lvl)) | "." -> Exp.unreachable ~loc:_loc ()} ->
  Exp.case pat ?guard e

let _ = set_grammar match_cases (
  parser
  | '|'? l:{(match_case Let Seq) '|'}* x:(match_case Match Seq) no_semi -> l @ [x]
  | EMPTY -> []
  | '$' - {"cases" ":"}? e:expression - '$' ->
      list_antiquotation _loc e
  )

let parser type_coercion =
  | STR(":") t:typexpr t':{STR(":>") t':typexpr}? -> (Some t, t')
  | STR(":>") t':typexpr -> (None, Some t')

let parser expression_list =
  | l:{ e:(expression_lvl (NoMatch, ExpPrio.next Seq)) _:semi_col -> (e, _loc_e)}*
    e:(expression_lvl (Match, ExpPrio.next Seq)) semi_col? ->
      l @ [e,_loc_e]
  | EMPTY -> []

let parser record_item =
  | f:field '=' e:(expression_lvl (NoMatch, ExpPrio.next Seq)) ->
      (Location.mkloc f _loc_f, e)
  | f:lident ->
      let id = Location.mkloc (Lident f) _loc_f in
      (id, Exp.ident ~loc:_loc_f id)

let parser last_record_item =
  | f:field '=' e:(expression_lvl (Match, ExpPrio.next Seq)) ->
      (Location.mkloc f _loc_f,e)
  | f:lident ->
      let id = Location.mkloc (Lident f) _loc_f in
      (id, Exp.ident ~loc:_loc_f id)

let _ = set_grammar record_list (
  parser
  | l:{ record_item _:semi_col }* it:last_record_item semi_col? -> (l@[it])
(*  | dol:CHR('$') - e:(expression_lvl App) - CHR('$') STR(semi_col)? ls:record_list ->
    push_pop_record (start_pos _loc_dol).Lexing.pos_cnum e @ ls*)
  | EMPTY -> [])

(****************************************************************************
 * classes and objects                                                      *
 ****************************************************************************)

let parser obj_item =
  | v:inst_var_name CHR('=') e:(expression_lvl (Match, ExpPrio.next Seq)) (* FIXME match always allowed ?*)
     -> (Location.mkloc v _loc_v, e)

(* Class expression *)

let parser class_expr_base =
  | cp:class_path ->
      let cp = Location.mkloc cp _loc_cp in
      Cl.constr ~loc:_loc cp []
  | '[' te:typexpr tes:{',' te:typexpr}* ']' cp:class_path ->
      let cp = Location.mkloc cp _loc_cp in
      Cl.constr ~loc:_loc cp (te :: tes)
  | STR("(") ce:class_expr STR(")") ->
      Cl.mk ~loc:_loc ce.pcl_desc
  | STR("(") ce:class_expr STR(":") ct:class_type STR(")") ->
      Cl.constraint_ ~loc:_loc ce ct
  | fun_kw ps:{p:(parameter false) -> (p, _loc)}+ "->" ce:class_expr ->
      apply_params_cls _loc ps ce
  | let_kw r:rec_flag lbs:let_binding in_kw ce:class_expr ->
      Cl.let_ ~loc:_loc r lbs ce
  | object_kw cb:class_body end_kw ->
      Cl.structure ~loc:_loc cb

let _ = set_grammar class_expr (
  parser ce:class_expr_base args:{arg:argument+}? ->
    match args with None -> ce | Some l -> Cl.apply ~loc:_loc ce l
  )

let parser class_field =
  | inherit_kw o:override_flag ce:class_expr
    id:{_:as_kw id:lident -> Location.mkloc id _loc_id}? ->
      Cf.inherit_ ~loc:_loc o ce id
  | val_kw o:override_flag m:mutable_flag ivn:inst_var_name te:{':' t:typexpr}?
    '=' e:expression ->
      let ivn = Location.mkloc ivn _loc_ivn in
      let ex =
        match te with
        | None   -> e
        | Some t -> Exp.constraint_ ~loc:(ghost (merge2 _loc_ivn _loc)) e t
      in
      Cf.val_ ~loc:_loc ivn m (Cf.concrete o ex)
  | val_kw m:mutable_flag virtual_kw ivn:inst_var_name ':' te:typexpr ->
      let ivn = Location.mkloc ivn _loc_ivn in
      Cf.val_ ~loc:_loc ivn m (Cf.virtual_ te)
  | val_kw virtual_kw mutable_kw ivn:inst_var_name STR(":") te:typexpr ->
      let ivn = Location.mkloc ivn _loc_ivn in
      Cf.val_ ~loc:_loc ivn Mutable (Cf.virtual_ te)
  | method_kw t:{override_flag private_flag method_name} ':' te:poly_typexpr
    '=' e:expression ->
      let (o,p,mn) = t in
      let e = Exp.poly ~loc:(ghost (merge2 _loc_t _loc)) e (Some te) in
      Cf.method_ ~loc:_loc mn p (Cf.concrete o e)
  | method_kw t:{override_flag private_flag method_name}
    ':' (ids,te):poly_syntax_typexpr '=' e:expression ->
      let (o,p,mn) = t in
      let _loc_e = merge2 _loc_t _loc in
      let e, poly =  wrap_type_annotation _loc_e ids te e in
      let e = Exp.poly ~loc:(ghost _loc_e) e (Some poly) in
      Cf.method_ ~loc:_loc mn p (Cf.concrete o e)
  | method_kw t:{override_flag private_flag method_name}
    ps:{p:(parameter true) -> p,_loc_p}* te:{':' te:typexpr}?
    '=' e:expression ->
      let (o,p,mn) = t in
      if ps = [] && te <> None then give_up ();
      let e =
        match te with
        | None    -> e
        | Some te -> Exp.constraint_ ~loc:(ghost (merge2 _loc_te _loc_e)) e te
      in
      let e : expression = apply_params ~gh:true _loc_e ps e in
      let e = Exp.poly ~loc:(ghost (merge2 _loc_t _loc_e)) e None in
      Cf.method_ ~loc:_loc mn p (Cf.concrete o e)
  | method_kw p:private_flag virtual_kw mn:method_name ':' pte:poly_typexpr ->
      Cf.method_ ~loc:_loc mn p (Cf.virtual_ pte)
  | method_kw virtual_kw private_kw mn:method_name ':' pte:poly_typexpr ->
      Cf.method_ ~loc:_loc mn Private (Cf.virtual_ pte)
  | constraint_kw te:typexpr CHR('=') te':typexpr ->
      Cf.constraint_ ~loc:_loc te te'
  | initializer_kw e:expression ->
      Cf.initializer_ ~loc:_loc e
  | attr:floating_attribute ->
      Cf.attribute ~loc:_loc attr
  | ext:floating_extension ->
      Cf.extension ~loc:_loc ext

let _ = set_grammar class_body (
  parser p:pattern? f:class_field* ->
    let p =
      match p with
      | None   -> Pat.any ~loc:(ghost _loc_p) ()
      | Some p -> p
    in
    Cstr.mk p f
  )

(* Class definition *)
let parser class_binding =
  | virt:virtual_flag params:{'[' params:type_parameters ']'}?[[]]
    cn:class_name ps:{p:(parameter false) -> (p,_loc)}*
    ct:{':' ct:class_type}? '=' ce:class_expr ->
      let ce = apply_params_cls ~gh:true (merge2 _loc_ps _loc) ps ce in
      let ce =
        match ct with
        | None    -> ce
        | Some ct -> Cl.constraint_ ~loc:_loc ce ct
      in
      (fun loc -> Ci.mk ~loc ~attrs:(attach_attrib _loc []) ~virt ~params
         (Location.mkloc cn _loc_cn) ce)

let parser class_definition =
  | k:class_kw cb:class_binding cbs:{_:and_kw cb:class_binding -> cb _loc}*
        -> (cb (merge2 _loc_k _loc_cb)::cbs)

let pexp_list loc ?loc_cl l =
  let nil loc = Exp.construct ~loc (Location.mkloc (Lident "[]") loc) None in
  match l with
  | [] -> nil loc
  | _  ->
      let loc_cl = ghost (match loc_cl with None -> loc | Some pos -> pos) in
      let fn (x, pos) acc =
        let loc = ghost (merge2 pos loc_cl) in
        Exp.construct ~loc
          (Location.mkloc (Lident "::") (ghost loc))
          (Some (Exp.tuple ~loc [x;acc]))
      in
      List.fold_right fn l (nil loc_cl)


let apply_lbl loc (lbl, e) =
  match e with
  | None   -> (lbl, Exp.ident ~loc (Location.mkloc (Lident lbl) loc))
  | Some e -> (lbl, e)

let rec mk_seq loc_c final l =
  match l with
  | []     -> final
  | e :: l -> let rest = mk_seq loc_c final l in
              Exp.sequence ~loc:(merge2 e.pexp_loc loc_c) e rest

(* Expressions *)
let parser extra_expressions_grammar c =
  (alternatives (List.map (fun g -> g c) extra_expressions))

let structure_item_simple = declare_grammar "structure_item_simple"

let parser left_expr @(alm,lvl) =
  | fun_kw l:{lbl:(parameter true) -> lbl,_loc_lbl}* "->"
    when allow_let alm && lvl < App ->
      (Seq, false, (fun e (_loc,_) -> Exp.mk ~loc:_loc (apply_params _loc l e).pexp_desc))

  | _:let_kw f:{
    | r:rec_flag l:let_binding
         -> (fun e (_l,_) -> Exp.let_ ~loc:_l r l e)
    | module_kw mn:module_name l:{ '(' mn:module_name mt:{':' module_type}? ')'
                                     -> (mn, mt, _loc)}*
                mt:{STR":" mt:module_type }?
                STR"=" me:module_expr
         -> (fun e (_l,_) ->
               let me =
                 match mt with
                 | None    -> me
                 | Some mt -> Mod.constraint_ ~loc:(merge2 _loc_mt _loc_me) me mt
               in
               let me =
                 List.fold_left (fun acc (mn,mt,_l) -> Mod.functor_
                   ~loc:(merge2 _l _loc_me) mn mt acc) me (List.rev l)
               in
               Exp.letmodule ~loc:_l mn me e)
    | open_kw o:override_flag mp:module_path
         -> (fun e (_l,_) ->
              (let mp = Location.mkloc mp _loc_mp in
               Exp.mk ~loc:_l (Pexp_open (o, mp, e)))) (* FIXME *)
    } _:in_kw when allow_let alm && lvl < App
    -> (Seq, false, f)

  | if_kw c:expression then_kw e:(expression_lvl (Match, ExpPrio.next Seq)) else_kw
       when (allow_let alm || lvl = If) && lvl < App
    -> (ExpPrio.next Seq, false, (fun e' (_loc,_) -> <:expr< if $c$ then $e$ else $e'$>>))

  | if_kw c:expression then_kw
       when (allow_let alm || lvl = If) && lvl < App
    -> (ExpPrio.next Seq, true, (fun e (_loc,_) ->  <:expr< if $c$ then $e$>>))

  | ls:{(expression_lvl (NoMatch, ExpPrio.next Seq)) _:semi_col }+ when lvl <= Seq ->
       (ExpPrio.next Seq, false, (fun e' (_,_l) ->
        mk_seq _l e' ls))

  | v:inst_var_name STR("<-") when lvl <= Aff
    -> (ExpPrio.next Aff, false, (fun e (_l,_) ->
          Exp.setinstvar ~loc:_l (Location.mkloc v _loc_v) e))

  | e':(expression_lvl (NoMatch, Dot)) '.'
      f:{ STR("(") f:expression STR(")") ->
           fun e' e (_l,_) ->
             Exp.apply ~loc:_l (array_function (ghost (merge2 e'.pexp_loc _l)) "Array" "set")
               [(Nolabel, e');(Nolabel, f);(Nolabel, e)]

        | STR("[") f:expression STR("]") ->
           fun e' e (_l,_) ->
             Exp.apply ~loc:_l (array_function (ghost (merge2 e'.pexp_loc _l)) "String" "set")
               [(Nolabel, e');(Nolabel, f);(Nolabel, e)]

        | STR("{") f:expression STR("}") ->
           fun e' e (_l,_) ->
             de_ghost (bigarray_set (ghost (merge2 e'.pexp_loc _l)) e' f e)

        | f:field ->
           fun e' e (_l,_) -> let f = Location.mkloc f _loc_f in
             Exp.setfield ~loc:_l e' f e

        } "<-"
      when lvl <= Aff
    -> (ExpPrio.next Aff, false, f e')

  | l:{(expression_lvl (NoMatch, ExpPrio.next Tupl)) _:',' }+
      when lvl <= Tupl ->
       (ExpPrio.next Tupl, false, (fun e' (_l,_) -> Exp.tuple ~loc:_l (l@[e'])))

  | assert_kw when lvl <= App ->
      (ExpPrio.next App, false, (fun e (_l,_) -> Exp.assert_ ~loc:_l e))

  | lazy_kw when lvl <= App ->
      (ExpPrio.next App, false, (fun e (_l,_) -> Exp.lazy_ ~loc:_l e))

  | (prefix_expr Opp) when lvl <= Opp
  | (prefix_expr Prefix) when lvl <= Prefix

  | (infix_expr Prod) when lvl <= Prod
  | (infix_expr Sum) when lvl <= Sum
  | (infix_expr Append) when lvl <= Append
  | (infix_expr Cons) when lvl <= Cons
  | (infix_expr Aff) when lvl <= Aff
  | (infix_expr Eq) when lvl <= Eq
  | (infix_expr Conj) when lvl <= Conj
  | (infix_expr Disj) when lvl <= Disj
  | (infix_expr Pow) when lvl <= Pow

and parser prefix_expr lvl =
  p:(prefix_symbol lvl) -> (lvl, false, (fun e (_l,_) -> mk_unary_op _l p _loc_p e))

and infix_expr lvl =
  if assoc lvl = Left then
    parser
      e':(expression_lvl (NoMatch, lvl)) op:(infix_symbol lvl) ->
         (ExpPrio.next lvl, false,
          fun e (_l,_) -> mk_binary_op _l e' op _loc_op e)
         else if assoc lvl = NoAssoc then
    parser
      e':(expression_lvl (NoMatch, ExpPrio.next lvl)) op:(infix_symbol lvl) ->
         (ExpPrio.next lvl, false,
          fun e (_l,_) -> mk_binary_op _l e' op _loc_op e)
  else
    parser
      ls:{e':(expression_lvl (NoMatch, ExpPrio.next lvl)) op:(infix_symbol lvl)
             -> (_loc,e',op,_loc_op) }+ ->
         (ExpPrio.next lvl, false,
          fun e (_l,_) ->
          List.fold_right
            (fun (_loc_e,e',op,_loc_op) acc
             -> mk_binary_op (merge2 _loc_e _l) e' op _loc_op acc) ls e)

let parser prefix_expression =
  | function_kw l:match_cases
       -> <:expr< function $cases:l$>>

  | match_kw e:expression with_kw l:match_cases
       -> <:expr< match $e$ with $cases:l$>>

  | try_kw e:expression with_kw l:match_cases
       -> <:expr< try $e$ with $cases:l$>>

  | e:(alternatives extra_prefix_expressions)

let parser right_expression @lvl =
  | id:value_path when lvl <= Atom -> Exp.ident ~loc:_loc (Location.mkloc id _loc_id)

  | c:constant when lvl <= Atom -> Exp.constant ~loc:_loc c

  | mp:module_path STR(".") STR("(") e:expression STR(")") when lvl <= Atom ->
      let mp = Location.mkloc mp _loc_mp in
      Exp.mk ~loc:_loc (Pexp_open (Fresh, mp, e))
      (* FIXME *)

  | mp:module_path '.' '[' l:expression_list cl: ']' when lvl <= Atom ->
      let mp = Location.mkloc mp _loc_mp in
      Exp.mk ~loc:_loc (Pexp_open (Fresh, mp, Exp.mk ~loc:_loc (pexp_list _loc ~loc_cl:_loc_cl l).pexp_desc))
      (* FIXME *)

  | mp:module_path '.' '{' e:{expression _:with_kw}? l:record_list '}' when lvl <= Atom ->
      let mp = Location.mkloc mp _loc_mp in
      Exp.mk ~loc:_loc (Pexp_open (Fresh, mp, Exp.record ~loc:_loc l e))

  | '(' e:expression? ')' when lvl <= Atom ->
      begin
        match e with
        | Some e -> if Quote.is_antiquotation e.pexp_loc then e
                    else Exp.mk ~loc:_loc e.pexp_desc
        | None   ->
           let cunit = Location.mkloc (Lident "()") _loc in
           Exp.construct ~loc:_loc cunit None
      end

  | '(' no_parser e:expression t:type_coercion ')'  when lvl <= Atom  ->
      begin
        match t with
        | (Some t1, None   ) -> Exp.constraint_ ~loc:(ghost _loc) e t1
        | (t1     , Some t2) -> Exp.coerce ~loc:(ghost _loc) e t1 t2
        | (None   , None   ) -> assert false
      end

  | begin_kw e:expression? end_kw when lvl <= Atom ->
      begin
        match e with
        | Some e -> if Quote.is_antiquotation e.pexp_loc then e
                    else Exp.mk ~loc:_loc e.pexp_desc
        | None   ->
           let cunit = Location.mkloc (Lident "()") _loc in
           Exp.construct ~loc:_loc cunit None
      end

  | f:(expression_lvl (NoMatch, ExpPrio.next App)) l:argument+ when lvl <= App ->
      begin
        match (f.pexp_desc, l) with
        | (Pexp_construct(c,None), [Nolabel, a]) ->
            Exp.construct ~loc:_loc c (Some a)
        | (Pexp_variant(c,None)  , [Nolabel, a]) ->
            Exp.variant ~loc:_loc c (Some a)
        | (_                     , _           ) ->
            Exp.apply ~loc:_loc f l
      end

  | c:constructor no_dot when lvl <= Atom ->
      Exp.construct ~loc:_loc (Location.mkloc c _loc_c) None

  | l:tag_name  when lvl <= Atom ->
      Exp.variant ~loc:_loc l None

  | "[|" l:expression_list "|]" when lvl <= Atom ->
      Exp.array ~loc:_loc (List.map fst l)

  | '[' l:expression_list cl:']' when lvl <= Atom ->
      Exp.mk ~loc:_loc (pexp_list _loc ~loc_cl:_loc_cl l).pexp_desc

  | STR("{") e:{expression _:with_kw}? l:record_list STR("}") when lvl <= Atom ->
      Exp.record ~loc:_loc l e

  | while_kw e:expression do_kw e':expression done_kw when lvl <= Atom ->
      Exp.while_ ~loc:_loc e e'

  | for_kw id:pattern CHR('=') e:expression d:downto_flag e':expression
    do_kw e'':expression done_kw when lvl <= Atom ->
      Exp.for_ ~loc:_loc id e e' d e''

  | new_kw p:class_path when lvl <= Atom ->
      Exp.new_ ~loc:_loc (Location.mkloc p _loc_p)

  | object_kw o:class_body end_kw when lvl <= Atom ->
      Exp.object_ ~loc:_loc o

  | "{<" l:{o:obj_item l:{_:semi_col o:obj_item}* _:semi_col? -> o::l}?[[]]
    ">}" when lvl <= Atom ->
      Exp.override ~loc:_loc l

  | '(' module_kw me:module_expr pt:{STR(":") pt:package_type}? ')' when lvl <= Atom ->
      begin
        match pt with
        | None    -> Exp.pack ~loc:_loc me
        | Some pt -> let me = Exp.pack ~loc:(ghost _loc) me in
                     (* FIXME OCAML: why enlarge and ghost ?*)
                     let pt = Typ.mk ~loc:(ghost _loc) pt.ptyp_desc in
                     Exp.constraint_ ~loc:_loc me pt
      end
  | e':{e':(expression_lvl (NoMatch, Dot)) -> e'} '.'
      r:{ STR("(") f:expression STR(")") ->
           fun e' _l -> Exp.apply ~loc:_l (array_function (ghost (merge2 e'.pexp_loc _l)) "Array" "get")
             [(Nolabel, e'); (Nolabel, f)]

        | STR("[") f:expression STR("]") ->
           fun e' _l -> Exp.apply ~loc:_l (array_function (ghost (merge2 e'.pexp_loc _l)) "String" "get")
             [(Nolabel, e'); (Nolabel, f)]

        | STR("{") f:expression STR("}") ->
           fun e' _l -> bigarray_get (ghost (merge2 e'.pexp_loc _l)) e' f

        | f:field ->
           fun e' _l ->
             let f = Location.mkloc f _loc_f in Exp.field ~loc:_l e' f
        } when lvl <= Dot -> r e' _loc

  | e':(expression_lvl (NoMatch, Dash)) '#' f:method_name when lvl <= Dash ->
      Exp.send ~loc:_loc e' f

  | '$' - c:uident when lvl <= Atom ->
      begin
        match c with
        | "FILE" -> let str = (_loc.loc_start).Lexing.pos_fname in
                    Exp.constant ~loc:_loc (Const.string str)
        | "LINE" -> let i = (_loc.loc_start).Lexing.pos_lnum in
                    Exp.constant ~loc:_loc (Const.int i)
        | _      ->
            try
              let str = Sys.getenv c in
              parse_string ~filename:("ENV:"^c) expression ocaml_blank str
            with Not_found -> give_up ()
      end

  | "<:" r:{ "expr"          '<' e:expression            ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_expression e_loc _loc_e e
           | "type"          '<' e:typexpr               ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_core_type  e_loc _loc_e e
           | "pat"           '<' e:pattern               ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_pattern    e_loc _loc_e e
           | "struct"        '<' e:structure_item_simple ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_structure  e_loc _loc_e e
           | "sig"           '<' e:signature_item        ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_signature  e_loc _loc_e e
           | "constructors"  '<' e:constr_decl_list      ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.(quote_list quote_constructor_declaration e_loc _loc_e e)
           | "fields"        '<' e:field_decl_list       ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.(quote_list quote_label_declaration e_loc _loc_e e)
           | "bindings"      '<' e:let_binding           ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.(quote_list quote_value_binding e_loc _loc_e e)
           | "cases"         '<' e:match_cases           ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.(quote_list quote_case e_loc _loc_e e)
           | "module"        '<' e:module_expr           ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_module_expr e_loc _loc_e e
           | "module" "type" '<' e:module_type           ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               Quote.quote_module_type e_loc _loc_e e
           | "record"        '<' e:record_list           ">>" ->
               let lid = Location.mkloc (Lident "_loc") _loc in
               let e_loc = Exp.ident ~loc:_loc lid in
               let quote_fields =
                 let open Quote in
                 quote_list (fun e_loc _loc (x1,x2) ->
                   quote_tuple e_loc _loc
                     [(quote_loc quote_longident) e_loc _loc x1
                     ; quote_expression e_loc _loc x2;])
               in
               quote_fields e_loc _loc_e e
         } when lvl <= Atom
        -> r

  | '$' - aq:{''[a-z]+'' - ':'}?["expr"] e:expression - '$' when lvl <= Atom ->
    let f =
      let open Quote in
      let e_loc = Exp.ident ~loc:_loc (Location.mkloc (Lident "_loc") _loc) in
      let generic_antiquote = generic_antiquote Quote_pexp _loc in
      match aq with
      | "expr"      -> generic_antiquote e
      | "longident" -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         Earley_helpers.Helper.Exp.ident ~loc (Location.mkloc $e$ loc)
                       >>
      | "bool"      -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let id = if $e$ then "true" else "false" in
                         let id = Location.mkloc (Longident.Lident id) loc in
                         Earley_helpers.Helper.Exp.construct ~loc id None
                       >>
      | "int"       -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let i = Earley_helpers.Helper.Const.int $e$ in
                         Earley_helpers.Helper.Exp.constant ~loc i
                       >>
      | "float"     -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let f = string_of_float $e$ in
                         let f = Earley_helpers.Helper.Const.float f in
                         Earley_helpers.Helper.Exp.constant ~loc f
                       >>
      | "string"    -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let s = Earley_helpers.Helper.Const.string $e$ in
                         Earley_helpers.Helper.Exp.constant ~loc s
                       >>
      | "char"      -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let c = Earley_helpers.Helper.Const.char $e$ in
                         Earley_helpers.Helper.Exp.constant ~loc c
                       >>
      | "list"      -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         let n = Location.mkloc (Longident.Lident "[]") loc in
                         let n =
                           Earley_helpers.Helper.Exp.construct ~loc n None
                         in
                         let c x xs =
                           let open Earley_helpers.Helper in
                           let c = Location.mkloc (Longident.Lident "::") loc in
                           let a = Exp.tuple ~loc [x;xs] in
                           Exp.construct ~loc c (Some a)
                         in
                         List.fold_right c $e$ n
                       >>
      | "tuple"     -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         assert (List.length $e$ > 1);
                         Earley_helpers.Helper.Exp.tuple ~loc $e$
                       >>
      | "array"     -> generic_antiquote <:expr<
                         let loc = $quote_location_t e_loc _loc _loc$ in
                         Earley_helpers.Helper.Exp.array ~loc $e$
                       >>
      | _           -> give_up ()
    in
    Quote.pexp_antiquotation _loc f

let parser semicol @(alm, lvl) =
  | semi_col when lvl = Seq -> true
  | no_semi  when lvl = Seq -> false
  | EMPTY    when lvl > Seq -> false

let parser noelse @b =
  | no_else when b
  | EMPTY   when not b

let parser debut lvl alm = s:(left_expr (alm,lvl)) ->
  let (lvl0, no_else, f) = s in
  ((lvl0,no_else), (f, _loc_s))

let parser suit lvl alm (lvl0,no_else) =
  | e:(expression_lvl (alm,lvl0)) c:(semicol (alm,lvl)) (noelse no_else) ->
      fun (f, _loc_s) ->
        let _l = merge2 _loc_s _loc_e in
        (* position of the last semi column for sequence only *)
        let _loc_c = if c then _loc_c else _loc_e in
        f e (_l, _loc_c)

let _ = set_expression_lvl (fun (alm, lvl as c) -> parser
  | e:(extra_expressions_grammar c) (semicol (alm,lvl)) -> e
  | (Earley.dependent_sequence (debut lvl alm) (suit lvl alm))
  | r:(right_expression lvl) (semicol (alm,lvl)) -> r
  | r:prefix_expression (semicol (alm,lvl)) when allow_match alm -> r )

(****************************************************************************
 * Module expressions (module implementations)                              *
 ****************************************************************************)

let parser module_expr_base =
  | mp:module_path ->
      Mod.ident ~loc:_loc (Location.mkloc mp _loc)
  | {struct_kw -> push_comments ()} ms:{ms:structure -> ms @ attach_str _loc}
    {end_kw ->  pop_comments ()} ->
      Mod.structure ~loc:_loc ms
  | functor_kw '(' mn:module_name mt:{':' mt:module_type}? ')'
    "->" me:module_expr ->
      Mod.functor_ ~loc:_loc mn mt me
  | '(' me:module_expr mt:{':' mt:module_type}? ')' ->
      begin
        match mt with
        | None    -> me
        | Some mt -> Mod.constraint_ ~loc:_loc me mt
      end
  | '(' val_kw e:expression pt:{STR(":") pt:package_type}? ')' ->
      let e =
        match pt with
        | None    -> e
        | Some pt -> Exp.constraint_ ~loc:(ghost _loc) e pt
      in
      Mod.unpack ~loc:_loc e

let _ = set_grammar module_expr (
  parser m:module_expr_base l:{'(' m:module_expr ')' -> (_loc, m)}* ->
    let fn acc (_loc_n, n) = Mod.apply ~loc:(merge2 _loc_m _loc_n) acc n in
    List.fold_left fn m l
  )

let parser module_type_base =
  | mp:modtype_path ->
      Mty.ident ~loc:_loc (Location.mkloc mp _loc)
  | {sig_kw -> push_comments ()} ms:{ms:signature -> ms @ attach_sig _loc}
    {end_kw -> pop_comments () } ->
      Mty.signature ~loc:_loc ms
  | functor_kw '(' mn:module_name mt:{':' mt:module_type}? ')'
    "->" me:module_type no_with ->
      Mty.functor_ ~loc:_loc mn mt me
  | '(' module_type ')'
  | module_kw type_kw of_kw me:module_expr ->
      Mty.typeof_ ~loc:_loc me

let parser mod_constraint =
  | t:type_kw tf:typedef_in_constraint ->
      let (tn,ty) = tf (Some _loc_t) in
      Pwith_type(tn, ty)
  | module_kw m1:module_path '=' m2:extended_module_path ->
      let name = Location.mkloc m1 _loc_m1 in
      Pwith_module(name, Location.mkloc m2 _loc_m2 )
  | type_kw tps:type_params tcn:typeconstr ":=" te:typexpr ->
      let tcn0 = Location.mkloc (Longident.last tcn) _loc_tcn in
      let _tcn = Location.mkloc tcn _loc_tcn in
      let td = Type.mk ~loc:_loc ~params:tps ~cstrs:[] ~kind:Ptype_abstract
                ~priv:Public ~manifest:te tcn0 in
      Pwith_typesubst(_tcn,td)
  | module_kw mn:module_path STR(":=") emp:extended_module_path ->
      let mn = Location.mkloc mn _loc_mn in
      Pwith_modsubst(mn, Location.mkloc emp _loc_emp)

let _ = set_grammar module_type (
  parser
  | m:module_type_base
    l:{_:with_kw m:mod_constraint l:{_:and_kw mod_constraint}* -> m::l}? ->
      match l with
      | None   -> m
      | Some l -> Mty.with_ ~loc:_loc m l
  )

let parser structure_item_base =
  | RE(let_re) r:rec_flag l:let_binding ->
      Str.value ~loc:_loc r l
  | external_kw n:value_name ':' ty:typexpr
    '=' ls:string_litteral*  a:post_item_attributes ->
      let ls = List.map fst ls in
      let l = List.length ls in
      if l < 1 || l > 3 then give_up ();
      Str.primitive ~loc:_loc (Val.mk ~loc:_loc ~attrs:(attach_attrib _loc a)
        ~prim:ls (Location.mkloc n _loc_n) ty)
  | td:type_definition -> Str.type_ ~loc:_loc Recursive td (* FIXME for NonRec *)
  | te:type_extension  -> Str.type_extension ~loc:_loc te
  | ex:exception_definition -> Str.mk ~loc:_loc ex
  | module_kw r:{ rec_kw mn:module_name mt:{':' mt:module_type}?
                  '=' me:module_expr
                  ms:{and_kw mn:module_name mt:{':' mt:module_type}? '='
                      me:module_expr ->
                        let loc = merge2 _loc_mt _loc_me in
                        let me =
                          match mt with
                          | None    -> me
                          | Some mt -> Mod.constraint_ ~loc me mt
                        in
                        Mb.mk ~loc mn me
                     }* ->
                   let loc = merge2 _loc_mt _loc_me in
                   let me =
                     match mt with
                     | None    -> me
                     | Some mt -> Mod.constraint_ ~loc me mt
                   in
                   let m = Mb.mk ~loc mn me in
                   Pstr_recmodule(m::ms)
                | mn:module_name l:{'(' mn:module_name
                  mt:{':' mt:module_type}? ')' -> (mn, mt, _loc)}*
                  mt:{':' mt:module_type }? '=' me:module_expr ->
                   let loc = merge2 _loc_mt _loc_me in
                   let me =
                     match mt with
                     | None    -> me
                     | Some mt -> Mod.constraint_ ~loc me mt
                   in
                   let fn acc (mn,mt,_loc) =
                     Mod.functor_ ~loc:(merge2 _loc _loc_me) mn mt acc
                   in
                   let me = List.fold_left fn me (List.rev l) in
                   Pstr_module(Mb.mk ~loc:_loc mn me)
                | type_kw mn:modtype_name mt:{'=' mt:module_type}?
                  a:post_item_attributes ->
                   Pstr_modtype{pmtd_name = Location.mkloc mn _loc_mn; pmtd_type = mt;
                   pmtd_attributes = attach_attrib _loc a; pmtd_loc = _loc }
                } -> Str.mk ~loc:_loc r
  | open_kw o:override_flag m:module_path a:post_item_attributes ->
      Str.mk ~loc:_loc (Pstr_open{ popen_lid = Location.mkloc m _loc_m; popen_override = o; popen_loc = _loc;
                  popen_attributes = attach_attrib _loc a})
  | include_kw me:module_expr a:post_item_attributes ->
      Str.include_ ~loc:_loc ({pincl_mod = me; pincl_loc = _loc; pincl_attributes = attach_attrib _loc a })
  | ctd:classtype_definition ->
      Str.class_type ~loc:_loc ctd
  | cds:class_definition ->
      Str.class_ ~loc:_loc cds
  | attr:floating_attribute ->
      Str.attribute ~loc:_loc attr
  | ext:floating_extension ->
      Str.extension ~loc:_loc ext

  | "$struct:" e:expression - '$' ->
     let open Quote in
     pstr_antiquotation _loc (function
     | Quote_pstr ->
        let e_loc =
          Exp.ident ~loc:_loc (Location.mkloc (Lident "_loc") _loc)
        in
        <:expr<
          let loc = $quote_location_t e_loc _loc _loc$ in
          let attr = $quote_list quote_attribute e_loc _loc []$ in
          let pincl_mod = Earley_helpers.Helper.Mod.structure ~loc $e$ in
          Earley_helpers.Helper.Str.include_ ~loc
            Parsetree.{pincl_loc = loc; pincl_attributes = attr; pincl_mod}
        >>
     | _ -> failwith "Bad antiquotation..." (* FIXME:add location *))

(* FIXME ext_attributes *)
let parser structure_item_aux =
  | _:ext_attributes -> []
  | _:ext_attributes e:expression ->
      attach_str _loc @ [Str.eval ~loc:_loc_e e]
  | s1:structure_item_aux double_semi_col?[()] _:ext_attributes f:{
             | e:(alternatives extra_structure) ->
                 (fun s1 -> List.rev_append e (List.rev_append (attach_str _loc_e) s1))
             | s2:structure_item_base ->
                  (fun s1 -> s2 :: (List.rev_append (attach_str _loc_s2) s1)) } -> f s1
  | s1:structure_item_aux double_semi_col _:ext_attributes e:expression
      -> Str.eval ~loc:_loc_e e :: (List.rev_append (attach_str _loc_e) s1)

let _ = set_grammar structure_item
  (parser l:structure_item_aux double_semi_col?[()] -> List.rev l)
let _ = set_grammar structure_item_simple
  (parser ls:{l:structure_item_base -> l}* -> ls)

let parser signature_item_base =
  | val_kw n:value_name ':' ty:typexpr a:post_item_attributes ->
      Sig.value ~loc:_loc (Val.mk ~loc:_loc ~attrs:(attach_attrib _loc a)
        ~prim:[] (Location.mkloc n _loc_n) ty)
  | external_kw n:value_name STR":" ty:typexpr STR"=" ls:string_litteral* a:post_item_attributes ->
      let ls = List.map fst ls in
      let l = List.length ls in
      if l < 1 || l > 3 then give_up ();
      Sig.value ~loc:_loc (Val.mk ~loc:_loc ~attrs:(attach_attrib _loc a)
        ~prim:ls (Location.mkloc n _loc_n) ty)
  | td:type_definition -> Sig.type_ ~loc:_loc Recursive td (* FIXME non rec *)
  | te:type_extension  -> Sig.type_extension ~loc:_loc te
(* FIXME
  | exception_kw (name,args,res,a):(constr_decl false) ->
      let cd = Te.decl ~attrs:(attach_attrib _loc a) ~loc:_loc ~args ?res name in
      Sig.exception_ ~loc:_loc cd
*)
  | module_kw rec_kw mn:module_name ':' mt:module_type a:post_item_attributes
    ms:{and_kw mn:module_name ':' mt:module_type a:post_item_attributes ->
    Md.mk ~loc:_loc ~attrs:(attach_attrib _loc a) mn mt}* ->
      let loc_first = merge2 _loc_mn _loc_a in
      let m = Md.mk ~loc:loc_first ~attrs:(attach_attrib loc_first a) mn mt in
      Sig.rec_module ~loc:_loc (m::ms)
  | module_kw mn:module_name
    l:{'(' mn:module_name mt:{':' mt:module_type}? ')' -> (mn, mt, _loc)}*
    ':' mt:module_type a:post_item_attributes ->
      let mt =
        let fn acc (mn,mt,_l) =
          Mty.functor_ ~loc:(merge2 _l _loc_mt) mn mt acc
        in
        List.fold_left fn mt (List.rev l)
      in
      Sig.module_ ~loc:_loc (Md.mk ~loc:_loc ~attrs:(attach_attrib _loc a) mn mt)

  | module_kw type_kw mn:modtype_name typ:{'=' module_type}? a:post_item_attributes ->
      Sig.modtype ~loc:_loc (Mtd.mk ~loc:_loc ~attrs:(attach_attrib _loc a)
        ?typ (Location.mkloc mn _loc_mn))
  | open_kw o:override_flag m:module_path a:post_item_attributes ->
      Sig.mk ~loc:_loc (Psig_open{ popen_lid = Location.mkloc m _loc_m; popen_override = o; popen_loc = _loc;
                   popen_attributes = attach_attrib _loc a})
      (* FIXME *)
  | include_kw me:module_type a:post_item_attributes ->
      Sig.include_ ~loc:_loc {pincl_mod = me; pincl_loc = _loc; pincl_attributes = attach_attrib _loc a}
  | ctd:classtype_definition ->
      Sig.class_type ~loc:_loc ctd
  | cs:class_specification ->
      Sig.class_ ~loc:_loc cs
  | attr:floating_attribute ->
      Sig.attribute ~loc:_loc attr
  | ext:floating_extension ->
      Sig.extension ~loc:_loc ext
  | dol:'$' - e:expression - '$' ->
     let open Quote in
     psig_antiquotation _loc (function
     | Quote_psig -> e
     | _ -> failwith "Bad antiquotation..." (* FIXME:add location *))

let _ = set_grammar signature_item (
  parser
  | e:(alternatives extra_signature)         -> attach_sig _loc @ e
  | s:signature_item_base _:double_semi_col? -> attach_sig _loc @ [s]
)

end
