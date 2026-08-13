#!/usr/bin/env bash

# @file probe-runner-bootstrap.sh
#
# Credential-free guest probe for an allocated Azure runner VM.
#
# The provisioning control job sends this reviewed script through Azure Run
# Command while GitHub still reports the JIT runner offline. It does not decide
# success: GitHub's online runner record plus the unique label remains
# authoritative. Its only purpose is to distinguish a bootstrap that is still
# progressing from one that has already terminated, so the control job can stop
# billing promptly and enter unconditional cleanup.
#
# Implementation workflow (single entry point: main):
#   main()
#     - read each atomically replaced status generation through one file
#       descriptor and validate its fixed schema as data, never by sourcing it;
#     - give a validated terminal status precedence over cloud-final failure,
#       then give cloud-final failure precedence over a running
#       handoff/inconclusive marker. A failed cloud-final causes exactly one
#       status re-read so an EXIT-trap record published during the service check
#       retains its precise phase and exit code;
#     - return as soon as bootstrap terminates or hands control to a live runner
#       process, while a bounded inconclusive result preserves the caller's
#       original slow-boot allowance;
#     - call emit_terminal_diagnostics() for failed, exited, or malformed state,
#       then emit the machine-readable terminal marker last so Azure's 4-KiB
#       returned-output limit cannot truncate it.
#   emit_terminal_diagnostics()
#     - collect only validated status fields, non-secret structured
#       storage/service state, and the reviewed bootstrap phase log;
#     - cap the diagnostic prefix to 3.2 KiB. Never inspect customData,
#       arbitrary cloud-init output, environment variables, process arguments,
#       runner `_diag`, or shell history because those sources can contain the
#       one-time JIT credential.
#
# The explicit test-mode root redirects file reads into a fixture directory.
# Production ignores every path override unless GEOS_BOOTSTRAP_PROBE_TEST_MODE
# is exactly 1.

set -u

if [[ "${GEOS_BOOTSTRAP_PROBE_TEST_MODE:-0}" == "1" ]]; then
  PROBE_ROOT="${GEOS_BOOTSTRAP_PROBE_TEST_ROOT:?test root is required}"
  STATUS_FILE="${PROBE_ROOT}/run/geos-runner-bootstrap.status"
  BOOT_LOG="${PROBE_ROOT}/var/log/geos-runner-bootstrap.log"
  MDSTAT_PATH="${PROBE_ROOT}/proc/mdstat"
  MOUNT_TARGET="${PROBE_ROOT}/mnt/hbv4-local"
  MONITOR_SECONDS="${GEOS_BOOTSTRAP_PROBE_TEST_TIMEOUT_SECONDS:-1}"
  POLL_SECONDS="${GEOS_BOOTSTRAP_PROBE_TEST_POLL_SECONDS:-1}"
else
  STATUS_FILE="/run/geos-runner-bootstrap.status"
  BOOT_LOG="/var/log/geos-runner-bootstrap.log"
  MDSTAT_PATH="/proc/mdstat"
  MOUNT_TARGET="/mnt/hbv4-local"
  MONITOR_SECONDS=300
  POLL_SECONDS=5
fi
readonly STATUS_FILE BOOT_LOG MDSTAT_PATH MOUNT_TARGET
readonly MONITOR_SECONDS POLL_SECONDS

[[ "${MONITOR_SECONDS}" =~ ^[1-9][0-9]*$ ]] ||
  {
    echo "GEOS_BOOTSTRAP_STATE=terminal source=probe phase=invalid-monitor-timeout exit_code=1"
    exit 0
  }
[[ "${POLL_SECONDS}" =~ ^[1-9][0-9]*$ ]] ||
  {
    echo "GEOS_BOOTSTRAP_STATE=terminal source=probe phase=invalid-poll-interval exit_code=1"
    exit 0
  }

# This string is populated only from fields that passed the fixed-schema
# allowlists below. In particular, malformed status-file contents are never
# copied into workflow logs.
STATUS_DIAGNOSTIC="bootstrap status was unavailable or invalid"
STATUS_RECORD_KIND="missing"
STATUS_INVALID_REASON="invalid-record"
STATUS_VERSION=""
STATUS_STATE=""
STATUS_PHASE=""
STATUS_EXIT_CODE=""
STATUS_UPDATED_AT=""

