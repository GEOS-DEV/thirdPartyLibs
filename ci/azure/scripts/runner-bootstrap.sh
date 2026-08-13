#!/usr/bin/env bash

# @file runner-bootstrap.sh
#
# First-boot bootstrap for a GEOS Azure ephemeral CI runner VM.
#
# KEEP THIS FILE ASCII-ONLY. It is passed verbatim as `az vm create --custom-data`,
# which encodes the payload as latin-1 and FAILS on any non-ASCII byte (e.g. an
# em-dash or section sign): "'latin-1' codec can't encode character ...".
#
# This script is the VM `--custom-data` payload passed by the `provision` job of
# the in-workflow trio (.github/workflows/azure-job.yml, see
# plans/azure-ephemeral-runners.md sec 3, sec 5.5, sec 9). On the
# caller-selected Ubuntu Marketplace image (a GEOS-specific pre-baked image is
# deferred -- plan sec 6/sec 10 M1a), the Azure VM agent runs this once, as
# root, via cloud-init's "script" custom-data path on first boot. Its job is to
# turn the VM into a single-use,
# just-in-time (JIT) GitHub Actions runner that pulls the GEOS build container
# from the foundation ACR, runs exactly ONE CI job, and exits.
#
# Why this lives in a committed file rather than being generated inline: the
# bootstrap is security-sensitive shell that runs as root on a VM that holds the
# runner-VM managed identity (reachable via IMDS by the CI job's own code), so it
# must be reviewable, shellcheck-clean, and version-controlled. The `provision`
# job templates per-run values into a COPY of this file before handing it to
# `az vm create` (see the "Templated placeholders" contract below); the committed
# file itself contains only inert placeholder tokens and never a real credential.
#
# Templated placeholders (substituted by the provision job, never committed live):
#   RUNNER_ENCODED_JITCONFIG      -- the base64 `encoded_jit_config` returned by
#                                    GitHub's generate-jitconfig endpoint. This is
#                                    a ONE-TIME runner credential (see the
#                                    sensitivity note below). Required.
#   RUNNER_VERSION                -- the pinned actions/runner version, e.g.
#                                    2.335.1. Pinned + SHA-verified (plan gotcha).
#   RUNNER_TARBALL_SHA256         -- the expected SHA-256 of the linux-x64 runner
#                                    tarball for RUNNER_VERSION. Verified
#                                    before the tarball is unpacked/executed.
#   ACR_NAME                      -- the ACR registry NAME (not login server),
#                                    e.g. geoscisc2053650e, for `az acr login`.
#   RUNNER_VM_UAMI_CLIENT_ID      -- the client id of the user-assigned managed
#                                    identity id-geos-runner-vm attached to this
#                                    VM. REQUIRED for `az login --identity` because
#                                    a bare --identity resolves to the system
#                                    identity (which this VM does not have) and
#                                    fails (plan sec 8.3 gotcha).
#   RUNNER_STORAGE_PROFILE        -- "none" for the historical OS-disk layout or
#                                    "hbv4-nvme-raid0" for the reviewed HB176
#                                    two-device local-NVMe layout.
#   STORAGE_HELPER_GZIP_BASE64    -- gzip-compressed, base64-encoded bytes of the
#                                    committed setup-hbv4-local-nvme.sh helper.
#   STORAGE_HELPER_SHA256         -- SHA-256 of the uncompressed helper. The VM
#                                    verifies this before installing it as root.
#   HOST_VALIDATOR_*, CONTAINER_VALIDATOR_*, PARALLEL_HDF5_SOURCE_*
#                                  -- independently hashed gzip/base64 payloads
#                                    from the trusted default-branch control SHA.
#
# Implementation workflow (single entry point: main, run once at first boot):
#   main()
#     log()/die()                  -- timestamped logging to a boot log file +
#                                     stdout (captured by cloud-init / serial
#                                     console for post-mortem, plan sec 9.5).
#     set_bootstrap_phase()        -- atomically publish a credential-free
#                                     phase/state record for the control-plane
#                                     post-boot health check.
#     record_bootstrap_exit()      -- EXIT trap that converts any early shell
#                                     termination into a sanitized terminal
#                                     state without recording the failed command,
#                                     environment, arguments, or JIT credential.
#     require_placeholders()       -- fail fast if any @@...@@ token survived (a
#                                     templating bug); refusing to proceed avoids
#                                     a half-configured VM that bills while never
#                                     coming online (the runner would then only be
#                                     reaped by the janitor's hard max-age cap).
#     install_base_packages()      -- apt-get the host tooling the runner agent +
#                                     the GEOS docker-run build model need (curl,
#                                     jq, git, git-lfs, ca-certs). The GEOS
#                                     TOOLCHAIN itself lives in the container
#                                     image; only this thin host layer is here.
#     install_storage_helper()     -- decode the embedded RAID helper, verify its
#                                     independent SHA-256, and install it as root.
#     configure_runner_storage()  -- for the HBv4 profile only, synchronously
#                                     create/mount the reviewed RAID-0 array,
#                                     place runner state on that mount, and create
#                                     the dedicated scratch directory that the
#                                     workload binds over container /tmp.
#     install_docker()             -- install Docker Engine from Docker's apt repo
#                                     and enable the daemon, because the workload
#                                     job runs the build as `docker run` on the
#                                     host (plan sec 2/sec 3: not a job-level container,
#                                     so ARC/DinD is rejected).
#     ensure_azure_cli()           -- ensure `az` + the azcopy binary exist (Blob
#                                     artifact/baseline transfer, plan sec 9.3). The
#                                     CLI may already be present on some images;
#                                     installation is idempotent.
#     azure_login_and_acr_login()  -- `az login --identity --client-id <UAMI>`
#                                     then `az acr login --name <ACR>` so the
#                                     subsequent in-job `docker pull` from ACR is
#                                     authenticated by the VM's AcrPull role
#                                     without any stored registry secret
#                                     (plan sec 8.1: AcrPull RBAC alone does not
#                                     authenticate docker; an `az acr login` is
#                                     required, best done here at boot).
#     install_runner_agent()       -- download the PINNED runner tarball, VERIFY
#                                     its SHA-256 before touching it, unpack it as
#                                     a non-root runner user, and install the
#                                     agent's OS dependencies.
#     validate_runner_storage()   -- immediately before the foreground runner,
#                                     prove the HB mount/RAID/XFS/capacity,
#                                     runner-home, and container-scratch
#                                     invariants, including RAID-backed Docker.
#     run_runner_ephemeral()       -- start the agent with `--jitconfig` so it
#                                     registers JIT, accepts exactly one job, and
#                                     exits (ephemeral). No registration token,
#                                     no long-lived runner.
#
# Sensitivity of the encoded jitconfig (accepted, documented):
#   The base64 jitconfig embedded here is a one-time credential that lets this VM
#   register as the named JIT runner and receive one job. Because it is delivered
#   as custom-data, it is readable from inside the VM via IMDS
#   (http://169.254.169.254/metadata/instance/compute/customData) by anything that
#   can reach IMDS, including the CI job's own code. That exposure is ACCEPTED for
#   a SINGLE-JOB EPHEMERAL VM: the credential is consumed on first registration,
#   the runner is removed from GitHub once it accepts its one job (JIT
#   auto-removal), the `cleanup` job deletes both the VM and the registration, and
#   the janitor is the backstop. It is NOT a standing secret and grants only the
#   ability to be this one runner. Do not reuse this VM for a second job, and do
#   not widen the runner-VM identity beyond AcrPull + container-scoped Blob.

