#!/usr/bin/env bash

set -euo pipefail

: "${AZURE_RUNNER_RESOURCE_GROUP:?}"
: "${AZURE_ACR_NAME:?}"
: "${GH_TOKEN:?}"
: "${ACTIONS_READ_TOKEN:?}"
: "${EVIDENCE_FILE:?}"

install -d -m 0700 "$(dirname "${EVIDENCE_FILE}")"
: > "${EVIDENCE_FILE}"
now_epoch="$(date -u +%s)"

record() {
  local kind="$1" name="$2" action="$3"
  jq -nc --arg kind "${kind}" --arg name "${name}" --arg action "${action}" \
    '{kind:$kind,name:$name,action:$action}' >> "${EVIDENCE_FILE}"
}

is_expired() {
  local created_at="$1" ttl_hours="$2" created_epoch
  [[ "${created_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 2
  [[ "${ttl_hours}" =~ ^[1-9][0-9]*$ ]] || return 2
  (( ttl_hours <= 24 )) || return 2
  created_epoch="$(date -u -d "${created_at}" +%s)" || return 2
  (( now_epoch >= created_epoch + ttl_hours * 3600 ))
}

vm_inventory="$(az vm list --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" \
  --output json --only-show-errors)"
jq -e 'type == "array"' <<< "${vm_inventory}" >/dev/null
mapfile -t vm_records < <(jq -c '.[]' <<< "${vm_inventory}")
for vm in "${vm_records[@]}"; do
  name="$(jq -r '.name // empty' <<< "${vm}")"
  project="$(jq -r '.tags.project // empty' <<< "${vm}")"
  purpose="$(jq -r '.tags.purpose // empty' <<< "${vm}")"
  provider="$(jq -r '.tags.provider // empty' <<< "${vm}")"
  role="$(jq -r '.tags.runnerRole // empty' <<< "${vm}")"
  run_id="$(jq -r '.tags.githubRunId // empty' <<< "${vm}")"
  attempt="$(jq -r '.tags.runAttempt // empty' <<< "${vm}")"
  created_at="$(jq -r '.tags.createdAtUtc // empty' <<< "${vm}")"
  ttl_hours="$(jq -r '.tags.ttlHours // empty' <<< "${vm}")"

  [[ "${project}" == GEOS && "${purpose}" == hbv4-tpl-ci ]] || continue
  case "${provider}" in openmpi|mpich) ;; *) record vm "${name}" preserved-invalid-tags; continue ;; esac
  case "${role}" in builder|tester) ;; *) record vm "${name}" preserved-invalid-tags; continue ;; esac
  [[ "${run_id}" =~ ^[1-9][0-9]*$ && "${attempt}" =~ ^[1-9][0-9]*$ ]] || {
    record vm "${name}" preserved-invalid-tags
    continue
  }
  expected="geos-hbv4-${run_id}-${attempt}-${provider}-${role}"
  [[ "${name}" == "${expected}" ]] || { record vm "${name}" preserved-invalid-name; continue; }
  if is_expired "${created_at}" "${ttl_hours}"; then
    az vm delete --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" --name "${name}" \
      --yes --force-deletion true --only-show-errors
    remaining="$(az vm list --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" \
      --query "[?name=='${name}'] | length(@)" --output tsv --only-show-errors)"
    [[ "${remaining}" == 0 ]] || { echo "VM ${name} remains after janitor deletion" >&2; exit 1; }
    record vm "${name}" deleted-expired
  else
    status=$?
    if (( status == 2 )); then record vm "${name}" preserved-invalid-ttl; fi
  fi
done

# Reclaim explicitly tagged NIC/disk remnants left by a partial VM create or
# teardown. Other resource types and untagged resources are never candidates.
resource_inventory="$(az resource list --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" \
  --output json --only-show-errors)"
