# Minimal pipeline to demo Semgrep -> LLVM IR -> Alive2 -> rewrite

PYTHON ?= python3
RULE_DIR := example/rules
CODE_DIR := example/code
BUILD_DIR := build
IR_DIR := $(BUILD_DIR)/ir
REPORT_DIR := $(BUILD_DIR)/reports
OUT_DIR := $(BUILD_DIR)/out
ALIVE2_DIR := deps/alive2
ALIVE2_BUILD := $(ALIVE2_DIR)/build
ALIVE_BIN ?= $(ALIVE2_BUILD)/alive-tv
LLVM_DIR ?= /usr/lib/llvm-20/lib/cmake/llvm
ALIVE2_REF ?= v20.0
ALIVE_FLAGS ?= --smt-to=60000

.PHONY: all setup semgrep ir alive apply clean

all: setup semgrep ir alive apply

setup:
	$(PYTHON) -m pip install -r requirements.txt

$(BUILD_DIR):
	mkdir -p $(IR_DIR) $(REPORT_DIR) $(OUT_DIR)

semgrep: $(BUILD_DIR)
	@semgrep scan --config $(RULE_DIR) --json --quiet --timeout 60 --include '*.c' $(CODE_DIR) > $(REPORT_DIR)/semgrep.json; \
	  rc=$$?; \
	  if [ $$rc -gt 1 ]; then exit $$rc; fi
	@echo "Semgrep findings written to $(REPORT_DIR)/semgrep.json"

ir: $(BUILD_DIR)
	@found=0; \
	for f in $(RULE_DIR)/*.yaml; do \
	  [ -e $$f ] || continue; \
	  found=1; \
	  $(PYTHON) semgrep_to_IR.py $$f --out $(IR_DIR); \
	done; \
	if [ $$found -eq 0 ]; then echo "No rule files under $(RULE_DIR)" && exit 1; fi

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
	    $(ALIVE_BIN) $(ALIVE_FLAGS) $$f || exit $$?; \
	  done; \
	else \
	  echo "Alive2 binary '$(ALIVE_BIN)' not found even after build" && exit 1; \
	fi

apply: semgrep
	rsync -a $(CODE_DIR)/ $(OUT_DIR)/
	@semgrep scan --config $(RULE_DIR) --autofix --timeout 60 $(OUT_DIR); \
	  rc=$$?; \
	  if [ $$rc -gt 1 ]; then exit $$rc; fi
	@echo "Rewritten sources placed under $(OUT_DIR)" 

clean:
	rm -rf $(BUILD_DIR)
