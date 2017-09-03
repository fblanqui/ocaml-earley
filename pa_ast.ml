(*
  ======================================================================
  Copyright Christophe Raffalli & Rodolphe Lepigre
  LAMA, UMR 5127 - Université Savoie Mont Blanc

  christophe.raffalli@univ-savoie.fr
  rodolphe.lepigre@univ-savoie.fr

  This software contains implements a parser combinator library together
  with a syntax extension mechanism for the OCaml language.  It  can  be
  used to write parsers using a BNF-like format through a syntax extens-
  ion called pa_parser.

  This software is governed by the CeCILL-B license under French law and
  abiding by the rules of distribution of free software.  You  can  use,
  modify and/or redistribute it under the terms of the CeCILL-B  license
  as circulated by CEA, CNRS and INRIA at the following URL:

            http://www.cecill.info

  The exercising of this freedom is conditional upon a strong obligation
  of giving credits for everybody that distributes a software incorpora-
  ting a software ruled by the current license so as  all  contributions
  to be properly identified and acknowledged.

  As a counterpart to the access to the source code and rights to  copy,
  modify and redistribute granted by the  license,  users  are  provided
  only with a limited warranty and the software's author, the holder  of
  the economic rights, and the successive licensors  have  only  limited
  liability.

  In this respect, the user's attention is drawn to the risks associated
  with loading, using, modifying and/or developing  or  reproducing  the
  software by the user in light of its specific status of free software,
  that may mean that it is complicated  to  manipulate,  and  that  also
  therefore means that it is reserved  for  developers  and  experienced
  professionals having in-depth computer knowledge. Users are  therefore
  encouraged to load and test  the  software's  suitability  as  regards
  their requirements in conditions enabling the security of  their  sys-
  tems and/or data to be ensured and, more generally, to use and operate
  it in the same conditions as regards security.

  The fact that you are presently reading this means that you  have  had
  knowledge of the CeCILL-B license and that you accept its terms.
  ======================================================================
*)

open Asttypes
open Parsetree
open Longident

let print_location ch {Location.loc_start = s ; Location.loc_end = e} =
  let open Lexing in
  Printf.fprintf ch "Position %d:%d to %d:%d%!"
    s.pos_lnum (s.pos_cnum - s.pos_bol)
    e.pos_lnum (e.pos_cnum - e.pos_bol)

let loc_str _loc desc = { pstr_desc = desc; pstr_loc = _loc; }
let loc_sig _loc desc = { psig_desc = desc; psig_loc = _loc; }

#ifversion >= 4.02
#ifversion >= 4.03
let const_string s = Pconst_string(s, None)
#else
let const_string s = Const_string(s, None)
#endif
let loc_expr ?(attributes=[]) _loc e = { pexp_desc = e; pexp_loc = _loc; pexp_attributes = attributes; }
let loc_pat ?(attributes=[]) _loc pat = { ppat_desc = pat; ppat_loc = _loc; ppat_attributes = attributes; }
let loc_pcl ?(attributes=[]) _loc desc = { pcl_desc = desc; pcl_loc = _loc; pcl_attributes = attributes; }
let loc_typ ?(attributes=[]) _loc typ = { ptyp_desc = typ; ptyp_loc = _loc; ptyp_attributes = attributes; }
let pctf_loc ?(attributes=[]) _loc desc = { pctf_desc = desc; pctf_loc = _loc; pctf_attributes = attributes }
let pcty_loc ?(attributes=[]) _loc desc = { pcty_desc = desc; pcty_loc = _loc; pcty_attributes = attributes }
let loc_pcf ?(attributes=[]) _loc desc = { pcf_desc = desc; pcf_loc = _loc; pcf_attributes = attributes }
let mexpr_loc ?(attributes=[]) _loc desc = { pmod_desc = desc; pmod_loc = _loc; pmod_attributes = attributes }
let mtyp_loc ?(attributes=[]) _loc desc = { pmty_desc = desc; pmty_loc = _loc; pmty_attributes = attributes }
let pexp_construct(a,b) = Pexp_construct(a,b)
let pexp_fun(label, opt, pat, expr) =
  Pexp_fun(label,opt,pat,expr)
