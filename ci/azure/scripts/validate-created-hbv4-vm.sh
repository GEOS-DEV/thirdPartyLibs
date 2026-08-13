#!/usr/bin/env bash

# Validate the post-create Azure VM model before the paid runner is accepted.
#
# The action passes the unprojected `az vm show` JSON on stdin so this helper
# and its fixtures exercise Azure's real response keys. In particular, the
# Compute schema spells the OS-disk field `diskSizeGB`; validating the raw model
# prevents a misspelled JMESPath projection from silently turning it into null.
# Diagnostics intentionally contain field names only: the complete VM response
# can include deployment metadata that does not belong in Actions logs.

set -euo pipefail

if (( $# != 6 )); then
  echo "usage: $0 VM_NAME PROVIDER ROLE INSTANCE_KEY RUNNER_LABEL UAMI_ID" >&2
  exit 2
fi

vm_name="$1"
provider="$2"
role="$3"
instance_key="$4"
runner_label="$5"
uami_id="$6"
vm_contract="$(cat)"

if [[ -z "${vm_contract}" ]]; then
  echo '::error::Azure returned an empty VM contract.' >&2
  exit 1
fi

# Keep the expected machine tuple here, rather than accepting caller-provided
# size/image/location values, so the validation boundary remains fail-closed.
# Azure resource identifiers and platform enum-like fields are case-insensitive;
# lifecycle tag values remain exact because cleanup joins on those strings.
if ! mismatches="$(jq -r \
    --arg name "${vm_name}" \
    --arg provider "${provider}" \
    --arg role "${role}" \
    --arg instance_key "${instance_key}" \
    --arg runner_label "${runner_label}" \
    --arg uami_id "${uami_id}" '
      def lower_string:
        if type == "string" then ascii_downcase else "" end;
      def nonempty_string:
        type == "string" and length > 0;

      (.identity.userAssignedIdentities // null) as $identities
      | [
          if .name == $name then empty else "name" end,
          if ((.hardwareProfile.vmSize // null) | lower_string) ==
             "standard_hb176rs_v4"
          then empty else "hardwareProfile.vmSize" end,
          if ((.location // null) | lower_string) == "southcentralus"
          then empty else "location" end,
          if .tags.project == "GEOS" then empty else "tags.project" end,
          if .tags.purpose == "hbv4-tpl-ci"
          then empty else "tags.purpose" end,
          if .tags.provider == $provider
          then empty else "tags.provider" end,
          if .tags.runnerRole == $role
          then empty else "tags.runnerRole" end,
          if .tags.runnerInstanceKey == $instance_key
          then empty else "tags.runnerInstanceKey" end,
          if .tags.runnerLabel == $runner_label
          then empty else "tags.runnerLabel" end,
          if ((.tags.ttlHours // "") | tostring) == "6"
          then empty else "tags.ttlHours" end,
          if .storageProfile.osDisk.diskSizeGB == 128
          then empty else "storageProfile.osDisk.diskSizeGB" end,
          if ((.storageProfile.imageReference.publisher // null) | lower_string) ==
             "microsoft-dsvm"
          then empty else "storageProfile.imageReference.publisher" end,
          if ((.storageProfile.imageReference.offer // null) | lower_string) ==
             "ubuntu-hpc"
          then empty else "storageProfile.imageReference.offer" end,
          if ((.storageProfile.imageReference.sku // null) | lower_string) == "2404"
          then empty else "storageProfile.imageReference.sku" end,
          if ((.storageProfile.imageReference.exactVersion //
               .storageProfile.imageReference.version // "") | tostring) ==
             "24.04.2026070201"
          then empty else "storageProfile.imageReference.version" end,
          if (($identities | type) == "object" and
              ([$identities | keys[] | ascii_downcase] |
               index($uami_id | ascii_downcase)) != null)
          then empty else "identity.userAssignedIdentities" end,
          if ((.networkProfile.networkInterfaces[0].id // null) | nonempty_string)
          then empty else "networkProfile.networkInterfaces[0].id" end,
          if ((.storageProfile.osDisk.managedDisk.id // null) | nonempty_string)
          then empty else "storageProfile.osDisk.managedDisk.id" end
        ]
      | join(", ")
    ' <<< "${vm_contract}" 2>/dev/null)"; then
  echo '::error::Azure returned malformed VM contract JSON.' >&2
  exit 1
fi

if [[ -n "${mismatches}" ]]; then
  echo "::error::Azure VM failed fixed HBv4 contract fields: ${mismatches}" >&2
  exit 1
fi
