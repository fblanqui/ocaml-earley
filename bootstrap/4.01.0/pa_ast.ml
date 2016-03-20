open Asttypes
open Parsetree
open Longident
let loc_str _loc desc = { pstr_desc = desc; pstr_loc = _loc }
let loc_sig _loc desc = { psig_desc = desc; psig_loc = _loc }
let const_string s = Const_string s
let loc_expr ?(attributes= [])  _loc e = { pexp_desc = e; pexp_loc = _loc }
let loc_pat ?(attributes= [])  _loc pat =
  { ppat_desc = pat; ppat_loc = _loc }
let loc_pcl ?(attributes= [])  _loc desc =
  { pcl_desc = desc; pcl_loc = _loc }
let loc_typ ?(attributes= [])  _loc typ =
  { ptyp_desc = typ; ptyp_loc = _loc }
let loc_pfield ?(attributes= [])  _loc field =
  { pfield_desc = field; pfield_loc = _loc }
let pctf_loc ?(attributes= [])  _loc desc =
  { pctf_desc = desc; pctf_loc = _loc }
let loc_pcf ?(attributes= [])  _loc desc =
  { pcf_desc = desc; pcf_loc = _loc }
let id_loc txt loc = { txt; loc }
let pcty_loc ?(attributes= [])  _loc desc =
  { pcty_desc = desc; pcty_loc = _loc }
let mexpr_loc ?(attributes= [])  _loc desc =
  { pmod_desc = desc; pmod_loc = _loc }
let mtyp_loc ?(attributes= [])  _loc desc =
  { pmty_desc = desc; pmty_loc = _loc }
let pexp_construct (a,b) = Pexp_construct (a, b, false)
let pexp_fun (label,opt,pat,expr) = Pexp_function (label, opt, [(pat, expr)])
let exp_string _loc s = loc_expr _loc (Pexp_constant (const_string s))
let const_float s = Const_float s
let const_char s = Const_char s
let const_int s = Const_int s
let const_int32 s = Const_int32 s
let const_int64 s = Const_int64 s
let const_nativeint s = Const_nativeint s
let exp_int _loc i = loc_expr _loc (Pexp_constant (Const_int i))
let exp_char _loc c = loc_expr _loc (Pexp_constant (Const_char c))
let exp_float _loc f = loc_expr _loc (Pexp_constant (Const_float f))
let exp_int32 _loc i = loc_expr _loc (Pexp_constant (Const_int32 i))
let exp_int64 _loc i = loc_expr _loc (Pexp_constant (Const_int64 i))
let exp_nativeint _loc i = loc_expr _loc (Pexp_constant (Const_nativeint i))
let exp_const _loc c es =
  let c = id_loc c _loc in loc_expr _loc (pexp_construct (c, es))
let exp_record _loc fs =
  let f (l,e) = ((id_loc l _loc), e) in
  let fs = List.map f fs in loc_expr _loc (Pexp_record (fs, None))
let exp_None _loc =
  let cnone = id_loc (Lident "None") _loc in
  loc_expr _loc (pexp_construct (cnone, None))
let exp_Some _loc a =
  let csome = id_loc (Lident "Some") _loc in
  loc_expr _loc (pexp_construct (csome, (Some a)))
let exp_option _loc =
  function | None  -> exp_None _loc | Some e -> exp_Some _loc e
let exp_unit _loc =
  let cunit = id_loc (Lident "()") _loc in
  loc_expr _loc (pexp_construct (cunit, None))
let exp_tuple _loc l = loc_expr _loc (Pexp_tuple l)
let exp_Nil _loc =
  let cnil = id_loc (Lident "[]") _loc in
  loc_expr _loc (pexp_construct (cnil, None))
let exp_true _loc =
  let ctrue = id_loc (Lident "true") _loc in
  loc_expr _loc (pexp_construct (ctrue, None))
let exp_false _loc =
  let cfalse = id_loc (Lident "false") _loc in
  loc_expr _loc (pexp_construct (cfalse, None))
let exp_bool _loc b = if b then exp_true _loc else exp_false _loc
let exp_Cons _loc a l =
  loc_expr _loc
    (pexp_construct
       ((id_loc (Lident "::") _loc), (Some (exp_tuple _loc [a; l]))))
