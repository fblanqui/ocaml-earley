VERSION   = 1.0.0
OCAMLFIND = ocamlfind
OCAMLC    = $(OCAMLFIND) ocamlc -package bytes,earley,earley.str
OCAMLOPT  = $(OCAMLFIND) ocamlopt -package bytes,earley,earley.str -intf-suffix .cmi
BINDIR    = $(dir $(shell which ocamlc))

INSTALLED = pa_ocaml_prelude.cmi pa_ocaml_prelude.cmo pa_ocaml_prelude.cmx \
						pa_ocaml.cmi pa_ocaml.cmo pa_ocaml.cmx \
						pa_parser.cmi pa_parser.cmx pa_parser.cmo \
						pa_main.cmi pa_main.cmx pa_main.cmo \
						earley_ocaml.cmxa earley_ocaml.cma earley_ocaml.a \
						pa_ast.cmx pa_ast.cmo pa_ast.cmi \
						pa_lexing.cmi pa_lexing.cmx pa_lexing.cmo

HAS_PA_OCAML=$(shell if [ -x pa_ocaml ]; then echo 1; else echo 0; fi)
OCAMLVERSION=$(shell ocamlc -version | sed s/+.*//)
BOOTDIR=./bootstrap/$(OCAMLVERSION)
export OCAMLFIND_IGNORE_DUPS_IN = $(BOOTDIR)

ifeq ($(HAS_PA_OCAML),1)
B=.
IB=-I $(B) -I $(BOOTDIR)
PA_OCAML=./pa_ocaml
PP= -pp "$(PA_OCAML) $(ASCII)"
all: pa_ocaml $(B)/earley_ocaml.cmxa $(B)/earley_ocaml.cma
else
B=$(BOOTDIR)
IB=-I $(B)
PP=
all: pa_ocaml $(B)/earley_ocaml.cmxa
endif

ASCII =

COMPILER_INC = -I +compiler-libs
COMPILER_LIBS = ocamlcommon.cma
COMPILER_PARSERS =
COMPILER_TOP = ocamlbytecomp.cma ocamltoplevel.cma
COMPILER_LIBO := $(COMPILER_LIBS:.cma=.cmxa)
COMPILER_LIBO := $(COMPILER_LIBO:.cmo=.cmx)
COMPILER_PARSERO := $(COMPILER_PARSERS:.cma=.cmxa)
COMPILER_PARSERO := $(COMPILER_PARSERO:.cmo=.cmx)

ASTTOOLSI=$(BOOTDIR)/compare.cmi $(BOOTDIR)/iter.cmi $(BOOTDIR)/quote.cmi
ASTTOOLSO=$(ASTTOOLSI:.cmi=.cmo)
ASTTOOLSX=$(ASTTOOLSI:.cmi=.cmx)
ASTTOOLSIO=$(ASTTOOLSI) $(ASTTOOLSO)
ASTTOOLSIX=$(ASTTOOLSI) $(ASTTOOLSX)

%.cmi: %.mli
	$(OCAMLC) $(OCAMLFLAGS) -c $<

%.cmo: %.ml
	$(OCAMLC) $(OCAMLFLAGS) -c $<

%.cmx: %.cmo

%.cmx: %.ml %.cmi
	$(OCAMLOPT) $(OCAMLFLAGS) -c $<

$(B)/earley_ocaml.cma: $(B)/pa_lexing.cmo $(B)/pa_ast.cmo $(ASTTOOLSO) $(B)/pa_ocaml_prelude.cmo $(B)/pa_parser.cmo $(B)/pa_ocaml.cmo $(B)/pa_main.cmo
	$(OCAMLC) $(OCAMLFLAGS) -a -o $@ $^

$(B)/earley_ocaml.cmxa: $(B)/pa_lexing.cmx $(B)/pa_ast.cmx $(ASTTOOLSX) $(B)/pa_ocaml_prelude.cmx $(B)/pa_parser.cmx $(B)/pa_ocaml.cmx $(B)/pa_main.cmx
	$(OCAMLOPT) $(OCAMLFLAGS) -a -o $@ $^

decap_ocaml.a: decap_ocaml.cmxa;

$(BOOTDIR)/compare.cmo $(BOOTDIR)/compare.cmi: $(BOOTDIR)/compare.ml
	$(OCAMLC) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(BOOTDIR)/compare.cmx: $(BOOTDIR)/compare.ml $(BOOTDIR)/compare.cmi
	$(OCAMLOPT) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(BOOTDIR)/iter.cmo $(BOOTDIR)/iter.cmi: $(BOOTDIR)/iter.ml
	$(OCAMLC) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(BOOTDIR)/iter.cmx: $(BOOTDIR)/iter.ml $(BOOTDIR)/iter.cmi
	$(OCAMLOPT) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(BOOTDIR)/quote.cmo $(BOOTDIR)/quote.cmi: $(BOOTDIR)/quote.ml $(B)/pa_ast.cmi
	$(OCAMLC) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(BOOTDIR)/quote.cmx: $(BOOTDIR)/quote.ml $(BOOTDIR)/quote.cmi $(B)/pa_ast.cmx
	$(OCAMLOPT) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_lexing.cmo $(B)/pa_lexing.cmi: $(B)/pa_lexing.ml
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_lexing.cmx: $(B)/pa_lexing.ml $(B)/pa_lexing.cmi
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ocaml_prelude.cmo $(B)/pa_ocaml_prelude.cmi: $(B)/pa_ocaml_prelude.ml $(B)/pa_ast.cmi $(B)/pa_lexing.cmi
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ocaml_prelude.cmx: $(B)/pa_ocaml_prelude.ml $(B)/pa_ocaml_prelude.cmi $(B)/pa_ast.cmx $(B)/pa_lexing.cmx
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ast.cmo $(B)/pa_ast.cmi: $(B)/pa_ast.ml
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ast.cmx: $(B)/pa_ast.ml $(B)/pa_ast.cmi
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_parser.cmo $(B)/pa_parser.cmi: $(B)/pa_parser.ml $(B)/pa_ast.cmo $(B)/pa_ocaml_prelude.cmo $(ASTTOOLSI)
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_parser.cmx: $(B)/pa_parser.ml $(B)/pa_parser.cmi $(B)/pa_ast.cmx $(B)/pa_ocaml_prelude.cmx $(ASTTOOLSIX)
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ocaml.cmo $(B)/pa_ocaml.cmi: $(B)/pa_ocaml.ml $(ASTTOOLSI) $(B)/pa_ocaml_prelude.cmo
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_ocaml.cmx: $(B)/pa_ocaml.ml $(B)/pa_ocaml.cmi $(ASTTOOLSIX) $(B)/pa_ocaml_prelude.cmx
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_main.cmo $(B)/pa_main.cmi: $(B)/pa_main.ml $(B)/pa_ocaml.cmo
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_main.cmx: $(B)/pa_main.ml $(B)/pa_main.cmi $(B)/pa_ocaml.cmx
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_default.cmo $(B)/pa_default.cmi: $(B)/pa_default.ml $(B)/pa_ocaml_prelude.cmo $(B)/pa_parser.cmo $(B)/pa_ocaml.cmo $(B)/pa_main.cmo
	$(OCAMLC) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

$(B)/pa_default.cmx: $(B)/pa_default.ml $(B)/pa_default.cmi $(B)/pa_ocaml_prelude.cmx $(B)/pa_parser.cmx $(B)/pa_ocaml.cmx $(B)/pa_main.cmx
	$(OCAMLOPT) $(PP) $(OCAMLFLAGS) $(COMPILER_INC) -c $(IB) $<

pa_ocaml: $(B)/earley_ocaml.cmxa $(B)/pa_default.cmx
	$(OCAMLOPT) $(OCAMLFLAGS) $(COMPILER_INC) -linkall $(IB) -o $@ unix.cmxa str.cmxa earley.cmxa earleyStr.cmxa $(COMPILER_LIBO) $^

pa_ocaml.byt: $(B)/earley_ocaml.cma $(B)/pa_default.cmo
	$(OCAMLC) $(OCAMLFLAGS) $(COMPILER_INC) -linkall $(IB) -o $@ unix.cma str.cma earley.cma earleyStr.cma$(COMPILER_LIBS) $^

test_parsers: $(B)/earley_ocaml.cmxa test_parsers.ml
	$(OCAMLOPT) $(OCAMLFLAGS) $(COMPILER_INC) -o $@ dynlink.cmxa unix.cmxa str.cmxa earley.cmxa earleyStr.cmxa $(COMPILER_INC) $(COMPILER_LIBO) $(COMPILER_PARSERO) $^

asttools:
	- rm pa_lexing.cm*
	OCAMLVERSION=$(OCAMLVERSION) make ASCII=--ascii pa_lexing.cmx
	make -C ast_tools

#BOOTSTRAP OF ONE VERSION (SEE all_boot.sh AND INSTALL opam FOR MULTIPLE OCAML VERSION
boot: BACKUP:=$(BOOTDIR)/$(shell date +%Y-%m-%d-%H-%M-%S)
boot:
	- if [ ! -d $(BOOTDIR) ] ; then mkdir $(BOOTDIR); fi
	- if [ ! -d $(BACKUP) ] ; then \
	     mkdir $(BACKUP) ; \
	     cp $(BOOTDIR)/*.ml $(BACKUP) ; \
	fi
	export OCAMLVERSION=$(OCAMLVERSION); \
	./pa_ocaml --ascii pa_lexing.ml > $(BOOTDIR)/pa_lexing.ml ;\
	./pa_ocaml --ascii pa_ocaml_prelude.ml > $(BOOTDIR)/pa_ocaml_prelude.ml ;\
	./pa_ocaml --ascii pa_parser.ml > $(BOOTDIR)/pa_parser.ml ;\
	./pa_ocaml --ascii pa_ocaml.ml > $(BOOTDIR)/pa_ocaml.ml ;\
	./pa_ocaml --ascii pa_ast.ml > $(BOOTDIR)/pa_ast.ml ;\
	./pa_ocaml --ascii pa_main.ml > $(BOOTDIR)/pa_main.ml ;\
	./pa_ocaml --ascii pa_default.ml > $(BOOTDIR)/pa_default.ml

install: uninstall $(INSTALLED)
	install -m 755 -d $(BINDIR)
	ocamlfind install earley_ocaml META $(INSTALLED)
	install -m 755 pa_ocaml $(BINDIR)

uninstall:
	ocamlfind remove earley_ocaml
	rm -f $(BINDIR)/pa_ocaml

clean:
	- rm -f *.cm* *.o *.a
	- rm -f bootstrap/*/*.cm* bootstrap/*/*.o bootstrap/*/*.a
	- rm -f tests_pa_ocaml/*.ml*.ocamlc* tests_pa_ocaml/*.ml*.pa_ocaml* \
                tests_pa_ocaml/*.ml*.*diff tests_pa_ocaml/*.cm*
	- rm -f test_parsers ocaml.csv
	$(MAKE) -e -j 1 -C ast_tools clean
	$(MAKE) -e -j 1 -C doc/examples clean
	- cd doc; patoline --clean;

distclean: clean
	- rm -f pa_ocaml pa_ocaml-* pa_ocaml.byt *~ \#*\#
	$(MAKE) -e -j 1 -C ast_tools distclean
	$(MAKE) -e -j 1 -C doc/examples distclean
	- rm doc/doc.pdf

.PHONY: release
release: distclean
	git push origin
	git tag -a ocaml-earley-ocaml_$(VERSION)
	git push origin ocaml-earley-ocaml_$(VERSION)
