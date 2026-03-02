# Minimal pipeline to demo Semgrep -> LLVM IR -> Alive2 -> rewrite

PYTHON ?= python3
RULE_DIR := example/rules
RULE_FILES := $(wildcard $(RULE_DIR)/*.yaml)
BAD_RULE_DIR := example/bad_rules
BAD_RULE_FILES := $(wildcard $(BAD_RULE_DIR)/*.yaml)
BAD_LL_SRC := $(wildcard $(BAD_RULE_DIR)/*.ll)
ALIVE_SAMPLE_DIR := example/alive
BAD_ALIVE_SAMPLE_DIR := example/bad-alive
ALIVE_SAMPLE_FILES := $(wildcard $(ALIVE_SAMPLE_DIR)/*.ll)
BAD_ALIVE_SAMPLE_FILES := $(wildcard $(BAD_ALIVE_SAMPLE_DIR)/*.ll)
CODE_DIR := example/code
BUILD_DIR := build
IR_DIR := $(BUILD_DIR)/ir
BAD_IR_DIR := $(BUILD_DIR)/ir_bad
REPORT_DIR := $(BUILD_DIR)/reports
OUT_DIR := $(BUILD_DIR)/out
IR_FILES := $(patsubst $(RULE_DIR)/%.yaml,$(IR_DIR)/%.ll,$(RULE_FILES))
BAD_IR_FILES := $(patsubst $(BAD_RULE_DIR)/%.yaml,$(BAD_IR_DIR)/%.ll,$(BAD_RULE_FILES)) \
	$(patsubst $(BAD_RULE_DIR)/%.ll,$(BAD_IR_DIR)/%.ll,$(BAD_LL_SRC))
ALIVE2_DIR := deps/alive2
ALIVE2_BUILD := $(ALIVE2_DIR)/build
ALIVE_BIN ?= $(ALIVE2_BUILD)/alive-tv
LLVM_DIR ?= /usr/lib/llvm-20/lib/cmake/llvm
ALIVE2_REF ?= v20.0
ALIVE_FLAGS ?= --smt-to=60000
ALIVE_SAMPLE_LOG := $(BUILD_DIR)/alive-tests.log
BAD_ALIVE_SAMPLE_LOG := $(BUILD_DIR)/bad-alive-tests.log

.PHONY: all semgrep alive apply clean bad-ir bad-alive alive-tests bad-alive-tests

all: setup semgrep ir alive apply

setup: $(BUILD_DIR)/.setup

$(BUILD_DIR)/.setup: requirements.txt | $(BUILD_DIR)
	$(PYTHON) -m pip install -r $<
	touch $@

$(BUILD_DIR):
	mkdir -p $(IR_DIR) $(BAD_IR_DIR) $(REPORT_DIR) $(OUT_DIR)

$(IR_DIR) $(BAD_IR_DIR) $(REPORT_DIR) $(OUT_DIR): | $(BUILD_DIR)
	mkdir -p $@

semgrep: $(BUILD_DIR)
	@semgrep scan --config $(RULE_DIR) --json --quiet --timeout 60 --include '*.c' $(CODE_DIR) > $(REPORT_DIR)/semgrep.json; \
	  rc=$$?; \
	  if [ $$rc -gt 1 ]; then exit $$rc; fi
	@echo "Semgrep findings written to $(REPORT_DIR)/semgrep.json"

ir: $(IR_FILES)
	@echo "IR up to date under $(IR_DIR)"

$(IR_DIR)/%.ll: $(RULE_DIR)/%.yaml semgrep_to_IR.py | $(IR_DIR)
	$(PYTHON) semgrep_to_IR.py $< --out $(IR_DIR)

$(BAD_IR_DIR)/%.ll: $(BAD_RULE_DIR)/%.yaml semgrep_to_IR.py | $(BAD_IR_DIR)
	$(PYTHON) semgrep_to_IR.py $< --out $(BAD_IR_DIR)

$(BAD_IR_DIR)/%.ll: $(BAD_RULE_DIR)/%.ll | $(BAD_IR_DIR)
	cp $< $@

bad-ir: $(BAD_IR_FILES)
	@echo "Bad IR up to date under $(BAD_IR_DIR)"

$(ALIVE2_BUILD)/.built:
	git submodule update --init --recursive $(ALIVE2_DIR)
	@if [ -n "$(ALIVE2_REF)" ]; then git -C $(ALIVE2_DIR) checkout $(ALIVE2_REF); fi
	mkdir -p $(ALIVE2_BUILD)
	cmake -S $(ALIVE2_DIR) -B $(ALIVE2_BUILD) -DCMAKE_BUILD_TYPE=Release -DLLVM_DIR=$(LLVM_DIR)
	cmake --build $(ALIVE2_BUILD) --target alive-tv -- -j$$(nproc)
	touch $@

alive: ir $(ALIVE2_BUILD)/.built
	@if [ -x "$(ALIVE_BIN)" ]; then \
	  for f in $(IR_DIR)/*.ll; do \
	    [ -e $$f ] || continue; \
	    echo "Checking $$f with $(ALIVE_BIN)"; \
	    tmp=$$(mktemp); \
	    $(ALIVE_BIN) $(ALIVE_FLAGS) $$f >$$tmp 2>&1 || true; \
	    if grep -q "Transformation doesn't verify" $$tmp; then \
	      echo "Alive2 reported a failure for $$f"; \
	      cat $$tmp; \
	      rm -f $$tmp; \
	      exit 1; \
	    else \
	      echo "Transformation verified: $$f"; \
	    fi; \
	    rm -f $$tmp; \
	  done; \
	else \
	  echo "Alive2 binary '$(ALIVE_BIN)' not found even after build" && exit 1; \
	fi

apply: semgrep
	rsync -a $(CODE_DIR)/ $(OUT_DIR)/
	@files=$$(find $(OUT_DIR) -type f \( -name '*.c' -o -name '*.cpp' \)); \
	if [ -z "$$files" ]; then echo "No source files under $(OUT_DIR)"; else \
	  semgrep scan --config $(RULE_DIR) --autofix --timeout 60 --no-git-ignore $$files; \
	  rc=$$?; \
	  if [ $$rc -gt 1 ]; then exit $$rc; fi; \
	fi
	@echo "Rewritten sources placed under $(OUT_DIR)" 

clean:
	rm -rf $(BUILD_DIR)

bad-alive: bad-ir $(ALIVE2_BUILD)/.built
	@if [ -x "$(ALIVE_BIN)" ]; then \
	  found=false; \
	  for f in $(BAD_IR_DIR)/*.ll; do \
	    [ -e $$f ] || continue; found=true; \
	    echo "Expecting Alive2 rejection for $$f"; \
	    tmp=$$(mktemp); \
	    $(ALIVE_BIN) $(ALIVE_FLAGS) $$f >$$tmp 2>&1 || true; \
	    if grep -q "Transformation doesn't verify" $$tmp; then \
	      echo "Correctly rejected: $$f"; \
	    else \
	      echo "Unexpected success: $$f"; \
	      cat $$tmp; \
	      rm -f $$tmp; \
	      exit 1; \
	    fi; \
	    rm -f $$tmp; \
	  done; \
	  if [ $$found = false ]; then echo "No bad IR files under $(BAD_IR_DIR)"; fi; \
	else \
	  echo "Alive2 binary '$(ALIVE_BIN)' not found even after build" && exit 1; \
	fi

alive-tests: $(ALIVE2_BUILD)/.built
	@if [ -x "$(ALIVE_BIN)" ]; then \
	  : > $(ALIVE_SAMPLE_LOG); \
	  found=false; \
	  for f in $(ALIVE_SAMPLE_FILES); do \
	    [ -e $$f ] || continue; found=true; \
	    echo "Checking sample $$f" | tee -a $(ALIVE_SAMPLE_LOG); \
	    tmp=$$(mktemp); \
	    $(ALIVE_BIN) $(ALIVE_FLAGS) $$f >$$tmp 2>&1 || true; \
	    if grep -q "Transformation doesn't verify" $$tmp; then \
	      echo "Sample failed: $$f" | tee -a $(ALIVE_SAMPLE_LOG); \
	      cat $$tmp | tee -a $(ALIVE_SAMPLE_LOG); \
	      rm -f $$tmp; \
	      exit 1; \
	    else \
	      echo "Sample verified: $$f" | tee -a $(ALIVE_SAMPLE_LOG); \
	      cat $$tmp >> $(ALIVE_SAMPLE_LOG); \
	    fi; \
	    rm -f $$tmp; \
	  done; \
	  if [ $$found = false ]; then echo "No Alive samples under $(ALIVE_SAMPLE_DIR)" | tee -a $(ALIVE_SAMPLE_LOG); fi; \
	else \
	  echo "Alive2 binary '$(ALIVE_BIN)' not found even after build" && exit 1; \
	fi

bad-alive-tests: $(ALIVE2_BUILD)/.built
	@if [ -x "$(ALIVE_BIN)" ]; then \
	  : > $(BAD_ALIVE_SAMPLE_LOG); \
	  found=false; \
	  for f in $(BAD_ALIVE_SAMPLE_FILES); do \
	    [ -e $$f ] || continue; found=true; \
	    echo "Expecting failure for sample $$f" | tee -a $(BAD_ALIVE_SAMPLE_LOG); \
	    tmp=$$(mktemp); \
	    $(ALIVE_BIN) $(ALIVE_FLAGS) $$f >$$tmp 2>&1 || true; \
	    if grep -q "Transformation doesn't verify" $$tmp; then \
	      echo "Correctly rejected: $$f" | tee -a $(BAD_ALIVE_SAMPLE_LOG); \
	      cat $$tmp >> $(BAD_ALIVE_SAMPLE_LOG); \
	    else \
	      echo "Unexpected success: $$f" | tee -a $(BAD_ALIVE_SAMPLE_LOG); \
	      cat $$tmp | tee -a $(BAD_ALIVE_SAMPLE_LOG); \
	      rm -f $$tmp; \
	      exit 1; \
	    fi; \
	    rm -f $$tmp; \
	  done; \
	  if [ $$found = false ]; then echo "No bad Alive samples under $(BAD_ALIVE_SAMPLE_DIR)" | tee -a $(BAD_ALIVE_SAMPLE_LOG); fi; \
	else \
	  echo "Alive2 binary '$(ALIVE_BIN)' not found even after build" && exit 1; \
	fi
