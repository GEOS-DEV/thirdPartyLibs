#!/usr/bin/env bash
#
# Unified driver to build the GEOS third-party libraries.
#
# Supported configurations:
#   z5tux        gcc + mpich, host only
#   z5tux-cuda   gcc + mpich + CUDA (sm_120)
#   z5tux-hip    amdclang + mpich + ROCm (gfx1100)
#   z5tux-sycl   not supported yet (see NOTES below)
#   matrix       gcc + mvapich2 + CUDA (sm_90)
#   tioga        amdclang + cray-mpich + ROCm (gfx90a)
#   tuo-cpu      amdclang + cray-mpich, host only
#   tuo-gpu      amdclang + cray-mpich + ROCm (gfx942)
#
# By default the TPLs are built with the CMake superbuild of this repository
# (CMakeLists.txt), configured with the Ninja generator both for the superbuild
# itself and for every sub-project (-DENABLE_NINJA=ON).  With --spack the same
# configurations are built through uberenv/spack instead.
#
# The script is meant to be run *on* the target machine: on the LC systems,
# clone/copy this repository there and run it from a login node (optionally
# with --alloc to push the compilation onto a compute node).
#
# NOTES
#   * z5tux-sycl is declared but disabled: neither the superbuild nor the spack
#     packages have SYCL plumbing, and no SYCL toolchain is installed on z5tux.
#   * Trilinos is off by default (GEOS defaults to the hypre interface); enable
#     it with --trilinos.
#   * The ROCm configurations compile Fortran with gfortran, not amdflang: the
#     flang runtime is not pulled in when clang++ links Fortran objects, which
#     breaks superlu_dist. Override with --fc if needed.
#   * Known issue: ROCm 7.2 (AMD clang 22) miscompiles hypre's spgemm kernels
#     for gfx942/gfx1100 ("Illegal instruction detected: Operand has incorrect
#     register class"); gfx90a is fine. LC uses ROCm 6.4.3, which is unaffected.
#
# Usage:  ./build.sh [config] [options] [-D<var>=<value> ...]
# Run     ./build.sh --help    for the full option list.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------
CONFIG=""
BUILD_TYPE="Release"
BUILD_DIR=""
INSTALL_DIR=""
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"
TOP_JOBS=1
GENERATOR="auto"          # auto | ninja | make
GPU_ARCH=""               # overrides the per-config cuda arch / amdgpu target
ROCM_DIR_OPT=""
CUDA_DIR_OPT=""
MPI_DIR_OPT=""
FC_OPT=""
USE_ALLOC=0
ALLOC_CMD=""
ACCOUNT="${GEOS_TPL_ACCOUNT:-vortex}"
LOAD_MODULES=1
MODULES_OPT=""
CLEAN=0
DO_CONFIGURE=1
DO_BUILD=1
USE_SPACK=0
SPACK_SPEC_OPT=""
ENABLE_TRILINOS="OFF"
ENABLE_OPENMP=""          # per-config default unless set here
ENABLE_ROCTX="OFF"
ENABLE_SUPERLU_DIST="ON"
ENABLE_HYPRE_GPU_PROFILING="OFF"
DRY_RUN=0
LOG_FILE=""
EXTRA_CMAKE_ARGS=()
FORWARDED_ARGS=()

# Populated by select_config()
CFG_DESC=""
CFG_SUPPORTED=1
CFG_UNSUPPORTED_REASON=""
CMAKE_ARGS=()
MPI_PREFIX=""       # set by the setup_*_mpi helpers, used by setup_hip

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "${SCRIPT_NAME}" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

run() {
  printf '[%s] + %s\n' "${SCRIPT_NAME}" "$*"
  if [[ ${DRY_RUN} -eq 0 ]]; then
    "$@"
  fi
}

# Newest (version-sorted) existing path matching the given glob, empty if none.
newest_path() {
  local match
  # shellcheck disable=SC2086  # deliberate globbing
  match="$(ls -d $1 2>/dev/null | sort -V | tail -1 || true)"
  printf '%s' "${match}"
}

require_file() {
  [[ -e "$1" ]] || die "${2:-required file} not found: $1"
}

require_exec() {
  [[ -x "$1" ]] || die "${2:-required executable} not found or not executable: $1"
}

add_arg() { CMAKE_ARGS+=( "$@" ); }

