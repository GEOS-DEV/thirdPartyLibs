#!/usr/bin/env python3
"""Render the reviewed HBv4 cloud-init payload without shell evaluation."""

from __future__ import annotations

import base64
import gzip
import hashlib
import os
import pathlib
import re
import sys
import textwrap


AZURE_CUSTOM_DATA_LIMIT = 65_535


def render_payload(source: str) -> bytes:
    """Substitute the allowlisted single-line values into the reviewed script."""


    replacements = {
        "@@RUNNER_ENCODED_JITCONFIG@@": "RUNNER_ENCODED_JITCONFIG",
        "@@RUNNER_VERSION@@": "RUNNER_VERSION",
        "@@RUNNER_TARBALL_SHA256@@": "RUNNER_TARBALL_SHA256",
        "@@ACR_NAME@@": "ACR_NAME",
        "@@RUNNER_VM_UAMI_CLIENT_ID@@": "RUNNER_VM_UAMI_CLIENT_ID",
        "@@RUNNER_STORAGE_PROFILE@@": "RUNNER_STORAGE_PROFILE",
        "@@STORAGE_HELPER_SHA256@@": "STORAGE_HELPER_SHA256",
        "@@STORAGE_HELPER_GZIP_BASE64@@": "STORAGE_HELPER_GZIP_BASE64",
        "@@HOST_VALIDATOR_SHA256@@": "HOST_VALIDATOR_SHA256",
        "@@HOST_VALIDATOR_GZIP_BASE64@@": "HOST_VALIDATOR_GZIP_BASE64",
        "@@CONTAINER_VALIDATOR_SHA256@@": "CONTAINER_VALIDATOR_SHA256",
        "@@CONTAINER_VALIDATOR_GZIP_BASE64@@": "CONTAINER_VALIDATOR_GZIP_BASE64",
        "@@PARALLEL_HDF5_SOURCE_SHA256@@": "PARALLEL_HDF5_SOURCE_SHA256",
        "@@PARALLEL_HDF5_SOURCE_GZIP_BASE64@@": "PARALLEL_HDF5_SOURCE_GZIP_BASE64",
    }
    for marker, variable in replacements.items():
        if source.count(marker) != 1:
            raise SystemExit(f"{marker} must occur exactly once")
        value = os.environ.get(variable, "")
        if not value:
            raise SystemExit(f"required render variable {variable} is empty")
        if "\x00" in value or "\n" in value or "\r" in value:
            raise SystemExit(f"render variable {variable} is not single-line")
        source = source.replace(marker, value)

    payload = source.encode("ascii")
    if re.search(rb"@@[A-Z0-9_]+@@", payload):
        raise SystemExit("unrecognized template placeholder remains in bootstrap payload")
    return payload


def wrap_payload(payload: bytes) -> bytes:
    """Create a small, deterministic, authenticated first-boot decoder."""

    payload_sha256 = hashlib.sha256(payload).hexdigest()
    encoded = base64.b64encode(gzip.compress(payload, compresslevel=9, mtime=0)).decode("ascii")
    wrapped_encoded = "\n".join(textwrap.wrap(encoded, 120))
    wrapper = f"""#!/usr/bin/env bash
set -Eeuo pipefail

readonly PAYLOAD_SHA256='{payload_sha256}'
payload_path="$(mktemp /var/tmp/geos-hbv4-bootstrap.XXXXXX)"
cleanup() {{ rm -f "${{payload_path}}"; }}
trap cleanup EXIT

if ! base64 --decode <<'__GEOS_HBV4_BOOTSTRAP__' | gzip -dc > "${{payload_path}}"
{wrapped_encoded}
__GEOS_HBV4_BOOTSTRAP__
then
  echo 'GEOS HBv4 bootstrap payload decode failed' >&2
  exit 1
fi
actual_sha256="$(sha256sum "${{payload_path}}" | awk '{{print $1}}')"
if [[ "${{actual_sha256}}" != "${{PAYLOAD_SHA256}}" ]]; then
  echo 'GEOS HBv4 bootstrap payload SHA-256 mismatch' >&2
  exit 1
fi
chmod 0700 "${{payload_path}}"
"${{payload_path}}"
""".encode("ascii")
    if len(wrapper) > AZURE_CUSTOM_DATA_LIMIT:
        raise SystemExit(
            f"Azure custom data is {len(wrapper)} bytes; limit is {AZURE_CUSTOM_DATA_LIMIT}"
        )
    return wrapper


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: render-runner-bootstrap.py INPUT OUTPUT")

    source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    payload = render_payload(source)
    pathlib.Path(sys.argv[2]).write_bytes(wrap_payload(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
