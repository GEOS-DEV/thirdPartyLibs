#!/usr/bin/env bash

# @file test-runner-bootstrap-probe.sh
#
# Credential-free fixtures for the guest bootstrap-state probe.
#
# Each case redirects the production probe into an isolated file tree and
# PATH-injected Azure guest-command shims. Positive fixtures model a progressing
# bootstrap; negative fixtures model one terminal or malformed state at a time.
# The assertions protect the precedence invariants: a validated status record
# takes precedence over cloud-final's coarser fallback; cloud-final failure takes
# precedence over a stale running record, including runner-agent handoff;
# terminal state is detected without waiting for GitHub's outer timeout;
# runner-process handoff and the bounded inconclusive state are distinct; and no
# credential-bearing guest source is ever read. Terminal machine markers must
# remain the final output line. Race fixtures also replace a running generation
# while cloud-final is inspected, proving the probe re-reads once and retains
# the EXIT trap's more precise phase and exit code.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
probe="${repo_root}/ci/azure/scripts/probe-runner-bootstrap.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail()
{
  echo "FAIL: $*" >&2
  exit 1
}

make_mock()
{
  local name="$1"
  shift
  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    printf "%s\n" "$@"
  } > "${tmp_dir}/bin/${name}"
  chmod +x "${tmp_dir}/bin/${name}"
}

mkdir -p \
  "${tmp_dir}/bin" \
  "${tmp_dir}/root/run" \
  "${tmp_dir}/root/var/log" \
  "${tmp_dir}/root/var/lib/waagent" \
  "${tmp_dir}/root/proc" \
  "${tmp_dir}/root/mnt/hbv4-local" \
  "${tmp_dir}/root/runner/_diag"

# These mock bodies are written verbatim into child scripts; their parameter
# expansions must occur when the probe invokes the child, not while the fixture
# creates it.
# shellcheck disable=SC2016
make_mock cloud-init \
  '[[ "${1:-}" == "status" ]] || exit 2' \
  'printf "%s\n" "${MOCK_CLOUD_INIT_STATUS:-status: running}"'
# shellcheck disable=SC2016
make_mock systemctl \
  'if [[ "${1:-}" == "is-failed" ]]; then' \
  '  if [[ "${MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK:-0}" == "1" ]]; then' \
  '    printf "version=1\nstate=failed\nphase=install-azure-cli\nexit_code=100\nupdated_at=2026-07-27T22:00:00Z\n" > "${MOCK_STATUS_FILE:?}"' \
  '  fi' \
  '  [[ "${MOCK_CLOUD_FINAL_FAILED:-0}" == "1" ]]' \
  '  exit' \
  'fi' \
  'if [[ "${1:-}" == "show" ]]; then echo "Id=docker.service"; echo "ActiveState=inactive"; echo "Result=success"; exit 0; fi' \
  'exit 1'
make_mock lsblk 'echo "nvme0n1 disk 1.7T Microsoft NVMe Direct Disk"'
make_mock findmnt 'exit 1'

printf "PersonalData=DO_NOT_READ_CUSTOM_DATA\n" \
  > "${tmp_dir}/root/var/lib/waagent/CustomData"
printf "DO_NOT_READ_RUNNER_DIAGNOSTICS\n" \
  > "${tmp_dir}/root/runner/_diag/Runner_test.log"
printf "ERROR: DO_NOT_READ_ARBITRARY_CLOUD_INIT_OUTPUT\n" \
  > "${tmp_dir}/root/var/log/cloud-init-output.log"
printf "unused\n" > "${tmp_dir}/root/proc/mdstat"
printf "safe bootstrap phase line\n" \
  > "${tmp_dir}/root/var/log/geos-runner-bootstrap.log"