#else
let const_string s = Const_string(s)
let loc_expr ?(attributes=[]) _loc e = { pexp_desc = e; pexp_loc = _loc; }
let loc_pat ?(attributes=[]) _loc pat = { ppat_desc = pat; ppat_loc = _loc; }
let loc_pcl ?(attributes=[]) _loc desc = { pcl_desc = desc; pcl_loc = _loc }
let loc_typ ?(attributes=[]) _loc typ = { ptyp_desc = typ; ptyp_loc = _loc; }
let loc_pfield ?(attributes=[]) _loc field = { pfield_desc = field; pfield_loc = _loc; }
let pctf_loc ?(attributes=[]) _loc desc = { pctf_desc = desc; pctf_loc = _loc; }
let loc_pcf ?(attributes=[]) _loc desc = { pcf_desc = desc; pcf_loc = _loc; }
let pcty_loc ?(attributes=[]) _loc desc = { pcty_desc = desc; pcty_loc = _loc; }
let mexpr_loc ?(attributes=[]) _loc desc = { pmod_desc = desc; pmod_loc = _loc }
let mtyp_loc ?(attributes=[]) _loc desc = { pmty_desc = desc; pmty_loc = _loc }
let pexp_construct(a,b) = Pexp_construct(a,b,false)
let pexp_fun(label, opt, pat, expr) =
  Pexp_function(label,opt,[pat,expr])
#endif

let ghost loc =
  Location.({loc with loc_ghost = true})

let no_ghost loc =
  Location.({loc with loc_ghost = false})

let de_ghost e =
  loc_expr (no_ghost e.pexp_loc) e.pexp_desc

let id_loc txt loc = { txt; loc }
let loc_id loc txt = { txt; loc }

let rec merge = function
  | [] -> assert false
  | [loc] -> loc
  | l1::_ as ls ->
     let ls = List.rev ls in
     let rec fn = function
       | [] -> assert false
       | [loc] -> loc
       | l2::ls when Location.(l2.loc_start = l2.loc_end) -> fn ls
       | l2::ls ->
	  Location.(
	   {loc_start = l1.loc_start; loc_end = l2.loc_end; loc_ghost = l1.loc_ghost && l2.loc_ghost})
     in fn ls

let merge2 l1 l2 =
  Location.(
    {loc_start = l1.loc_start; loc_end = l2.loc_end; loc_ghost = l1.loc_ghost && l2.loc_ghost})

let exp_string _loc s = loc_expr _loc (Pexp_constant (const_string s))

#ifversion >= 4.03
let const_float s = Pconst_float(s,None)
let const_char s = Pconst_char(s)
let const_int s = Pconst_integer(string_of_int s,None)
let const_int32 s = Pconst_integer(Int32.to_string s, Some 'l')
let const_int64 s = Pconst_integer(Int64.to_string s, Some 'L')
let const_nativeint s = Pconst_integer(Nativeint.to_string s, Some 'n')
let exp_int _loc i = loc_expr _loc (Pexp_constant (Pconst_integer (string_of_int i,None)))
let exp_char _loc c = loc_expr _loc (Pexp_constant (Pconst_char c))
let exp_float _loc f = loc_expr _loc (Pexp_constant (Pconst_float (f,None)))
let exp_int32 _loc i = loc_expr _loc (Pexp_constant (Pconst_integer (Int32.to_string i,Some 'l')))
let exp_int64 _loc i = loc_expr _loc (Pexp_constant (Pconst_integer (Int64.to_string i,Some 'L')))
let exp_nativeint _loc i = loc_expr _loc (Pexp_constant (Pconst_integer(Nativeint.to_string i,Some 'n')))
#else
let const_float s = Const_float(s)
let const_char s = Const_char(s)
let const_int s = Const_int(s)
let const_int32 s = Const_int32(s)
let const_int64 s = Const_int64(s)
let const_nativeint s = Const_nativeint(s)
let exp_int _loc i = loc_expr _loc (Pexp_constant (Const_int i))
let exp_char _loc c = loc_expr _loc (Pexp_constant (Const_char c))
let exp_float _loc f = loc_expr _loc (Pexp_constant (Const_float f))
let exp_int32 _loc i = loc_expr _loc (Pexp_constant (Const_int32 i))
let exp_int64 _loc i = loc_expr _loc (Pexp_constant (Const_int64 i))
let exp_nativeint _loc i = loc_expr _loc (Pexp_constant (Const_nativeint i))
#endif

let exp_const _loc c es =
  let c = id_loc c _loc in
  loc_expr _loc (pexp_construct(c, es))

let exp_record _loc fs =
  let f (l, e) = (id_loc l _loc, e) in
  let fs = List.map f fs in
  loc_expr _loc (Pexp_record (fs, None))

let exp_None _loc =
  let cnone = id_loc (Lident "None") _loc in
  loc_expr _loc (pexp_construct(cnone, None))

let exp_Some _loc a =
  let csome = id_loc (Lident "Some") _loc in
  loc_expr _loc (pexp_construct(csome, Some a))

let exp_option _loc = function
  | None   -> exp_None _loc
  | Some e -> exp_Some _loc e

let exp_unit _loc =
  let cunit = id_loc (Lident "()") _loc in
  loc_expr _loc (pexp_construct(cunit, None))

let exp_tuple _loc l =
  loc_expr _loc (Pexp_tuple l)

let exp_array _loc l =
  loc_expr _loc (Pexp_array l)

