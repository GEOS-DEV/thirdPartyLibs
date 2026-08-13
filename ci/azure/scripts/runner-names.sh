#!/usr/bin/env bash

set -euo pipefail

geos_ci_slugify() {
  local raw="${1:-}"
  local slug

  slug="$(printf '%s' "${raw}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

  if [[ -z "${slug}" ]]; then
    slug="job"
  fi

  printf '%s' "${slug}"
}

geos_ci_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{ print substr($1, 1, 10) }'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{ print substr($1, 1, 10) }'
  else
    printf '%s' "$1" | cksum | awk '{ print $1 }'
  fi
}

geos_ci_runner_identity() {
  local run_id="${1:?github run id is required}"
  local run_attempt="${2:?github run attempt is required}"
  local runner_instance_key="${3:?runner instance key is required}"
  local slug
  local base
  local suffix
  local max_vm_name_length=64

  if ! [[ "${run_id}" =~ ^[0-9]+$ ]]; then
    echo "github run id must be numeric: ${run_id}" >&2
    return 2
  fi
  if ! [[ "${run_attempt}" =~ ^[0-9]+$ ]]; then
    echo "github run attempt must be numeric: ${run_attempt}" >&2
    return 2
  fi

  slug="$(geos_ci_slugify "${runner_instance_key}")"
  # Preserve the TPL workflow's public lifecycle key while using the GEOS
  # deterministic identity algorithm and collision-resistant truncation.
  base="geos-hbv4-${run_id}-${run_attempt}-${slug}"

  # Azure Linux VM names are capped at 64 characters. The generated GitHub
  # runner label and VM name must remain joined by a stable key, so long matrix
  # labels are compacted with a deterministic suffix instead of being silently
  # truncated to a value that could collide with another matrix row.
  if (( ${#base} > max_vm_name_length )); then
    suffix="$(geos_ci_hash "${base}")"
    slug="${slug:0:$(( max_vm_name_length - 10 - ${#run_id} - ${#run_attempt} - ${#suffix} - 4 ))}"
    slug="${slug%-}"
    base="geos-hbv4-${run_id}-${run_attempt}-${slug}-${suffix}"
  fi

  printf 'runner_name=%s\n' "${base}"
  printf 'runner_label=%s\n' "${base}"
  printf 'vm_name=%s\n' "${base}"
  printf 'log_blob_prefix=github/%s/%s/%s\n' "${run_id}" "${run_attempt}" "${slug}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  geos_ci_runner_identity "$@"
fi