jq -e 'type == "array"' <<< "${resource_inventory}" >/dev/null
mapfile -t resource_records < <(jq -c '.[]' <<< "${resource_inventory}")
for resource in "${resource_records[@]}"; do
  type="$(jq -r '.type // empty' <<< "${resource}")"
  case "${type}" in
    Microsoft.Network/networkInterfaces|Microsoft.Compute/disks) ;;
    *) continue ;;
  esac
  id="$(jq -r '.id // empty' <<< "${resource}")"
  name="$(jq -r '.name // empty' <<< "${resource}")"
  project="$(jq -r '.tags.project // empty' <<< "${resource}")"
  purpose="$(jq -r '.tags.purpose // empty' <<< "${resource}")"
  provider="$(jq -r '.tags.provider // empty' <<< "${resource}")"
  role="$(jq -r '.tags.runnerRole // empty' <<< "${resource}")"
  run_id="$(jq -r '.tags.githubRunId // empty' <<< "${resource}")"
  attempt="$(jq -r '.tags.runAttempt // empty' <<< "${resource}")"
  created_at="$(jq -r '.tags.createdAtUtc // empty' <<< "${resource}")"
  ttl_hours="$(jq -r '.tags.ttlHours // empty' <<< "${resource}")"
  [[ "${project}" == GEOS && "${purpose}" == hbv4-tpl-ci ]] || continue
  case "${provider}:${role}" in
    openmpi:builder|openmpi:tester|mpich:builder|mpich:tester) ;;
    *) record resource "${name}" preserved-invalid-tags; continue ;;
  esac
  [[ "${run_id}" =~ ^[1-9][0-9]*$ && "${attempt}" =~ ^[1-9][0-9]*$ ]] || {
    record resource "${name}" preserved-invalid-tags
    continue
  }
  runner_prefix="geos-hbv4-${run_id}-${attempt}-${provider}-${role}"
  [[ "${name}" == "${runner_prefix}"* ]] || {
    record resource "${name}" preserved-invalid-name
    continue
  }
  if is_expired "${created_at}" "${ttl_hours}"; then
    az resource delete --ids "${id}" --only-show-errors
    record resource "${name}" deleted-expired
  else
    status=$?
    if (( status == 2 )); then record resource "${name}" preserved-invalid-ttl; fi
  fi
done

# Remove an offline registration with no lifecycle-matched VM only when the
# workflow-run metadata encoded in its exact label proves that no VM can still
# be provisioned for it. A newly minted JIT runner is offline before az vm
# create completes, so VM absence alone is not evidence that it is orphaned.
#
# Labels are authoritative here. GitHub reserves RUNNER_NAME on hosted control
# runners; an older provision action accidentally passed that protected value
# to generate-jitconfig, producing names such as "GitHub Actions 1000003390".
# The same registrations retained their unique geos-hbv4 lifecycle labels.
vm_inventory="$(az vm list --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" \
  --output json --only-show-errors)"
jq -e 'type == "array" and all(.[]; (.name | type) == "string")' \
  <<< "${vm_inventory}" >/dev/null

max_gh_attempts=4
is_gh_not_found() {
  grep -Eiq 'HTTP 404|Not Found' "$1"
}

is_gh_retryable() {
  grep -Eiq \
    'HTTP (408|429|5[0-9][0-9])|secondary rate limit|rate limit|timeout|temporar' \
    "$1"
}

validate_runner_inventory() {
  jq -e '
    type == "array" and
    all(.[];
      type == "object" and (.runners | type) == "array" and
      all(.runners[]?;
        (.id | type) == "number" and .id >= 1 and
        .id == (.id | floor) and
        (.name | type) == "string" and (.name | length) > 0 and
        (.status | type) == "string" and
        (.busy | type) == "boolean" and
        (.labels | type) == "array" and
        all(.labels[]?; (.name | type) == "string")
      )
    )
  ' >/dev/null
}

probe_runner_collection_access() {
  local context="$1" response err_file attempt
  for (( attempt = 1; attempt <= max_gh_attempts; attempt++ )); do
    err_file="$(mktemp)"
    if response="$(gh api \
        -H 'Accept: application/vnd.github+json' \
        "repos/${GITHUB_REPOSITORY}/actions/runners?per_page=1" \
        2>"${err_file}")"; then
      rm -f "${err_file}"
      jq -e '
        type == "object" and
        (.total_count | type) == "number" and
        .total_count >= 0 and .total_count == (.total_count | floor) and
        (.runners | type) == "array"
      ' <<< "${response}" >/dev/null || {
        echo "Cannot classify ${context}: runner collection response is malformed." >&2
        return 1
      }
      return 0
    fi
    if (( attempt < max_gh_attempts )) && is_gh_retryable "${err_file}"; then
      echo "Runner collection probe attempt ${attempt} for ${context} was transient; retrying." >&2
      sed -n '1,40p' "${err_file}" >&2
      rm -f "${err_file}"
      sleep $(( attempt * 10 ))
      continue
    fi
    echo "Cannot classify ${context}: runner collection access failed." >&2
    sed -n '1,40p' "${err_file}" >&2
    rm -f "${err_file}"
    return 1
  done
  return 1
}