let exp_list _loc l = List.fold_right (exp_Cons _loc) l (exp_Nil _loc)
let exp_ident _loc id = loc_expr _loc (Pexp_ident (id_loc (Lident id) _loc))
let exp_lident _loc id = loc_expr _loc (Pexp_ident (id_loc id _loc))
let pat_ident _loc id = loc_pat _loc (Ppat_var (id_loc id _loc))
let nolabel = ""
let labelled s = s
let optional s = "?" ^ s
let exp_apply _loc f l =
  loc_expr _loc (Pexp_apply (f, (List.map (fun x  -> (nolabel, x)) l)))
let exp_apply1 _loc f x = loc_expr _loc (Pexp_apply (f, [(nolabel, x)]))
let exp_apply2 _loc f x y =
  loc_expr _loc (Pexp_apply (f, [(nolabel, x); (nolabel, y)]))
let exp_Some_fun _loc =
  loc_expr _loc
    (pexp_fun
       (nolabel, None, (pat_ident _loc "x"),
         (exp_Some _loc (exp_ident _loc "x"))))
let exp_fun _loc id e =
  loc_expr _loc (pexp_fun (nolabel, None, (pat_ident _loc id), e))
let exp_lab_apply _loc f l = loc_expr _loc (Pexp_apply (f, l))
let exp_app _loc =
  exp_fun _loc "x"
    (exp_fun _loc "y"
       (exp_apply _loc (exp_ident _loc "y") [exp_ident _loc "x"]))
let exp_glr_fun _loc f =
  loc_expr _loc (Pexp_ident (id_loc (Ldot ((Lident "Decap"), f)) _loc))
let exp_list_fun _loc f =
  loc_expr _loc (Pexp_ident (id_loc (Ldot ((Lident "List"), f)) _loc))
let exp_str_fun _loc f =
  loc_expr _loc (Pexp_ident (id_loc (Ldot ((Lident "Str"), f)) _loc))
let exp_prelude_fun _loc f =
  loc_expr _loc
    (Pexp_ident (id_loc (Ldot ((Lident "Pa_ocaml_prelude"), f)) _loc))
let exp_location_fun _loc f =
  loc_expr _loc (Pexp_ident (id_loc (Ldot ((Lident "Location"), f)) _loc))
let exp_Cons_fun _loc =
  exp_fun _loc "x"
    (exp_fun _loc "l"
       (exp_Cons _loc (exp_ident _loc "x") (exp_ident _loc "l")))
let exp_Cons_rev_fun _loc =
  exp_fun _loc "x"
    (exp_fun _loc "l"
       (exp_Cons _loc (exp_ident _loc "x")
          (exp_apply _loc (exp_list_fun _loc "rev") [exp_ident _loc "l"])))
let exp_apply_fun _loc =
  exp_fun _loc "a"
    (exp_fun _loc "f"
       (exp_apply _loc (exp_ident _loc "f") [exp_ident _loc "a"]))
let ppat_alias _loc p id =
  if id = "_" then p else loc_pat _loc (Ppat_alias (p, (id_loc id _loc)))
let rec expression_to_pattern p =
  let fn arg =
    match arg with | None  -> None | Some e -> Some (expression_to_pattern e) in
  let p' =
    match p.pexp_desc with
    | Pexp_ident { txt = Lident id; loc = l } ->
        Ppat_var { txt = id; loc = l }
    | Pexp_constant c -> Ppat_constant c
    | Pexp_tuple l -> Ppat_tuple (List.map expression_to_pattern l)
    | Pexp_array l -> Ppat_array (List.map expression_to_pattern l)
    | Pexp_construct (id,arg,b) -> Ppat_construct (id, (fn arg), b)
    | Pexp_variant (id,arg) -> Ppat_variant (id, (fn arg))
    | Pexp_record (l,None ) ->
        Ppat_record
          ((List.map (fun (id,e)  -> (id, (expression_to_pattern e))) l),
            Open)
    | Pexp_lazy e -> Ppat_lazy (expression_to_pattern e)
    | Pexp_poly (e,Some ty) ->
        Ppat_constraint ((expression_to_pattern e), ty)
    | _ ->
        (Pprintast.expression Format.std_formatter p;
         failwith "Illegal quotation pattern") in
  { ppat_desc = p'; ppat_loc = (p.pexp_loc) }
