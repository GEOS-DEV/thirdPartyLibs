# HBv4 TPL validation assets

These scripts split tester-host facts from fresh-container image validation.
They make no cloud API calls and never dump the process environment.

Run `validate-host.sh` on the tester VM before launching a container:

```sh
scripts/hbv4/validate-host.sh \
  --instance-type Standard_HB176rs_v4 \
  --compiler-flags 'target=zen4 -march=native -mtune=native -O3' \
  --writable-path /mnt/hbv4-local/container-tmp
```

The instance type must come from the CI/cloud control-plane metadata step. The
script independently checks the 9V33X CPU identity, 176 visible CPUs, AVX-512,
explicit Zen 4 target evidence, required `-march=native` and `-mtune=native`,
and the exact two-member md RAID0 XFS mount at `/mnt/hbv4-local`. It rejects
`-mcpu=native`. The required writable path must resolve to that same XFS RAID
mount. The mount root intentionally remains root-owned; callers should select a
runner-owned workspace or the mode-`1777` `container-tmp` child.

Embed `validate-hbv4-tpls` and `parallel_hdf5_shared.c` together at
`/opt/GEOS/bin/`. In a fresh tester container, bind-mount the validated host
mount at (for example) `/hbv4-scratch`, then run:

```sh
/opt/GEOS/bin/validate-hbv4-tpls --provider openmpi --scratch /hbv4-scratch
/opt/GEOS/bin/validate-hbv4-tpls --provider mpich --scratch /hbv4-scratch
```

These commands belong in their respective images, not in one combined image.
The OpenMPI image runs the shared-file test once with `io/ompio` and once with
`io/romio341`; the MPICH image runs it with ROMIO. All MPI tests use four ranks.
Before changing the test environment, the validator checks the image-provided
`MPI_PROVIDER`, `MPI_HOME`, wrapper/launcher variables, `PATH`, and loader path.
It requires all four MPI executables to resolve below the exact provider prefix,
requires the alternate provider tree to be absent, and rejects Debian MPI
packages plus MPI libraries or commands under `/usr`. The package database check
is skipped only on images without `dpkg-query`; filesystem checks still run.
The fresh-container validator first verifies every checksum and field under
`/opt/GEOS/hbv4-build-evidence`. The image integration must also copy or link
the checksummed `mpi-provider.json` to `/opt/GEOS/mpi-provider.json`; the two
files must match byte-for-byte. A sanitized Spack build log is mandatory for a
passing image, even though its collector input variable is optional to support
non-HBv4 diagnostic use of the collector.

Build evidence is collected with this stable interface:

```sh
HBV4_TPL_SHA="$tpl_sha" HBV4_COMPILER_FLAGS="$compiler_flags" \
  scripts/hbv4/collect-build-evidence.sh \
  /opt/GEOS/hbv4-build-evidence openmpi "$source_sha" "$base_digest" \
  /tmp/mpi-configure-args.txt /tmp/generated-spack-concretization.txt
```

`SOURCE_SHA` and `HBV4_TPL_SHA` are lowercase, 40-hex repository commits;
`BASE_IMAGE` must be an immutable `repository@sha256:<64 lowercase hex>` base
image reference. The provider's pinned MPI
archive SHA-256 is recorded separately. The final positional input must be an
actual generated Spack lock/spec or concretization log, not merely the source
manifest. Set `HBV4_SPACK_BUILD_LOG` to copy one sanitized Spack build log.
`HBV4_MPIEXEC` can explicitly name the provider launcher; it must resolve below
the exact provider prefix. Other optional path/version variables are documented
by `--help`; they are read only when explicitly supplied. The output is a
`manifest.json`, referenced evidence files, and `checksums.sha256`.