read_runner_inventory() {
  local context="$1" response err_file attempt
  for (( attempt = 1; attempt <= max_gh_attempts; attempt++ )); do
    err_file="$(mktemp)"
    if response="$(gh api --paginate --slurp \
        -H 'Accept: application/vnd.github+json' \
        "repos/${GITHUB_REPOSITORY}/actions/runners?per_page=100" \
        2>"${err_file}")"; then
      rm -f "${err_file}"
      validate_runner_inventory <<< "${response}" || {
        echo "${context} runner inventory is malformed." >&2
        return 1
      }
      RUNNER_PAGES="${response}"
      return 0
    fi
    if (( attempt < max_gh_attempts )) && is_gh_retryable "${err_file}"; then
      echo "Runner inventory attempt ${attempt} for ${context} was transient; retrying." >&2
      sed -n '1,40p' "${err_file}" >&2
      rm -f "${err_file}"
      sleep $(( attempt * 10 ))
      continue
    fi
    echo "Unable to read ${context} runner inventory." >&2
    sed -n '1,40p' "${err_file}" >&2
    rm -f "${err_file}"
    return 1
  done
  return 1
}

delete_and_verify_runner() {
  local runner_id="$1" lifecycle_label="$2" runner_name="$3"
  local delete_done=false err_file response attempt remaining_id remaining_label

  for (( attempt = 1; attempt <= max_gh_attempts; attempt++ )); do
    err_file="$(mktemp)"
    if gh api --method DELETE \
        -H 'Accept: application/vnd.github+json' \
        "repos/${GITHUB_REPOSITORY}/actions/runners/${runner_id}" \
        >/dev/null 2>"${err_file}"; then
      rm -f "${err_file}"
      delete_done=true
      break
    fi
    if is_gh_not_found "${err_file}"; then
      rm -f "${err_file}"
      probe_runner_collection_access "runner DELETE 404 for ${runner_id}" || return 1
      delete_done=true
      break
    fi
    if (( attempt < max_gh_attempts )) && is_gh_retryable "${err_file}"; then
      echo "Runner DELETE attempt ${attempt} was transient; retrying." >&2
      sed -n '1,40p' "${err_file}" >&2
      rm -f "${err_file}"
      sleep $(( attempt * 10 ))
      continue
    fi
    echo "GitHub runner DELETE failed for ${runner_id}." >&2
    sed -n '1,40p' "${err_file}" >&2
    rm -f "${err_file}"
    return 1
  done
  [[ "${delete_done}" == true ]] || return 1

  for (( attempt = 1; attempt <= max_gh_attempts; attempt++ )); do
    err_file="$(mktemp)"
    if response="$(gh api \
        -H 'Accept: application/vnd.github+json' \
        "repos/${GITHUB_REPOSITORY}/actions/runners/${runner_id}" \
        2>"${err_file}")"; then
      rm -f "${err_file}"
      jq -e --argjson id "${runner_id}" 'type == "object" and .id == $id' \
        <<< "${response}" >/dev/null || {
        echo "Runner GET returned a malformed identity for ${runner_id}." >&2
        return 1
      }
      if (( attempt < max_gh_attempts )); then
        sleep $(( attempt * 10 ))
        continue
      fi
      echo "Runner ${runner_id} remains after janitor deletion." >&2
      return 1
    fi
    if is_gh_not_found "${err_file}"; then
      rm -f "${err_file}"
      probe_runner_collection_access "runner verification 404 for ${runner_id}" || return 1
      break
    fi
    if (( attempt < max_gh_attempts )) && is_gh_retryable "${err_file}"; then
      sed -n '1,40p' "${err_file}" >&2
      rm -f "${err_file}"
      sleep $(( attempt * 10 ))
      continue
    fi
    echo "Unable to verify runner ${runner_id} deletion." >&2
    sed -n '1,40p' "${err_file}" >&2
    rm -f "${err_file}"
    return 1
  done

  read_runner_inventory deletion-verification || return 1
  remaining_id="$(jq -r --argjson id "${runner_id}" \
    '[.[].runners[]? | select(.id == $id)] | length' <<< "${RUNNER_PAGES}")"
  remaining_label="$(jq -r --arg label "${lifecycle_label}" '
    [.[].runners[]? |
      select([.labels[]?.name | select(. == $label)] | length > 0)] | length
    ' <<< "${RUNNER_PAGES}")"
  if (( remaining_id != 0 || remaining_label != 0 )); then
    echo "Runner identity remains after janitor deletion: ${runner_name} / ${lifecycle_label}." >&2
    return 1
  fi
}

