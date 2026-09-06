#!/bin/sh
set -eu
# Run in the .NET SDK image with /fixture read-only and /output writable.
# The author branch stays unchanged while the review fixture has its correction.
git clone -q --no-local --branch rate-limit /fixture /tmp/before
cd /tmp/before
if dotnet test --logger 'console;verbosity=normal' > /output/before-tests.txt 2>&1; then
    echo 'The original boundary bug unexpectedly passed.' >&2
    exit 1
else
    test_exit=$?
fi
test "$test_exit" -eq 1
grep -F 'Failed RateLimiterTests.BlocksRequestsAtTheLimit' /output/before-tests.txt
grep -F 'Total tests: 3' /output/before-tests.txt
grep -F 'Passed: 2' /output/before-tests.txt
grep -F 'Failed: 1' /output/before-tests.txt
