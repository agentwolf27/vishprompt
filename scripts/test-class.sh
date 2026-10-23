#!/bin/bash
# Runs one XCTest class and fails unless it genuinely ran.
#
# xcodebuild exits 0 when -only-testing names a class that does not exist (nothing ran, so
# nothing failed), and a skipped test is not a failure either. A VERIFY built on that would go
# green after the class was deleted, so this checks the summary as well as the exit status.
#
# Usage: scripts/test-class.sh <TestClass> <xcodebuild command...>
set -o pipefail
class="$1"
shift

log="$(mktemp -t vishprompt-test-class)"
trap 'rm -f "$log"' EXIT

"$@" test -only-testing:"VishPromptTests/$class" > "$log" 2>&1
status=$?
grep -E "error:|Test Case .* (passed|failed|skipped)|Executed|TEST |LATENCY |PROBE " "$log"

if [ "$status" -ne 0 ]; then
    echo "test-class: xcodebuild failed for $class" >&2
    exit "$status"
fi
if ! grep -qE "Test Suite '$class' (passed|failed)" "$log"; then
    echo "test-class: no test suite named $class ran" >&2
    exit 1
fi
if ! grep -qE "Executed [1-9][0-9]* tests?" "$log"; then
    echo "test-class: $class executed no tests" >&2
    exit 1
fi
if grep -qE "Test Case .* skipped|[1-9][0-9]* tests? skipped" "$log"; then
    echo "test-class: $class skipped a test, which does not count as passing" >&2
    exit 1
fi
echo "test-class: $class passed"
