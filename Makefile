# Sources in dependency order; also the input to the self-check.
TEXT_HOST = src/subset_text_host.sml

CUSTOM_BASIS = src/subset_option_value.sml src/subset_bool.sml src/subset_result.sml src/subset_host.sml src/subset_option.sml src/subset_list.sml src/subset_list_pair.sml src/subset_order.sml src/subset_char.sml src/subset_bytes.sml src/subset_unicode.sml src/subset_utf8.sml src/subset_utf16.sml src/subset_string.sml src/subset_text.sml src/subset_int32.sml src/subset_string_cvt.sml src/subset_path.sml src/subset_natural.sml src/subset_source.sml src/subset_utf16_source.sml src/subset_sml_escape.sml src/subset_io.sml src/subset_process.sml

SRCS = $(TEXT_HOST) $(CUSTOM_BASIS) src/sml_list.sml src/sml_list_pair.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/lexer.sml src/parser.sml src/print.sml src/int_map.sml src/types.sml \
       src/unify.sml src/env.sml src/elab.sml src/basis.sml src/doc.sml \
       src/sml_print.sml src/wm_print.sml src/wm_lexer.sml \
       src/backend_names.sml src/wm_parse.sml src/normalize.sml src/translate.sml src/module_imports.sml src/module_project.sml src/wm_project.sml src/native_int.sml src/sml_target.sml src/main.sml

bin/subsetml: $(SRCS) src/subsetml.mlb lib/subset_text_host.sml lib/subset_host.sml
	mkdir -p bin
	mlton -output $@ src/subsetml.mlb

# The implementation must itself be SubsetML.
selfcheck: bin/subsetml
	bin/subsetml check-portable $$(python3 scripts/basis-sources.py)
	python3 tests/basis/dependencies.py
	python3 tests/portable_profile.py
	bin/subsetml check-portable $(SRCS)
	bin/subsetml check-portable src/main.sml

# Run the generated compiler through its explicit entry-file import graph.
wm-selfcheck: wm
	wm run src/main.wm -- check-portable src/main.sml

# Every suite script, in its historical order. `make test` runs them in parallel, each with its
# own temp directory and log; `make test JOBS=1` runs them one at a time.
TEST_SCRIPTS = run integer roundtrip translation pipes wm-modules \
  wm-entry native-adapters mlworks-host sml-targets sml-compiler backend-names \
  no-sml-declarations pattern-lowering selector-scope record-updates record-constructors carrier-lowering \
  basis char-basis custom-basis text-basis won-basis utf16-source \
  lexer-bytes doc-portable sml-printer wm-printer kernel-portable io-portable \
  process-panic process-os panic-lowering cli-portable module-loading alias-module
JOBS ?= $(shell nproc 2>/dev/null || echo 4)

test: bin/subsetml selfcheck
	$(MAKE) wm
	@rm -rf build/test-logs && mkdir -p build/test-logs
	@$(MAKE) --no-print-directory -k -j$(JOBS) $(TEST_SCRIPTS:%=test-%)
	@echo "all $(words $(TEST_SCRIPTS)) suite scripts passed"

# One suite script. `make wm` already ran, so scripts that refresh the generated WM skip it.
test-%:
	@mkdir -p build/test-logs
	@start=$$(date +%s); \
	if SUBSETML_WM_FRESH=1 sh tests/$*.sh > build/test-logs/$*.log 2>&1; then echo "ok $* ($$(($$(date +%s) - start)) s)"; \
	else echo "FAILED $* (build/test-logs/$*.log):"; tail -40 build/test-logs/$*.log; exit 1; fi

clean:
	rm -rf bin build

# Translates the implementation to Workman, writing each foo.wm next to src/foo.sml for
# side-by-side reading. Edit .sml sources; text and file/process kernel adapters are staged from lib/.
wm: bin/subsetml lib/subset_text_host.wm lib/subset_host.wm lib/subset_host.js
	bin/subsetml wm src $(SRCS)
	sh scripts/stage-text-host.sh src

# The strongest round trip: translate the implementation to Workman and back, then build and
# use the regenerated compiler.
bootstrap-check: bin/subsetml
	rm -rf build/bootstrap && mkdir -p build/bootstrap/wm build/bootstrap/sml build/bootstrap/lib
	bin/subsetml wm build/bootstrap/wm $(SRCS)
	bin/subsetml sml build/bootstrap/sml build/bootstrap/wm/*.wm
	cp src/subsetml.mlb build/bootstrap/sml/
	cp lib/subset_text_host.sml lib/subset_host.sml build/bootstrap/lib/
	mlton -output build/bootstrap/subsetml build/bootstrap/sml/subsetml.mlb
	build/bootstrap/subsetml roundtrip $(SRCS)
	build/bootstrap/subsetml check-portable src/main.sml

integer-check: bin/subsetml
	sh tests/integer.sh

native-check: bin/subsetml selfcheck
	sh tests/run.sh
	sh tests/integer.sh
	sh tests/roundtrip.sh
	sh tests/sml-targets.sh
	sh tests/sml-compiler.sh
	sh tests/index-integers.sh
	sh tests/mlworks-host.sh
	sh tests/mlworks-batch-stage.sh

mlworks-host-check: bin/subsetml
	sh tests/mlworks-host.sh

sml-target-check: bin/subsetml
	sh tests/sml-targets.sh
	sh tests/sml-compiler.sh
	sh tests/index-integers.sh
	sh tests/mlworks-batch-stage.sh

# Validates the initial custom Basis independently of compiler host compatibility APIs.
custom-basis-check: bin/subsetml
	sh tests/custom-basis.sh

text-basis-check: bin/subsetml
	sh tests/text-basis.sh
	sh tests/utf16-source.sh

# Regenerates src/*.wm whenever a source file changes.
watch:
	sh scripts/watch.sh

.PHONY: native-check sml-target-check mlworks-host-check integer-check selfcheck wm-selfcheck test clean wm watch bootstrap-check text-basis-check custom-basis-check
