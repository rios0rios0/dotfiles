SCRIPTS_DIR ?= $(HOME)/Development/github.com/rios0rios0/pipelines
-include $(SCRIPTS_DIR)/makefiles/common.mk

CI_DIR := .github/ci

# === Lint targets ===

.PHONY: lint lint-shellcheck lint-templates lint-python lint-powershell lint-syntax

lint: lint-shellcheck lint-templates lint-python lint-powershell lint-syntax

lint-shellcheck:
	@bash $(CI_DIR)/scripts/lint-shellcheck.sh

lint-templates:
	@cd $(CI_DIR)/cmd/tmplcheck && go run .

lint-python:
	@bash $(CI_DIR)/scripts/lint-python.sh

lint-powershell:
	@bash $(CI_DIR)/scripts/lint-powershell.sh

lint-syntax:
	@bash $(CI_DIR)/scripts/lint-yaml-json.sh

# === Test targets ===

.PHONY: test test-template-render test-chezmoiignore test-script-order test-modify-scripts

test: test-template-render test-chezmoiignore test-script-order test-modify-scripts

test-template-render:
	@bash $(CI_DIR)/scripts/test-template-render.sh

test-chezmoiignore:
	@bash $(CI_DIR)/scripts/test-chezmoiignore.sh

test-script-order:
	@bash $(CI_DIR)/scripts/test-script-order.sh

test-modify-scripts:
	@bash $(CI_DIR)/scripts/test-modify-scripts.sh

# === SAST targets (override common.mk to only run relevant tools) ===

.PHONY: sast

sast: gitleaks semgrep