set -Eeuo pipefail

# Per-run values templated in by the provision job. Kept as shell variables (not
# scattered inline) so require_placeholders() can validate them in one place and
# so a future maintainer sees the full substitution contract at the top of the
# executable body. The committed values are inert @@...@@ tokens.
RUNNER_ENCODED_JITCONFIG="@@RUNNER_ENCODED_JITCONFIG@@"
RUNNER_VERSION="@@RUNNER_VERSION@@"
RUNNER_TARBALL_SHA256="@@RUNNER_TARBALL_SHA256@@"
ACR_NAME="@@ACR_NAME@@"
RUNNER_VM_UAMI_CLIENT_ID="@@RUNNER_VM_UAMI_CLIENT_ID@@"
RUNNER_STORAGE_PROFILE="@@RUNNER_STORAGE_PROFILE@@"
STORAGE_HELPER_GZIP_BASE64="@@STORAGE_HELPER_GZIP_BASE64@@"
STORAGE_HELPER_SHA256="@@STORAGE_HELPER_SHA256@@"
HOST_VALIDATOR_GZIP_BASE64="@@HOST_VALIDATOR_GZIP_BASE64@@"
HOST_VALIDATOR_SHA256="@@HOST_VALIDATOR_SHA256@@"
CONTAINER_VALIDATOR_GZIP_BASE64="@@CONTAINER_VALIDATOR_GZIP_BASE64@@"
CONTAINER_VALIDATOR_SHA256="@@CONTAINER_VALIDATOR_SHA256@@"
PARALLEL_HDF5_SOURCE_GZIP_BASE64="@@PARALLEL_HDF5_SOURCE_GZIP_BASE64@@"
PARALLEL_HDF5_SOURCE_SHA256="@@PARALLEL_HDF5_SOURCE_SHA256@@"

# Non-root account the runner agent runs under. The agent refuses to run its
# service as root; jobs that need root use sudo/docker. The default preserves
# the historical path. The HBv4 profile changes this to the mounted local NVMe
# before any runner files are installed, while JIT work_folder remains the
# relative "_work" under this directory.
RUNNER_USER="ghrunner"
RUNNER_HOME="/opt/actions-runner"
HBV4_MOUNT_ROOT="/mnt/hbv4-local"
HBV4_MD_DEVICE="/dev/md/hbv4-local"
HBV4_CONTAINER_TMP="${HBV4_MOUNT_ROOT}/container-tmp"
STORAGE_HELPER_PATH="/usr/local/sbin/setup-hbv4-local-nvme"
TRUSTED_VALIDATION_ROOT="/opt/geos-ci/scripts/hbv4"

# Boot log path. cloud-init also captures stdout/stderr, but an explicit log file
# under /var/log is the artifact the sec 9.5 finalizer would upload to the
# runner-logs Blob container before teardown.
BOOT_LOG="/var/log/geos-runner-bootstrap.log"

# The provisioning control plane cannot infer a terminal custom-data failure
# from GitHub's pre-created offline JIT record. This root-owned, atomically
# replaced status file exposes only controlled state, phase, exit code, and UTC
# time. It never contains a command, argument, environment value, custom-data
# payload, or credential. Azure Run Command reads it as data (never `source`s
# it) while the VM is still isolated from repository workload code.
BOOTSTRAP_STATUS_FILE="/run/geos-runner-bootstrap.status"
BOOTSTRAP_PHASE="initializing"

# AzCopy is ensured on the selected host image at boot because artifact and
# baseline transfers use it directly from the runner host. The version and
# release tarball hashes are fixed here so the root bootstrap never unpacks a
# mutable redirect target. When this is bumped, update both architecture hashes
# from the official release metadata and keep the live drill on the cheap SKU
# until the first boot path has been revalidated.
AZCOPY_VERSION="10.32.4"
AZCOPY_LINUX_AMD64_SHA256="8f859a0dbbc117660c249fb3569694fc8a0f33b68701f5b2b92ccc001ee50784"
AZCOPY_LINUX_ARM64_SHA256="c614777841277ab2c53eecc9ecca5704fd697375c2ffaf4a407058891f00f673"

log() {
  # Timestamped so the serial-console/boot-diagnostics view (plan sec 9.5) shows how
  # long each phase took on a cold boot -- the latency the custom-image bake is
  # meant to cut.
  printf '%s [geos-bootstrap] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${BOOT_LOG}"
}

die() {
  printf '%s [geos-bootstrap] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${BOOT_LOG}" >&2
  exit 1
}