# emit_terminal_diagnostics: return a bounded, credential-free failure report.
#
# Entry state: a terminal condition has already been proved. Exit state: at
# most the last 3.2 KiB of the approved sources has been written. The caller
# must emit its terminal marker after this function returns.
emit_terminal_diagnostics()
{
  local diagnostic_file
  diagnostic_file="$(mktemp)"
  {
    echo "--- validated bootstrap status (credential-free) ---"
    printf "%s\n" "${STATUS_DIAGNOSTIC}"

    echo "--- non-secret guest storage state ---"
    lsblk -e 7 -o NAME,KNAME,PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL \
      2>/dev/null || true
    cat "${MDSTAT_PATH}" 2>/dev/null || true
    findmnt --target "${MOUNT_TARGET}" 2>/dev/null || true
    systemctl show cloud-final.service docker.service \
      --property=Id \
      --property=ActiveState \
      --property=SubState \
      --property=Result \
      --property=ExecMainCode \
      --property=ExecMainStatus \
      2>/dev/null || true

    echo "--- GEOS bootstrap phase log (credential-free) ---"
    if [[ -r "${BOOT_LOG}" ]]; then
      tail -n 80 "${BOOT_LOG}"
    else
      echo "${BOOT_LOG} is unavailable"
    fi
  } > "${diagnostic_file}"
  tail -c 3200 "${diagnostic_file}"
  rm -f "${diagnostic_file}"
}

# read_status_record: capture and validate one complete status generation.
#
# Atomic replacement guarantees that one open descriptor continues reading the
# same inode even if the writer publishes a newer phase concurrently. The
# single-stream parser therefore cannot combine fields from different
# generations. It accepts the writer's five keys in any order, rejects
# duplicate/missing/extra fields without logging their contents, and exposes
# values only after every fixed allowlist has passed. On return,
# STATUS_RECORD_KIND is exactly missing, invalid, running, failed, or exited;
# STATUS_INVALID_REASON retains the sanitized schema/value distinction when the
# classification is invalid.
read_status_record()
{
  local line
  local version_count=0
  local state_count=0
  local phase_count=0
  local exit_code_count=0
  local updated_at_count=0
  local -a status_lines=()

  STATUS_DIAGNOSTIC="bootstrap status was unavailable or invalid"
  STATUS_RECORD_KIND="missing"
  STATUS_INVALID_REASON="invalid-record"
  STATUS_VERSION=""
  STATUS_STATE=""
  STATUS_PHASE=""
  STATUS_EXIT_CODE=""
  STATUS_UPDATED_AT=""

  [[ -r "${STATUS_FILE}" ]] || return 0
  if ! while IFS= read -r line || [[ -n "${line}" ]]; do
    status_lines+=("${line}")
  done < "${STATUS_FILE}"; then
    return 0
  fi

  if (( ${#status_lines[@]} != 5 )); then
    STATUS_RECORD_KIND="invalid"
    return 0
  fi

  for line in "${status_lines[@]}"; do
    case "${line}" in
      version=*)
        version_count=$(( version_count + 1 ))
        STATUS_VERSION="${line#version=}"
        ;;
      state=*)
        state_count=$(( state_count + 1 ))
        STATUS_STATE="${line#state=}"
        ;;
      phase=*)
        phase_count=$(( phase_count + 1 ))
        STATUS_PHASE="${line#phase=}"
        ;;
      exit_code=*)
        exit_code_count=$(( exit_code_count + 1 ))
        STATUS_EXIT_CODE="${line#exit_code=}"
        ;;
      updated_at=*)
        updated_at_count=$(( updated_at_count + 1 ))
        STATUS_UPDATED_AT="${line#updated_at=}"
        ;;
      *)
        STATUS_RECORD_KIND="invalid"
        return 0
        ;;
    esac
  done

  if (( version_count != 1 ||
        state_count != 1 ||
        phase_count != 1 ||
        exit_code_count != 1 ||
        updated_at_count != 1 )); then
    STATUS_RECORD_KIND="invalid"
    return 0
  fi

  if [[ "${STATUS_VERSION}" != "1" ]] ||
     ! printf "%s\n" "${STATUS_STATE}" | grep -Eq '^(running|failed|exited)$' ||
     ! printf "%s\n" "${STATUS_PHASE}" | grep -Eq '^[a-z0-9-]+$' ||
     ! printf "%s\n" "${STATUS_EXIT_CODE}" | grep -Eq '^[0-9]+$' ||
     ! printf "%s\n" "${STATUS_UPDATED_AT}" |
       grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    STATUS_RECORD_KIND="invalid"
    STATUS_INVALID_REASON="invalid-value"
    return 0
  fi

  STATUS_RECORD_KIND="${STATUS_STATE}"
  STATUS_DIAGNOSTIC="version=${STATUS_VERSION} state=${STATUS_STATE} phase=${STATUS_PHASE} exit_code=${STATUS_EXIT_CODE} updated_at=${STATUS_UPDATED_AT}"
}