usage() {
  cat <<EOF
Build the GEOS third-party libraries.

Usage:
  ./${SCRIPT_NAME} [config] [options] [-D<var>=<value> ...] [-- <extra args>]

Configurations (auto-detected from the hostname when omitted):
  z5tux        gcc + mpich, host only
  z5tux-cuda   gcc + mpich + CUDA, sm_120
  z5tux-hip    amdclang + mpich + ROCm, gfx1100
  z5tux-sycl   not supported yet
  matrix       gcc + mvapich2 + CUDA, sm_90            (LC)
  tioga        amdclang + cray-mpich + ROCm, gfx90a    (LC)
  tuo-cpu      amdclang + cray-mpich, host only        (LC, tuolumne)
  tuo-gpu      amdclang + cray-mpich + ROCm, gfx942    (LC, tuolumne)

Options:
  -bt, --build-type <type>   Release|RelWithDebInfo|Debug|MinSizeRel (default: ${BUILD_TYPE})
  -b,  --build-dir <path>    build directory   (default: <repo>/build-<config>-<buildtype>)
  -i,  --install-dir <path>  install directory (default: <repo>/install-<config>-<buildtype>)
  -j,  --jobs <n>            parallelism inside each TPL (default: ${JOBS})
       --top-jobs <n>        TPLs built concurrently (default: ${TOP_JOBS})
       --generator <g>       auto|ninja|make (default: auto, prefers ninja)
       --gpu-arch <arch>     override the cuda arch (e.g. 90) or amdgpu target (e.g. gfx942)
       --rocm <path>         ROCm installation to use
       --cuda <path>         CUDA toolkit to use
       --mpi <path>          MPI installation to use (expects <path>/bin/mpicc)
       --fc <path>           Fortran compiler to use
       --trilinos            build Trilinos as well (off by default)
       --openmp <ON|OFF>     override the per-configuration OpenMP setting
       --roctx               enable ROCTx/rocm profiling support (raja, caliper, hypre)
       --superlu <ON|OFF>    build superlu_dist and link it into hypre (default: ${ENABLE_SUPERLU_DIST})
       --gpu-profiling       configure hypre with --enable-gpu-profiling (nvtx/roctx)
       --alloc               run the build step through the machine's scheduler
       --alloc-cmd <cmd>     scheduler command to use with --alloc
       --account <bank>      bank used by --alloc (default: ${ACCOUNT})
       --modules "<m1 m2>"   replace the default module list
       --no-modules          do not touch modules at all
       --spack               build through uberenv/spack instead of the cmake superbuild
       --spec "<spec>"       spack spec to build (implies --spack)
       --clean               remove the build and install directories first
       --configure-only      stop after the cmake configure step
       --build-only          skip the configure step (reuse an existing build directory)
       --log <file>          also write the output to <file>
  -n,  --dry-run             print the commands instead of running them
  -l,  --list                list the configurations and exit
  -h,  --help                show this help and exit

  Any -D<var>=<value> argument is forwarded to cmake (or, with --spack, any
  argument after -- is forwarded to uberenv.py).

Examples:
  ./${SCRIPT_NAME} z5tux
  ./${SCRIPT_NAME} z5tux-cuda -bt RelWithDebInfo -j 24
  ./${SCRIPT_NAME} z5tux-hip --gpu-arch gfx1036
  ./${SCRIPT_NAME} tuo-gpu --alloc                     # on a tuolumne login node
  ./${SCRIPT_NAME} matrix --spack                      # same config, through spack
  ./${SCRIPT_NAME} tioga -DENABLE_VTK=OFF
EOF
}

# Static description of each configuration: used by --list and by the run banner,
# so that neither needs the toolchain to be resolved first.
describe_config() {
  case "$1" in
    z5tux)                        printf 'z5tux: gcc + mpich, host only' ;;
    z5tux-cuda)                   printf 'z5tux: gcc + mpich + CUDA, sm_%s' "${GPU_ARCH:-120}" ;;
    z5tux-hip)                    printf 'z5tux: amdclang + mpich + ROCm, %s' "${GPU_ARCH:-gfx1100}" ;;
    z5tux-sycl)                   printf 'z5tux: SYCL (Intel Battlemage)' ;;
    matrix)                       printf 'matrix: gcc + mvapich2 + CUDA, sm_%s' "${GPU_ARCH:-90}" ;;
    tioga|tioga-gpu)              printf 'tioga: amdclang + cray-mpich + ROCm, %s' "${GPU_ARCH:-gfx90a}" ;;
    tuo-cpu|tuolumne-cpu)         printf 'tuolumne: amdclang + cray-mpich, host only' ;;
    tuo-gpu|tuolumne-gpu|tuolumne) printf 'tuolumne: amdclang + cray-mpich + ROCm, %s' "${GPU_ARCH:-gfx942}" ;;
    *)                            printf '' ;;
  esac
}

# Modules to load on the LC machines. Kept separate from select_config() so that
# they are loaded *before* the compilers and cmake/ninja are looked up.
modules_for_config() {
  case "$1" in
    matrix)
      printf '%s\n' "gcc/13.3.1-magic" "mvapich2/2.3.7" "cuda/12.9.1" "cmake/3.30.5" "ninja" ;;
    tioga|tioga-gpu|tuo-cpu|tuo-gpu|tuolumne|tuolumne-cpu|tuolumne-gpu)
      printf '%s\n' "rocm" "cray-mpich" "cmake/3.29" "ninja" ;;
    *)
      ;;
  esac
}

# Machine a configuration runs on (used for the scheduler defaults).
machine_for_config() {
  case "$1" in
    z5tux|z5tux-cuda|z5tux-hip|z5tux-sycl)  printf 'z5tux' ;;
    matrix)                                 printf 'matrix' ;;
    tioga|tioga-gpu)                        printf 'tioga' ;;
    tuo-cpu|tuo-gpu|tuolumne*)              printf 'tuolumne' ;;
    *)                                      printf '' ;;
  esac
}