# download_with_retries: fetch one public bootstrap artifact with bounded retry.
#
# The runner starts from a clean Marketplace VM, so Docker/Azure signing keys and
# the pinned GitHub release assets cannot come from a warm local cache. Treat
# transport failures and transient HTTP responses as retryable, but keep each
# request and the complete retry sequence bounded so provisioning cannot leave a
# paid VM waiting forever. Callers still SHA-verify executable release archives
# before unpacking them.
download_with_retries() {
  local url="$1"
  local output="$2"
  local description="$3"
  local attempt

  for attempt in 1 2 3 4 5; do
    rm -f "${output}"
    log "downloading ${description} (attempt ${attempt}/5)"
    if curl --fail --silent --show-error --location \
      --connect-timeout 20 \
      --max-time 180 \
      --output "${output}" \
      "${url}"; then
      return 0
    fi

    if (( attempt < 5 )); then
      log "download of ${description} failed; retrying after bounded backoff"
      sleep $(( attempt * 5 ))
    fi
  done

  die "failed to download ${description} after 5 attempts"
}

# write_bootstrap_status: atomically publish one sanitized lifecycle record.
#
# Entry state: callers supply only controlled literal states/phases and the
# shell's numeric exit status. Exit state: readers see either the complete old
# record or the complete new record; a partial write can never be mistaken for
# a valid running bootstrap. The explicit allowlists keep future callers from
# turning this diagnostic channel into an accidental command/environment log.
write_bootstrap_status() {
  local state="$1"
  local phase="$2"
  local exit_code="$3"
  local status_tmp

  case "${state}" in
    running|failed|exited)
      ;;
    *)
      return 1
      ;;
  esac
  [[ "${phase}" =~ ^[a-z0-9-]+$ ]] || return 1
  [[ "${exit_code}" =~ ^[0-9]+$ ]] || return 1

  status_tmp="$(mktemp "${BOOTSTRAP_STATUS_FILE}.XXXXXX")"
  {
    echo "version=1"
    echo "state=${state}"
    echo "phase=${phase}"
    echo "exit_code=${exit_code}"
    echo "updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${status_tmp}"
  chmod 0644 "${status_tmp}"
  mv -f "${status_tmp}" "${BOOTSTRAP_STATUS_FILE}"
}

# set_bootstrap_phase: expose the next deterministic bootstrap operation.
#
# The phase is written before its operation starts, so an EXIT caused by that
# operation retains the exact safe phase name. The corresponding function logs
# its ordinary progress separately; this record exists for machine-readable
# control-plane failure detection rather than verbose tracing.
set_bootstrap_phase() {
  BOOTSTRAP_PHASE="$1"
  write_bootstrap_status running "${BOOTSTRAP_PHASE}" 0
}

# record_bootstrap_exit: preserve the terminal result without leaking context.
#
# Bash passes the status of the command that ended main through `$?`. Disable
# the trap before doing any reporting so a diagnostic failure cannot recurse.
# A zero exit means the foreground JIT runner has already exited; while the
# provisioning health check is still waiting, both `failed` and `exited` are
# terminal because no agent remains that could become online.
record_bootstrap_exit() {
  local exit_code="$?"
  local terminal_state="failed"

  trap - EXIT
  set +e
  if (( exit_code == 0 )); then
    terminal_state="exited"
  fi
  if ! write_bootstrap_status "${terminal_state}" "${BOOTSTRAP_PHASE}" "${exit_code}"; then
    printf '%s [geos-bootstrap] ERROR: unable to publish terminal bootstrap status\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${BOOT_LOG}" >&2
  fi
  printf '%s [geos-bootstrap] terminal state=%s phase=%s exit_code=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${terminal_state}" "${BOOTSTRAP_PHASE}" "${exit_code}" |
    tee -a "${BOOT_LOG}"
  exit "${exit_code}"
}

# require_placeholders: assert every templated value was substituted.
#
# Entry state: the provision job has (or should have) replaced every @@...@@
# token. If any token survives, templating failed and proceeding would create a
# VM that bills but never becomes a usable runner (e.g. an unsubstituted
# jitconfig cannot register), leaving the post-boot health check to time out and
# the cleanup/janitor to reclaim it. Failing loudly here makes the misconfig
# obvious in the boot log instead of manifesting as a mysterious health-check
# timeout. We grep for the literal sentinel pattern rather than checking each
# variable so a newly added placeholder cannot be forgotten.
require_placeholders() {
  local v
  for v in \
    "${RUNNER_ENCODED_JITCONFIG}" \
    "${RUNNER_VERSION}" \
    "${RUNNER_TARBALL_SHA256}" \
    "${ACR_NAME}" \
    "${RUNNER_VM_UAMI_CLIENT_ID}" \
    "${RUNNER_STORAGE_PROFILE}" \
    "${STORAGE_HELPER_GZIP_BASE64}" \
    "${STORAGE_HELPER_SHA256}" \
    "${HOST_VALIDATOR_GZIP_BASE64}" \
    "${HOST_VALIDATOR_SHA256}" \
    "${CONTAINER_VALIDATOR_GZIP_BASE64}" \
    "${CONTAINER_VALIDATOR_SHA256}" \
    "${PARALLEL_HDF5_SOURCE_GZIP_BASE64}" \
    "${PARALLEL_HDF5_SOURCE_SHA256}"; do
    case "${v}" in
      *@@*@@*)
        die "unsubstituted template placeholder detected ('${v}'); the provision job did not template runner-bootstrap.sh correctly"
        ;;
    esac
  done

  case "${RUNNER_STORAGE_PROFILE}" in
    none|hbv4-nvme-raid0)
      ;;
    *)
      die "unsupported RUNNER_STORAGE_PROFILE '${RUNNER_STORAGE_PROFILE}'"
      ;;
  esac
  local digest
  for digest in \
    "${STORAGE_HELPER_SHA256}" \
    "${HOST_VALIDATOR_SHA256}" \
    "${CONTAINER_VALIDATOR_SHA256}" \
    "${PARALLEL_HDF5_SOURCE_SHA256}"; do
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] \
      || die "embedded payload SHA-256 is not a lowercase 64-character digest"
  done
}