write_status()
{
  local state="$1"
  local phase="$2"
  local exit_code="$3"
  {
    echo "version=1"
    echo "state=${state}"
    echo "phase=${phase}"
    echo "exit_code=${exit_code}"
    echo "updated_at=2026-07-27T22:00:00Z"
  } > "${tmp_dir}/root/run/geos-runner-bootstrap.status"
}

run_probe()
{
  PATH="${tmp_dir}/bin:${PATH}" \
  GEOS_BOOTSTRAP_PROBE_TEST_MODE=1 \
  GEOS_BOOTSTRAP_PROBE_TEST_ROOT="${tmp_dir}/root" \
  GEOS_BOOTSTRAP_PROBE_TEST_TIMEOUT_SECONDS=1 \
  GEOS_BOOTSTRAP_PROBE_TEST_POLL_SECONDS=1 \
  MOCK_CLOUD_INIT_STATUS="${MOCK_CLOUD_INIT_STATUS:-status: running}" \
  MOCK_CLOUD_FINAL_FAILED="${MOCK_CLOUD_FINAL_FAILED:-0}" \
  MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK="${MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK:-0}" \
  MOCK_STATUS_FILE="${tmp_dir}/root/run/geos-runner-bootstrap.status" \
    "${probe}"
}

assert_no_sensitive_source()
{
  local output="$1"
  [[ "${output}" != *"DO_NOT_READ_CUSTOM_DATA"* ]] ||
    fail "probe read Azure custom data"
  [[ "${output}" != *"DO_NOT_READ_RUNNER_DIAGNOSTICS"* ]] ||
    fail "probe read runner diagnostics"
  [[ "${output}" != *"DO_NOT_READ_ARBITRARY_CLOUD_INIT_OUTPUT"* ]] ||
    fail "probe read arbitrary cloud-init output"
}

write_status running configure-runner-storage 0
output="$(run_probe)"
[[ "${output}" == "GEOS_BOOTSTRAP_STATE=inconclusive last_state=running phase=configure-runner-storage updated_at=2026-07-27T22:00:00Z" ]] ||
  fail "bounded progressing status was not reported as inconclusive"

write_status running runner-agent 0
output="$(run_probe)"
[[ "${output}" == "GEOS_BOOTSTRAP_STATE=handoff phase=runner-agent updated_at=2026-07-27T22:00:00Z" ]] ||
  fail "live runner-process handoff was not reported exactly"

# A SIGKILL/OOM termination cannot run the bootstrap's EXIT trap, so the last
# valid running generation can outlive its custom-data supervisor. Once
# cloud-final is failed, that record is stale and must not consume the remainder
# of the paid VM's outer health-check allowance.
write_status running configure-runner-storage 0
MOCK_CLOUD_FINAL_FAILED=1
output="$(run_probe)"
unset MOCK_CLOUD_FINAL_FAILED
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=cloud-init phase=cloud-final exit_code=1" ]] ||
  fail "failed cloud-final did not override a stale running bootstrap phase"
[[ "${output}" != *"GEOS_BOOTSTRAP_STATE=handoff"* ]] ||
  fail "stale running bootstrap phase was reported as handoff"
[[ "${#output}" -lt 4096 ]] || fail "stale-running diagnostics exceeded Azure output headroom"
assert_no_sensitive_source "${output}"

# runner-agent proves only that the child survived its five-second launch guard.
# It is a valid handoff while cloud-final is active, but not after the supervisor
# has terminated and can no longer reap or report the child.
write_status running runner-agent 0
MOCK_CLOUD_FINAL_FAILED=1
output="$(run_probe)"
unset MOCK_CLOUD_FINAL_FAILED
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=cloud-init phase=cloud-final exit_code=1" ]] ||
  fail "failed cloud-final did not override stale runner-agent handoff"
[[ "${output}" != *"GEOS_BOOTSTRAP_STATE=handoff"* ]] ||
  fail "stale runner-agent state was reported as handoff"
assert_no_sensitive_source "${output}"

