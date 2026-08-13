#!/usr/bin/env bash

# Credential-free regression fixtures for the GitHub-registration half of the
# cleanup composite. The test executes the production action's embedded shell
# verbatim with a PATH-injected `gh` shim; no Azure or GitHub resource is used.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
action="${repo_root}/ci/azure/actions/cleanup-runner/action.yml"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ruby -ryaml -e '
  action = YAML.load_file(ARGV.fetch(0))
  step = action.fetch("runs").fetch("steps").find do |item|
    item["name"] == "Delete and verify exact runner registration"
  end
  abort "cleanup registration step is missing" unless step
  File.write(ARGV.fetch(1), step.fetch("run"))
' "${action}" "${test_root}/cleanup-registration.sh"
chmod +x "${test_root}/cleanup-registration.sh"

mkdir -p "${test_root}/bin"
cat > "${test_root}/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${test_root}/bin/sleep"

cat > "${test_root}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

endpoint="${!#}"
state="$(<"${MOCK_STATE_FILE}")"
if [[ "${state}" == present ]]; then
  runners="$(<"${MOCK_RUNNERS_FILE}")"
else
  runners='[]'
fi

if [[ " $* " == *' --method DELETE '* ]]; then
  case "${MOCK_SCENARIO}" in
    delete-404-denied)
      printf 'absent\n' > "${MOCK_STATE_FILE}"
      echo 'gh: Not Found (HTTP 404)' >&2
      exit 1
      ;;
    *)
      printf 'absent\n' > "${MOCK_STATE_FILE}"
      exit 0
      ;;
  esac
fi

case "${endpoint}" in
  *'actions/runners?per_page=100')
    count="$(jq -r 'length' <<< "${runners}")"
    jq -cn --argjson count "${count}" --argjson runners "${runners}" \
      '[{total_count:$count,runners:$runners}]'
    ;;
  *'actions/runners?per_page=1')
    if [[ "${MOCK_SCENARIO}" == delete-404-denied ]]; then
      echo 'gh: Resource not accessible by integration (HTTP 403)' >&2
      exit 1
    fi
    count="$(jq -r 'length' <<< "${runners}")"
    jq -cn --argjson count "${count}" --argjson runners "${runners}" \
      '{total_count:$count,runners:($runners[0:1])}'
    ;;
  *'/actions/runners/'*)
    runner_id="${endpoint##*/}"
    match="$(jq -c --argjson id "${runner_id}" '[.[] | select(.id == $id)]' <<< "${runners}")"
    if (( $(jq -r 'length' <<< "${match}") == 1 )); then
      jq -c '.[0]' <<< "${match}"
      exit 0
    fi
    echo 'gh: Not Found (HTTP 404)' >&2
    exit 1
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${test_root}/bin/gh"

canonical_label='geos-hbv4-31555791403-1-openmpi-builder'

runner_json() {
  local id="$1" name="$2" label="$3"
  jq -cn \
    --argjson id "${id}" \
    --arg name "${name}" \
    --arg label "${label}" \
    '{id:$id,name:$name,status:"offline",busy:false,labels:[{id:0,name:$label,type:"read-only"}]}'
}

run_fixture() {
  local scenario="$1" runners="$2" provision_id="${3:-}"
  local case_dir="${test_root}/${scenario}"
  mkdir -p "${case_dir}"
  printf '%s\n' "${runners}" > "${case_dir}/runners.json"
  printf 'present\n' > "${case_dir}/state"
  PATH="${test_root}/bin:${PATH}" \
  GH_TOKEN='fixture-runner-admin-token' \
  GITHUB_REPOSITORY='earthflow-sim/thirdPartyLibs' \
  GITHUB_RUN_ID='31555791403' \
  GITHUB_RUN_ATTEMPT='1' \
  PROVIDER='openmpi' \
  RUNNER_ROLE='builder' \
  PROVISION_RUNNER_ID="${provision_id}" \
  MOCK_SCENARIO="${scenario}" \
  MOCK_RUNNERS_FILE="${case_dir}/runners.json" \
  MOCK_STATE_FILE="${case_dir}/state" \
    bash "${test_root}/cleanup-registration.sh" \
      >"${case_dir}/stdout" 2>"${case_dir}/stderr"
}

legacy_runner="$(runner_json 22 'GitHub Actions 1000003390' "${canonical_label}")"
run_fixture legacy-protected-name "[${legacy_runner}]"
[[ "$(<"${test_root}/legacy-protected-name/state")" == absent ]] ||
  fail 'protected-name regression was not deleted by exact lifecycle label'

canonical_runner="$(runner_json 41 "${canonical_label}" "${canonical_label}")"
run_fixture canonical-name "[${canonical_runner}]" 41
[[ "$(<"${test_root}/canonical-name/state")" == absent ]] ||
  fail 'canonical exact-ID runner was not deleted'

duplicate_runner="$(runner_json 42 'GitHub Actions 1000003391' "${canonical_label}")"
if run_fixture duplicate-label "[${legacy_runner},${duplicate_runner}]"; then
  fail 'duplicate lifecycle label was not rejected as ambiguous'
fi
[[ "$(<"${test_root}/duplicate-label/state")" == present ]] ||
  fail 'ambiguous registration was mutated before rejection'

wrong_label='geos-hbv4-31555791403-1-mpich-builder'
wrong_runner="$(runner_json 43 'GitHub Actions 1000003392' "${wrong_label}")"
if run_fixture mismatched-provision-id "[${wrong_runner}]" 43; then
  fail 'supplied ID without the requested provider label was accepted'
fi
[[ "$(<"${test_root}/mismatched-provision-id/state")" == present ]] ||
  fail 'mismatched supplied ID was mutated before rejection'

missing_label="$(jq -cn --arg name "${canonical_label}" \
  '{id:44,name:$name,status:"offline",busy:false,labels:[]}')"
if run_fixture canonical-name-missing-label "[${missing_label}]"; then
  fail 'canonical name without its matching lifecycle label was accepted'
fi

malformed_runner='{"id":45,"name":"malformed","status":"offline","busy":false,"labels":null}'
if run_fixture malformed-inventory "[${malformed_runner}]"; then
  fail 'malformed runner inventory was accepted'
fi

if run_fixture delete-404-denied "[${legacy_runner}]"; then
  fail 'DELETE 404 was accepted without an independent collection-access proof'
fi

echo 'cleanup runner registration fixtures passed.'
