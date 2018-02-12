#!/bin/bash

export MAKE="make"

set -v

SAVE=`opam config var switch`
GOOD=""
VERSIONS="4.07.0+trunk 4.06.0 4.05.0 4.04.2 4.04.1 4.04.0 4.03.0"

function build {
    opam switch $1
    eval `opam config env`
    opam install -y ocamlbuild ocamlfind
    $MAKE distclean && $MAKE && $MAKE install
    GOOD="$1 , $GOOD"
}

for v in $VERSIONS; do
    build $v
done

$MAKE distclean

opam switch $SAVE
eval `opam config env`