let exp_Nil _loc =
  let cnil = id_loc (Lident "[]") _loc in
  loc_expr _loc (pexp_construct(cnil, None))

let exp_true _loc =
  let ctrue = id_loc (Lident "true") _loc in
  loc_expr _loc (pexp_construct(ctrue, None))

let exp_false _loc =
  let cfalse = id_loc (Lident "false") _loc in
  loc_expr _loc (pexp_construct(cfalse, None))

let exp_bool _loc b =
  if b then exp_true _loc else exp_false _loc

let exp_Cons _loc a l =
  loc_expr _loc (pexp_construct(id_loc (Lident "::") _loc, Some (exp_tuple _loc [a;l])))

let exp_list _loc l =
  List.fold_right (exp_Cons _loc) l (exp_Nil _loc)

let exp_ident _loc id =
  loc_expr _loc (Pexp_ident (id_loc (Lident id) _loc ))

let exp_lident _loc id =
  loc_expr _loc (Pexp_ident (id_loc id _loc ))

let pat_ident _loc id =
  loc_pat _loc (Ppat_var (id_loc id _loc))

let pat_tuple _loc l =
  loc_pat _loc (Ppat_tuple l)

let pat_array _loc l =
  loc_pat _loc (Ppat_array l)

let typ_tuple _loc l =
  loc_typ _loc (Ptyp_tuple l)

#ifversion >= 4.03
let nolabel = Nolabel
let labelled s = Labelled s
let optional s = Optional s
#else
let nolabel = ""
let labelled s = s
let optional s = "?"^s
#endif

let exp_apply _loc f l =
  loc_expr _loc (Pexp_apply(f, List.map (fun x -> nolabel, x) l))

let exp_apply1 _loc f x =
  loc_expr _loc (Pexp_apply(f, [nolabel, x]))

let exp_apply2 _loc f x y =
  loc_expr _loc (Pexp_apply(f, [nolabel, x; nolabel, y]))

let exp_Some_fun _loc =
  loc_expr _loc (pexp_fun(nolabel, None, pat_ident _loc "x", (exp_Some _loc (exp_ident _loc "x"))))

let exp_fun _loc id e =
  loc_expr _loc (pexp_fun(nolabel, None, pat_ident _loc id, e))

let exp_lab_apply _loc f l =
  loc_expr _loc (Pexp_apply(f, l))

let exp_app _loc =
  exp_fun _loc "x" (exp_fun _loc "y" (exp_apply _loc (exp_ident _loc "y") [exp_ident _loc "x"]))

let exp_glr_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "Earley",f)) _loc) ))

let exp_glrstr_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "EarleyStr",f)) _loc) ))

let exp_list_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "List",f)) _loc) ))

let exp_str_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "Str",f)) _loc) ))

let exp_prelude_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "Pa_ocaml_prelude",f)) _loc) ))

let exp_location_fun _loc f =
  loc_expr _loc (Pexp_ident((id_loc (Ldot(Lident "Location",f)) _loc) ))

let exp_Cons_fun _loc =
  exp_fun _loc "x" (exp_fun _loc "l" (exp_Cons _loc (exp_ident _loc "x") (exp_ident _loc "l")))

let exp_Cons_rev_fun _loc =
  exp_fun _loc "x" (exp_fun _loc "l" (exp_Cons _loc (exp_ident _loc "x") (exp_apply _loc (exp_list_fun _loc "rev") [exp_ident _loc "l"])))

let exp_apply_fun _loc =
  exp_fun _loc "a" (exp_fun _loc "f" (exp_apply _loc (exp_ident _loc "f") [exp_ident _loc "a"]))

let ppat_alias _loc p id =
  if id = "_" then p else
    loc_pat _loc (Ppat_alias (p, (id_loc (id) _loc)))