# Model the normal race in which the EXIT trap replaces a running generation
# while the probe observes cloud-final becoming failed. The re-read must prefer
# the precise status record rather than emitting cloud-final's generic marker.
write_status running install-azure-cli 0
MOCK_CLOUD_FINAL_FAILED=1
MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK=1
output="$(run_probe)"
unset MOCK_CLOUD_FINAL_FAILED MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=install-azure-cli exit_code=100" ]] ||
  fail "terminal status published over a running record did not win the cloud-final race"
assert_no_sensitive_source "${output}"

write_status failed configure-runner-storage 1
output="$(run_probe)"
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=configure-runner-storage exit_code=1" ]] ||
  fail "failed status did not end with the terminal marker"
[[ "${#output}" -lt 4096 ]] || fail "terminal diagnostics exceeded Azure output headroom"
assert_no_sensitive_source "${output}"

# Once bootstrap has published a valid terminal record, cloud-final may also be
# failed but is no longer authoritative. Preserve the bootstrap's precise phase
# and exit code so the control job reports the actionable guest failure.
write_status failed install-azure-cli 100
MOCK_CLOUD_FINAL_FAILED=1
output="$(run_probe)"
unset MOCK_CLOUD_FINAL_FAILED
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=install-azure-cli exit_code=100" ]] ||
  fail "cloud-final failure masked the valid bootstrap terminal status"
assert_no_sensitive_source "${output}"

write_status exited runner-agent 0
output="$(run_probe)"
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=runner-agent exit_code=0" ]] ||
  fail "early zero-status runner exit was not terminal"

write_status running runner-agent 9
output="$(run_probe)"
[[ "$(tail -n 1 <<< "${output}")" == *"phase=invalid-running-exit-code exit_code=1" ]] ||
  fail "contradictory running state was not rejected"

printf "version=1\nstate=running\n" \
  > "${tmp_dir}/root/run/geos-runner-bootstrap.status"
output="$(run_probe)"
[[ "$(tail -n 1 <<< "${output}")" == *"phase=invalid-record exit_code=1" ]] ||
  fail "truncated status record was not rejected"

write_status "DO_NOT_ECHO_MALFORMED_STATUS" runner-agent 0
output="$(run_probe)"
[[ "$(tail -n 1 <<< "${output}")" == *"phase=invalid-value exit_code=1" ]] ||
  fail "unallowlisted status value was not rejected"
[[ "${output}" != *"DO_NOT_ECHO_MALFORMED_STATUS"* ]] ||
  fail "probe echoed malformed status-file content"

rm -f "${tmp_dir}/root/run/geos-runner-bootstrap.status"
output="$(run_probe)"
[[ "${output}" == "GEOS_BOOTSTRAP_STATE=inconclusive last_state=missing" ]] ||
  fail "bounded missing status did not preserve the slow-boot path"

# Model the status file appearing while the fallback checks cloud-final. The
# probe must restart status parsing instead of emitting the coarser cloud-final
# marker observed in the original Azure CLI provisioning failure.
MOCK_CLOUD_FINAL_FAILED=1
MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK=1
output="$(run_probe)"
unset MOCK_CLOUD_FINAL_FAILED MOCK_CREATE_STATUS_DURING_CLOUD_FINAL_CHECK
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=install-azure-cli exit_code=100" ]] ||
  fail "status published during cloud-final inspection was not preferred"
assert_no_sensitive_source "${output}"

rm -f "${tmp_dir}/root/run/geos-runner-bootstrap.status"
MOCK_CLOUD_INIT_STATUS="status: error"
output="$(run_probe)"
unset MOCK_CLOUD_INIT_STATUS
[[ "$(tail -n 1 <<< "${output}")" == \
   "GEOS_BOOTSTRAP_STATE=terminal source=cloud-init phase=cloud-final exit_code=1" ]] ||
  fail "cloud-init failure before status creation was not terminal"
assert_no_sensitive_source "${output}"

echo "runner bootstrap probe fixtures passed."