# emit_status_terminal_if_present: apply status-only terminal precedence.
#
# Valid terminal states preserve the bootstrap's precise phase and exit code.
# Malformed records and contradictory state/exit-code pairs remain sanitized
# status-file failures. A return of one means the current record is either
# absent or validly running and therefore requires the cloud-final decision.
emit_status_terminal_if_present()
{
  case "${STATUS_RECORD_KIND}" in
    invalid)
      emit_terminal_diagnostics
      printf "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=%s exit_code=1\n" \
        "${STATUS_INVALID_REASON}"
      return 0
      ;;
    missing)
      return 1
      ;;
  esac

  case "${STATUS_RECORD_KIND}" in
    running)
      if [[ "${STATUS_EXIT_CODE}" != "0" ]]; then
        emit_terminal_diagnostics
        echo "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=invalid-running-exit-code exit_code=1"
        return 0
      fi
      return 1
      ;;
    failed)
      if [[ "${STATUS_EXIT_CODE}" == "0" ]]; then
        emit_terminal_diagnostics
        echo "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=invalid-failed-exit-code exit_code=1"
        return 0
      fi
      emit_terminal_diagnostics
      printf "\nGEOS_BOOTSTRAP_STATE=terminal source=status-file phase=%s exit_code=%s\n" \
        "${STATUS_PHASE}" "${STATUS_EXIT_CODE}"
      return 0
      ;;
    exited)
      if [[ "${STATUS_EXIT_CODE}" != "0" ]]; then
        emit_terminal_diagnostics
        echo "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=invalid-exited-exit-code exit_code=1"
        return 0
      fi
      emit_terminal_diagnostics
      printf "\nGEOS_BOOTSTRAP_STATE=terminal source=status-file phase=%s exit_code=0\n" \
        "${STATUS_PHASE}"
      return 0
      ;;
  esac

  emit_terminal_diagnostics
  echo "GEOS_BOOTSTRAP_STATE=terminal source=status-file phase=invalid-state exit_code=1"
  return 0
}

# cloud_final_failed: consume only cloud-init's fixed terminal classification.
#
# A running bootstrap keeps cloud-final active, so a failed service means the
# custom-data supervisor has terminated. The caller re-reads status after this
# result to preserve any precise EXIT-trap record published during these checks.
cloud_final_failed()
{
  local cloud_init_summary
  cloud_init_summary="$(cloud-init status 2>/dev/null || true)"
  systemctl is-failed --quiet cloud-final.service 2>/dev/null ||
    printf "%s\n" "${cloud_init_summary}" |
      grep -Eq '^status:[[:space:]]*error([[:space:]]|$)'
}

main()
{
  local deadline
  local last_running_marker="GEOS_BOOTSTRAP_STATE=inconclusive last_state=missing"

  deadline=$(( SECONDS + MONITOR_SECONDS ))
  while true; do
    read_status_record
    if emit_status_terminal_if_present; then
      return 0
    fi

    if [[ "${STATUS_RECORD_KIND}" == "running" ]]; then
      last_running_marker="GEOS_BOOTSTRAP_STATE=inconclusive last_state=running phase=${STATUS_PHASE} updated_at=${STATUS_UPDATED_AT}"
    fi

    if cloud_final_failed; then
      # The EXIT trap can publish a precise terminal record while cloud-final is
      # transitioning to failed. Re-read exactly once and prefer that record;
      # an unchanged running record is stale because its supervisor has ended.
      read_status_record
      if emit_status_terminal_if_present; then
        return 0
      fi
      if [[ "${STATUS_RECORD_KIND}" == "running" ]]; then
        STATUS_DIAGNOSTIC="${STATUS_DIAGNOSTIC}; cloud-final reported a terminal failure while this running record remained"
      else
        STATUS_DIAGNOSTIC="bootstrap status unavailable; cloud-final reported a terminal failure"
      fi
      emit_terminal_diagnostics
      echo "GEOS_BOOTSTRAP_STATE=terminal source=cloud-init phase=cloud-final exit_code=1"
      return 0
    fi

    # runner-bootstrap.sh publishes this phase only after the runner child has
    # survived its launch guard. Handoff is valid only while cloud-final remains
    # active; a failed supervisor outranks even this otherwise-live child state.
    if [[ "${STATUS_RECORD_KIND}" == "running" &&
          "${STATUS_PHASE}" == "runner-agent" ]]; then
      printf "GEOS_BOOTSTRAP_STATE=handoff phase=%s updated_at=%s\n" \
        "${STATUS_PHASE}" "${STATUS_UPDATED_AT}"
      return 0
    fi

    if (( SECONDS >= deadline )); then
      printf "%s\n" "${last_running_marker}"
      return 0
    fi
    sleep "${POLL_SECONDS}"
  done
}

main "$@"
