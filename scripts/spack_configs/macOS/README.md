# macOS Homebrew prerequisites

The macOS TPL build uses a deliberately narrow Homebrew boundary. Homebrew
provides the C/Fortran toolchain, MPI, BLAS, CMake, Perl, Python, and selected
build tools listed in [`homebrew-manifest.json`](homebrew-manifest.json).
Diffutils and zlib are intentionally absent from the Homebrew list and are
built by Spack.

The setup is fail-closed for the dependency set. It does not install Homebrew,
update Homebrew, upgrade or downgrade an installed formula, or silently accept
a changed exact-pinned formula definition. The macOS, SDK, Apple Clang, and
Homebrew versions recorded in the manifest identify the qualification host;
they are reported for traceability but are not exact host-version gates.

## One-time prerequisite

Install Homebrew for the machine's architecture using the official installer.
In every shell used for setup and building, make sure Homebrew is on `PATH`:

```console
eval "$(brew shellenv)"
```

The dependency script discovers Homebrew through `PATH` (and also checks the
standard Apple Silicon and Intel install paths). It validates exact versions
and source checksums for the exact-pinned formulas in the manifest. No GEOS tap
or other Homebrew tap is required. CMake only has to satisfy the project
minimum of `3.24`; an installed `mpich` or `open-mpi` satisfies the MPI
requirement.
When neither MPI implementation is installed, normal mode installs `open-mpi`
as the fallback.

## Audit or install

From the `thirdPartyLibs` repository root, audit without changing anything:

```console
scripts/setupMacOS-TPL-deps.bash --check-only
```

To install formulas that are missing and write a host-specific Spack
environment file:

```console
SPACK_CONFIG="${TMPDIR:-/tmp}/geosx-macos-spack.yaml"
scripts/setupMacOS-TPL-deps.bash --spack-config-out "${SPACK_CONFIG}"
```

The generated file contains the detected Apple Clang version, active Homebrew
prefix, selected MPI provider, and generic Darwin constraints. Keep the file
with the build until the TPL installation is complete; it can then be removed.

Apple Clang is the default compiler for C and C++ on macOS. Homebrew GCC is
used only for Fortran because Apple Clang does not provide a Fortran compiler.
The environment uses macOS `curl` for source downloads so certificate
validation uses the system trust store rather than Homebrew Python's OpenSSL
backend.

Then run the TPL build as a separate step. The canonical invocation for this
configuration is:

```console
scripts/uberenv/uberenv.py \
  --spack-env-file="${SPACK_CONFIG}" \
  --prefix=/absolute/path/to/geos-tpls \
  --spec="%c,cxx=apple-clang %fortran=gcc@16.2.0"
```

Use another absolute `--prefix` when the TPL installation belongs elsewhere;
do not reuse a prefix containing a lock file or installation from a different
dependency set.

Installation occurs only when all of the following preflight checks pass:

- the host is Darwin/arm64 and the Apple Command Line Tools are available;
- CMake is at least `3.24`, and either `mpich` or `open-mpi` is available;
- Homebrew reports the exact stable formula version, formula revision, and Ruby
  source checksum for the exact-pinned formulas in the manifest;
- every formula already installed has the exact receipt version and prefix;
- every required executable, header, and library from an installed formula is
  present.

If the preflight succeeds, all missing formulas are installed in one Homebrew
invocation. If neither MPI implementation is present, `open-mpi` is added to
that invocation. The complete set is then checked again, including
metadata, receipts, prefixes, and required paths. A partial or changed
installation is an error.

The script exports `HOMEBREW_NO_AUTO_UPDATE=1`, so the formula metadata visible
to the invoked Homebrew is authoritative for that run. A stale local API cache
is reported as drift instead of being mistaken for the tested formula set.

The generated Spack environment selects the installed MPI provider and its
concrete version. It also selects `/usr/bin/ar` and
`/usr/bin/ranlib` and puts `/usr/bin` ahead of user PATH entries while packages
are built. It also removes Homebrew's keg-only `binutils/bin` directory from
that build PATH. This keeps GNU `ar` from producing archives that Apple's
linker cannot consume; GEOS still receives the required Homebrew `addr2line`
executable through its absolute path in the generated host-config. No global
PATH setup is required beyond Homebrew's `shellenv`.

The checked-in Spack file is the qualification template. Use the generated
file for a build so the compiler identity and Homebrew paths match the current
machine. This configuration remains Apple-Silicon-only (`arm64`/`aarch64`);
the portability change is for macOS and toolchain revisions.

## Expected drift behavior

Homebrew core formulas are moving names, not immutable version selectors. If a
required formula is missing and core no longer offers the manifest version, the
script stops before installing anything. Do not work around this with `brew
upgrade`, an unreviewed downgrade, or `--force` linking. Qualify the newer
dependency set with a clean TPL build and update the manifest and macOS Spack
configuration together.

The checked-in exact formula pins and source checksums come from the official
Homebrew formula API snapshot dated 2026-09-04 and are selected for
qualification. They are not yet described as qualified until a clean TPL build
and its smoke tests pass. The manifest records the exact host used to select
them for traceability, but macOS patch/build revisions, Apple Clang build
revisions, Apple Clang versions, CMake versions at or above `3.24`, MPI provider
choice, and Homebrew executable patch releases are informational rather than
support gates. Homebrew-managed transitive dependencies are not separate Spack
externals; the post-install executable and link-library checks are the local
compatibility guard for this boundary.

## Updating the manifest

Treat a manifest change as a toolchain change:

1. obtain exact-pinned formula versions (`stable`, plus `_<revision>` when the
   formula revision is nonzero) and `ruby_source_checksum.sha256` from
   `brew info --json=v2` or the official formula API; keep CMake at or above
   `3.24` and keep either `mpich` or `open-mpi` available;
2. update the matching external version and prefix in the macOS Spack
   environment;
3. run `scripts/tests/macos_homebrew/test_setupMacOS_TPL_deps.bash`;
4. build into a new, empty TPL prefix;
5. verify the generated Spack lock file uses the declared Homebrew externals
    while diffutils and zlib are non-external and Perl is the declared Homebrew
    external; and
6. compile and run MPI, BLAS, and zlib smoke tests before calling the new set
   qualified.

The dependency script prepares and validates Homebrew and can emit the
host-specific Spack environment. Run uberenv separately after it succeeds. It
also does not initialize BLT. A direct CMake configuration of this repository
requires the BLT submodule, so initialize it first when needed:

```console
git submodule update --init cmake/blt
```