# Spack spec used by --spack, mirroring scripts/setupLC-TPL-uberenv.bash.
# '%%' propagates the compiler choice to the dependencies (spack v1 syntax).
spack_spec_for_config() {
  case "$1" in
    z5tux)
      printf '~docs %%gcc ^vtk generator=ninja' ;;
    z5tux-cuda)
      printf '+cuda ~uncrustify ~docs cuda_arch=%s %%gcc ^vtk generator=ninja' "${GPU_ARCH:-120}" ;;
    z5tux-hip)
      printf '+rocm ~pygeosx ~trilinos ~petsc ~docs amdgpu_target=%s %%llvm-amdgpu ^vtk generator=ninja' "${GPU_ARCH:-gfx1100}" ;;
    matrix)
      printf '+cuda ~uncrustify cuda_arch=%s %%%%gcc-13 ^cuda@12.9.1+allow-unsupported-compilers ^vtk generator=ninja' "${GPU_ARCH:-90}" ;;
    tioga|tioga-gpu)
      printf '+rocm ~pygeosx ~trilinos ~petsc ~docs amdgpu_target=%s %%%%cce-20 ^vtk generator=ninja' "${GPU_ARCH:-gfx90a}" ;;
    tuo-cpu|tuolumne-cpu)
      printf '~pygeosx ~trilinos ~petsc ~docs %%%%cce-20 ^vtk generator=ninja' ;;
    tuo-gpu|tuolumne-gpu|tuolumne)
      printf '+rocm ~pygeosx ~trilinos ~petsc ~docs amdgpu_target=%s %%%%cce-20 ^vtk generator=ninja' "${GPU_ARCH:-gfx942}" ;;
    *)
      printf '' ;;
  esac
}

# Configurations that cannot be built (yet); prints the reason.
unsupported_reason() {
  case "$1" in
    z5tux-sycl) printf 'no SYCL support in the superbuild nor in the spack packages, and no SYCL toolchain installed on z5tux' ;;
    *)          printf '' ;;
  esac
}

list_configs() {
  local cfg
  printf '%-12s %s\n' "CONFIG" "DESCRIPTION"
  for cfg in z5tux z5tux-cuda z5tux-hip matrix tioga tuo-cpu tuo-gpu; do
    printf '%-12s %s\n' "${cfg}" "$(describe_config "${cfg}")"
  done
  printf '%-12s %s [UNSUPPORTED: %s]\n' "z5tux-sycl" "$(describe_config z5tux-sycl)" \
    "no SYCL support in the superbuild nor in the spack packages"
}

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)          usage; exit 0 ;;
    -l|--list)          list_configs; exit 0 ;;
    -bt|--build-type)   BUILD_TYPE="${2:?"missing value for $1"}"; shift 2 ;;
    -b|--build-dir)     BUILD_DIR="${2:?"missing value for $1"}"; shift 2 ;;
    -i|--install-dir)   INSTALL_DIR="${2:?"missing value for $1"}"; shift 2 ;;
    -j|--jobs)          JOBS="${2:?"missing value for $1"}"; shift 2 ;;
    --top-jobs)         TOP_JOBS="${2:?"missing value for $1"}"; shift 2 ;;
    --generator)        GENERATOR="${2:?"missing value for $1"}"; shift 2 ;;
    --gpu-arch)         GPU_ARCH="${2:?"missing value for $1"}"; shift 2 ;;
    --rocm)             ROCM_DIR_OPT="${2:?"missing value for $1"}"; shift 2 ;;
    --cuda)             CUDA_DIR_OPT="${2:?"missing value for $1"}"; shift 2 ;;
    --mpi)              MPI_DIR_OPT="${2:?"missing value for $1"}"; shift 2 ;;
    --fc)               FC_OPT="${2:?"missing value for $1"}"; shift 2 ;;
    --trilinos)         ENABLE_TRILINOS="ON"; shift ;;
    --openmp)           ENABLE_OPENMP="${2:?"missing value for $1"}"; shift 2 ;;
    --roctx)            ENABLE_ROCTX="ON"; shift ;;
    --superlu)          ENABLE_SUPERLU_DIST="${2:?"missing value for $1"}"; shift 2 ;;
    --gpu-profiling)    ENABLE_HYPRE_GPU_PROFILING="ON"; shift ;;
    --alloc)            USE_ALLOC=1; shift ;;
    --alloc-cmd)        ALLOC_CMD="$2"; USE_ALLOC=1; shift 2 ;;
    --account)          ACCOUNT="${2:?"missing value for $1"}"; shift 2 ;;
    --modules)          MODULES_OPT="${2:?"missing value for $1"}"; shift 2 ;;
    --no-modules)       LOAD_MODULES=0; shift ;;
    --spack)            USE_SPACK=1; shift ;;
    --spec)             SPACK_SPEC_OPT="${2:?"missing value for $1"}"; USE_SPACK=1; shift 2 ;;
    --clean)            CLEAN=1; shift ;;
    --configure-only)   DO_BUILD=0; shift ;;
    --build-only)       DO_CONFIGURE=0; shift ;;
    --log)              LOG_FILE="${2:?"missing value for $1"}"; shift 2 ;;
    -n|--dry-run)       DRY_RUN=1; shift ;;
    -D*)                EXTRA_CMAKE_ARGS+=( "$1" ); shift ;;
    --)                 shift; FORWARDED_ARGS+=( "$@" ); break ;;
    -*)                 die "unknown option '$1' (see --help)" ;;
    *)
      [[ -z "${CONFIG}" ]] || die "more than one configuration given ('${CONFIG}' and '$1')"
      CONFIG="$1"; shift ;;
  esac
