#!/bin/bash
#
# Test suite for shared dotfiles installation components
# This file tests the shared utilities and functions
#

# Test configuration
readonly TEST_DIR="/tmp/dotfiles_test"
readonly TEST_LOG="$TEST_DIR/test.log"

# Create test environment
setup_test_env() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR" || exit 1
    
    # Source the shared components (using absolute paths for testing)
    DOTFILES_ROOT="/home/runner/work/dotfiles/dotfiles"
    source "$DOTFILES_ROOT/dot_scripts/shared/executable_utils.sh"
    source "$DOTFILES_ROOT/dot_scripts/shared/executable_config.sh"
    source "$DOTFILES_ROOT/dot_scripts/shared/executable_packages.sh"
}

# Test utilities
test_utilities() {
    echo "Testing utility functions..."
    
    # Test command_exists
    if command_exists "bash"; then
        echo "✓ command_exists works for existing command"
    else
        echo "✗ command_exists failed for bash"
        return 1
    fi
    
    if ! command_exists "nonexistent_command_12345"; then
        echo "✓ command_exists correctly returns false for non-existent command"
    else
        echo "✗ command_exists incorrectly returned true for non-existent command"
        return 1
    fi
    
    # Test platform detection
    if is_linux || is_android; then
        echo "✓ Platform detection working"
    else
        echo "✗ Platform detection failed"
        return 1
    fi
    
    # Test logging functions
    log "Test log message" > "$TEST_LOG" 2>&1
    if grep -q "Test log message" "$TEST_LOG"; then
        echo "✓ Logging function works"
    else
        echo "✗ Logging function failed"
        return 1
    fi
    
    # Test directory creation
    local test_dir="$TEST_DIR/test_subdir"
    ensure_directory "$test_dir"
    if [ -d "$test_dir" ]; then
        echo "✓ Directory creation works"
    else
        echo "✗ Directory creation failed"
        return 1
    fi
    
    return 0
}

# Test configuration
test_config() {
    echo "Testing configuration functions..."
    
    # Test architecture detection
    local arch
    arch=$(get_architecture)
    if [ -n "$arch" ]; then
        echo "✓ Architecture detection works: $arch"
    else
        echo "✗ Architecture detection failed"
        return 1
    fi
    
    # Test URL generation
    local terragrunt_url terraform_url
    terragrunt_url=$(get_terragrunt_url "amd64")
    terraform_url=$(get_terraform_url "amd64")
    
    if [[ "$terragrunt_url" == *"terragrunt"* ]]; then
        echo "✓ Terragrunt URL generation works"
    else
        echo "✗ Terragrunt URL generation failed: $terragrunt_url"
        return 1
    fi
    
    if [[ "$terraform_url" == *"terraform"* ]]; then
        echo "✓ Terraform URL generation works"
    else
        echo "✗ Terraform URL generation failed: $terraform_url"
        return 1
    fi
    
    return 0
}

# Test package definitions
test_packages() {
    echo "Testing package definitions..."
    
    # Test requirements packages
    local requirements
    mapfile -t requirements < <(get_requirements_packages)
    if [ ${#requirements[@]} -gt 0 ]; then
        echo "✓ Requirements packages defined: ${#requirements[@]} packages"
    else
        echo "✗ No requirements packages found"
        return 1
    fi
    
    # Test hardware packages
    local hardware
    mapfile -t hardware < <(get_hardware_packages)
    if [ ${#hardware[@]} -gt 0 ]; then
        echo "✓ Hardware packages defined: ${#hardware[@]} packages"
    else
        echo "✗ No hardware packages found"
        return 1
    fi
    
    # Test utilities packages
    local utilities
    mapfile -t utilities < <(get_utilities_packages)
    if [ ${#utilities[@]} -gt 0 ]; then
        echo "✓ Utilities packages defined: ${#utilities[@]} packages"
    else
        echo "✗ No utilities packages found"
        return 1
    fi
    
    return 0
}

# Test package manager detection
test_package_manager() {
    echo "Testing package manager detection..."
    
    local pkg_manager
    pkg_manager=$(get_package_manager)
    if [ -n "$pkg_manager" ]; then
        echo "✓ Package manager detected: $pkg_manager"
    else
        echo "✗ Package manager detection failed"
        return 1
    fi
    
    return 0
}

# Run all tests
run_tests() {
    echo "Running dotfiles shared components tests..."
    echo "=========================================="
    
    setup_test_env
    
    local failed=0
    
    test_utilities || failed=1
    echo
    
    test_config || failed=1
    echo
    
    test_packages || failed=1
    echo
    
    test_package_manager || failed=1
    echo
    
    # Cleanup
    rm -rf "$TEST_DIR"
    
    if [ $failed -eq 0 ]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed!"
        return 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_tests
fi