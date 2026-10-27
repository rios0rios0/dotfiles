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

.PHONY: test test-template-render test-chezmoiignore test-script-order test-modify-scripts test-remove-dependencies test-remove-dependencies-windows test-install-dependencies-windows test-prune-tmp-modcache test-shell-credentials test-nvm-resolution test-zshrc-functions test-sentry-setup test-local-llm test-opencode test-tailscale test-wsl-systemd test-statusline test-claude-lsp test-omniroute-backup test-omniroute-image test-ocode test-terra-update test-yq test-chlog test-export-keys test-export-key-windows test-install-fonts-windows test-powershell-profile-windows

test: test-template-render test-chezmoiignore test-script-order test-modify-scripts test-remove-dependencies test-remove-dependencies-windows test-install-dependencies-windows test-prune-tmp-modcache test-shell-credentials test-clipboard-shim test-nvm-resolution test-zshrc-functions test-sentry-setup test-local-llm test-opencode test-tailscale test-wsl-systemd test-statusline test-claude-lsp test-omniroute-backup test-omniroute-image test-ocode test-terra-update test-yq test-chlog test-export-keys test-export-key-windows test-install-fonts-windows test-powershell-profile-windows

test-template-render:
	@bash $(CI_DIR)/scripts/test-template-render.sh

test-chezmoiignore:
	@bash $(CI_DIR)/scripts/test-chezmoiignore.sh

test-script-order:
	@bash $(CI_DIR)/scripts/test-script-order.sh

test-modify-scripts:
	@bash $(CI_DIR)/scripts/test-modify-scripts.sh

test-remove-dependencies:
	@bash $(CI_DIR)/scripts/test-remove-dependencies.sh

test-remove-dependencies-windows:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -File $(CI_DIR)/scripts/test-remove-dependencies-windows.ps1; \
	else \
		echo "[test-remove-dependencies-windows] SKIP: pwsh not installed" >&2; \
	fi

test-install-dependencies-windows:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -File $(CI_DIR)/scripts/test-install-dependencies-windows.ps1; \
	else \
		echo "[test-install-dependencies-windows] SKIP: pwsh not installed" >&2; \
	fi

test-prune-tmp-modcache:
	@bash $(CI_DIR)/scripts/test-prune-tmp-modcache.sh

test-shell-credentials:
	@bash $(CI_DIR)/scripts/test-shell-credentials.sh

test-clipboard-shim:
	@bash $(CI_DIR)/scripts/test-clipboard-shim.sh

test-nvm-resolution:
	@bash $(CI_DIR)/scripts/test-nvm-resolution.sh

test-zshrc-functions:
	@bash $(CI_DIR)/scripts/test-zshrc-functions.sh

test-sentry-setup:
	@bash $(CI_DIR)/scripts/test-sentry-setup.sh

test-local-llm:
	@bash $(CI_DIR)/scripts/test-local-llm.sh

test-opencode:
	@bash $(CI_DIR)/scripts/test-opencode.sh

test-tailscale:
	@bash $(CI_DIR)/scripts/test-tailscale.sh

test-wsl-systemd:
	@bash $(CI_DIR)/scripts/test-wsl-systemd.sh

test-statusline:
	@bash $(CI_DIR)/scripts/test-statusline.sh

test-claude-lsp:
	@bash $(CI_DIR)/scripts/test-claude-lsp.sh

test-omniroute-backup:
	@bash $(CI_DIR)/scripts/test-omniroute-backup.sh

test-omniroute-image:
	@bash $(CI_DIR)/scripts/test-omniroute-image.sh

test-ocode:
	@bash $(CI_DIR)/scripts/test-ocode.sh

test-terra-update:
	@bash $(CI_DIR)/scripts/test-terra-update.sh

test-yq:
	@bash $(CI_DIR)/scripts/test-yq.sh

test-chlog:
	@bash $(CI_DIR)/scripts/test-chlog.sh

test-export-keys:
	@bash $(CI_DIR)/scripts/test-export-keys.sh

test-export-key-windows:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -File $(CI_DIR)/scripts/test-export-key-windows.ps1; \
	else \
		echo "[test-export-key-windows] SKIP: pwsh not installed" >&2; \
	fi

test-install-fonts-windows:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -File $(CI_DIR)/scripts/test-install-fonts-windows.ps1; \
	else \
		echo "[test-install-fonts-windows] SKIP: pwsh not installed" >&2; \
	fi

test-powershell-profile-windows:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -File $(CI_DIR)/scripts/test-powershell-profile-windows.ps1; \
	else \
		echo "[test-powershell-profile-windows] SKIP: pwsh not installed" >&2; \
	fi

# === SAST targets ===

.PHONY: sast

sast:
	@echo '[sast] running gitleaks...' >&2
	gitleaks detect --source . --verbose
	@echo '[sast] running semgrep...' >&2
	semgrep --config auto .
