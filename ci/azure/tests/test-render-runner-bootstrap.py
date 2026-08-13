#!/usr/bin/env python3
"""Offline contract tests for the reviewed Azure custom-data renderer."""

from __future__ import annotations

import base64
import gzip
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RENDERER = REPOSITORY_ROOT / "ci/azure/scripts/render-runner-bootstrap.py"
BOOTSTRAP = REPOSITORY_ROOT / "ci/azure/scripts/runner-bootstrap.sh"
STORAGE_HELPER = REPOSITORY_ROOT / "ci/azure/scripts/setup-hbv4-local-nvme.sh"
HOST_VALIDATOR = REPOSITORY_ROOT / "scripts/hbv4/validate-host.sh"
CONTAINER_VALIDATOR = REPOSITORY_ROOT / "scripts/hbv4/validate-hbv4-tpls"
PARALLEL_HDF5_SOURCE = REPOSITORY_ROOT / "scripts/hbv4/parallel_hdf5_shared.c"
AZURE_CUSTOM_DATA_LIMIT = 65_535


class RunnerBootstrapRendererContract(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.helper_payload = STORAGE_HELPER.read_bytes()
        self.helper_digest = hashlib.sha256(self.helper_payload).hexdigest()
        self.helper_gzip_base64 = base64.b64encode(
            gzip.compress(self.helper_payload, compresslevel=9, mtime=0)
        ).decode("ascii")

        def encoded_file(path: Path) -> tuple[str, str]:
            payload = path.read_bytes()
            digest = hashlib.sha256(payload).hexdigest()
            encoded = base64.b64encode(
                gzip.compress(payload, compresslevel=9, mtime=0)
            ).decode("ascii")
            return digest, encoded

        host_digest, host_encoded = encoded_file(HOST_VALIDATOR)
        container_digest, container_encoded = encoded_file(CONTAINER_VALIDATOR)
        parallel_digest, parallel_encoded = encoded_file(PARALLEL_HDF5_SOURCE)
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "RUNNER_ENCODED_JITCONFIG": "Zml4dHVyZS1qaXQtY29uZmln",
                "RUNNER_VERSION": "2.335.1",
                "RUNNER_TARBALL_SHA256": "a" * 64,
                "ACR_NAME": "geoscifixture",
                "RUNNER_VM_UAMI_CLIENT_ID": "00000000-0000-4000-8000-000000000001",
                "RUNNER_STORAGE_PROFILE": "hbv4-nvme-raid0",
                "STORAGE_HELPER_SHA256": self.helper_digest,
                "STORAGE_HELPER_GZIP_BASE64": self.helper_gzip_base64,
                "HOST_VALIDATOR_SHA256": host_digest,
                "HOST_VALIDATOR_GZIP_BASE64": host_encoded,
                "CONTAINER_VALIDATOR_SHA256": container_digest,
                "CONTAINER_VALIDATOR_GZIP_BASE64": container_encoded,
                "PARALLEL_HDF5_SOURCE_SHA256": parallel_digest,
                "PARALLEL_HDF5_SOURCE_GZIP_BASE64": parallel_encoded,
            }
        )

    def render(
        self,
        *,
        environment: dict[str, str] | None = None,
        source: Path = BOOTSTRAP,
    ) -> tuple[subprocess.CompletedProcess[str], bytes]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "custom-data.sh"
            completed = subprocess.run(
                [sys.executable, str(RENDERER), str(source), str(output)],
                check=False,
                env=environment or self.environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            payload = output.read_bytes() if output.exists() else b""
        return completed, payload

    @staticmethod
    def assignment(payload: str, variable: str) -> str:
        match = re.search(
            rf'^{re.escape(variable)}="([^"]*)"$', payload, flags=re.MULTILINE
        )
        if match is None:
            raise AssertionError(f"rendered payload omitted {variable}")
        return match.group(1)

    @staticmethod
    def unwrap(wrapper: bytes) -> tuple[bytes, str]:
        wrapper_text = wrapper.decode("ascii")
        digest_match = re.search(
            r"^readonly PAYLOAD_SHA256='([0-9a-f]{64})'$",
            wrapper_text,
            flags=re.MULTILINE,
        )
        if digest_match is None:
            raise AssertionError("custom-data wrapper omitted PAYLOAD_SHA256")
        payload_match = re.search(
            r"^if ! base64 --decode <<'__GEOS_HBV4_BOOTSTRAP__' \| gzip -dc > "
            r'"\$\{payload_path\}"\n(?P<encoded>[A-Za-z0-9+/=\n]+)'
            r"^__GEOS_HBV4_BOOTSTRAP__$",
            wrapper_text,
            flags=re.MULTILINE,
        )
        if payload_match is None:
            raise AssertionError("custom-data wrapper omitted its encoded payload")
        encoded = "".join(payload_match.group("encoded").splitlines())
        payload = gzip.decompress(base64.b64decode(encoded, validate=True))
        return payload, digest_match.group(1)

    def test_renders_ascii_payload_and_embeds_exact_storage_helper(self) -> None:
        completed, rendered_bytes = self.render()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertGreater(len(rendered_bytes), 0)
        self.assertLessEqual(len(rendered_bytes), AZURE_CUSTOM_DATA_LIMIT)

        wrapper = rendered_bytes.decode("ascii")
        self.assertIn("base64 --decode", wrapper)
        self.assertIn("gzip -dc", wrapper)
        self.assertIn('"${payload_path}"', wrapper)
        self.assertNotIn('exec "${payload_path}"', wrapper)

        inner_bytes, wrapper_digest = self.unwrap(rendered_bytes)
        self.assertEqual(hashlib.sha256(inner_bytes).hexdigest(), wrapper_digest)
        self.assertGreater(len(inner_bytes), 0)
        rendered = inner_bytes.decode("ascii")
        self.assertNotRegex(wrapper, r"@@[A-Z0-9_]+@@")
        self.assertNotRegex(rendered, r"@@[A-Z0-9_]+@@")
        self.assertEqual(
            self.assignment(rendered, "RUNNER_STORAGE_PROFILE"),
            "hbv4-nvme-raid0",
        )
        self.assertEqual(
            self.assignment(rendered, "RUNNER_ENCODED_JITCONFIG"),
            self.environment["RUNNER_ENCODED_JITCONFIG"],
        )
        self.assertIn("download_with_retries() {", rendered)
        self.assertIn("for attempt in 1 2 3 4 5; do", rendered)
        self.assertIn("--connect-timeout 20", rendered)
        self.assertIn("--max-time 180", rendered)
        self.assertIn("curl ca-certificates jq gh git git-lfs", rendered)
        self.assertIn(
            '"${tmp}/${tarball}" \\\n    "GitHub Actions runner tarball"',
            rendered,
        )

        encoded_helper = self.assignment(rendered, "STORAGE_HELPER_GZIP_BASE64")
        embedded_digest = self.assignment(rendered, "STORAGE_HELPER_SHA256")
        decoded_helper = gzip.decompress(base64.b64decode(encoded_helper, validate=True))
        decoded_digest = hashlib.sha256(decoded_helper).hexdigest()
        self.assertEqual(decoded_helper, self.helper_payload)
        self.assertEqual(len(decoded_helper), len(self.helper_payload))
        self.assertEqual(embedded_digest, self.helper_digest)
        self.assertEqual(decoded_digest, embedded_digest)

    def test_missing_required_value_fails_without_output(self) -> None:
        environment = self.environment.copy()
        environment.pop("RUNNER_STORAGE_PROFILE")
        completed, rendered = self.render(environment=environment)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(rendered, b"")
        self.assertIn("RUNNER_STORAGE_PROFILE", completed.stderr)

    def test_multiline_value_is_rejected(self) -> None:
        environment = self.environment.copy()
        environment["ACR_NAME"] = "registry\nsecond-line"
        completed, rendered = self.render(environment=environment)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(rendered, b"")
        self.assertIn("not single-line", completed.stderr)

    def test_duplicate_marker_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = Path(temporary_directory) / "duplicate-marker.sh"
            source.write_text(
                BOOTSTRAP.read_text(encoding="utf-8") + "\n@@ACR_NAME@@\n",
                encoding="utf-8",
            )
            completed, rendered = self.render(source=source)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(rendered, b"")
        self.assertIn("@@ACR_NAME@@ must occur exactly once", completed.stderr)

    def test_unknown_marker_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = Path(temporary_directory) / "unknown-marker.sh"
            source.write_text(
                BOOTSTRAP.read_text(encoding="utf-8") + "\n@@UNREVIEWED_VALUE@@\n",
                encoding="utf-8",
            )
            completed, rendered = self.render(source=source)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(rendered, b"")
        self.assertIn("unrecognized template placeholder", completed.stderr)

    def test_payload_larger_than_azure_limit_is_rejected(self) -> None:
        environment = self.environment.copy()
        # Incompressible base64 models a large real JIT payload; a repeated
        # character would compress below Azure's custom-data limit.
        environment["RUNNER_ENCODED_JITCONFIG"] = base64.b64encode(
            os.urandom(90_000)
        ).decode("ascii")
        completed, rendered = self.render(environment=environment)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(rendered, b"")
        self.assertIn("Azure custom data", completed.stderr)
        self.assertIn("limit is 65535", completed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
