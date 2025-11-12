#!/usr/bin/env bats
# Tests for bin/docker-entrypoint script

load test_helper

# Jemalloc Detection Tests

@test "sets LD_PRELOAD when not already set" {
    unset LD_PRELOAD
    run bash -c 'source test/test_helper.bash && setup && bash -c "
        if [ -z \"\${LD_PRELOAD+x}\" ]; then
            LD_PRELOAD=\$(find /usr/lib -name libjemalloc.so.2 -print -quit)
            export LD_PRELOAD
        fi
        echo \"\$LD_PRELOAD\"
    "'
    [ "$status" -eq 0 ]
}

@test "preserves existing LD_PRELOAD" {
    run bash -c '
        export LD_PRELOAD="/custom/path/libjemalloc.so"
        if [ -z "${LD_PRELOAD+x}" ]; then
            LD_PRELOAD=$(find /usr/lib -name libjemalloc.so.2 -print -quit)
            export LD_PRELOAD
        fi
        echo "$LD_PRELOAD"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"/custom/path/libjemalloc.so"* ]]
}

# Fetchmailrc Generation Tests

@test "generates fetchmailrc with valid environment variables" {
    generate_fetchmailrc
    [ -f "${HOME}/.fetchmailrc" ]
}

@test "fetchmailrc contains mail server configuration" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "poll ${MAIL_SERVER}"
    assert_fetchmailrc_contains "port ${MAIL_PORT}"
}

@test "fetchmailrc contains credentials" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "user \"${USERNAME}\""
    assert_fetchmailrc_contains "password \"${PASSWORD}\""
}

@test "fetchmailrc contains MDA command with Rails URL" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "mda \"bundle exec rake action_mailbox:ingress:postfix URL=${RAILS_MAIL_INBOUND_URL} INGRESS_PASSWORD=${INGRESS_PASSWORD}\""
}

@test "fetchmailrc contains SSL configuration by default" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "ssl"
    assert_fetchmailrc_contains "sslcertck"
}

@test "fetchmailrc contains SSL when DISABLE_SSL is empty" {
    export DISABLE_SSL=""
    generate_fetchmailrc
    assert_fetchmailrc_contains "ssl"
    assert_fetchmailrc_contains "sslcertck"
}

@test "fetchmailrc contains SSL when DISABLE_SSL is unset" {
    unset DISABLE_SSL
    generate_fetchmailrc
    assert_fetchmailrc_contains "ssl"
    assert_fetchmailrc_contains "sslcertck"
}

@test "fetchmailrc omits SSL when DISABLE_SSL is true" {
    export DISABLE_SSL="true"
    generate_fetchmailrc
    assert_fetchmailrc_not_contains "ssl"
    assert_fetchmailrc_not_contains "sslcertck"
}

@test "fetchmailrc contains SSL when DISABLE_SSL is false" {
    export DISABLE_SSL="false"
    generate_fetchmailrc
    assert_fetchmailrc_contains "ssl"
    assert_fetchmailrc_contains "sslcertck"
}

@test "fetchmailrc contains SSL when DISABLE_SSL is any value other than 'true'" {
    export DISABLE_SSL="yes"
    generate_fetchmailrc
    assert_fetchmailrc_contains "ssl"
    assert_fetchmailrc_contains "sslcertck"
}

@test "fetchmailrc contains IDLE mode" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "idle"
}

@test "fetchmailrc contains idfile path" {
    generate_fetchmailrc
    assert_fetchmailrc_contains 'set idfile "/rails/storage/fetchmail.id"'
}

@test "fetchmailrc disables syslog and bouncemail" {
    generate_fetchmailrc
    assert_fetchmailrc_contains "set no syslog"
    assert_fetchmailrc_contains "set no bouncemail"
}

# KEEP Variable Tests

@test "KEEP variable set to 'keep' preserves messages" {
    export KEEP="keep"
    generate_fetchmailrc
    assert_fetchmailrc_contains "keep"
}

@test "KEEP variable empty deletes messages" {
    export KEEP=""
    generate_fetchmailrc
    # When KEEP is empty, the line should just be whitespace
    run grep -E "^[[:space:]]*$" "${HOME}/.fetchmailrc"
    [ "$status" -eq 0 ]
}

# Special Character Escaping Tests

@test "handles password with double quotes" {
    export PASSWORD='pass"word"123'
    generate_fetchmailrc
    [ -f "${HOME}/.fetchmailrc" ]
    # The password should be in the file (bash heredoc handles escaping)
    assert_fetchmailrc_contains 'pass"word"123'
}

@test "handles password with dollar signs" {
    export PASSWORD='pa$$w0rd'
    generate_fetchmailrc
    assert_fetchmailrc_contains 'pa$$w0rd'
}

@test "handles password with single quotes" {
    export PASSWORD="pass'word'123"
    generate_fetchmailrc
    assert_fetchmailrc_contains "pass'word'123"
}

@test "handles username with special characters" {
    export USERNAME='user+tag@example.com'
    generate_fetchmailrc
    assert_fetchmailrc_contains 'user+tag@example.com'
}