#ifversion >= 4.02
  let constructor_declaration ?(attributes=[]) _loc name args res =
    { pcd_name = name; pcd_args = args; pcd_res = res; pcd_attributes = attributes; pcd_loc = _loc }
  let label_declaration _loc name mut ty =
    { pld_name = name; pld_mutable = mut; pld_type = ty; pld_attributes = []; pld_loc = _loc }
  let params_map _loc params =
    let fn (name, var) =
      match name with
	None -> (loc_typ _loc Ptyp_any, var)
      | Some name -> (loc_typ name.loc (Ptyp_var name.txt), var)
    in
    List.map fn params
  let type_declaration ?(attributes=[]) _loc name params cstrs kind priv manifest =
    let params = params_map _loc params in
    {
     ptype_name = name;
     ptype_params = params;
     ptype_cstrs = cstrs;
     ptype_kind = kind;
     ptype_private = priv;
     ptype_manifest = manifest;
     ptype_attributes = attributes;
     ptype_loc = _loc;
    }
  let class_type_declaration ?(attributes=[]) _loc' _loc name params virt expr =
    let params = params_map _loc' params in
      { pci_params = params
      ; pci_virt = virt
      ; pci_name = name
      ; pci_expr = expr
      ; pci_attributes = attributes
      ; pci_loc = _loc }
  let pstr_eval e = Pstr_eval(e, [])
  let psig_value ?(attributes=[]) _loc name ty prim =
    Psig_value { pval_name = name; pval_type = ty ; pval_prim = prim ; pval_attributes = attributes; pval_loc = _loc }
  let value_binding ?(attributes=[]) _loc pat expr =
    { pvb_pat = pat; pvb_expr = expr; pvb_attributes = attributes; pvb_loc = _loc }
  let module_binding _loc name mt me =
    let me = match mt with None -> me | Some mt -> mexpr_loc _loc (Pmod_constraint(me,mt)) in
    { pmb_name = name; pmb_expr = me; pmb_attributes = []; pmb_loc = _loc }
  let module_declaration ?(attributes=[]) _loc name mt =
    { pmd_name = name; pmd_type = mt; pmd_attributes = attributes; pmd_loc = _loc }
  let ppat_construct(a,b) = Ppat_construct(a,b)
  let pexp_constraint(a,b) = Pexp_constraint(a,b)
  let pexp_coerce(a,b,c) = Pexp_coerce(a,b,c)
  let pexp_assertfalse _loc = Pexp_assert(loc_expr _loc (pexp_construct({ txt = Lident "false"; loc = _loc}, None)))
  let make_case = fun pat expr guard -> { pc_lhs = pat; pc_rhs = expr; pc_guard = guard }
  let pexp_function cases =
    Pexp_function (cases)
#else
  let value_binding ?(attributes=[]) _loc pat expr = (pat, expr)
  type constructor_declaration = string Asttypes.loc * Parsetree.core_type list * Parsetree.core_type option * Location.t
  let constructor_declaration ?(attributes=[]) _loc name args res = (name, args, res, _loc)
  type label_declaration = string Asttypes.loc * Asttypes.mutable_flag * Parsetree.core_type * Location.t
  type case = pattern * expression
  let label_declaration _loc name mut ty =
    (name, mut, ty, _loc)
  let type_declaration ?(attributes=[]) _loc name params cstrs kind priv manifest =
    let params, variance = List.split params in
    {
     ptype_params = params;
     ptype_cstrs = cstrs;
     ptype_kind = kind;
     ptype_private = priv;
     ptype_variance = variance;
     ptype_manifest = manifest;
     ptype_loc = _loc;
    }
  let class_type_declaration ?(attributes=[]) _loc' _loc name params virt expr =
    let params, variance = List.split params in
    let params = List.map (function None   -> id_loc "" _loc'
                                  | Some x -> x) params
    in
      { pci_params = params, _loc'
      ; pci_variance = variance
      ; pci_virt = virt
      ; pci_name = name
      ; pci_expr = expr
      ; pci_loc = _loc }
  let pstr_eval e = Pstr_eval(e)
  let psig_value ?(attributes=[]) _loc name ty prim =
    Psig_value( name, { pval_type = ty ; pval_prim = prim ; pval_loc = _loc; } )

  let value_binding  ?(attributes=[]) _loc pat expr =
    ( pat, expr)
  let module_binding _loc name mt me =
    (name, mt, me)
  let module_declaration ?(attributes=[]) _loc name mt =
    (name, mt)
  let ppat_construct(a,b) = Ppat_construct(a,b,false)
  let pexp_constraint(a,b) = Pexp_constraint(a,Some b,None)
  let pexp_coerce(a,b,c) = Pexp_constraint(a,b,Some c)
  let pexp_assertfalse _loc = Pexp_assertfalse
  let make_case = fun pat expr guard ->
    match guard with None -> (pat, expr)
    | Some e -> (pat, loc_expr (merge2 e.pexp_loc expr.pexp_loc) (Pexp_when(e,expr)))

  let map_cases cases = List.map (fun (pat, expr, guard) ->make_case pat expr guard) cases
  let pexp_function(cases) =
    Pexp_function("", None, cases)
  type value_binding = Parsetree.pattern * Parsetree.expression
#endif

let pat_list _loc _loc_c l =
  let nil = id_loc (Lident "[]") (ghost _loc_c) in
  let cons x xs =
    let cloc = ghost (merge2 x.ppat_loc _loc) in
    let c = id_loc (Lident "::") cloc in
    let cons = ppat_construct (c, Some (loc_pat cloc (Ppat_tuple [x;xs]))) in
    loc_pat _loc cons
  in
  List.fold_right cons l (loc_pat (ghost _loc_c) (ppat_construct (nil, None)))

let ppat_list = pat_list