# install_base_packages: install the thin host tooling layer.
#
# The GEOS build runs inside the container image (which carries the compiler/TPL
# toolchain), so every host needs the ordinary runner/network tools. Only the
# HBv4 profile adds mdadm, XFS, NVMe, and mount-inspection packages; profile
# "none" retains the exact historical package set and performs no storage-helper
# decode, install, discovery, or mutation. Idempotent: apt-get install is safe to
# re-run, and on a pre-baked image these packages are already present.
install_base_packages() {
  log "installing base host packages"
  export DEBIAN_FRONTEND=noninteractive
  local -a packages=(
    curl ca-certificates jq gh git git-lfs tar gzip apt-transport-https lsb-release gnupg
  )
  if [[ "${RUNNER_STORAGE_PROFILE}" == "hbv4-nvme-raid0" ]]; then
    packages+=(mdadm xfsprogs nvme-cli util-linux)
  fi
  apt-get update -y
  apt-get install -y --no-install-recommends "${packages[@]}"
  git lfs install --system || true
}

# install_storage_helper: reconstruct and authenticate the reviewed disk helper.
#
# The provision job embeds a gzip/base64 representation because Azure accepts
# only one bounded custom-data payload. Decode to a private temporary file,
# verify the uncompressed bytes against the separately embedded SHA-256, and
# install only those authenticated bytes. main calls this only for the HBv4
# profile; profile "none" still validates the inert placeholder and digest shape
# but preserves its historical host package and filesystem behavior.
install_storage_helper() {
  local tmp computed
  tmp="$(mktemp)"
  if ! printf '%s' "${STORAGE_HELPER_GZIP_BASE64}" \
      | base64 --decode \
      | gzip -dc > "${tmp}"; then
    rm -f "${tmp}"
    die "unable to decode the embedded HBv4 storage helper"
  fi

  computed="$(sha256sum "${tmp}" | awk '{print $1}')"
  if [[ "${computed}" != "${STORAGE_HELPER_SHA256}" ]]; then
    rm -f "${tmp}"
    die "storage helper SHA-256 mismatch: expected ${STORAGE_HELPER_SHA256}, got ${computed}"
  fi
  install -m 0755 "${tmp}" "${STORAGE_HELPER_PATH}"
  rm -f "${tmp}"
  log "embedded storage helper SHA-256 verified and installed"
}

# Install one trusted, independently hashed source-controlled payload without
# ever evaluating its contents in the control-plane renderer.
install_embedded_file() {
  local encoded="$1"
  local expected_sha256="$2"
  local destination="$3"
  local mode="$4"
  local tmp computed

  tmp="$(mktemp)"
  if ! printf '%s' "${encoded}" | base64 --decode | gzip -dc > "${tmp}"; then
    rm -f "${tmp}"
    die "unable to decode trusted payload for ${destination}"
  fi
  computed="$(sha256sum "${tmp}" | awk '{print $1}')"
  if [[ "${computed}" != "${expected_sha256}" ]]; then
    rm -f "${tmp}"
    die "trusted payload SHA-256 mismatch for ${destination}"
  fi
  install -m "${mode}" "${tmp}" "${destination}"
  rm -f "${tmp}"
}

install_trusted_validation() {
  install -d -m 0755 "${TRUSTED_VALIDATION_ROOT}"
  install_embedded_file \
    "${HOST_VALIDATOR_GZIP_BASE64}" "${HOST_VALIDATOR_SHA256}" \
    "${TRUSTED_VALIDATION_ROOT}/validate-host.sh" 0755
  install_embedded_file \
    "${CONTAINER_VALIDATOR_GZIP_BASE64}" "${CONTAINER_VALIDATOR_SHA256}" \
    "${TRUSTED_VALIDATION_ROOT}/validate-hbv4-tpls" 0755
  install_embedded_file \
    "${PARALLEL_HDF5_SOURCE_GZIP_BASE64}" "${PARALLEL_HDF5_SOURCE_SHA256}" \
    "${TRUSTED_VALIDATION_ROOT}/parallel_hdf5_shared.c" 0644
  log "trusted HBv4 validation payloads verified and installed"
}

# configure_runner_storage: establish RAID-backed runner and workload state.
#
# Profile "none" deliberately returns without changing the historical paths or
# Docker configuration. The HBv4 profile invokes the fail-closed disk helper,
# then places the GitHub runner home (including its relative _work directory) on
# the XFS RAID mount. It also creates one sticky, world-writable host directory
# that the profile-specific workload wiring binds over container /tmp. Docker's
# images, logs, and writable layers are also placed on the same RAID mount.
configure_runner_storage() {
  if [[ "${RUNNER_STORAGE_PROFILE}" == "none" ]]; then
    log "runner storage profile none; preserving historical OS-disk paths"
    return 0
  fi

  log "configuring HBv4 local NVMe RAID-0 runner storage"
  # The helper's accepted/rejected device observations are credential-free and
  # are needed to diagnose a failed discovery after cleanup removes the VM.
  # pipefail preserves the helper's nonzero status while tee copies the exact
  # output to both cloud-init and the reviewed bootstrap log.
  if ! "${STORAGE_HELPER_PATH}" 2>&1 | tee -a "${BOOT_LOG}"; then
    die "HBv4 local-NVMe storage helper failed"
  fi
  if ! mountpoint -q "${HBV4_MOUNT_ROOT}"; then
    die "storage helper returned without mounting ${HBV4_MOUNT_ROOT}"
  fi

  RUNNER_HOME="${HBV4_MOUNT_ROOT}/actions-runner"
  install -m 0755 -d "${RUNNER_HOME}"
  # The sticky bit gives each container process a conventional /tmp contract
  # while preventing one user from removing another user's entries. `--mount`
  # in the workload fails if this source disappears, and the final validation
  # below independently proves that the directory still resolves to the RAID.
  install -o root -g root -m 1777 -d "${HBV4_CONTAINER_TMP}"
}

