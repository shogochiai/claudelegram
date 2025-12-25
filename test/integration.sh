#!/bin/bash
# Integration tests for claudelegram
# Requires: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID environment variables

set -e

CLAUDELEGRAM="${CLAUDELEGRAM:-./build/exec/claudelegram}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
}

# Check prerequisites
check_prereqs() {
    if [ ! -x "$CLAUDELEGRAM" ]; then
        echo "Error: claudelegram not found at $CLAUDELEGRAM"
        echo "Run: idris2 --build claudelegram.ipkg"
        exit 1
    fi

    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        echo "Error: TELEGRAM_BOT_TOKEN not set"
        exit 1
    fi

    if [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Error: TELEGRAM_CHAT_ID not set"
        exit 1
    fi
}

echo "=== claudelegram Integration Tests ==="
echo ""

check_prereqs

# Test 1: CLI help
echo "--- Test: CLI help ---"
if $CLAUDELEGRAM --help 2>&1 | grep -q "claudelegram"; then
    pass "CLI help output"
else
    fail "CLI help output"
fi

# Test 2: CLI version
echo "--- Test: CLI version ---"
if $CLAUDELEGRAM --version 2>&1 | grep -q "0.1.0"; then
    pass "CLI version output"
else
    fail "CLI version output"
fi

# Test 3: Send message (non-interactive)
echo "--- Test: Send message ---"
if $CLAUDELEGRAM send "Integration test: $(date)" 2>&1 | grep -q "Message sent"; then
    pass "Send message"
else
    fail "Send message"
fi

# Test 4: Notify without choices (non-blocking)
echo "--- Test: Notify without choices ---"
if $CLAUDELEGRAM send "Notify test (no choices): $(date)" 2>&1 | grep -q "Message sent"; then
    pass "Notify without choices"
else
    fail "Notify without choices"
fi

# Test 5: Interactive notify (requires human)
echo ""
echo "--- Interactive Test: Notify with choices ---"
echo "This test requires manual interaction."
echo "A message will be sent to Telegram with buttons."
echo ""
read -p "Run interactive test? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Sending notify with choices..."
    echo "Please press 'yes' on Telegram within 60 seconds."

    export CLAUDELEGRAM_POLL_TIMEOUT=60
    response=$($CLAUDELEGRAM notify "Integration test: Press YES" -c "yes,no" 2>&1 | tail -1)

    if [ "$response" = "yes" ]; then
        pass "Notify with choices (response: $response)"
    else
        fail "Notify with choices (expected 'yes', got: $response)"
    fi
else
    skip "Interactive notify test"
fi

# Test 6: CID uniqueness (multiple sends should have different CIDs)
echo ""
echo "--- Test: CID uniqueness ---"
cid1=$($CLAUDELEGRAM send "CID test 1" 2>&1 | grep -o 'Notification sent: [^ ]*' | cut -d' ' -f3 || echo "")
cid2=$($CLAUDELEGRAM send "CID test 2" 2>&1 | grep -o 'Notification sent: [^ ]*' | cut -d' ' -f3 || echo "")
if [ -n "$cid1" ] && [ -n "$cid2" ] && [ "$cid1" != "$cid2" ]; then
    pass "CID uniqueness ($cid1 != $cid2)"
else
    skip "CID uniqueness (could not extract CIDs)"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    exit 1
fi