RUNNER_PAGES=''
read_runner_inventory initial
runner_pages="${RUNNER_PAGES}"
mapfile -t runners < <(jq -c '.[].runners[]?' <<< "${runner_pages}")
lifecycle_pattern='^geos-hbv4-([1-9][0-9]*)-([1-9][0-9]*)-(openmpi|mpich)-(builder|tester)$'
for runner in "${runners[@]}"; do
  runner_id="$(jq -r '.id // empty' <<< "${runner}")"
  name="$(jq -r '.name // empty' <<< "${runner}")"
  status="$(jq -r '.status // empty' <<< "${runner}")"
  lifecycle_labels="$(jq -c --arg regex "${lifecycle_pattern}" \
    '[.labels[]?.name | select(test($regex))]' <<< "${runner}")"
  lifecycle_label_count="$(jq -r 'length' <<< "${lifecycle_labels}")"

  if (( lifecycle_label_count == 0 )); then
    if [[ "${name}" =~ ${lifecycle_pattern} ]]; then
      record runner "${name}" preserved-missing-lifecycle-label
    fi
    continue
  fi
  if (( lifecycle_label_count != 1 )); then
    record runner "${name}" preserved-ambiguous-lifecycle-label
    continue
  fi
  lifecycle_label="$(jq -r '.[0]' <<< "${lifecycle_labels}")"
  if [[ "${name}" =~ ${lifecycle_pattern} && "${name}" != "${lifecycle_label}" ]]; then
    record runner "${name}" preserved-inconsistent-lifecycle-identity
    continue
  fi
  label_owner_count="$(jq -r --arg label "${lifecycle_label}" '
    [.[].runners[]? |
      select([.labels[]?.name | select(. == $label)] | length > 0)] | length
    ' <<< "${runner_pages}")"
  if (( label_owner_count != 1 )); then
    record runner "${lifecycle_label}" preserved-ambiguous-lifecycle-label
    continue
  fi
  [[ "${status}" == offline ]] || continue
  [[ "${lifecycle_label}" =~ ${lifecycle_pattern} ]]
  encoded_run_id="${BASH_REMATCH[1]}"
  encoded_attempt="${BASH_REMATCH[2]}"
  encoded_provider="${BASH_REMATCH[3]}"
  encoded_role="${BASH_REMATCH[4]}"
  has_vm="$(jq -r \
    --arg name "${lifecycle_label}" \
    --arg run_id "${encoded_run_id}" \
    --arg attempt "${encoded_attempt}" \
    --arg provider "${encoded_provider}" \
    --arg role "${encoded_role}" '
      [
        .[]
        | select(
            .name == $name or
            (
              (.tags | type) == "object" and
              .tags.project == "GEOS" and
              .tags.purpose == "hbv4-tpl-ci" and
              (.tags.githubRunId | tostring) == $run_id and
              (.tags.runAttempt | tostring) == $attempt and
              .tags.provider == $provider and
              .tags.runnerRole == $role
            )
          )
      ] | length
    ' <<< "${vm_inventory}")"
  (( has_vm == 0 )) || continue

  set +e
  workflow_run="$(GH_TOKEN="${ACTIONS_READ_TOKEN}" gh api \
    -H 'Accept: application/vnd.github+json' \
    "repos/${GITHUB_REPOSITORY}/actions/runs/${encoded_run_id}" 2>/dev/null)"
  workflow_run_status=$?
  set -e
  if (( workflow_run_status != 0 )); then
    record runner "${lifecycle_label}" preserved-unverifiable-workflow-run
    continue
  fi

  if ! jq -e \
      --arg repository "${GITHUB_REPOSITORY}" \
      --argjson run_id "${encoded_run_id}" '
        type == "object" and
        (.id | type) == "number" and .id == $run_id and
        (.repository.full_name | type) == "string" and
          .repository.full_name == $repository and
        (.path | type) == "string" and
          .path == ".github/workflows/docker_build_tpls_hbv4.yml" and
        (.event == "workflow_dispatch" or .event == "pull_request_target") and
        (.run_attempt | type) == "number" and
          .run_attempt >= 1 and .run_attempt == (.run_attempt | floor) and
        (.status | type) == "string" and
        (.conclusion == null or (.conclusion | type) == "string")
      ' <<< "${workflow_run}" >/dev/null; then
    record runner "${lifecycle_label}" preserved-unverifiable-workflow-run
    continue
  fi

  live_attempt="$(jq -r '.run_attempt' <<< "${workflow_run}")"
  run_status="$(jq -r '.status' <<< "${workflow_run}")"
  conclusion="$(jq -r '.conclusion // empty' <<< "${workflow_run}")"
  delete_action=''
  if (( encoded_attempt < live_attempt )); then
    delete_action=deleted-superseded-attempt-orphan
  elif (( encoded_attempt > live_attempt )); then
    record runner "${lifecycle_label}" preserved-inconsistent-workflow-run
    continue
  elif [[ "${run_status}" == completed && -n "${conclusion}" ]]; then
    delete_action=deleted-completed-orphan
  elif [[ "${run_status}" =~ ^(queued|in_progress|requested|waiting|pending)$ && -z "${conclusion}" ]]; then
    record runner "${lifecycle_label}" preserved-active-workflow-run
    continue
  else
    record runner "${lifecycle_label}" preserved-inconsistent-workflow-run
    continue
  fi

  delete_and_verify_runner "${runner_id}" "${lifecycle_label}" "${name}"
  record runner "${lifecycle_label}" "${delete_action}"