# install_docker: install Docker Engine and start the daemon.
#
# The workload job's build is `docker run ...` ON THE HOST (plan sec 2/sec 3), so a
# working Docker daemon is a hard prerequisite before the runner accepts the job.
# We install from Docker's official apt repository (stable channel) pinned to the
# detected Ubuntu codename. The runner user is added to the docker group so the
# agent can launch containers without per-call sudo. Idempotent on a pre-baked
# image (install + enable are no-ops if already satisfied).
install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "installing Docker Engine from Docker apt repo"
    export DEBIAN_FRONTEND=noninteractive
    local docker_key
    install -m 0755 -d /etc/apt/keyrings
    docker_key="$(mktemp)"
    download_with_retries \
      "https://download.docker.com/linux/ubuntu/gpg" \
      "${docker_key}" \
      "Docker repository signing key"
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg < "${docker_key}"
    rm -f "${docker_key}"
    chmod a+r /etc/apt/keyrings/docker.gpg
    local codename
    # shellcheck source=/dev/null
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$(dpkg --print-architecture)" "${codename}" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  else
    log "docker already present"
  fi

  if [[ "${RUNNER_STORAGE_PROFILE}" == "hbv4-nvme-raid0" ]]; then
    local daemon_tmp
    install -m 0711 -d "${HBV4_MOUNT_ROOT}/docker"
    install -m 0755 -d /etc/docker
    daemon_tmp="$(mktemp)"
    if [[ -s /etc/docker/daemon.json ]]; then
      jq -e 'type == "object"' /etc/docker/daemon.json >/dev/null \
        || die "/etc/docker/daemon.json is not a JSON object"
      jq --arg root "${HBV4_MOUNT_ROOT}/docker" '. + {"data-root": $root}' \
        /etc/docker/daemon.json > "${daemon_tmp}"
    else
      jq -n --arg root "${HBV4_MOUNT_ROOT}/docker" '{"data-root": $root}' > "${daemon_tmp}"
    fi
    install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json
    rm -f "${daemon_tmp}"
  fi
  systemctl enable --now docker
  systemctl restart docker
}

# ensure_azure_cli: guarantee `az` and `azcopy` are available.
#
# `az` is needed for the identity + ACR login below; `azcopy` is the Blob
# transfer tool the artifact/baseline provider commands invoke on the runner
# (plan sec 8.3/sec 9.3). Some Ubuntu images ship `az`; otherwise we add Microsoft's
# signed apt repository explicitly instead of piping a downloaded installer into
# root. AzCopy is fetched from a versioned GitHub release URL and SHA-verified
# before unpacking. The Azure CLI repository operations tolerate transient
# downloads through apt's native acquire retries. Package installation also
# waits for apt's dpkg lock; repository-index updates use a separate lists lock,
# so only that exact contention error receives a bounded command retry. Other
# update failures remain immediately fatal because without `az` the ACR login
# cannot happen and the in-job docker pull would fail.
ensure_azure_cli() {
  if ! command -v az >/dev/null 2>&1; then
    log "installing Azure CLI from Microsoft signed apt repo"
    export DEBIAN_FRONTEND=noninteractive
    local apt_output apt_status attempt codename dpkg_arch microsoft_key
    # Callers use different reviewed Ubuntu Marketplace images, so deriving the
    # codename preserves the signed repository boundary across both the manual
    # proof and automated HBv4 routes. The package version is intentionally left
    # to the repo so security updates flow until the custom-image bake pins host
    # tooling.
    # shellcheck source=/dev/null
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
    dpkg_arch="$(dpkg --print-architecture)"
    install -m 0755 -d /etc/apt/keyrings
    microsoft_key="$(mktemp)"
    download_with_retries \
      "https://packages.microsoft.com/keys/microsoft.asc" \
      "${microsoft_key}" \
      "Microsoft repository signing key"
    gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg < "${microsoft_key}"
    rm -f "${microsoft_key}"
    chmod a+r /etc/apt/keyrings/microsoft.gpg
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' \
      "${dpkg_arch}" "${codename}" > /etc/apt/sources.list.d/azure-cli.list
    # These credential-free markers distinguish repository availability from
    # package installation failures in the bounded bootstrap log.
    log "updating Azure CLI package repository indexes"
    for attempt in 1 2 3 4 5; do
      if apt_output="$(apt-get -o Acquire::Retries=3 update -y 2>&1)"; then
        printf '%s\n' "${apt_output}"
        break
      else
        apt_status=$?
      fi

      # DPkg::Lock::Timeout does not cover apt-get update's lists lock. Retry
      # only that recognized transient contention; repository, signature, and
      # other deterministic failures return immediately with apt's status.
      if (( attempt < 5 )) &&
         printf '%s\n' "${apt_output}" |
           grep -Eq 'Could not get lock /var/lib/apt/lists/lock|Unable to lock directory /var/lib/apt/lists/'; then
        log "Azure CLI package repository indexes are locked; retrying after bounded backoff (attempt ${attempt}/5)"
        sleep $(( attempt * 10 ))
        continue
      fi
      printf '%s\n' "${apt_output}" >&2
      return "${apt_status}"
    done
    log "installing Azure CLI package"
    apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y --no-install-recommends azure-cli
  else
    log "Azure CLI already present"
  fi

  if ! command -v azcopy >/dev/null 2>&1; then
    log "installing azcopy v${AZCOPY_VERSION}"
    local azcopy_arch azcopy_sha azcopy_url computed tmp
    case "$(dpkg --print-architecture)" in
      amd64)
        azcopy_arch="amd64"
        azcopy_sha="${AZCOPY_LINUX_AMD64_SHA256}"
        ;;
      arm64)
        azcopy_arch="arm64"
        azcopy_sha="${AZCOPY_LINUX_ARM64_SHA256}"
        ;;
      *)
        die "unsupported architecture for azcopy: $(dpkg --print-architecture)"
        ;;
    esac
    azcopy_url="https://github.com/Azure/azure-storage-azcopy/releases/download/v${AZCOPY_VERSION}/azcopy_linux_${azcopy_arch}_${AZCOPY_VERSION}.tar.gz"
    tmp="$(mktemp -d)"
    download_with_retries \
      "${azcopy_url}" \
      "${tmp}/azcopy.tar.gz" \
      "AzCopy release tarball"
    computed="$(sha256sum "${tmp}/azcopy.tar.gz" | awk '{print $1}')"
    if [[ "${computed}" != "${azcopy_sha}" ]]; then
      die "azcopy tarball SHA-256 mismatch: expected ${azcopy_sha}, got ${computed} (refusing to unpack an unverified azcopy)"
    fi
    log "azcopy tarball SHA-256 verified"
    tar -xzf "${tmp}/azcopy.tar.gz" -C "${tmp}"
    install -m 0755 "$(find "${tmp}" -name azcopy -type f | head -1)" /usr/local/bin/azcopy
    rm -rf "${tmp}"
  else
    log "azcopy already present"
  fi
}

