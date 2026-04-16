#!/bin/bash
# Mock 1Password CLI for CI testing
# Returns deterministic JSON fixtures based on the command and arguments

FIXTURES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Debug: log all arguments received
echo "[mock-op] called with: $*" >&2

# Strip --session flag and its value (chezmoi passes this after signin)
while [[ "${1:-}" == --session ]]; do
    shift 2
done

# Parse the command
CMD="$1"
shift

case "$CMD" in
    item)
        SUBCMD="$1"
        shift
        case "$SUBCMD" in
            get)
                # Skip flags (--format, --vault, --account) to find the positional item name
                ITEM_NAME=""
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --format|--vault|--account)
                            shift
                            [[ $# -gt 0 ]] && shift
                            ;;
                        *)
                            if [[ -z "$ITEM_NAME" ]]; then
                                ITEM_NAME="$1"
                            fi
                            shift
                            ;;
                    esac
                done
                case "$ITEM_NAME" in
                    "Device: testdevice")
                        cat "$FIXTURES_DIR/device-testdevice.json"
                        ;;
                    *)
                        # Individual item lookup (e.g., "Test SSH Key")
                        cat "$FIXTURES_DIR/ssh-item-sample.json"
                        ;;
                esac
                ;;
            *)
                echo "{}"
                ;;
        esac
        ;;
    read)
        URI="$1"
        case "$URI" in
            *"Chezmoi Key"*|*"public key"*)
                cat "$FIXTURES_DIR/chezmoi-key.txt"
                ;;
            *"Wakatime"*)
                echo "stub-wakatime-value"
                ;;
            *)
                echo "stub-value"
                ;;
        esac
        ;;
    whoami)
        echo '{"email":"test@example.com","account_uuid":"test-uuid"}'
        ;;
    signin)
        echo "mock-session-token"
        ;;
    account)
        echo '[{"shorthand":"my","url":"https://my.1password.com","email":"test@example.com","user_uuid":"test-user-uuid","account_uuid":"test-account-uuid"}]'
        ;;
    *)
        echo "{}"
        ;;
esac

exit 0
