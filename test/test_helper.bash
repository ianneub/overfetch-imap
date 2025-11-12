#!/usr/bin/env bash
# Test helper functions for BATS tests

# Setup function run before each test
setup() {
    # Create a temporary directory for test isolation
    TEST_TEMP_DIR="$(mktemp -d)"
    export HOME="${TEST_TEMP_DIR}"

    # Set up default test environment variables
    export MAIL_SERVER="imap.example.com"
    export MAIL_PORT="993"
    export USERNAME="testuser@example.com"
    export PASSWORD="testpassword123"
    export RAILS_MAIL_INBOUND_URL="https://example.com/rails/action_mailbox/postfix/inbound_emails"
    export INGRESS_PASSWORD="ingress-secret"
    export KEEP=""

    # Mock LD_PRELOAD if not set
    unset LD_PRELOAD

    # Path to the script under test
    ENTRYPOINT="${BATS_TEST_DIRNAME}/../bin/docker-entrypoint"
}

# Teardown function run after each test
teardown() {
    # Clean up temporary directory
    if [ -n "${TEST_TEMP_DIR}" ] && [ -d "${TEST_TEMP_DIR}" ]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Helper: Run the entrypoint script up to fetchmailrc generation only
# (doesn't execute the final exec commands)
generate_fetchmailrc() {
    # Extract just the fetchmailrc generation portion
    # Lines 9-43 include jemalloc setup, umask, and fetchmailrc generation with SSL logic
    bash -c "
        set -euo pipefail
        $(sed -n '9,43p' "${ENTRYPOINT}")
    "
}

# Helper: Check if a string is present in the fetchmailrc
assert_fetchmailrc_contains() {
    local expected="$1"
    grep -qF "${expected}" "${HOME}/.fetchmailrc"
}

# Helper: Check if a string is NOT present in the fetchmailrc
assert_fetchmailrc_not_contains() {
    local unexpected="$1"
    ! grep -qF "${unexpected}" "${HOME}/.fetchmailrc"
}

# Helper: Get the file permissions of .fetchmailrc in octal
get_fetchmailrc_permissions() {
    if [ -f "${HOME}/.fetchmailrc" ]; then
        stat -f "%OLp" "${HOME}/.fetchmailrc" 2>/dev/null || stat -c "%a" "${HOME}/.fetchmailrc" 2>/dev/null
    fi
}