# azure_login_and_acr_login: authenticate the VM to Azure and ACR via the UAMI.
#
# Entry state: the VM was created with --assign-identity <id-geos-runner-vm>, so
# the UAMI is reachable through IMDS. Running AS ${RUNNER_USER} (see body), we log
# in with that identity and then run `az acr login`, which writes Docker
# credentials into that user's ~/.docker/config.json so the later in-job
# `docker pull <ACR>/geosx/...:<tag>` -- which also runs as ${RUNNER_USER} -- is
# authenticated by the UAMI's AcrPull role (plan sec 8.1). Exit state: ${RUNNER_USER}
# can pull from the foundation ACR with no stored registry secret.
#
# --client-id <UAMI clientId> is REQUIRED (plan sec 8.3): id-geos-runner-vm is a
# user-assigned identity, so a bare `az login --identity` would try the
# system-assigned identity, which this VM does not have, and fail. RBAC
# propagation can briefly 403 right after VM create, so we retry with backoff
# rather than treating the first failure as fatal (plan sec 5.4).
azure_login_and_acr_login() {
  # Run AS ${RUNNER_USER}, not root. az acr login writes Docker credentials into the
  # INVOKING user's ~/.docker/config.json, and the workload's
  # `docker run <ACR>/geosx/...` executes as ${RUNNER_USER} (run.sh runs as that
  # user, HOME=/home/${RUNNER_USER}). Doing this as root authenticates root while
  # the real pull (as ${RUNNER_USER}) gets "authentication required" and az reports
  # docker exit 125. ${RUNNER_USER} must already exist (install_runner_agent creates
  # it) and be in the docker group; IMDS is reachable by any user for --identity.
  log "az login via user-assigned managed identity (client-id ${RUNNER_VM_UAMI_CLIENT_ID}) as ${RUNNER_USER}"
  local attempt
  for attempt in 1 2 3 4 5; do
    if sudo -u "${RUNNER_USER}" -H az login --identity --client-id "${RUNNER_VM_UAMI_CLIENT_ID}" >/dev/null 2>&1; then
      break
    fi
    log "az login attempt ${attempt} failed (possible RBAC propagation delay); retrying"
    sleep $(( attempt * 10 ))
    if [[ "${attempt}" == "5" ]]; then
      die "az login --identity failed after retries; cannot authenticate ACR pull"
    fi
  done

  log "az acr login --name ${ACR_NAME} as ${RUNNER_USER}"
  for attempt in 1 2 3 4 5; do
    if sudo -u "${RUNNER_USER}" -H az acr login --name "${ACR_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    log "az acr login attempt ${attempt} failed; retrying"
    sleep $(( attempt * 10 ))
  done
  die "az acr login failed after retries; in-job docker pull from ACR would fail"
}

# install_runner_agent: download, SHA-256 VERIFY, and unpack the pinned runner.
#
# SHA-pin gotcha (plan deliverable): pinning only the version is not enough -- a
# tarball fetched over the network must be integrity-checked before it is
# unpacked and executed as the runner agent. We compute the SHA-256 of the
# downloaded tarball and compare it to the expected value templated in from the
# release metadata; a mismatch aborts (die) BEFORE anything from the tarball runs,
# so a corrupted or substituted download can never execute on the VM. The agent
# runs as a dedicated non-root user (the agent refuses to configure as root); we
# create that user, unpack into its home, and let the bundled installdependencies
# script pull the agent's own OS libs.
install_runner_agent() {
  log "installing GitHub Actions runner agent v${RUNNER_VERSION}"

  if ! id -u "${RUNNER_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "${RUNNER_USER}"
  fi
  usermod -aG docker "${RUNNER_USER}" || true

  mkdir -p "${RUNNER_HOME}"
  chown "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"

  local arch tarball url tmp computed
  # The runner ships per-arch tarballs; map dpkg arch to the runner's naming.
  case "$(dpkg --print-architecture)" in
    amd64) arch="x64" ;;
    arm64) arch="arm64" ;;
    *) die "unsupported architecture for runner agent: $(dpkg --print-architecture)" ;;
  esac
  tarball="actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz"
  url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"

  tmp="$(mktemp -d)"
  download_with_retries \
    "${url}" \
    "${tmp}/${tarball}" \
    "GitHub Actions runner tarball"

  # Integrity gate: verify BEFORE unpacking. We only enforce the pin for the
  # x64 tarball whose SHA was templated in; if a different arch is ever used the
  # provision job must template the matching SHA, otherwise we refuse to proceed.
  computed="$(sha256sum "${tmp}/${tarball}" | awk '{print $1}')"
  if [[ "${computed}" != "${RUNNER_TARBALL_SHA256}" ]]; then
    die "runner tarball SHA-256 mismatch: expected ${RUNNER_TARBALL_SHA256}, got ${computed} (refusing to unpack an unverified runner)"
  fi
  log "runner tarball SHA-256 verified"

  tar -xzf "${tmp}/${tarball}" -C "${RUNNER_HOME}"
  chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"
  rm -rf "${tmp}"

  # The agent's bundled dependency installer needs root; run it from the unpacked
  # tree. It is idempotent and a no-op on a pre-baked image.
  if [[ -x "${RUNNER_HOME}/bin/installdependencies.sh" ]]; then
    log "installing runner agent OS dependencies"
    "${RUNNER_HOME}/bin/installdependencies.sh"
  fi
}

