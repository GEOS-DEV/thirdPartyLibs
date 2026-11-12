# macOS Homebrew prerequisites

On Apple Silicon macOS, install Homebrew and the Apple Command Line Tools,
then run from the repository root:

```console
eval "$(brew shellenv)"
scripts/setupMacOS-TPL-deps.bash --check-only
```

To install missing formulas and generate the Spack environment for this host:

```console
SPACK_CONFIG="${TMPDIR:-/tmp}/geosx-macos-spack.yaml"
scripts/setupMacOS-TPL-deps.bash --spack-config-out "${SPACK_CONFIG}"
```

Use the generated file with uberenv's `--spack-env-file` option. It records
the detected Apple Clang, Perl, Homebrew prefix, MPI provider, and installed
versions for one-to-one Homebrew/Spack mappings. Setup validates the full set
before installing anything and never upgrades or downgrades installed formulas.
CMake has a separate minimum of `3.24`; installed MPICH or OpenMPI satisfies
MPI, with OpenMPI installed as the fallback.

[`homebrew-manifest.json`](homebrew-manifest.json) records qualified version
floors, so equal or newer versions are accepted. CI does not need to chase
Homebrew releases. A same-version formula-file checksum change is reported
and accepted.

Edit the manifest when the oldest supported version needs to change, a newer
release requires a compatibility change, or required paths or prefixes change.
Update the matching external in [`spack.yaml`](spack.yaml), run
`scripts/tests/macos_homebrew/test_setupMacOS_TPL_deps.bash`, and qualify the
change with a fresh TPL build and MPI, BLAS, and zlib smoke tests.
