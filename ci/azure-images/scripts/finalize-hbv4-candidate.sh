#!/usr/bin/env bash

# Promote one tested run-scoped candidate. Every lookup is closed over the
# provider/run/source tuple and a non-future attempt; ambiguous or conflicting
# state exits before candidate deletion so the seven-day janitor window remains
# available and failed-only reruns can reuse their already-tested candidate.
set -euo pipefail

: "${ACR_NAME:?}"
: "${CANDIDATE_REPOSITORY:?}"
: "${CANDIDATE_DIGEST:?}"
: "${TESTED_DIGEST:?}"
: "${PROVIDER:?}"
: "${SOURCE_SHA:?}"

case "${PROVIDER}" in openmpi|mpich) ;; *) echo 'invalid provider' >&2; exit 2 ;; esac
[[ "${ACR_NAME}" =~ ^[a-z0-9]{5,50}$ ]] || exit 2
[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || exit 2
[[ "${CANDIDATE_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || exit 2
[[ "${TESTED_DIGEST}" == "${CANDIDATE_DIGEST}" ]] || {
  echo 'tested digest does not equal candidate digest' >&2
  exit 1
}
[[ "${GITHUB_RUN_ID}" =~ ^[1-9][0-9]*$ ]] || exit 2
candidate_pattern="^geos/hbv4-tpl-candidates/${PROVIDER}/run-${GITHUB_RUN_ID}-attempt-([1-9][0-9]*)$"
[[ "${GITHUB_RUN_ATTEMPT}" =~ ^[1-9][0-9]*$ ]] || exit 2
[[ "${CANDIDATE_REPOSITORY}" =~ ${candidate_pattern} ]] || {
  echo 'candidate repository is outside this run/provider namespace' >&2
  exit 1
}
candidate_run_attempt="${BASH_REMATCH[1]}"
(( candidate_run_attempt <= GITHUB_RUN_ATTEMPT )) || {
  echo 'candidate repository belongs to a future run attempt' >&2
  exit 1
}

destination_repository="geosx/ubuntu24.04-gcc13-hbv4-${PROVIDER}"
destination_tag="sha-${SOURCE_SHA}"
acr_login_server="${ACR_NAME}.azurecr.io"
acr_destination="${destination_repository}:${destination_tag}"

repositories="$(az acr repository list --name "${ACR_NAME}" --output json --only-show-errors)"
jq -e 'type == "array" and all(.[]; type == "string")' <<< "${repositories}" >/dev/null || {
  echo 'ACR repository inventory is malformed; preserving candidate' >&2
  exit 1
}
candidate_count="$(jq -r --arg repo "${CANDIDATE_REPOSITORY}" '[.[] | select(. == $repo)] | length' <<< "${repositories}")"
[[ "${candidate_count}" == 1 ]] || {
  echo 'ACR candidate repository is missing or ambiguous; preserving candidate' >&2
  exit 1
}
live_candidate_digest="$(az acr repository show \
  --name "${ACR_NAME}" --image "${CANDIDATE_REPOSITORY}:candidate" \
  --query digest --output tsv --only-show-errors)"
[[ "${live_candidate_digest}" == "${CANDIDATE_DIGEST}" ]] || {
  echo 'live ACR candidate digest changed; preserving candidate' >&2
  exit 1
}

existing_acr_digest=''
if jq -e --arg repo "${destination_repository}" 'any(.[]; . == $repo)' \
    <<< "${repositories}" >/dev/null; then
  tags="$(az acr repository show-tags --name "${ACR_NAME}" \
    --repository "${destination_repository}" --detail --output json --only-show-errors)"
  jq -e 'type == "array" and all(.[]; type == "object" and (.name | type) == "string")' \
    <<< "${tags}" >/dev/null || {
    echo 'ACR destination tag inventory is malformed; preserving candidate' >&2
    exit 1
  }
  matches="$(jq -c --arg tag "${destination_tag}" '[.[] | select(.name == $tag)]' <<< "${tags}")"
  match_count="$(jq -r 'length' <<< "${matches}")"
  (( match_count <= 1 )) || { echo 'duplicate ACR immutable tags' >&2; exit 1; }
  if (( match_count == 1 )); then
    existing_acr_digest="$(jq -r '.[0].digest // empty' <<< "${matches}")"
    [[ "${existing_acr_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      echo 'ACR immutable tag has malformed digest' >&2
      exit 1
    }
  fi
fi

if [[ -n "${existing_acr_digest}" && "${existing_acr_digest}" != "${CANDIDATE_DIGEST}" ]]; then
  echo "ACR immutable tag conflicts: ${existing_acr_digest}" >&2
  exit 1
fi
if [[ -z "${existing_acr_digest}" ]]; then
  az acr import \
    --name "${ACR_NAME}" \
    --source "${acr_login_server}/${CANDIDATE_REPOSITORY}@${CANDIDATE_DIGEST}" \
    --image "${acr_destination}" \
    --only-show-errors
fi
promoted_acr_digest="$(az acr repository show \
  --name "${ACR_NAME}" --image "${acr_destination}" \
  --query digest --output tsv --only-show-errors)"
[[ "${promoted_acr_digest}" == "${CANDIDATE_DIGEST}" ]] || {
  echo 'ACR immutable promotion did not resolve to the tested digest' >&2
  exit 1
}
az acr repository update --name "${ACR_NAME}" --image "${acr_destination}" \
  --write-enabled false --delete-enabled false --only-show-errors >/dev/null
az acr repository update --name "${ACR_NAME}" \
  --image "${destination_repository}@${CANDIDATE_DIGEST}" \
  --write-enabled false --delete-enabled false --only-show-errors >/dev/null
acr_tag_attributes="$(az acr repository show --name "${ACR_NAME}" \
  --image "${acr_destination}" --output json --only-show-errors)"
acr_manifest_attributes="$(az acr repository show --name "${ACR_NAME}" \
  --image "${destination_repository}@${CANDIDATE_DIGEST}" \
  --output json --only-show-errors)"
for acr_attributes in "${acr_tag_attributes}" "${acr_manifest_attributes}"; do
  jq -e --arg digest "${CANDIDATE_DIGEST}" '
  .digest == $digest and
  (.changeableAttributes | type) == "object" and
  .changeableAttributes.writeEnabled == false and
  .changeableAttributes.deleteEnabled == false
  ' <<< "${acr_attributes}" >/dev/null || {
    echo 'ACR promoted tag or manifest is not locked against overwrite/deletion' >&2
    exit 1
  }
done

# Azure OIDC remains on this hosted finalizer. Pulling the promoted digest back
# through ACR verifies that the immutable destination is readable by digest and
# still resolves to the exact image tested on the fresh HBv4 runner.
az acr login --name "${ACR_NAME}" --only-show-errors >/dev/null
promoted_digest_reference="${acr_login_server}/${destination_repository}@${CANDIDATE_DIGEST}"
docker pull "${promoted_digest_reference}" >/dev/null
docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' \
  "${promoted_digest_reference}" | grep -Fx -- "${promoted_digest_reference}" >/dev/null

# Only an unambiguous, locked, and readable ACR promotion removes the
# run-scoped candidate.
az acr repository delete --name "${ACR_NAME}" \
  --repository "${CANDIDATE_REPOSITORY}" --yes --only-show-errors
repositories="$(az acr repository list --name "${ACR_NAME}" --output json --only-show-errors)"
jq -e --arg repo "${CANDIDATE_REPOSITORY}" \
  'type == "array" and all(.[]; type == "string") and all(.[]; . != $repo)' \
  <<< "${repositories}" >/dev/null || {
  echo 'Candidate repository remains after successful promotion' >&2
  exit 1
}

echo "Promoted ${PROVIDER} ${CANDIDATE_DIGEST} to ${acr_login_server}/${acr_destination}."
