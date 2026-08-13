#!/usr/bin/env bash

# Exercise the exact raw Azure VM response consumed after `az vm create`.
#
# The positive fixture preserves Azure CLI's case-sensitive `diskSizeGB` key.
# Negative mutations protect the fail-closed boundary and ensure diagnostics
# identify only mismatched fields without echoing the VM document.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
validator="${repo_root}/ci/azure/scripts/validate-created-hbv4-vm.sh"
fixture="${repo_root}/ci/azure/tests/fixtures/hbv4-vm-show.json"
vm_name='geos-hbv4-123456-1-openmpi-builder'
provider='openmpi'
role='builder'
instance_key='openmpi-builder'
runner_label='geos-hbv4-123456-1-openmpi-builder'
uami_id='/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-geos-ci-foundation-scus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-geos-runner-vm'
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail()
{
  echo "FAIL: $*" >&2
  exit 1
}

validate()
{
  bash "${validator}" \
    "${vm_name}" "${provider}" "${role}" "${instance_key}" \
    "${runner_label}" "${uami_id}"
}

assert_rejected()
{
  local jq_filter="$1"
  local expected_field="$2"

  if jq "${jq_filter}" "${fixture}" | validate \
      >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
    fail "malformed ${expected_field} contract unexpectedly passed"
  fi
  grep -Fq "${expected_field}" "${tmp_dir}/stderr" ||
    fail "${expected_field} rejection omitted its field name"
  if grep -Fq 'DO_NOT_LOG_VM_METADATA' "${tmp_dir}/stderr"; then
    fail "contract rejection exposed the raw Azure VM response"
  fi
}

validate < "${fixture}" || fail 'canonical Azure VM response was rejected'

# Regression for the live failure: Azure emits uppercase `GB`. A projection or
# validator using `diskSizeGb` must not make a realistic response appear valid.
assert_rejected \
  '.storageProfile.osDisk |= (del(.diskSizeGB) + {diskSizeGb: 128})' \
  'storageProfile.osDisk.diskSizeGB'

assert_rejected \
  '.storageProfile.imageReference.exactVersion = "24.04.unreviewed"' \
  'storageProfile.imageReference.version'

if printf '{' | validate >"${tmp_dir}/stdout" 2>"${tmp_dir}/stderr"; then
  fail 'malformed JSON unexpectedly passed'
fi
grep -Fq 'malformed VM contract JSON' "${tmp_dir}/stderr" ||
  fail 'malformed JSON did not produce a classified diagnostic'

echo 'created HBv4 VM contract fixtures passed.'