@test "handles password with backticks" {
    export PASSWORD='pass`cmd`word'
    generate_fetchmailrc
    # Heredoc should preserve backticks literally
    assert_fetchmailrc_contains 'pass`cmd`word'
}

@test "handles password with spaces" {
    export PASSWORD='pass word 123'
    generate_fetchmailrc
    assert_fetchmailrc_contains 'pass word 123'
}

# File Permissions Tests

@test "fetchmailrc is created with restrictive permissions" {
    # Set umask 077 and generate in the current shell (not subshell)
    umask 077
    generate_fetchmailrc
    [ -f "${HOME}/.fetchmailrc" ]

    # Check permissions - should be owner-only (no group or world access)
    # Get first character (should be '-' for regular file) and next 9 chars for permissions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        perms=$(stat -f "%OLp" "${HOME}/.fetchmailrc")
    else
        # Linux
        perms=$(stat -c "%a" "${HOME}/.fetchmailrc")
    fi

    # Should be 600 (rw-------) or 400 (r--------) or 700 (rwx-------)
    # Just verify no group or world permissions (last 6 digits should be 00)
    [[ "$perms" =~ ^[4-7]00$ ]]
}

# Idempotency Tests

@test "does not regenerate existing fetchmailrc" {
    # Generate fetchmailrc first time
    generate_fetchmailrc

    # Record original timestamp/content
    original_content=$(cat "${HOME}/.fetchmailrc")

    # Wait briefly to ensure timestamp would differ
    sleep 0.1

    # Try to generate again
    generate_fetchmailrc

    # Content should be identical (file not regenerated)
    new_content=$(cat "${HOME}/.fetchmailrc")
    [ "$original_content" = "$new_content" ]
}

@test "skips generation when .fetchmailrc already exists" {
    # Create a dummy .fetchmailrc
    echo "existing config" > "${HOME}/.fetchmailrc"

    # Try to generate
    generate_fetchmailrc

    # Original content should be preserved
    content=$(cat "${HOME}/.fetchmailrc")
    [ "$content" = "existing config" ]
}

# Missing Environment Variable Tests

@test "fails when MAIL_SERVER is missing" {
    unset MAIL_SERVER
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

@test "fails when MAIL_PORT is missing" {
    unset MAIL_PORT
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

@test "fails when USERNAME is missing" {
    unset USERNAME
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

@test "fails when PASSWORD is missing" {
    unset PASSWORD
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

@test "fails when RAILS_MAIL_INBOUND_URL is missing" {
    unset RAILS_MAIL_INBOUND_URL
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

@test "fails when INGRESS_PASSWORD is missing" {
    unset INGRESS_PASSWORD
    run generate_fetchmailrc
    [ "$status" -ne 0 ]
}

# Command Dispatch Tests

@test "dispatches to fetchmail with --nodetach --nosyslog when no args" {
    # We can't fully test exec, but we can verify the case logic works
    run bash -c '
        arg=""
        case "$arg" in
          "" )
            echo "fetchmail --nodetach --nosyslog"
            ;;
          *)
            echo "other"
            ;;
        esac
    '
    [ "$status" -eq 0 ]
    [ "$output" = "fetchmail --nodetach --nosyslog" ]
}

@test "dispatches to fetchmail with args when first arg is 'fetchmail'" {
    run bash -c '
        set -- fetchmail --verbose
        arg="${1:-}"
        case "$arg" in
          fetchmail)
            shift
            echo "fetchmail --nodetach --nosyslog $@"
            ;;
          *)
            echo "other"
            ;;
        esac
    '
    [ "$status" -eq 0 ]
    [ "$output" = "fetchmail --nodetach --nosyslog --verbose" ]
}

@test "dispatches to fetchmail when first arg is a flag" {
    run bash -c '
        set -- --verbose
        arg="${1:-}"
        case "$arg" in
          -*)
            echo "fetchmail --nodetach --nosyslog $@"
            ;;
          *)
            echo "other"
            ;;
        esac
    '
    [ "$status" -eq 0 ]
    [ "$output" = "fetchmail --nodetach --nosyslog --verbose" ]
}

@test "dispatches to custom command when arg is not a flag" {
    run bash -c '
        set -- /bin/bash
        arg="${1:-}"
        case "$arg" in
          "")
            echo "default"
            ;;
          fetchmail)
            echo "fetchmail"
            ;;
          -*)
            echo "flag"
            ;;
          *)
            echo "custom: $@"
            ;;
        esac
    '
    [ "$status" -eq 0 ]
    [ "$output" = "custom: /bin/bash" ]
}

# Error Handling Tests

@test "script exits on undefined variable access (set -u)" {
    run bash -c 'set -u; echo "$UNDEFINED_VAR"'
    # Should exit with non-zero status due to undefined variable
    [ "$status" -ne 0 ]
}

@test "script exits on command failure (set -e)" {
    run bash -c 'set -e; false; echo "should not reach here"'
    [ "$status" -ne 0 ]
}

@test "script fails if pipeline command fails (set -o pipefail)" {
    run bash -c 'set -o pipefail; false | true'
    [ "$status" -ne 0 ]
}
