#!/bin/bash
# Mock 1Password CLI for CI testing
# Returns deterministic JSON fixtures based on the command and arguments

FIXTURES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse the command
CMD="$1"
shift

case "$CMD" in
    item)
        SUBCMD="$1"
        shift
        case "$SUBCMD" in
            get)
                ITEM_NAME="$1"
                case "$ITEM_NAME" in
                    "Active SSHs")
                        cat "$FIXTURES_DIR/active-sshs.json"
                        ;;
                    "Active GPGs")
                        cat "$FIXTURES_DIR/active-gpgs.json"
                        ;;
                    "Active PEMs")
                        cat "$FIXTURES_DIR/active-pems.json"
                        ;;
                    "Active Docker Registries")
                        cat "$FIXTURES_DIR/active-docker-registries.json"
                        ;;
                    *)
                        # Individual item lookup (e.g., "testdevice@My SSH Key")
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
    account)
        echo '[{"shorthand":"my","url":"https://my.1password.com"}]'
        ;;
    *)
        echo "{}"
        ;;
esac

exit 0