# validate_runner_storage: prove the HBv4 layout before accepting untrusted work.
#
# The disk helper runs before runner installation so runner and workload scratch
# state cannot land on the OS disk. This final boundary rechecks the live
# topology after Docker, Azure tooling, and the runner agent have been
# installed. Any lost mount, incomplete member set, wrong filesystem label,
# undersized device, unwritable runner directory, invalid container scratch
# contract, or unavailable Docker daemon aborts before the JIT runner registers
# and accepts repository-controlled code.
validate_runner_storage() {
  if [[ "${RUNNER_STORAGE_PROFILE}" == "none" ]]; then
    return 0
  fi

  log "validating HBv4 local NVMe storage before starting JIT runner"
  lsblk -e 7 -o NAME,KNAME,PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL \
    | tee -a "${BOOT_LOG}" || true
  ls -l /dev/disk/by-label 2>&1 | tee -a "${BOOT_LOG}" || true
  cat /proc/mdstat | tee -a "${BOOT_LOG}" || true
  findmnt --target "${HBV4_MOUNT_ROOT}" | tee -a "${BOOT_LOG}" || true
  xfs_info "${HBV4_MOUNT_ROOT}" | tee -a "${BOOT_LOG}" || true
  df -hT "${HBV4_MOUNT_ROOT}" | tee -a "${BOOT_LOG}" || true
  if ! docker info 2>&1 | tee -a "${BOOT_LOG}"; then
    die "Docker daemon is unavailable before runner registration"
  fi

  mountpoint -q "${HBV4_MOUNT_ROOT}" \
    || die "${HBV4_MOUNT_ROOT} is not a real mount point"
  [[ "$(findmnt -n -o FSTYPE --target "${HBV4_MOUNT_ROOT}")" == "xfs" ]] \
    || die "${HBV4_MOUNT_ROOT} is not mounted as XFS"
  case ",$(findmnt -n -o OPTIONS --target "${HBV4_MOUNT_ROOT}")," in
    *,noatime,*)
      ;;
    *)
      die "${HBV4_MOUNT_ROOT} is missing the required noatime mount option"
      ;;
  esac
  [[ -b "${HBV4_MD_DEVICE}" ]] \
    || die "expected RAID device ${HBV4_MD_DEVICE} is absent"

  local md_real md_name md_sysfs member_count mount_source
  md_real="$(readlink -f "${HBV4_MD_DEVICE}")"
  md_name="$(basename "${md_real}")"
  md_sysfs="/sys/class/block/${md_name}/md"
  [[ -r "${md_sysfs}/level" ]] \
    || die "${HBV4_MD_DEVICE} is not an assembled Linux MD array"
  [[ -r "${md_sysfs}/raid_disks" ]] \
    || die "${HBV4_MD_DEVICE} has no readable declared member count"
  [[ "$(cat "${md_sysfs}/level")" == "raid0" ]] \
    || die "${HBV4_MD_DEVICE} is not RAID-0"
  [[ "$(cat "${md_sysfs}/raid_disks")" == "2" ]] \
    || die "${HBV4_MD_DEVICE} does not declare exactly two RAID members"
  # The kernel exposes md/degraded only for levels with redundant members.
  # RAID-0 completeness is instead proven by matching its declared geometry to
  # the live sysfs slave count before any repository workload can start.
  [[ -d "/sys/class/block/${md_name}/slaves" ]] \
    || die "${HBV4_MD_DEVICE} has no readable active member set"
  member_count="$(find "/sys/class/block/${md_name}/slaves" -mindepth 1 -maxdepth 1 -type l | wc -l)"
  [[ "${member_count}" == "2" ]] \
    || die "${HBV4_MD_DEVICE} has ${member_count} active members, expected 2"

  mount_source="$(findmnt -n -o SOURCE --target "${HBV4_MOUNT_ROOT}")"
  [[ "$(readlink -f "${mount_source}")" == "${md_real}" ]] \
    || die "${HBV4_MOUNT_ROOT} is not mounted from ${HBV4_MD_DEVICE}"
  [[ "$(blkid -s LABEL -o value "${HBV4_MD_DEVICE}")" == "hbv4-local" ]] \
    || die "${HBV4_MD_DEVICE} does not have XFS label hbv4-local"

  local minimum_bytes total_bytes runner_mount scratch_mount docker_root docker_mount
  local scratch_mode runner_probe scratch_probe
  minimum_bytes=$(( 3 * 1024 * 1024 * 1024 * 1024 ))
  total_bytes="$(df --output=size -B1 "${HBV4_MOUNT_ROOT}" | awk 'NR == 2 {print $1}')"
  if ! [[ "${total_bytes}" =~ ^[0-9]+$ ]] ||
     (( total_bytes < minimum_bytes )); then
    die "${HBV4_MOUNT_ROOT} usable capacity ${total_bytes} is below 3 TiB"
  fi

  runner_mount="$(findmnt -n -o TARGET -T "${RUNNER_HOME}")"
  [[ "${runner_mount}" == "${HBV4_MOUNT_ROOT}" ]] \
    || die "runner home ${RUNNER_HOME} is not backed by ${HBV4_MOUNT_ROOT}"
  runner_probe="${RUNNER_HOME}/.bootstrap-write-probe"
  sudo -u "${RUNNER_USER}" -H bash -c \
    "printf 'HBv4 bootstrap preflight\\n' > '${runner_probe}'" \
    || die "runner user cannot write to ${RUNNER_HOME}"
  rm -f "${runner_probe}"

  [[ -d "${HBV4_CONTAINER_TMP}" ]] \
    || die "container scratch directory ${HBV4_CONTAINER_TMP} is missing"
  scratch_mode="$(stat -c '%a' "${HBV4_CONTAINER_TMP}")"
  [[ "${scratch_mode}" == "1777" ]] \
    || die "container scratch directory ${HBV4_CONTAINER_TMP} has mode ${scratch_mode}, expected 1777"
  scratch_mount="$(findmnt -n -o TARGET -T "${HBV4_CONTAINER_TMP}")"
  [[ "${scratch_mount}" == "${HBV4_MOUNT_ROOT}" ]] \
    || die "container scratch directory ${HBV4_CONTAINER_TMP} is not backed by ${HBV4_MOUNT_ROOT}"
  scratch_probe="${HBV4_CONTAINER_TMP}/.bootstrap-write-probe"
  sudo -u "${RUNNER_USER}" -H bash -c \
    "printf 'HBv4 container scratch preflight\\n' > '${scratch_probe}'" \
    || die "runner user cannot write to container scratch ${HBV4_CONTAINER_TMP}"
  rm -f "${scratch_probe}"

  docker_root="$(docker info --format '{{.DockerRootDir}}')"
  [[ "${docker_root}" == "${HBV4_MOUNT_ROOT}/docker" ]] \
    || die "Docker root ${docker_root} is not the reviewed HBv4 RAID path"
  docker_mount="$(findmnt -n -o TARGET -T "${docker_root}")"
  [[ "${docker_mount}" == "${HBV4_MOUNT_ROOT}" ]] \
    || die "Docker root ${docker_root} is not backed by ${HBV4_MOUNT_ROOT}"

  log "HBv4 local NVMe storage validation passed"
}