done

# ------------------------------------------------------------------------------
# Configurations
# ------------------------------------------------------------------------------

# Compilers + MPI wrappers of the mpich installation used on z5tux.
setup_z5tux_mpi() {
  local mpi_dir="${MPI_DIR_OPT:-${MPICH_HOME:-/home/victor/projects/mpich-4.2.2/install/release}}"
  require_exec "${mpi_dir}/bin/mpicc" "mpicc (use --mpi <path>)"
  add_arg -DENABLE_MPI=ON \
          -DMPI_C_COMPILER="${mpi_dir}/bin/mpicc" \
          -DMPI_CXX_COMPILER="${mpi_dir}/bin/mpicxx" \
          -DMPI_Fortran_COMPILER="${mpi_dir}/bin/mpifort" \
          -DMPIEXEC_EXECUTABLE="${mpi_dir}/bin/mpirun" \
          -DMPIEXEC_NUMPROC_FLAG="-np"
  MPI_PREFIX="${mpi_dir}"
}

# The mpich/cray-mpich wrappers pick their back-end compiler from these.
export_mpich_backend() {
  export MPICH_CC="$1"
  export MPICH_CXX="$2"
  export MPICH_FC="$3"
  export MPICH_F90="$3"
}

# ROCm installation: --rocm, then $ROCM_PATH, then the newest /opt/rocm-*.
resolve_rocm() {
  local rocm="${ROCM_DIR_OPT:-${ROCM_PATH:-}}"
  if [[ -z "${rocm}" ]]; then
    rocm="$(newest_path '/opt/rocm-*')"
    [[ -n "${rocm}" ]] || rocm="/opt/rocm"
  fi
  [[ -d "${rocm}" ]] || die "ROCm installation not found (tried '${rocm}', use --rocm <path>)"
  printf '%s' "${rocm}"
}

# CUDA toolkit: --cuda, then $CUDA_HOME, then the LC/system locations.
resolve_cuda() {
  local cuda="${CUDA_DIR_OPT:-${CUDA_HOME:-}}"
  if [[ -z "${cuda}" ]]; then
    cuda="$(newest_path '/usr/tce/packages/cuda/cuda-*')"
    [[ -n "${cuda}" ]] || cuda="$(newest_path '/usr/local/cuda-*')"
    [[ -n "${cuda}" ]] || cuda="/usr/local/cuda"
  fi
  [[ -d "${cuda}" ]] || die "CUDA toolkit not found (tried '${cuda}', use --cuda <path>)"
  printf '%s' "${cuda}"
}

# Fortran compiler paired with the ROCm toolchain. gfortran is preferred over
# amdflang: clang++ links Fortran objects without the flang runtime, which
# breaks the mixed-language TPLs (superlu_dist).
resolve_fortran() {
  local rocm="$1" fc
  if [[ -n "${FC_OPT}" ]]; then
    printf '%s' "${FC_OPT}"; return 0
  fi
  for fc in /usr/bin/gfortran \
            "$(newest_path '/usr/tce/packages/gcc-tce/gcc-*/bin/gfortran')" \
            "$(newest_path '/usr/tce/packages/gcc/gcc-*-magic/bin/gfortran')"; do
    if [[ -n "${fc}" && -x "${fc}" ]]; then
      printf '%s' "${fc}"; return 0
    fi
  done
  warn "no gfortran found, falling back to amdflang (mixed C++/Fortran TPLs may fail to link)"
  printf '%s' "${rocm}/llvm/bin/amdflang"
}

# amdclang/amdclang++ out of a ROCm installation, plus a Fortran compiler.
setup_rocm_compilers() {
  local rocm="$1"
  local cc="${rocm}/llvm/bin/amdclang"
  local cxx="${rocm}/llvm/bin/amdclang++"
  local fc
  fc="$(resolve_fortran "${rocm}")"
  require_exec "${cc}" "amdclang"
  require_exec "${cxx}" "amdclang++"
  require_exec "${fc}" "Fortran compiler (use --fc <path>)"
  add_arg -DCMAKE_C_COMPILER="${cc}" \
          -DCMAKE_CXX_COMPILER="${cxx}" \
          -DCMAKE_Fortran_COMPILER="${fc}"
  export_mpich_backend "${cc}" "${cxx}" "${fc}"
}

