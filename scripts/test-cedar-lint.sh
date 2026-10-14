#!/usr/bin/env bash
#
## Tests the Cedar lint rules: every fixture in tests/cedar-lint/valid must pass, and every fixture in
## tests/cedar-lint/invalid must fail with the rule its file name starts with (e.g. L2-no-when.cedar => L2).
#

set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="${ROOT}/scripts/cedar-lint.sh"
FIXTURES="${ROOT}/tests/cedar-lint"
FAILURES=0

for file in "${FIXTURES}"/valid/*.cedar; do
  if output=$("${LINT}" "${file}" 2>&1); then
    echo "PASS  valid fixture $(basename "${file}") is accepted"
  else
    echo "FAIL  valid fixture $(basename "${file}") was rejected:"
    echo "${output}" | sed 's/^/      /'
    FAILURES=$((FAILURES + 1))
  fi
done

for file in "${FIXTURES}"/invalid/*.cedar; do
  rule=$(basename "${file}" | cut -d- -f1)
  if output=$("${LINT}" "${file}" 2>&1); then
    echo "FAIL  invalid fixture $(basename "${file}") was accepted"
    FAILURES=$((FAILURES + 1))
  elif echo "${output}" | grep -q "ERROR ${rule} "; then
    echo "PASS  invalid fixture $(basename "${file}") is rejected by ${rule}"
  else
    echo "FAIL  invalid fixture $(basename "${file}") was rejected, but not by ${rule}:"
    echo "${output}" | sed 's/^/      /'
    FAILURES=$((FAILURES + 1))
  fi
done

echo "--> ${FAILURES} lint rule test(s) failed"
[[ ${FAILURES} -eq 0 ]]
