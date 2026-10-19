#!/usr/bin/env bash
#
## Lints Verified Access Cedar policies rendered by this module (or supplied through the raw_policy
## escape hatch) against the documented rule set. Every policy carries a machine readable header:
##
##   // managed-by: terraform-aws-verified-access
##   // kind: group | endpoint
##   // name: <name>
##   // source: structured | raw
##   // sensitive: true | false        (endpoints only)
##   // owner: <team>
##   // justification: <why>
##   // user-context: <policy reference name>
##   // device-context: <policy reference name>   (when a device provider is configured)
##
## Rules:
##   L1  the policy parses as Cedar (official cedar CLI; skipped with a warning when not installed,
##       unless --require-parser is given)
##   L2  no unscoped permit: every permit has a when clause referencing a trust provider context;
##       group policies must reference the user context
##   L3  the header has an owner and a justification of at least 10 characters
##   L4  a sensitive endpoint policy references the device context in a permit
##   L5  the header declares managed-by: terraform-aws-verified-access
##   L6  raw (escape hatch) policies are listed so reviewers always see them (informational)
##   L7  the policy contains at least one permit (a forbid-only policy denies everything)
##   L8  a forbid using protocol specific context (http_request, tcp_flow) guards it with context has; otherwise
##       it errors on the other protocol and Cedar skips it, so the forbid silently does not apply
##
## Usage: scripts/cedar-lint.sh [--require-parser] <file-or-directory>...
#

set -o nounset
set -o pipefail

REQUIRE_PARSER=false
TARGETS=()
ERRORS=0
CHECKED=0

usage() {
  echo "Usage: $0 [--require-parser] <file-or-directory>..."
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --require-parser) REQUIRE_PARSER=true ;;
  -h | --help) usage ;;
  *) TARGETS+=("$1") ;;
  esac
  shift
done

[[ ${#TARGETS[@]} -eq 0 ]] && usage

## Determine whether the official Cedar parser is available for L1
if command -v cedar >/dev/null 2>&1; then
  HAS_PARSER=true
elif [[ "${REQUIRE_PARSER}" == "true" ]]; then
  echo "ERROR L1 the cedar CLI is required (--require-parser) but was not found on PATH"
  exit 1
else
  HAS_PARSER=false
  echo "WARN  L1 the cedar CLI is not installed; skipping the parse check (CI enforces it)"
fi

## Lint a single policy file, printing one line per finding: <LEVEL> <RULE> <message>
lint_file() {
  local file="$1"

  if [[ "${HAS_PARSER}" == "true" ]]; then
    if ! cedar check-parse --policies "${file}" >/dev/null 2>&1; then
      echo "ERROR L1 the policy does not parse as Cedar"
    fi
  fi

  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

    ## Header lines are // key: value comments before the first statement
    /^[ \t]*\/\// {
      line = $0
      sub(/^[ \t]*\/\/[ \t]*/, "", line)
      position = index(line, ":")
      if (!in_body && position > 0) {
        header[trim(substr(line, 1, position - 1))] = trim(substr(line, position + 1))
      }
      next
    }

    { in_body = 1; body = body " " $0 }

    END {
      kind = header["kind"]; user = header["user-context"]; device = header["device-context"]

      if (header["managed-by"] != "terraform-aws-verified-access")
        print "ERROR L5 missing header managed-by: terraform-aws-verified-access"
      if (header["owner"] == "")
        print "ERROR L3 missing owner in the header"
      if (length(header["justification"]) < 10)
        print "ERROR L3 missing or too short justification in the header (min 10 characters)"
      if (kind != "group" && kind != "endpoint")
        print "ERROR L5 header kind must be group or endpoint"
      if (user == "")
        print "ERROR L5 missing user-context in the header"
      if (header["source"] == "raw")
        print "INFO  L6 raw policy (escape hatch) owned by " header["owner"] ": " header["justification"]

      permits = 0; device_permit = 0
      count = split(body, statements, ";")
      for (i = 1; i <= count; i++) {
        statement = trim(statements[i])
        if (statement == "") continue

        if (statement ~ /^permit[ \t]*\(/) {
          permits++
          scoped = (statement ~ /\)[ \t]*when[ \t]*\{/)
          has_user = (user != "" && index(statement, "context." user ".") > 0)
          has_device = (device != "" && index(statement, "context." device ".") > 0)
          if (has_device) device_permit = 1

          if (!scoped)
            print "ERROR L2 unscoped permit: every permit needs a when clause"
          else if (kind == "group" && !has_user)
            print "ERROR L2 unscoped permit: a group permit must reference context." user "."
          else if (kind == "endpoint" && !has_user && !has_device)
            print "ERROR L2 unscoped permit: an endpoint permit must reference a trust provider context"
        } else if (statement ~ /^forbid[ \t]*\(/) {
          if (index(statement, "context.http_request") > 0 && index(statement, "context has \"http_request\"") == 0)
            print "ERROR L8 unguarded forbid: add context has \"http_request\", or the forbid is skipped on TCP endpoints"
          if (index(statement, "context.tcp_flow") > 0 && index(statement, "context has \"tcp_flow\"") == 0)
            print "ERROR L8 unguarded forbid: add context has \"tcp_flow\", or the forbid is skipped on HTTP endpoints"
        } else {
          print "ERROR L1 unrecognised statement, expected permit or forbid"
        }
      }

      if (permits == 0)
        print "ERROR L7 the policy has no permit, so it denies everything"
      if (kind == "endpoint" && header["sensitive"] == "true" && !device_permit)
        print "ERROR L4 a sensitive endpoint must reference the device context in a permit"
    }
  ' "${file}"
}

## Collect the policy files from the targets
FILES=()
for target in "${TARGETS[@]}"; do
  if [[ -d "${target}" ]]; then
    while IFS= read -r found; do FILES+=("${found}"); done < <(find "${target}" -type f -name '*.cedar' | sort)
  elif [[ -f "${target}" ]]; then
    FILES+=("${target}")
  else
    echo "ERROR the target ${target} does not exist"
    exit 2
  fi
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR no .cedar files found in ${TARGETS[*]}"
  exit 2
fi

for file in "${FILES[@]}"; do
  CHECKED=$((CHECKED + 1))
  findings=$(lint_file "${file}")

  if echo "${findings}" | grep -q '^ERROR'; then
    echo "FAIL  ${file}"
    ERRORS=$((ERRORS + 1))
  else
    echo "PASS  ${file}"
  fi

  if [[ -n "${findings}" ]]; then
    echo "${findings}" | sed 's/^/      /'
    ## Surface raw policies in the GitHub Actions job summary for reviewers
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "${findings}" | grep -q 'L6'; then
      echo "- \`${file}\`: $(echo "${findings}" | grep 'L6' | sed 's/^INFO  L6 //')" >>"${GITHUB_STEP_SUMMARY}"
    fi
  fi
done

echo "--> Linted ${CHECKED} policies, ${ERRORS} failed"
[[ ${ERRORS} -eq 0 ]]
