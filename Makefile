SCRIPTS_DIR ?= $(HOME)/Development/github.com/rios0rios0/pipelines
-include $(SCRIPTS_DIR)/makefiles/common.mk

# One target per task, each running one script. `ONLY` narrows lint or test to the named linters or
# tests: `make lint ONLY=shellcheck`, `make test ONLY="yq chlog"`.
.PHONY: lint test sast

# shellcheck, the Go template checker, ruff, PSScriptAnalyzer and the YAML/JSON syntax check.
lint:
	@bash .github/ci/scripts/lint.sh $(ONLY)

# Every .github/ci/scripts/test-<name>.sh with bash and test-<name>.ps1 with pwsh.
test:
	@bash .github/ci/scripts/test.sh $(ONLY)

# gitleaks and semgrep over the whole repository.
sast:
	@echo '[sast] running gitleaks...' >&2
	gitleaks detect --source . --verbose
	@echo '[sast] running semgrep...' >&2
	semgrep --config auto .
