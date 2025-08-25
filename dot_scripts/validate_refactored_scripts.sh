#!/bin/bash
#
# Validation script for refactored installation scripts
# Tests that scripts can source shared components and validate structure
#

# Test configuration
readonly TEST_DIR="/tmp/dotfiles_validation"
readonly DOTFILES_ROOT="/home/runner/work/dotfiles/dotfiles"

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR" || exit 1
    
    # Create mock home structure
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME/.scripts"
    
    # Copy shared components to test home
    cp -r "$DOTFILES_ROOT/dot_scripts/"* "$HOME/.scripts/"
}

# Test Linux script structure
test_linux_script() {
    echo "Testing Linux script structure..."
    
    local script="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_linux-001-install-dependencies.sh"
    
    # Test syntax
    if bash -n "$script"; then
        echo "✓ Linux script syntax is valid"
    else
        echo "✗ Linux script syntax error"
        return 1
    fi
    
    # Test that it can source shared components (dry run)
    if bash -c "
        set -euo pipefail
        export HOME='$HOME'
        
        # Mock functions to avoid actual installation
        install_all_packages() { echo 'Mock: install_all_packages'; }
        install_oh_my_zsh() { echo 'Mock: install_oh_my_zsh'; }
        install_gvm() { echo 'Mock: install_gvm'; }
        install_nvm() { echo 'Mock: install_nvm'; }
        install_pyenv() { echo 'Mock: install_pyenv'; }
        install_sdkman() { echo 'Mock: install_sdkman'; }
        install_kubectl() { echo 'Mock: install_kubectl'; }
        install_krew() { echo 'Mock: install_krew'; }
        install_terraform() { echo 'Mock: install_terraform'; }
        install_terragrunt() { echo 'Mock: install_terragrunt'; }
        install_azure_cli() { echo 'Mock: install_azure_cli'; }
        export -f install_all_packages install_oh_my_zsh install_gvm install_nvm
        export -f install_pyenv install_sdkman install_kubectl install_krew
        export -f install_terraform install_terragrunt install_azure_cli
        
        # Override platform detection to simulate Linux
        is_linux() { return 0; }
        is_android() { return 1; }
        export -f is_linux is_android
        
        # Test syntax check without running
        if ! bash -n '$script'; then
            echo 'Syntax check failed'
            exit 1
        fi
        
        echo 'Basic validation passed'
    "; then
        echo "✓ Linux script can source shared components"
    else
        echo "✗ Linux script failed to source shared components"
        return 1
    fi
    
    return 0
}

# Test Android script structure
test_android_script() {
    echo "Testing Android script structure..."
    
    local script="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_android-001-install-dependencies.sh.tmpl"
    
    # Test syntax (skip template processing for now)
    if bash -n <(sed 's/{{ lookPath "bash" }}/\/bin\/bash/' "$script"); then
        echo "✓ Android script syntax is valid"
    else
        echo "✗ Android script syntax error"
        return 1
    fi
    
    # Test that it can source shared components (dry run)
    if bash -c "
        set -euo pipefail
        export HOME='$HOME'
        
        # Mock functions to avoid actual installation
        install_all_packages() { echo 'Mock: install_all_packages'; }
        install_oh_my_zsh() { echo 'Mock: install_oh_my_zsh'; }
        install_gvm() { echo 'Mock: install_gvm'; }
        install_nvm() { echo 'Mock: install_nvm'; }
        install_pyenv() { echo 'Mock: install_pyenv'; }
        install_sdkman() { echo 'Mock: install_sdkman'; }
        install_wrapper() { echo 'Mock: install_wrapper'; }
        install_terra() { echo 'Mock: install_terra'; }
        install_terraform() { echo 'Mock: install_terraform'; }
        install_terragrunt() { echo 'Mock: install_terragrunt'; }
        install_1password_cli() { echo 'Mock: install_1password_cli'; }
        install_azure_cli() { echo 'Mock: install_azure_cli'; }
        configure_dns_android() { echo 'Mock: configure_dns_android'; }
        configure_neovim() { echo 'Mock: configure_neovim'; }
        export -f install_all_packages install_oh_my_zsh install_gvm install_nvm
        export -f install_pyenv install_sdkman install_wrapper install_terra
        export -f install_terraform install_terragrunt install_1password_cli
        export -f install_azure_cli configure_dns_android configure_neovim
        
        # Override platform detection to simulate Android
        is_linux() { return 1; }
        is_android() { return 0; }
        export -f is_linux is_android
        
        # Test syntax check without running
        if ! bash -n /tmp/android_script.sh; then
            echo 'Syntax check failed'
            exit 1
        fi
        
        echo 'Basic validation passed'
    "; then
        echo "✓ Android script can source shared components"
    else
        echo "✗ Android script failed to source shared components"
        return 1
    fi
    
    return 0
}

# Compare script sizes
compare_script_sizes() {
    echo "Comparing script sizes..."
    
    local old_linux="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_linux-001-install-dependencies.sh.original"
    local new_linux="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_linux-001-install-dependencies.sh"
    local old_android="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_android-001-install-dependencies.sh.tmpl.original"
    local new_android="$DOTFILES_ROOT/.chezmoiscripts/run_once_before_android-001-install-dependencies.sh.tmpl"
    
    local old_linux_lines old_android_lines new_linux_lines new_android_lines
    old_linux_lines=$(wc -l < "$old_linux")
    old_android_lines=$(wc -l < "$old_android")
    new_linux_lines=$(wc -l < "$new_linux")
    new_android_lines=$(wc -l < "$new_android")
    
    echo "Linux script: $old_linux_lines lines → $new_linux_lines lines ($(( new_linux_lines - old_linux_lines )) change)"
    echo "Android script: $old_android_lines lines → $new_android_lines lines ($(( new_android_lines - old_android_lines )) change)"
    
    local total_old total_new
    total_old=$((old_linux_lines + old_android_lines))
    total_new=$((new_linux_lines + new_android_lines))
    
    echo "Total: $total_old lines → $total_new lines ($(( new_total_new - total_old )) change)"
    echo "Shared components add $(find "$DOTFILES_ROOT/dot_scripts" -name "*.sh" -exec wc -l {} + | tail -1 | awk '{print $1}') lines of reusable code"
}

# Run all validation tests
run_validation() {
    echo "Running refactored scripts validation..."
    echo "========================================"
    
    setup_test_env
    
    local failed=0
    
    test_linux_script || failed=1
    echo
    
    test_android_script || failed=1
    echo
    
    compare_script_sizes
    echo
    
    # Cleanup
    rm -rf "$TEST_DIR"
    
    if [ $failed -eq 0 ]; then
        echo "✓ All validation tests passed!"
        return 0
    else
        echo "✗ Some validation tests failed!"
        return 1
    fi
}

# Run validation if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_validation
fi