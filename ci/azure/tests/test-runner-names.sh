#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${repo_root}/ci/azure/scripts/runner-names.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

identity="$(geos_ci_runner_identity 123456 2 'Ubuntu 24.04 - gcc 13 debug')"
grep -q '^runner_label=geos-hbv4-123456-2-ubuntu-24-04-gcc-13-debug$' <<< "${identity}" \
  || fail "unexpected runner label for normal matrix row"
grep -q '^vm_name=geos-hbv4-123456-2-ubuntu-24-04-gcc-13-debug$' <<< "${identity}" \
  || fail "unexpected VM name for normal matrix row"

long_identity="$(geos_ci_runner_identity 123456789012345 12 'this is a deliberately long matrix row name that must fit azure vm names')"
long_vm_name="$(awk -F= '$1 == "vm_name" { print $2 }' <<< "${long_identity}")"
(( ${#long_vm_name} <= 64 )) || fail "VM name exceeds Azure's 64-character Linux VM name limit"

# Long-name truncation must AVOID a hash-suffix collision.
#
# Malformed state being modeled: two distinct matrix instance keys that share a
# common prefix long enough that a naive 64-character truncation would collapse
# them to the SAME string. If the identity helper truncated without a
# distinguishing suffix, both legs would claim one VM name / runner label, and
# the janitor's runner_name==vm_name join
# (ci/azure/scripts/runner-names.sh, ci/azure/scripts/janitor.sh)
# would no longer identify a unique backing VM per registration.
#
# Invariant protected: distinct instance keys yield distinct vm_names, each still
# <= 64 chars. runner-names.sh enforces this by appending a deterministic hash of
# the FULL pre-truncation base (which includes the differing slug tail), so the
# hash differs even when the visible truncated prefix is identical. The two keys
# below share a 90-char run of 'a' and differ only in a trailing word, which is
# exactly the case that collides under plain truncation.
collide_prefix="$(printf 'a%.0s' $(seq 1 90))"
collide_key_a="${collide_prefix}-alpha"
collide_key_b="${collide_prefix}-omega"
collide_vm_a="$(geos_ci_runner_identity 1 1 "${collide_key_a}" | awk -F= '$1 == "vm_name" { print $2 }')"
collide_vm_b="$(geos_ci_runner_identity 1 1 "${collide_key_b}" | awk -F= '$1 == "vm_name" { print $2 }')"
(( ${#collide_vm_a} <= 64 )) || fail "truncated VM name (a) exceeds Azure's 64-character limit"
(( ${#collide_vm_b} <= 64 )) || fail "truncated VM name (b) exceeds Azure's 64-character limit"
[[ "${collide_vm_a}" != "${collide_vm_b}" ]] \
  || fail "long instance keys sharing a 64-char prefix collided to the same VM name"

# Punctuation-only instance key must fall back to the 'job' slug.
#
# Malformed state being modeled: an instance key containing no alphanumeric
# characters at all (here '!!!---@@@'). geos_ci_slugify strips every non
# [a-z0-9] run, which would leave an EMPTY slug and produce a trailing-dash VM
# name like 'geos-hbv4-100-1-' that is both ugly and an invalid leaf. The helper
# guards this by substituting the literal slug 'job' when the slugified result is
# empty, so the name remains well-formed and join-stable.
punct_identity="$(geos_ci_runner_identity 100 1 '!!!---@@@')"
grep -q '^vm_name=geos-hbv4-100-1-job$' <<< "${punct_identity}" \
  || fail "punctuation-only instance key should fall back to the 'job' slug"

if geos_ci_runner_identity abc 1 row >/dev/null 2>&1; then
  fail "non-numeric run id should be rejected"
fi

echo "runner name tests passed"