# HIP settings shared by z5tux-hip, tioga and tuo-gpu.
setup_hip() {
  local rocm="$1" arch="$2"
  # cmake's HIP language requires clang itself, the hipcc wrapper is rejected.
  require_exec "${rocm}/llvm/bin/amdclang++" "amdclang++"
  add_arg -DENABLE_HIP=ON \
          -DROCM_PATH="${rocm}" \
          -DHIP_ROOT="${rocm}" \
          -DCMAKE_HIP_COMPILER="${rocm}/llvm/bin/amdclang++" \
          -DCMAKE_HIP_ARCHITECTURES="${arch}" \
          -DCMAKE_HIP_STANDARD=17 \
          -DENABLE_ROCTX="${ENABLE_ROCTX}" \
          -DENABLE_HYPRE=ON \
          -DENABLE_HYPRE_DEVICE=HIP
  # hypre compiles its device sources outside of cmake and needs the MPI headers
  [[ -z "${MPI_PREFIX}" ]] || add_arg -DMPI_INCLUDE_DIR="${MPI_PREFIX}/include"
}

# CUDA settings shared by z5tux-cuda and matrix.
setup_cuda() {
  local cuda="$1" arch="$2"
  require_exec "${cuda}/bin/nvcc" "nvcc"
  add_arg -DENABLE_CUDA=ON \
          -DENABLE_CUDA_NVTOOLSEXT=ON \
          -DCUDA_TOOLKIT_ROOT_DIR="${cuda}" \
          -DCMAKE_CUDA_COMPILER="${cuda}/bin/nvcc" \
          -DCMAKE_CUDA_ARCHITECTURES="${arch}" \
          -DCUDA_ARCH="sm_${arch}" \
          -DCMAKE_CUDA_STANDARD=17 \
          -DENABLE_HYPRE=ON \
          -DENABLE_HYPRE_DEVICE=CUDA
}

