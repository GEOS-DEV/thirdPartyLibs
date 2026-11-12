# macOS Homebrew prerequisites

The macOS TPL build uses a deliberately narrow Homebrew boundary. Homebrew
provides the C/Fortran toolchain, MPI, BLAS, CMake, Perl, Python, and selected
build tools listed in [`homebrew-manifest.json`](homebrew-manifest.json).
Diffutils and zlib are intentionally absent from the Homebrew list and are
built by Spack.

The setup is fail-closed for the dependency set. It does not install Homebrew,
update Homebrew, or upgrade or downgrade an installed formula. Qualified
formula versions in the manifest are minimums: a newer Homebrew release is
accepted, and an older one is rejected. The macOS, SDK, Apple Clang, and
Homebrew versions recorded in the manifest identify the qualification host;
they are reported for traceability but are not exact host-version gates. A
rewritten Homebrew formula file with the same version is also reported and
accepted.

## One-time prerequisite

Install Homebrew for the machine's architecture using the official installer.
In every shell used for setup and building, make sure Homebrew is on `PATH`:

```console
eval "$(brew shellenv)"
```

The dependency script discovers Homebrew through `PATH` (and also checks the
standard Apple Silicon and Intel install paths). It accepts each qualified
formula at the manifest version or newer. No GEOS tap
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
- Homebrew reports a stable formula version at or above the qualified version
  for each formula whose policy is the default minimum floor;
- every formula already installed meets that floor and uses the expected prefix;
- every required executable, header, and library from an installed formula is
  present.

If the preflight succeeds, all missing formulas are installed in one Homebrew
invocation. If neither MPI implementation is present, `open-mpi` is added to
that invocation. The complete set is then checked again, including
metadata, receipts, prefixes, and required paths. A partial or changed
installation is an error.

The script exports `HOMEBREW_NO_AUTO_UPDATE=1`, so the formula metadata visible
to the invoked Homebrew is authoritative for that run. A version older than
the qualified floor is rejected. A newer version is accepted, and when the
manifest maps that formula's Homebrew and Spack versions one-to-one, the
generated Spack environment records the installed version. A formula-file
checksum that differs while the version still matches is printed and does not
fail the run.

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

Homebrew core formulas move independently of this repository. The manifest
records the oldest qualified version, not the version that must be installed.
A GitHub-hosted macOS runner that already has a newer formula satisfies the
floor; do not edit the manifest just to match that runner. Update the floor
when a newer formula breaks the TPL build, when a required path changes (for
example the `gfortran-16` executable), or when the oldest accepted version
itself should move. Do not work around a too-old formula with an unreviewed
downgrade or `--force` linking. If a required formula is missing and Homebrew
no longer offers a version at or above the floor, the script stops before
installing anything.

The checked-in formula versions and source checksums come from the official
Homebrew formula API and are the qualified floors. The manifest records the
host used to select them for traceability, but macOS patch/build revisions,
Apple Clang build revisions, Apple Clang versions, CMake versions at or above
`3.24`, MPI provider choice, newer Homebrew formula releases, and later
rewrites of a formula file that keep the same version are not support gates.
Homebrew-managed transitive dependencies are not separate Spack externals; the
post-install executable and link-library checks are the local compatibility
guard for this boundary.

## Updating the manifest

A newer Homebrew release does not by itself require a manifest change. The
generated Spack environment records that release when the formula's Homebrew
and Spack versions match. Change the manifest when the qualified floor should
move, or when a required path or prefix changes:

1. obtain the new floor (`stable`, plus `_<revision>` when the formula
   revision is nonzero) from `brew info --json=v2` or the official formula
   API; record `ruby_source_checksum.sha256` for the qualification snapshot,
   but do not treat a later formula-file rewrite as a failure; keep CMake at
   or above `3.24` and keep either `mpich` or `open-mpi` available;
2. update the matching external version and prefix in the macOS Spack
   environment when the checked-in template should show the new floor;
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