done

# Failed or ambiguous candidates are intentionally recoverable for seven days.
repository_inventory="$(az acr repository list --name "${AZURE_ACR_NAME}" \
  --output json --only-show-errors)"
jq -e 'type == "array" and all(.[]; type == "string")' \
  <<< "${repository_inventory}" >/dev/null
mapfile -t candidate_repositories < <(jq -r '.[] | select(test("^geos/hbv4-tpl-candidates/(openmpi|mpich)/run-[1-9][0-9]*-attempt-[1-9][0-9]*$"))' \
  <<< "${repository_inventory}")
for repository in "${candidate_repositories[@]}"; do
  repository_metadata="$(az acr repository show --name "${AZURE_ACR_NAME}" \
    --repository "${repository}" --output json --only-show-errors)"
  if ! jq -e --arg repository "${repository}" '
      type == "object" and
      (has("imageName") or has("name")) and
      ((has("imageName") | not) or
        ((.imageName | type) == "string" and .imageName == $repository)) and
      ((has("name") | not) or
        ((.name | type) == "string" and .name == $repository)) and
      ((.lastUpdateTime | type) == "string" and
        (.lastUpdateTime | length) > 0)
      ' <<< "${repository_metadata}" >/dev/null; then
    record candidate "${repository}" preserved-malformed-repository-metadata
    echo "Candidate repository metadata is malformed for ${repository}; preserving it." >&2
    exit 1
  fi
  updated="$(jq -r '.lastUpdateTime' <<< "${repository_metadata}")"
  if ! updated_epoch="$(date -u -d "${updated}" +%s)"; then
    record candidate "${repository}" preserved-invalid-repository-time
    echo "Candidate repository timestamp is malformed for ${repository}; preserving it." >&2
    exit 1
  fi
  if (( now_epoch >= updated_epoch + 7 * 24 * 3600 )); then
    az acr repository delete --name "${AZURE_ACR_NAME}" \
      --repository "${repository}" --yes --only-show-errors
    repositories_after_delete="$(az acr repository list --name "${AZURE_ACR_NAME}" \
      --output json --only-show-errors)"
    jq -e --arg repository "${repository}" '
      type == "array" and all(.[]; type == "string") and
      all(.[]; . != $repository)
      ' <<< "${repositories_after_delete}" >/dev/null || {
      echo "Candidate repository remains after janitor deletion: ${repository}" >&2
      exit 1
    }
    record candidate "${repository}" deleted-seven-day
  else
    tags="$(az acr repository show-tags --name "${AZURE_ACR_NAME}" \
      --repository "${repository}" --detail --output json --only-show-errors)"
    if jq -e 'type == "array" and length == 1 and .[0].name == "candidate"' \
        <<< "${tags}" >/dev/null; then
      record candidate "${repository}" preserved-within-seven-day
    else
      record candidate "${repository}" preserved-ambiguous-within-seven-day
    fi
  fi
done

# A successful collection read after mutation is the verification boundary.
final_vms="$(az vm list --resource-group "${AZURE_RUNNER_RESOURCE_GROUP}" --output json --only-show-errors)"
final_repositories="$(az acr repository list --name "${AZURE_ACR_NAME}" --output json --only-show-errors)"
final_runners="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runners?per_page=1")"
jq -e 'type == "array"' <<< "${final_vms}" >/dev/null
jq -e 'type == "array"' <<< "${final_repositories}" >/dev/null
jq -e 'type == "object" and (.runners | type) == "array"' <<< "${final_runners}" >/dev/null