# cray-mpich as installed on tioga/tuolumne. Prefers the flavor matching the
# compiler family ('amd' for amdclang, 'cray' for cce).
setup_cray_mpi() {
  local flavor="${1:-amd}"
  local mpi_dir="${MPI_DIR_OPT:-${MPICH_DIR:-}}"
  if [[ -z "${mpi_dir}" ]]; then
    mpi_dir="$(newest_path "/opt/cray/pe/mpich/*/ofi/${flavor}/*")"
  fi
  [[ -n "${mpi_dir}" && -x "${mpi_dir}/bin/mpicc" ]] \
    || die "cray-mpich not found (tried '${mpi_dir:-/opt/cray/pe/mpich/*/ofi/${flavor}/*}'); load the cray-mpich module or pass --mpi <path>"
  add_arg -DENABLE_MPI=ON \
          -DMPI_C_COMPILER="${mpi_dir}/bin/mpicc" \
          -DMPI_CXX_COMPILER="${mpi_dir}/bin/mpicxx" \
          -DMPI_Fortran_COMPILER="${mpi_dir}/bin/mpifort" \
          -DMPIEXEC_EXECUTABLE="srun" \
          -DMPIEXEC_NUMPROC_FLAG="-n"
  MPI_PREFIX="${mpi_dir}"
}

# BLAS/LAPACK: openblas when available, reference blas/lapack otherwise.
setup_blas_lapack() {
  local candidates=( "$@" ) lib
  for lib in "${candidates[@]}"; do
    if [[ -e "${lib}" ]]; then
      add_arg -DBLAS_LIBRARIES="${lib}" -DLAPACK_LIBRARIES="${lib}"
      return 0
    fi
  done
  if [[ -e /usr/lib64/libblas.so && -e /usr/lib64/liblapack.so ]]; then
    add_arg -DBLAS_LIBRARIES="/usr/lib64/libblas.so" -DLAPACK_LIBRARIES="/usr/lib64/liblapack.so"
    return 0
  fi
  warn "no BLAS/LAPACK found in the usual locations, letting cmake search for it"
}

# Resolves the toolchain of a configuration into cmake cache arguments.
select_config() {
  local cfg="$1"
  CMAKE_ARGS=()

  case "${cfg}" in
    # --------------------------------------------------------------- z5tux ---
    z5tux)
      add_arg -DCMAKE_C_COMPILER=/usr/bin/gcc \
              -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
              -DCMAKE_Fortran_COMPILER="${FC_OPT:-/usr/bin/gfortran}" \
              -DENABLE_OPENMP="${ENABLE_OPENMP:-ON}"
      setup_z5tux_mpi
      setup_blas_lapack /usr/lib/x86_64-linux-gnu/libopenblas.so
      ;;

    z5tux-cuda)
      add_arg -DCMAKE_C_COMPILER=/usr/bin/gcc \
              -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
              -DCMAKE_Fortran_COMPILER="${FC_OPT:-/usr/bin/gfortran}" \
              -DENABLE_OPENMP="${ENABLE_OPENMP:-OFF}"
      setup_z5tux_mpi
      setup_blas_lapack /usr/lib/x86_64-linux-gnu/libopenblas.so
      setup_cuda "$(resolve_cuda)" "${GPU_ARCH:-120}"
      ;;

    z5tux-hip)
      local rocm; rocm="$(resolve_rocm)"
      setup_rocm_compilers "${rocm}"
      add_arg -DENABLE_OPENMP="${ENABLE_OPENMP:-OFF}"
      setup_z5tux_mpi
      setup_blas_lapack /usr/lib/x86_64-linux-gnu/libopenblas.so
      setup_hip "${rocm}" "${GPU_ARCH:-gfx1100}"
      ;;

    # ------------------------------------------------------------------ LC ---
    matrix)

      local gcc_dir mpi_dir
      gcc_dir="$(newest_path '/usr/tce/packages/gcc/gcc-13*-magic')"
      [[ -n "${gcc_dir}" ]] || gcc_dir="$(newest_path '/usr/tce/packages/gcc/gcc-*-magic')"
      [[ -n "${gcc_dir}" ]] || die "no gcc found under /usr/tce/packages/gcc"
      add_arg -DCMAKE_C_COMPILER="${gcc_dir}/bin/gcc" \
              -DCMAKE_CXX_COMPILER="${gcc_dir}/bin/g++" \
              -DCMAKE_Fortran_COMPILER="${FC_OPT:-${gcc_dir}/bin/gfortran}" \
              -DENABLE_OPENMP="${ENABLE_OPENMP:-OFF}"

      local gcc_ver
      gcc_ver="$(basename "${gcc_dir}")"; gcc_ver="${gcc_ver#gcc-}"; gcc_ver="${gcc_ver%-magic}"
      mpi_dir="${MPI_DIR_OPT:-$(newest_path "/usr/tce/packages/mvapich2/mvapich2-*-gcc-${gcc_ver}-magic")}"
      [[ -n "${mpi_dir}" ]] || mpi_dir="$(newest_path '/usr/tce/packages/mvapich2/mvapich2-*-gcc-*-magic')"
      [[ -n "${mpi_dir}" && -x "${mpi_dir}/bin/mpicc" ]] \
        || die "mvapich2 not found under /usr/tce/packages/mvapich2 (use --mpi <path>)"
      add_arg -DENABLE_MPI=ON \
              -DMPI_C_COMPILER="${mpi_dir}/bin/mpicc" \
              -DMPI_CXX_COMPILER="${mpi_dir}/bin/mpicxx" \
              -DMPI_Fortran_COMPILER="${mpi_dir}/bin/mpifort" \
              -DMPIEXEC_EXECUTABLE="srun" \
              -DMPIEXEC_NUMPROC_FLAG="-n"
      MPI_PREFIX="${mpi_dir}"

      setup_blas_lapack /usr/lib64/libopenblas.so
      setup_cuda "$(resolve_cuda)" "${GPU_ARCH:-90}"
      ;;

    tioga|tioga-gpu)
      local rocm; rocm="$(resolve_rocm)"
      setup_rocm_compilers "${rocm}"
      add_arg -DENABLE_OPENMP="${ENABLE_OPENMP:-OFF}"
      setup_cray_mpi amd
      setup_blas_lapack /usr/lib64/libopenblas.so
      setup_hip "${rocm}" "${GPU_ARCH:-gfx90a}"
      ;;

    tuo-cpu|tuolumne-cpu)
      local rocm; rocm="$(resolve_rocm)"
      setup_rocm_compilers "${rocm}"
      add_arg -DENABLE_OPENMP="${ENABLE_OPENMP:-ON}"
      setup_cray_mpi amd
      setup_blas_lapack /usr/lib64/libopenblas.so
      ;;

    tuo-gpu|tuolumne-gpu|tuolumne)
      local rocm; rocm="$(resolve_rocm)"
      setup_rocm_compilers "${rocm}"
      add_arg -DENABLE_OPENMP="${ENABLE_OPENMP:-OFF}"
      setup_cray_mpi amd
      setup_blas_lapack /usr/lib64/libopenblas.so
      setup_hip "${rocm}" "${GPU_ARCH:-gfx942}"
      ;;

    *)
      die "unknown configuration '${cfg}' (run --list to see the supported ones)"
      ;;
  esac
}

# Scheduler command used by --alloc, per machine.
default_alloc_cmd() {
  case "${CFG_MACHINE}" in
    matrix)            printf 'srun -N 1 --exclusive -t 180 -A %s' "${ACCOUNT}" ;;
    tuolumne)          printf 'srun -N 1 --exclusive -t 180 -A %s' "${ACCOUNT}" ;;
    tioga)             printf 'flux run -N 1 -t 180m' ;;
    *)                 printf '' ;;
  esac
}

detect_config() {
  local host="${HOSTNAME:-$(hostname)}"
  case "${host}" in
    z5tux*)              printf 'z5tux' ;;
    matrix*|rzmatrix*)   printf 'matrix' ;;
    tioga*|rzvernal*)    printf 'tioga' ;;
    tuolumne*|tuo[0-9]*) die "on tuolumne the configuration is ambiguous, pass 'tuo-cpu' or 'tuo-gpu'" ;;
    *)                   die "cannot guess the configuration for host '${host}', pass one explicitly (--list)" ;;
  esac
}

# ------------------------------------------------------------------------------
# Modules
# ------------------------------------------------------------------------------
init_modules() {
  if ! declare -F module >/dev/null 2>&1; then
    local init
    for init in /usr/share/lmod/lmod/init/bash /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
      if [[ -r "${init}" ]]; then
        # shellcheck disable=SC1090
        source "${init}"
        break
      fi
    done
  fi
  declare -F module >/dev/null 2>&1 || type module >/dev/null 2>&1
}

load_modules() {
  local -a mods=()
  local m
  if [[ -n "${MODULES_OPT}" ]]; then
    read -r -a mods <<< "${MODULES_OPT}"
  else
    while IFS= read -r m; do
      [[ -n "${m}" ]] && mods+=( "${m}" )
    done < <(modules_for_config "${CONFIG}")
  fi
  [[ ${#mods[@]} -gt 0 ]] || return 0

  if ! init_modules; then
    warn "no module command available, skipping module loading"
    return 0
  fi

  local m
  for m in "${mods[@]}"; do
    if [[ ${DRY_RUN} -eq 1 ]]; then
      log "+ module load ${m}"
      continue
    fi
    if module load "${m}" >/dev/null 2>&1; then
      log "module load ${m}"
    else
      # Retry without the version: LC renames those more often than the toolchains move.
      local base="${m%%/*}"
      if [[ "${base}" != "${m}" ]] && module load "${base}" >/dev/null 2>&1; then
        log "module load ${base} (fallback, '${m}' unavailable)"
      else
        warn "could not load module '${m}' (continuing; run 'module avail ${base}' to check)"
      fi
    fi
  done
}

# ------------------------------------------------------------------------------
# Build back-ends
# ------------------------------------------------------------------------------
resolve_generator() {
  case "${GENERATOR}" in
    ninja)
      command -v ninja >/dev/null 2>&1 || die "ninja not found in PATH (try --generator make)"
      ;;
    make)
      ;;
    auto)
      if command -v ninja >/dev/null 2>&1; then
        GENERATOR="ninja"
      else
        warn "ninja not found in PATH, falling back to Unix Makefiles"
        GENERATOR="make"
      fi
      ;;
    *)
      die "unknown generator '${GENERATOR}' (auto|ninja|make)"
      ;;
  esac
}

configure_cmake() {
  local -a cmd=( cmake -S "${REPO_DIR}" -B "${BUILD_DIR}" )

  if [[ "${GENERATOR}" == "ninja" ]]; then
    cmd+=( -G Ninja -DENABLE_NINJA=ON )
  else
    cmd+=( -G "Unix Makefiles" -DENABLE_NINJA=OFF )
  fi

  cmd+=( -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
         -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"
         -DNUM_PROC="${JOBS}"
         -DENABLE_TRILINOS="${ENABLE_TRILINOS}"
         -DENABLE_SUPERLU_DIST="${ENABLE_SUPERLU_DIST}"
         -DENABLE_HYPRE_GPU_PROFILING="${ENABLE_HYPRE_GPU_PROFILING}"
         -DBLT_CXX_STD=c++17
         -DCMAKE_CXX_STANDARD=17 )
  cmd+=( "${CMAKE_ARGS[@]+"${CMAKE_ARGS[@]}"}" )
  cmd+=( "${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"}" )
  cmd+=( "${FORWARDED_ARGS[@]+"${FORWARDED_ARGS[@]}"}" )

  run "${cmd[@]}"
  write_build_env
}

# The mpi wrappers pick their back-end compiler from the MPICH_* variables, and
# the TPLs configured outside of cmake (hypre) inherit them from this script.
# Dump them next to the build so that running ninja by hand stays equivalent.
write_build_env() {
  [[ ${DRY_RUN} -eq 0 && -n "${MPICH_CC:-}" ]] || return 0
  local env_file="${BUILD_DIR}/build-env.sh"
  cat > "${env_file}" <<EOF
# Generated by ${SCRIPT_NAME} for the '${CONFIG}' configuration.
# Source this before running ninja/make by hand in this directory.
export MPICH_CC="${MPICH_CC}"
export MPICH_CXX="${MPICH_CXX}"
export MPICH_FC="${MPICH_FC}"
export MPICH_F90="${MPICH_F90}"
EOF
  log "wrote ${env_file} (source it before building by hand)"
}

build_cmake() {
  local -a cmd=( cmake --build "${BUILD_DIR}" -j "${TOP_JOBS}" )
  if [[ ${USE_ALLOC} -eq 1 ]]; then
    [[ -n "${ALLOC_CMD}" ]] || ALLOC_CMD="$(default_alloc_cmd)"
    [[ -n "${ALLOC_CMD}" ]] || die "--alloc requested but no scheduler command is known for '${CFG_MACHINE}' (use --alloc-cmd)"
    local -a alloc=()
    read -r -a alloc <<< "${ALLOC_CMD}"
    run "${alloc[@]}" "${cmd[@]}"
  else
    run "${cmd[@]}"
  fi
}

build_spack() {
  # uberenv/spack expect to run from the repository root, like the other helpers.
  cd "${REPO_DIR}"
  local uberenv="${REPO_DIR}/scripts/uberenv/uberenv.py"
  [[ -f "${uberenv}" ]] \
    || die "${uberenv} not found, initialize the submodule first: git submodule update --init scripts/uberenv"

  local spec="${SPACK_SPEC_OPT:-$(spack_spec_for_config "${CONFIG}")}"
  [[ -n "${spec}" ]] || die "no spack spec known for configuration '${CONFIG}' (use --spec)"

  local prefix="${INSTALL_DIR}"
  log "spack spec   : ${spec}"
  log "spack prefix : ${prefix}"

  local -a cmd=( python3 "${uberenv}"
                 --spec "${spec}"
                 --prefix "${prefix}"
                 --spack-env-name "${CONFIG}_env" )
  cmd+=( "${FORWARDED_ARGS[@]+"${FORWARDED_ARGS[@]}"}" )

  if [[ ${USE_ALLOC} -eq 1 ]]; then
    [[ -n "${ALLOC_CMD}" ]] || ALLOC_CMD="$(default_alloc_cmd)"
    [[ -n "${ALLOC_CMD}" ]] || die "--alloc requested but no scheduler command is known for '${CFG_MACHINE}' (use --alloc-cmd)"
    local -a alloc=()
    read -r -a alloc <<< "${ALLOC_CMD}"
    run "${alloc[@]}" "${cmd[@]}"
  else
    run "${cmd[@]}"
  fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  [[ -n "${CONFIG}" ]] || CONFIG="$(detect_config)"

  CFG_DESC="$(describe_config "${CONFIG}")"
  CFG_MACHINE="$(machine_for_config "${CONFIG}")"
  [[ -n "${CFG_DESC}" ]] || die "unknown configuration '${CONFIG}' (run --list to see the supported ones)"

  local reason
  reason="$(unsupported_reason "${CONFIG}")"
  [[ -z "${reason}" ]] || die "configuration '${CONFIG}' is not supported: ${reason}"

  case "${BUILD_TYPE}" in
    Release|RelWithDebInfo|Debug|MinSizeRel) ;;
    *) die "invalid build type '${BUILD_TYPE}' (Release|RelWithDebInfo|Debug|MinSizeRel)" ;;
  esac

  # Modules first: they provide the compilers, cmake and ninja that the
  # configuration below looks up.
  if [[ ${LOAD_MODULES} -eq 1 ]]; then
    load_modules
  fi

  if [[ ${USE_SPACK} -eq 0 ]]; then
    select_config "${CONFIG}"
  fi

  local suffix
  suffix="$(printf '%s' "${BUILD_TYPE}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "${BUILD_DIR}" ]]   || BUILD_DIR="${REPO_DIR}/build-${CONFIG}-${suffix}"
  [[ -n "${INSTALL_DIR}" ]] || INSTALL_DIR="${REPO_DIR}/install-${CONFIG}-${suffix}"

  log "configuration : ${CONFIG} (${CFG_DESC})"
  log "build type    : ${BUILD_TYPE}"
  log "build dir     : ${BUILD_DIR}"
  log "install dir   : ${INSTALL_DIR}"
  log "back-end      : $([[ ${USE_SPACK} -eq 1 ]] && echo 'uberenv/spack' || echo 'cmake superbuild')"

  if [[ ${CLEAN} -eq 1 ]]; then
    run rm -rf "${BUILD_DIR}" "${INSTALL_DIR}"
  fi

  if [[ ${USE_SPACK} -eq 1 ]]; then
    [[ ${DRY_RUN} -eq 1 ]] || mkdir -p "${INSTALL_DIR}"
    build_spack
  else
    resolve_generator
    command -v cmake >/dev/null 2>&1 || die "cmake not found in PATH"
    log "generator     : ${GENERATOR}"
    log "jobs          : ${JOBS} per TPL, ${TOP_JOBS} TPL(s) at a time"

    if [[ ${DO_CONFIGURE} -eq 1 ]]; then
      configure_cmake
    else
      [[ -d "${BUILD_DIR}" ]] || die "--build-only given but '${BUILD_DIR}' does not exist"
    fi

    if [[ ${DO_BUILD} -eq 1 ]]; then
      build_cmake
    fi
  fi

  log "done."
  if [[ ${DO_BUILD} -eq 1 && ${DRY_RUN} -eq 0 ]]; then
    log "TPLs installed in ${INSTALL_DIR}"
  fi
}

if [[ -n "${LOG_FILE}" ]]; then
  main 2>&1 | tee "${LOG_FILE}"
  exit "${PIPESTATUS[0]}"
else
  main
fi
