(* empty cases list *)
let f3 x = match x with

(* no parenthèses after of *)
type (-'a,+'b) blip = Blip of 'a -> 'b

type x = A of int list

#ifdef TOTO
let toto = true
#else
let toto = false
#endif

#ifversion >= 4.01
let at_least_4_01 = true
#else
let at_least_4_01 = false
#endif

#ifversion >= 4.02
let at_least_4_02 = true
#else
let at_least_4_02 = false
#endif