# run_runner_ephemeral: start the agent for exactly one job, then exit.
#
# We use the JIT path (`--jitconfig <encoded>`): the runner registers from the
# encoded config GitHub already minted in the provision job with the unique label
# (the LABEL INVARIANT -- see azure-job.yml), comes online, accepts the ONE job
# routed to that label, runs it, and exits. A JIT runner is inherently
# single-use and is auto-removed from GitHub once it accepts a job; the trio's
# cleanup job still deletes the registration explicitly as a backstop. We run the
# agent in the foreground as the runner user so its exit ends bootstrap; the VM
# is then idle until the trio's cleanup (or the janitor) deletes it. We do NOT
# self-delete the VM from here: that would require giving the runner-VM identity
# VM-delete rights, re-introducing the IMDS escalation risk the plan rejects
# (sec 9.4) -- teardown is the control plane's job.
run_runner_ephemeral() {
  local runner_pid
  local runner_status

  log "starting ephemeral JIT runner (single job, then exit)"
  # Run as the non-root runner user from its home. `run.sh --jitconfig` consumes
  # the encoded config on stdin-free argument form; the agent treats a jitconfig
  # run as ephemeral automatically (no --once needed, and --once is deprecated).
  #
  # Start it in the background just long enough to distinguish an immediate
  # launch/JIT failure from a live process. Only after that guard succeeds do we
  # publish `runner-agent`, which lets the Azure guest monitor hand control back
  # to GitHub's authoritative online+label polling. We then wait in the
  # foreground for the single-use runner exactly as before.
  set_bootstrap_phase runner-launch
  sudo -u "${RUNNER_USER}" -H bash -c \
    "cd '${RUNNER_HOME}' && ./run.sh --jitconfig '${RUNNER_ENCODED_JITCONFIG}'" &
  runner_pid=$!
  sleep 5
  if ! kill -0 "${runner_pid}" 2>/dev/null; then
    set +e
    wait "${runner_pid}"
    runner_status=$?
    set -e
    die "runner agent exited during its launch guard with status ${runner_status}"
  fi

  set_bootstrap_phase runner-agent
  set +e
  wait "${runner_pid}"
  runner_status=$?
  set -e
  if (( runner_status != 0 )); then
    die "runner agent exited with status ${runner_status}"
  fi
  log "runner agent exited; VM is now idle awaiting trio cleanup / janitor teardown"
}

main() {
  : > "${BOOT_LOG}" || true
  trap record_bootstrap_exit EXIT
  set_bootstrap_phase initializing
  log "GEOS Azure ephemeral runner bootstrap starting"

  set_bootstrap_phase validate-template
  require_placeholders

  set_bootstrap_phase install-base-packages
  install_base_packages
  if [[ "${RUNNER_STORAGE_PROFILE}" == "hbv4-nvme-raid0" ]]; then
    set_bootstrap_phase install-storage-helper
    install_storage_helper
  fi
  # Storage setup precedes runner and Docker installation so their mutable
  # state cannot silently fall back to the OS disk.
  set_bootstrap_phase configure-runner-storage
  configure_runner_storage

  set_bootstrap_phase install-trusted-validation
  install_trusted_validation

  set_bootstrap_phase install-docker
  install_docker

  set_bootstrap_phase install-azure-cli
  ensure_azure_cli
  # Order matters: install_runner_agent creates ${RUNNER_USER} and adds it to the
  # docker group; azure_login_and_acr_login then authenticates ACR AS that user so
  # the workload's docker pull (also as ${RUNNER_USER}) finds the credentials.
  set_bootstrap_phase install-runner-agent
  install_runner_agent

  set_bootstrap_phase azure-login
  azure_login_and_acr_login

  set_bootstrap_phase validate-runner-storage
  validate_runner_storage
  # Re-run the trusted host contract as the exact non-root identity that will
  # accept the Actions job. The runner-owned home is the intended writable RAID
  # child; the XFS mount root remains protected as root:root.
  sudo -u "${RUNNER_USER}" -H "${TRUSTED_VALIDATION_ROOT}/validate-host.sh" \
    --instance-type Standard_HB176rs_v4 \
    --compiler-flags 'target=zen4 -march=native -mtune=native' \
    --writable-path "${RUNNER_HOME}"

  run_runner_ephemeral
  log "bootstrap complete"
}

main "$@"
