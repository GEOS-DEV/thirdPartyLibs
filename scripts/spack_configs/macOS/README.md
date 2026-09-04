# macOS Homebrew prerequisites

The macOS TPL build uses a deliberately narrow Homebrew boundary. Homebrew
provides the C/Fortran toolchain, MPI, BLAS, CMake, Python, and selected build
tools listed in [`homebrew-manifest.json`](homebrew-manifest.json). Perl,
diffutils, and zlib are intentionally absent from the Homebrew list and are
built by Spack.

The setup is fail-closed. It does not install Homebrew, update Homebrew, upgrade
or downgrade an installed formula, add taps, or silently accept a newer formula
definition.

## One-time prerequisite

Install Homebrew for Apple Silicon at `/opt/homebrew`, then add the GEOS tap:

```console
brew tap geos-dev/geos
```

The dependency script verifies that this tap already exists, that its `origin`
remote is exactly `https://github.com/GEOS-DEV/homebrew-geos`, and that the
versioned CMake formula has the source checksum recorded in the manifest. It
never adds or rewrites the tap itself.

## Audit or install

From the `thirdPartyLibs` repository root, audit without changing anything:

```console
scripts/setupMacOS-TPL-deps.bash --check-only
```

To install formulas that are missing:

```console
scripts/setupMacOS-TPL-deps.bash
```

Then run the TPL build as a separate step. The canonical invocation for this
configuration is:

```console
scripts/setupMacOS-TPL-deps.bash
scripts/uberenv/uberenv.py \
  --spack-env-file=scripts/spack_configs/macOS/spack.yaml \
  --prefix=/absolute/path/to/geos-tpls \
  --spec="%c,cxx=apple-clang@17.0.0 %fortran=gcc@16.2.0"
```

Use another absolute `--prefix` when the TPL installation belongs elsewhere;
do not reuse a prefix containing a lock file or installation from a different
dependency set.

Installation occurs only when all of the following preflight checks pass:

- the host is Darwin/arm64, the macOS and SDK major versions match the support
  contract, Apple Clang is the required upstream version, and Homebrew uses the
  declared prefix;
- every required tap and tap remote matches;
- Homebrew reports the exact stable formula version, formula revision, and Ruby
  source checksum in the manifest;
- every formula already installed has the exact receipt version and prefix;
- every required executable, header, and library from an installed formula is
  present.

If the preflight succeeds, all missing formulas are installed in one Homebrew
invocation. The complete set is then checked again, including metadata,
receipts, prefixes, and required paths. A partial or changed installation is an
error.

The script exports `HOMEBREW_NO_AUTO_UPDATE=1`, so the formula metadata visible
to the invoked Homebrew is authoritative for that run. A stale local API cache
is reported as drift instead of being mistaken for the tested formula set.

The Spack compiler environment selects `/usr/bin/ar` and `/usr/bin/ranlib` and
puts `/usr/bin` ahead of user PATH entries while packages are built. It also
removes Homebrew's keg-only `binutils/bin` directory from that build PATH. This
keeps GNU `ar` from producing archives that Apple's linker cannot consume;
GEOS still receives the required Homebrew `addr2line` executable through its
absolute path in the generated host-config. No global PATH setup is required.

## Expected drift behavior

Homebrew core formulas are moving names, not immutable version selectors. If a
required formula is missing and core no longer offers the manifest version, the
script stops before installing anything. Do not work around this with `brew
upgrade`, an unreviewed downgrade, or `--force` linking. Either:

1. add a versioned formula to the GEOS tap, or
2. qualify the newer dependency set with a clean TPL build and update the
   manifest and macOS Spack configuration together.

The checked-in formula pins and source checksums come from the official
Homebrew formula API snapshot dated 2026-09-04 and are selected for
qualification. They are not yet described as qualified until a clean TPL build
and its smoke tests pass. The manifest records the exact host used to select
them for traceability, but macOS patch/build revisions, Apple Clang build
revisions, and Homebrew executable patch releases are informational rather than
support gates. Homebrew-managed transitive dependencies are not separate Spack
externals; the post-install executable and link-library checks are the local
compatibility guard for this boundary.

## Updating the manifest

Treat a manifest change as a toolchain change:

1. obtain each formula's package version (`stable`, plus `_<revision>` when the
   formula revision is nonzero) and `ruby_source_checksum.sha256` from
   `brew info --json=v2` or the official formula API;
2. update the matching external version and prefix in the macOS Spack
   environment;
3. run `scripts/tests/macos_homebrew/test_setupMacOS_TPL_deps.bash`;
4. build into a new, empty TPL prefix;
5. verify the generated Spack lock file uses the declared Homebrew externals
   while Perl, diffutils, and zlib are non-external; and
6. compile and run MPI, BLAS, and zlib smoke tests before calling the new set
   qualified.

The dependency script only prepares and validates Homebrew. Run uberenv
separately after it succeeds. It also does not initialize BLT. A direct CMake
configuration of this repository requires the BLT submodule, so initialize it
first when needed:

```console
git submodule update --init cmake/blt
```
