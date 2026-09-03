# Copyright 2013-2023 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
import warnings

import socket
import os

import spack.llnl.util.tty as tty

from os import environ as env
from os.path import join as pjoin

from spack_repo.builtin.build_systems.cmake import CMakePackage
from spack_repo.builtin.build_systems.cuda import CudaPackage
from spack_repo.builtin.build_systems.cached_cmake import (
    cmake_cache_option,
    cmake_cache_path,
    cmake_cache_string,
)

# Tested specs are located at scripts/spack_configs/<$SYS_TYPE>/spack.yaml (e.g. %clang@10.0.1)
# WARNING: +petsc variant is yet to be tested.


def cmake_cache_entry(name, value, comment=""):
    """Generate a string for a cmake cache variable."""

    return 'set(%s "%s" CACHE PATH "%s")\n\n' % (name, value, comment)


def cmake_cache_list(name, value, comment=""):
    """Generate a list for a cmake cache variable"""

    indent = 5 + len(name)
    join_str = '\n' + ' ' * indent
    return 'set(%s %s CACHE STRING "%s")\n\n' % (name, join_str.join(value), comment)


_SANITIZER_COMPILE_FLAGS = "-fsanitize=address,undefined -fno-omit-frame-pointer"
_SANITIZER_LINK_FLAGS = "-fsanitize=address,undefined"
# ROCm's host ASan runtime is not usable on the supported GPUs: it installs
# HSA allocation interceptors that can crash before main().  Keep sanitizer
# coverage for HIP host code with UBSan, matching the legacy CMake build.
_HIP_SANITIZER_COMPILE_FLAGS = "-fsanitize=undefined -fno-omit-frame-pointer"
_HIP_SANITIZER_LINK_FLAGS = "-fsanitize=undefined"
_HIP_SANITIZER_HIP_FLAGS = (
    "-Xarch_host -fsanitize=undefined -fno-omit-frame-pointer -Wno-option-ignored"
)
_SANITIZER_VPTR_CXX_SPEC_FLAGS = "cxxflags='-fno-sanitize=vptr'"
# Non-exact flags so they compose with existing cflags='-fPIC' constraints.
_SANITIZER_SPEC_FLAGS = (
    "cflags='{0}' cxxflags='{0}' fflags='{0}' ldflags='{1}'".format(
        _SANITIZER_COMPILE_FLAGS, _SANITIZER_LINK_FLAGS
    )
)
_HIP_SANITIZER_SPEC_FLAGS = (
    "cflags='{0}' cxxflags='{0}' fflags='{0}' ldflags='{1}'".format(
        _HIP_SANITIZER_COMPILE_FLAGS, _HIP_SANITIZER_LINK_FLAGS
    )
)


def _join_flags(*parts):
    seen = []
    for part in parts:
        for tok in str(part).split():
            if tok and tok not in seen:
                seen.append(tok)
    return " ".join(seen)


def _sanitizer_compile_flags(spec):
    return _HIP_SANITIZER_COMPILE_FLAGS if "+rocm" in spec else _SANITIZER_COMPILE_FLAGS


def _sanitizer_link_flags(spec):
    return _HIP_SANITIZER_LINK_FLAGS if "+rocm" in spec else _SANITIZER_LINK_FLAGS


def write_sanitizer_cache(cfg, spec):
    enabled = "+sanitizers" in spec
    cfg.write(cmake_cache_option("GEOS_ENABLE_SANITIZERS", enabled))
    if not enabled:
        return
    link_flags = _sanitizer_link_flags(spec)
    cfg.write(cmake_cache_string("CMAKE_EXE_LINKER_FLAGS", link_flags))
    cfg.write(cmake_cache_string("CMAKE_SHARED_LINKER_FLAGS", link_flags))
    cfg.write(cmake_cache_string("CMAKE_MODULE_LINKER_FLAGS", link_flags))
    if "+cuda" in spec:
        # Sanitized CUDA host code must use the shared CUDA runtime so the
        # sanitizer runtime and CUDA runtime are loaded in a deterministic
        # order for every GEOS executable and shared library.
        cfg.write(cmake_cache_option("CUDA_USE_STATIC_CUDA_RUNTIME", False))
        cfg.write(cmake_cache_string("CMAKE_CUDA_RUNTIME_LIBRARY", "Shared"))


class Geosx(CMakePackage, CudaPackage, ROCmPackage):
    """GEOSX simulation framework."""

    homepage = "https://github.com/GEOS-DEV/GEOS"
    git = "https://github.com/GEOS-DEV/GEOS.git"

    # GEOSX needs submodules to build, but not necessary to build dependencies
    version('develop', branch='develop')

    # SPHINX_BEGIN_VARIANTS

    variant('openmp', default=True, description='Build with OpenMP support.')
    variant('shared', default=True, description='Build Shared Libs.')
    variant('caliper', default=True, description='Build Caliper support.')
    variant('vtk', default=True, description='Build VTK support.')
    variant('trilinos', default=False, description='Build Trilinos support.')
    variant('hypre', default=True, description='Build HYPRE support.')
    variant('hypredrive', default=True, description='Build hypredrive support.')
    variant('petsc', default=False, description='Build PETSc support.')
    variant('scotch', default=True, description='Build Scotch support.')
    variant('uncrustify', default=True, description='Build Uncrustify support.')
    variant('lai',
            default='hypre',
            description='Linear algebra interface.',
            values=('trilinos', 'hypre', 'petsc'),
            multi=False)
    variant('grpc', default=False, description='Enable gRPC.')
    variant('pygeosx', default=True, description='Enable pygeosx.')
    variant('cxxstd', default='20', description='CXX standard.')

    # SPHINX_END_VARIANTS

    # variant('tests', default=True, description='Build tests')
    # variant('benchmarks', default=False, description='Build benchmarks')
    # variant('examples', default=False, description='Build examples')

    variant('docs', default=False, description='Build docs')
    variant('addr2line', default=True,
            description='Add support for addr2line.')
    variant('mathpresso', default=True, description='Build mathpresso.')

    variant('cuda_stack_size', default="0", description="Defines the adjusted cuda stack \
        size limit if required. Zero or negative keep default behavior")
    variant('sanitizers', default=False,
            description='Build TPLs and GEOS with ASan/UBSan (GEOS_ENABLE_SANITIZERS).')

    # SPHINX_BEGIN_DEPENDS
    depends_on("c", type="build")
    depends_on("cxx", type="build")
    depends_on("fortran", type="build")

    depends_on('cmake@3.24:', type='build')

    depends_on('blt@0.7.2')

    #
    # Virtual packages
    #
    depends_on('mpi')
    depends_on('blas')
    depends_on('lapack')

    #
    # Performance portability
    #
    raja_suite_version="2026.07.0"
    chai_suite_version="2026.07.0"
    camp_suite_version="2026.07.1"
    umpire_suite_version="2026.07.1"
    depends_on(f"raja @{raja_suite_version} ~examples~exercises~shared")
    depends_on(f"chai @{chai_suite_version} +raja~examples")
    depends_on("chai~shared", when="~sanitizers")
    depends_on("chai+shared", when="+sanitizers")
    depends_on(f"camp @{camp_suite_version}")
    # Umpire's HIP interface exports ROCm's LLVM include directory to every
    # language in its CMake target.  That directory contains an iso_c_binding.mod
    # for Flang, which GNU Fortran rejects.  GEOS only uses Umpire's C/C++ API,
    # so leave the Umpire Fortran interface off for ROCm builds.
    depends_on(
        f"umpire @{umpire_suite_version} +c~examples+fortran~device_alloc",
        when="~rocm",
    )
    depends_on(
        f"umpire @{umpire_suite_version} +c~examples~fortran~device_alloc",
        when="+rocm",
    )
    depends_on("umpire~shared", when="~sanitizers")
    depends_on("umpire+shared", when="+sanitizers")
    with when('+openmp'):
        for pkg in ('raja', 'chai', 'umpire'):
            depends_on(f"{pkg}+openmp", when="+openmp")
    #
    # GPUs
    #
    with when('+cuda'):
        for sm_ in CudaPackage.cuda_arch_values:
            depends_on('raja+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('umpire+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('chai+cuda~separable_compilation cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('camp+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('hypre@develop+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))

    with when('+rocm'):
        for gfx_ in ROCmPackage.amdgpu_targets:
            depends_on(f"raja+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"umpire+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"chai+rocm~separable_compilation amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"camp+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"hypre@develop+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")

    #
    # IO
    #
    depends_on('hdf5@1.14.6')
    depends_on('silo@4.12.0~fortran~shared~python build_system=cmake')

    depends_on('conduit@0.9.5 ~test~fortran~hdf5_compat+shared')

    depends_on('adiak@0.4.0 ~shared', when='+caliper')
    depends_on('caliper@2.14.0 ~gotcha~sampler~libunwind~libdw', when='+caliper')

    depends_on('pugixml@1.13 ~shared')

    depends_on('fmt@12.1.0')
    for _fmt_cxxstd in ('14', '17', '20'):
        depends_on(f'fmt@12.1.0 cxxstd={_fmt_cxxstd}', when=f'cxxstd={_fmt_cxxstd}')
    depends_on('vtk@9.7.0', when='+vtk')

    #
    # Math
    #
    depends_on("parmetis@4.0.3+int64~shared cflags='-fPIC' cxxflags='-fPIC'")
    depends_on("metis +int64~shared cflags='-fPIC' cxxflags='-fPIC'")

    depends_on("superlu-dist@9.2.1 +int64 fflags='-fPIC'")
    depends_on("superlu-dist@9.2.1 +int64 fflags='-fPIC -ef'", when="%cce")
    depends_on("superlu-dist~openmp", when="~openmp")
    depends_on("superlu-dist+openmp", when="+openmp")

    # -Wno-error=implicit-function-declaration needed for 'METIS_PartMeshDual' error
    depends_on("scotch@7.0.8 ~compression +mpi +esmumps +int64 determinism=FULL ~metis build_system=cmake cflags='-fPIC' cxxflags='-fPIC'", when='+scotch')
    depends_on("scotch~shared", when="+scotch~sanitizers")
    depends_on("scotch+shared", when="+scotch+sanitizers")

    depends_on('suite-sparse@5.10.1')
    depends_on("suite-sparse~openmp", when="~openmp")
    depends_on("suite-sparse+openmp", when="+openmp")

    with when("+trilinos"):
        trilinos_packages = '+aztec+stratimikos~amesos2~anasazi~belos~ifpack2~muelu~sacado+thyra+zoltan'
        depends_on("trilinos@16.1.0 cflags='-fPIC' cxxflags='-fPIC -include cstdint' fflags='-fPIC'" + trilinos_packages)
        depends_on("trilinos fflags='-fsecond-underscore'", when="platform=darwin")
        depends_on("trilinos~openmp", when="~openmp")
        depends_on("trilinos+openmp", when="+openmp")

    with when("+hypre"):
        depends_on("hypre@develop +superlu-dist+mixedint+mpi", when='~cuda~rocm')
        depends_on("hypre@develop +cuda+superlu-dist+mixedint+mpi+umpire~unified-memory", when='+cuda')
        depends_on("hypre@develop +rocm+superlu-dist+mixedint+mpi+umpire~unified-memory", when='+rocm')
        depends_on("hypre@develop ~openmp", when="~openmp")
        depends_on("hypre@develop +caliper", when="+caliper")
        depends_on("hypre@develop +pic", when="~shared")
        depends_on("hypre@develop +shared", when="+shared")

    with when("+hypredrive"):
        depends_on("hypredrive@develop +superlu-dist")
        depends_on("hypredrive@develop +pic", when="~shared")
        depends_on("hypredrive@develop +shared", when="+shared")
        depends_on("hypredrive@develop +caliper", when="+caliper")

    depends_on('petsc@3.19.4~hdf5~hypre+int64', when='+petsc')
    depends_on('petsc+ptscotch', when='+petsc+scotch')

    #
    # Python
    #
    # Hostconfig always needs an interpreter. Keep python off the link/run DAG
    # unless +pygeosx; otherwise %%nvhpc prefers nvc for libffi/libiconv/libmd.
    depends_on('python', type='build', when='~pygeosx')
    depends_on('python', type=('build', 'link', 'run'), when='+pygeosx')


    #
    # Dev tools
    #
    depends_on('uncrustify', when='+uncrustify')

    #
    # Documentation
    #
    depends_on('doxygen@1.8.20', when='+docs', type='build')
    depends_on('py-sphinx@1.6.3:', when='+docs', type='build')

    #
    # Other
    #
    depends_on("mathpresso cxxflags='-fPIC'", when='+mathpresso')
    depends_on('grpc', when='+grpc')
    depends_on('addr2line', when='+addr2line')

    # Propagate sanitizer flags to C/C++/Fortran TPLs. Do not attach them to
    # externals (mpi, cuda, python, cmake) or they may try to rebuild the toolchain.
    # HIP uses host UBSan only; ROCm's host ASan runtime is not reliable on
    # the supported GPUs.
    with when("+sanitizers~rocm"):
        for _san_pkg in (
            "raja",
            "chai",
            "camp",
            "umpire",
            "hdf5",
            "silo",
            "conduit",
            "pugixml",
            "fmt",
            "parmetis",
            "metis",
            "superlu-dist",
            "suite-sparse",
        ):
            depends_on("{0} {1}".format(_san_pkg, _SANITIZER_SPEC_FLAGS))
        depends_on("vtk {0}".format(_SANITIZER_SPEC_FLAGS), when="+vtk")
        depends_on("adiak {0}".format(_SANITIZER_SPEC_FLAGS), when="+caliper")
        depends_on("caliper {0}".format(_SANITIZER_SPEC_FLAGS), when="+caliper")
        depends_on("scotch {0}".format(_SANITIZER_SPEC_FLAGS), when="+scotch")
        depends_on("hypre {0}".format(_SANITIZER_SPEC_FLAGS), when="+hypre")
        depends_on("hypredrive {0}".format(_SANITIZER_SPEC_FLAGS), when="+hypredrive")
        depends_on("mathpresso {0}".format(_SANITIZER_SPEC_FLAGS), when="+mathpresso")
        depends_on("trilinos {0}".format(_SANITIZER_SPEC_FLAGS), when="+trilinos")
        depends_on("petsc {0}".format(_SANITIZER_SPEC_FLAGS), when="+petsc")
        depends_on("grpc {0}".format(_SANITIZER_SPEC_FLAGS), when="+grpc")
        depends_on("chai {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS))
        depends_on("caliper {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS), when="+caliper")
        depends_on("mathpresso {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS), when="+mathpresso")
    with when("+sanitizers+rocm"):
        for _san_pkg in (
            "raja",
            "chai",
            "camp",
            "umpire",
            "hdf5",
            "silo",
            "conduit",
            "pugixml",
            "fmt",
            "parmetis",
            "metis",
            "superlu-dist",
            "suite-sparse",
        ):
            depends_on("{0} {1}".format(_san_pkg, _HIP_SANITIZER_SPEC_FLAGS))
        depends_on("vtk {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+vtk")
        depends_on("adiak {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+caliper")
        depends_on("caliper {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+caliper")
        depends_on("scotch {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+scotch")
        depends_on("hypre {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+hypre")
        depends_on("hypredrive {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+hypredrive")
        depends_on("mathpresso {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+mathpresso")
        depends_on("trilinos {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+trilinos")
        depends_on("petsc {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+petsc")
        depends_on("grpc {0}".format(_HIP_SANITIZER_SPEC_FLAGS), when="+grpc")
        depends_on("chai {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS))
        depends_on("caliper {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS), when="+caliper")
        depends_on("mathpresso {0}".format(_SANITIZER_VPTR_CXX_SPEC_FLAGS), when="+mathpresso")

    # SPHINX_END_DEPENDS

    #
    # Conflicts
    #
    conflicts('~trilinos lai=trilinos', msg='To use Trilinos as the Linear Algebra Interface you must build it.')
    conflicts('~hypre lai=hypre', msg='To use HYPRE as the Linear Algebra Interface you must build it.')
    conflicts('~petsc lai=petsc', msg='To use PETSc as the Linear Algebra Interface you must build it.')
    conflicts('+sanitizers', when='%nvhpc',
              msg='NVHPC does not support -fsanitize=address,undefined')
    conflicts('+sanitizers', when='%pgi',
              msg='PGI does not support -fsanitize=address,undefined')
    conflicts('~shared', when='+sanitizers',
              msg='+sanitizers requires +shared so instrumented GEOS components use one TPL instance')

    def flag_handler(self, name, flags):
        if self.spec.satisfies("+sanitizers"):
            compile_flags = _sanitizer_compile_flags(self.spec)
            link_flags = _sanitizer_link_flags(self.spec)
            if name in ("cflags", "cxxflags", "fflags"):
                flags.extend(compile_flags.split())
            elif name == "ldflags":
                flags.extend(link_flags.split())
        return (flags, None, None)

    # Only phases necessary for building dependencies and generate host configs
    phases = ['geos_hostconfig', 'lvarray_hostconfig']
    #phases = ['hostconfig', 'cmake', 'build', 'install']

    @run_after('build')
    @on_package_attributes(run_tests=True)
    def check(self):
        """
        Searches the CMake-generated Makefile for the target ``test``
        and runs it if found.
        """
        with working_dir(self.build_directory):
            ctest('-V', '--force-new-ctest-process', '-j 1')

    @run_after('build')
    def build_docs(self):
        if '+docs' in self.spec:
            with working_dir(self.build_directory):
                make('docs')

    def _get_sys_type(self, spec):
        sys_type = str(spec.architecture)
        # if on llnl systems, we can use the SYS_TYPE
        if "SYS_TYPE" in env:
            sys_type = env["SYS_TYPE"]
        return sys_type

    def _get_host_config_path(self, spec, lvarray=False):
        gpu_backend = ""
        if "+cuda" in spec:
            gpu_backend = f"cuda@{spec['cuda'].version}"
        elif "+rocm" in spec:
            gpu_backend = f"rocm@{spec['hip'].version}"

        hostname = socket.gethostname().rstrip('1234567890')

        if lvarray:
            hostname = "lvarray-" + hostname

        host_config_path = "%s-%s-%s@%s%s.cmake" % (hostname,
                                                    self._get_sys_type(spec),
                                                    str(spec.compiler.name),
                                                    str(spec.compiler.version),
                                                    gpu_backend)
        if "+sanitizers" in spec:
            host_config_path = host_config_path[:-6] + "-sanitizers.cmake"

        dest_dir = self.stage.source_path
        host_config_path = os.path.abspath(pjoin(dest_dir, host_config_path))
        return host_config_path

    def geos_hostconfig(self, spec, prefix, py_site_pkgs_dir=None):
        """
        This method creates a 'host-config' file that specifies
        all of the options used to configure and build GEOSX.

        Note:
          The `py_site_pkgs_dir` arg exists to allow a package that
          subclasses this package provide a specific site packages
          dir when calling this function. `py_site_pkgs_dir` should
          be an absolute path or `None`.

          This is necessary because the spack `site_packages_dir`
          var will not exist in the base class. For more details
          on this issue see: https://github.com/spack/spack/issues/6261
        """

        #######################
        # Compiler Info
        #######################
        c_compiler = env["SPACK_CC"]
        cpp_compiler = env["SPACK_CXX"]

        #######################################################################
        # By directly fetching the names of the actual compilers we appear
        # to doing something evil here, but this is necessary to create a
        # 'host config' file that works outside of the spack install env.
        #######################################################################

        sys_type = self._get_sys_type(spec)

        ##############################################
        # Find and record what CMake is used
        ##############################################

        cmake_exe = spec['cmake'].command.path
        cmake_exe = os.path.realpath(cmake_exe)

        host_config_path = self._get_host_config_path(spec)
        with open(host_config_path, "w") as cfg:
            cfg.write("#{0}\n".format("#" * 80))
            cfg.write("# Generated host-config - Edit at own risk!\n")
            cfg.write("#{0}\n".format("#" * 80))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# SYS_TYPE: {0}\n".format(sys_type))
            cfg.write("# Compiler Spec: {0}\n".format(spec.compiler))
            cfg.write("# CMake executable path: %s\n" % cmake_exe)
            cfg.write("#{0}\n\n".format("-" * 80))

            #######################
            # Compiler Settings
            #######################

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# Compilers\n")
            cfg.write("#{0}\n\n".format("-" * 80))
            cfg.write(cmake_cache_path("CMAKE_C_COMPILER", c_compiler))
            cflags = ' '.join(spec.compiler_flags['cflags'])
            cxxflags = ' '.join(spec.compiler_flags['cxxflags'])
            if '+sanitizers' in spec:
                sanitizer_compile_flags = _sanitizer_compile_flags(spec)
                cflags = _join_flags(cflags, sanitizer_compile_flags)
                cxxflags = _join_flags(cxxflags, sanitizer_compile_flags)
            if cflags:
                cfg.write(cmake_cache_string("CMAKE_C_FLAGS", cflags))

            cfg.write(cmake_cache_path("CMAKE_CXX_COMPILER", cpp_compiler))
            if cxxflags:
                cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS", cxxflags))
            write_sanitizer_cache(cfg, spec)

            release_flags = "-O3 -DNDEBUG"
            if "clang" in self.compiler.cxx:
                release_flags += " -march=native -mtune=native"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELEASE", release_flags))
            reldebinf_flags = "-O2 -g -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELWITHDEBINFO", reldebinf_flags))
            debug_flags = "-g"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_DEBUG", debug_flags))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# CMake Standard\n")
            cfg.write("#{0}\n\n".format("-" * 80))

            cfg.write(cmake_cache_string("BLT_CXX_STD", f"c++{spec.variants['cxxstd'].value}"))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# MPI\n")
            cfg.write("#{0}\n\n".format("-" * 80))

            cfg.write(cmake_cache_option('ENABLE_MPI', True))
            cfg.write(cmake_cache_path('MPI_C_COMPILER', spec['mpi'].mpicc))
            cfg.write(cmake_cache_path('MPI_CXX_COMPILER', spec['mpi'].mpicxx))

            hostname = socket.gethostname().rstrip('1234567890')

            if sys_type in ('toss_4_x86_64_ib_cray'):
                cfg.write(cmake_cache_string('MPIEXEC', 'srun'))
                cfg.write(cmake_cache_string('MPIEXEC_NUMPROC_FLAG', '-n'))
            else:
                # Taken from cached_cmake class:
                # https://github.com/spack/spack/blob/develop/lib/spack/spack/build_systems/cached_cmake.py#L180-234

                if hostname == 'p3dev':
                    cfg.write(cmake_cache_option('ENABLE_WRAP_ALL_TESTS_WITH_MPIEXEC', True))

                # Check for slurm
                using_slurm = False
                slurm_checks = ["+slurm", "schedulers=slurm", "process_managers=slurm"]
                if any(spec["mpi"].satisfies(variant) for variant in slurm_checks):
                    using_slurm = True

                # Determine MPIEXEC
                if using_slurm:
                    if spec["mpi"].external:
                        # Heuristic until we have dependents on externals
                        mpiexec = "/usr/bin/srun"
                    else:
                        mpiexec = os.path.join(spec["slurm"].prefix.bin, "srun")
                elif hasattr(spec["mpi"].package, "mpiexec"):
                    mpiexec = spec["mpi"].package.mpiexec
                else:
                    mpiexec = os.path.join(spec["mpi"].prefix.bin, "mpirun")
                    if not os.path.exists(mpiexec):
                        mpiexec = os.path.join(spec["mpi"].prefix.bin, "mpiexec")

                if not os.path.exists(mpiexec):
                    msg = "Unable to determine MPIEXEC, geos tests may fail"
                    cfg.write("# {0}\n".format(msg))
                    tty.warn(msg)
                else:
                    # starting with cmake 3.10, FindMPI expects MPIEXEC_EXECUTABLE
                    # vs the older versions which expect MPIEXEC
                    if spec["cmake"].satisfies("@3.10:"):
                        cfg.write(cmake_cache_path("MPIEXEC_EXECUTABLE", mpiexec))
                    else:
                        cfg.write(cmake_cache_path("MPIEXEC", mpiexec))

                # Determine MPIEXEC_NUMPROC_FLAG
                if using_slurm:
                    cfg.write(cmake_cache_string("MPIEXEC_NUMPROC_FLAG", "-n"))
                else:
                    cfg.write(cmake_cache_string("MPIEXEC_NUMPROC_FLAG", "-np"))


            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# OpenMP\n")
            cfg.write("#{0}\n\n".format("-" * 80))

            if '+openmp' in spec:
                cfg.write(cmake_cache_option('ENABLE_OPENMP', True))
            else:
                cfg.write(cmake_cache_option('ENABLE_OPENMP', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Cuda\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+cuda' in spec:
                cfg.write(cmake_cache_option('ENABLE_CUDA', True))
                cfg.write(cmake_cache_string('CMAKE_CUDA_STANDARD', spec.variants['cxxstd'].value))

                cudatoolkitdir = spec['cuda'].prefix
                cfg.write(cmake_cache_path('CUDA_TOOLKIT_ROOT_DIR', cudatoolkitdir))
                cudacompiler = '${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc'
                cfg.write(cmake_cache_path('CMAKE_CUDA_COMPILER', cudacompiler))

                cmake_cuda_flags = ('-restrict --allow-unsupported-compiler --extended-lambda -Werror '
                                    'cross-execution-space-call,reorder,'
                                    'deprecated-declarations')

                archSpecifiers = ('-mtune', '-mcpu', '-march', '-qtune', '-qarch')
                for archSpecifier in archSpecifiers:
                    for compilerArg in spec.compiler_flags['cxxflags']:
                        if compilerArg.startswith(archSpecifier):
                            cmake_cuda_flags += ' -Xcompiler ' + compilerArg

                if not spec.satisfies('cuda_arch=none'):
                    cuda_arches = [str(arch) for arch in spec.variants['cuda_arch'].value]
                    cfg.write(cmake_cache_string('CMAKE_CUDA_ARCHITECTURES', ';'.join(cuda_arches)))

                if '+sanitizers' in spec:
                    cmake_cuda_flags += (
                        ' -Xcompiler=-fsanitize=address,-fsanitize=undefined,-fno-omit-frame-pointer'
                    )

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS', cmake_cuda_flags))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELWITHDEBINFO', '-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}'))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_DEBUG', '-g -G -O0 -Xcompiler -O0'))

                cuda_stack_size = int(spec.variants['cuda_stack_size'].value)
                if 0 < cuda_stack_size:
                    cfg.write(cmake_cache_option('ENABLE_CUDA_STACK_SIZE', True, "Adjust the CUDA stack size limit"))
                    cfg.write(cmake_cache_string('CUDA_STACK_SIZE', cuda_stack_size, "CUDA stack size in KB"))

            else:
                cfg.write(cmake_cache_option('ENABLE_CUDA', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# ROCm/HIP\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+rocm' in spec:
                cfg.write(cmake_cache_option('ENABLE_HIP', True))
                cfg.write(cmake_cache_string('CMAKE_HIP_STANDARD', spec.variants['cxxstd'].value))
                hip_compiler = pjoin(str(spec['hip'].prefix), 'bin', 'amdclang++')
                cfg.write(cmake_cache_path('CMAKE_HIP_COMPILER', hip_compiler))

                if not spec.satisfies('amdgpu_target=none'):
                    cmake_hip_archs = ";".join(spec.variants["amdgpu_target"].value)
                    cfg.write(cmake_cache_string('CMAKE_HIP_ARCHITECTURES', cmake_hip_archs))
                    # ROCm 6.4's hip-config uses GPU_TARGETS to seed the
                    # imported hip::device target.  Set both spellings so
                    # host-config builds do not detect and add the build
                    # machine's GPUs when cross-compiling for a target node.
                    cfg.write(cmake_cache_string('GPU_TARGETS', cmake_hip_archs))
                    cfg.write(cmake_cache_string('AMDGPU_TARGETS', cmake_hip_archs))

                cfg.write(cmake_cache_path('ROCM_PATH', spec['hip'].prefix))
                if '+sanitizers' in spec:
                    cfg.write(cmake_cache_string('CMAKE_HIP_FLAGS',
                                                _HIP_SANITIZER_HIP_FLAGS))
            else:
                cfg.write(cmake_cache_option('ENABLE_HIP', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Performance Portability TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_option('ENABLE_CHAI', True))
            cfg.write(cmake_cache_path('CHAI_DIR', spec['chai'].prefix))

            cfg.write(cmake_cache_path('RAJA_DIR', spec['raja'].prefix))

            cfg.write(cmake_cache_option('ENABLE_UMPIRE', True))
            cfg.write(cmake_cache_path('UMPIRE_DIR', spec['umpire'].prefix))

            cfg.write(cmake_cache_path('CAMP_DIR', spec['camp'].prefix))

            # yapf: disable
            io_tpls = (
                ('zlib', 'ZLIB', True),
                ('hdf5', 'HDF5', True),
                ('conduit', 'CONDUIT', True),
                ('silo', 'SILO', True),
                ('pugixml', 'PUGIXML', True),
                ('vtk', 'VTK', '+vtk' in spec),
                ('fmt', 'FMT', True)
            )
            # yapf: enable

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# IO TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+caliper' in spec:
                cfg.write(cmake_cache_option('ENABLE_CALIPER', True))
                cfg.write(cmake_cache_path('CALIPER_DIR', spec['caliper'].prefix))
                cfg.write(cmake_cache_path('ADIAK_DIR', spec['adiak'].prefix))

            for tpl, cmake_name, enable in io_tpls:
                if enable:
                    dep_spec = None
                    if tpl == 'zlib':
                        # Spack may concretize zlib-api to zlib-ng instead of zlib.
                        for candidate in ('zlib', 'zlib-ng', 'zlib-api'):
                            try:
                                dep_spec = spec[candidate]
                                break
                            except KeyError:
                                pass
                        if dep_spec is None:
                            raise KeyError("No zlib provider (zlib/zlib-ng/zlib-api) found in {0}".format(spec))
                    else:
                        dep_spec = spec[tpl]
                    cfg.write(cmake_cache_path('{}_DIR'.format(cmake_name), dep_spec.prefix))
                else:
                    cfg.write(cmake_cache_option('ENABLE_{}'.format(cmake_name), False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# System Math Libraries\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if spec["blas"].name == "intel-oneapi-mkl":
                cfg.write(cmake_cache_option('ENABLE_MKL', True))
                cfg.write(cmake_cache_path('MKL_INCLUDE_DIRS', spec['intel-oneapi-mkl'].prefix.include))
                cfg.write(cmake_cache_list('MKL_LIBRARIES', spec['intel-oneapi-mkl'].libs))
            elif spec["blas"].name == "mkl":
                cfg.write(cmake_cache_option('ENABLE_MKL', True))
                cfg.write(cmake_cache_path('MKL_INCLUDE_DIRS', spec['intel-mkl'].prefix.include))
                cfg.write(cmake_cache_list('MKL_LIBRARIES', spec['intel-mkl'].libs))
            else:
                cfg.write(cmake_cache_list('BLAS_LIBRARIES', spec['blas'].libs))
                cfg.write(cmake_cache_list('LAPACK_LIBRARIES', spec['lapack'].libs))

            # yapf: disable
            math_tpls = (
                ('metis', 'METIS', True),
                ('parmetis', 'PARMETIS', True),
                ('scotch', 'SCOTCH', '+scotch' in spec),
                ('superlu-dist', 'SUPERLU_DIST', True),
                ('suite-sparse', 'SUITESPARSE', True),
                ('trilinos', 'TRILINOS', '+trilinos' in spec),
                ('hypre', 'HYPRE', '+hypre' in spec),
                ('hypredrive', 'HYPREDRV', '+hypredrive' in spec),
                ('petsc', 'PETSC', '+petsc' in spec)
            )
            # yapf: enable

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Math TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            for tpl, cmake_name, enable in math_tpls:
                if enable:
                    if tpl == 'hypredrive':
                        cfg.write(cmake_cache_option('ENABLE_HYPREDRV', True))
                    cfg.write(cmake_cache_path('{}_DIR'.format(cmake_name), spec[tpl].prefix))

                    if tpl == 'hypre' and '+cuda' in spec:
                        cfg.write(cmake_cache_string('ENABLE_HYPRE_DEVICE', "CUDA"))
                    elif tpl == 'hypre' and '+rocm' in spec:
                        cfg.write(cmake_cache_string('ENABLE_HYPRE_DEVICE', "HIP"))
                else:
                    cfg.write(cmake_cache_option('ENABLE_{}'.format(cmake_name), False))

            if '+caliper' in spec and '+hypre' in spec:
                cfg.write(cmake_cache_option('ENABLE_CALIPER_HYPRE', True))

            if 'lai=trilinos' in spec:
                cfg.write(cmake_cache_string('GEOS_LA_INTERFACE', 'Trilinos'))
            if 'lai=hypre' in spec:
                cfg.write(cmake_cache_string('GEOS_LA_INTERFACE', 'Hypre'))
            if 'lai=petsc' in spec:
                cfg.write(cmake_cache_string('GEOS_LA_INTERFACE', 'Petsc'))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Python\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_path('Python3_ROOT_DIR', os.path.join(spec['python'].prefix)))
            cfg.write(cmake_cache_path('Python3_EXECUTABLE', os.path.join(spec['python'].prefix.bin, 'python3')))

            if '+pygeosx' in spec:
                cfg.write(cmake_cache_option('ENABLE_PYGEOSX', True))
            else:
                cfg.write(cmake_cache_option('ENABLE_PYGEOSX', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Documentation\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+docs' in spec:
                sphinx_bin_dir = spec['py-sphinx'].prefix.bin
                cfg.write(cmake_cache_path('SPHINX_EXECUTABLE', os.path.join(sphinx_bin_dir, 'sphinx-build')))

                doxygen_bin_dir = spec['doxygen'].prefix.bin
                cfg.write(cmake_cache_path('DOXYGEN_EXECUTABLE', os.path.join(doxygen_bin_dir, 'doxygen')))
            else:
                cfg.write(cmake_cache_option('ENABLE_DOCS', False))
                cfg.write(cmake_cache_option('ENABLE_DOXYGEN', False))
                cfg.write(cmake_cache_option('ENABLE_SPHINX', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Development tools\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_option('ENABLE_UNCRUSTIFY', '+uncrustify' in spec))
            if '+uncrustify' in spec:
                cfg.write(
                    cmake_cache_path('UNCRUSTIFY_EXECUTABLE', os.path.join(spec['uncrustify'].prefix.bin, 'uncrustify')))

            if '+addr2line' in spec:
                cfg.write('#{0}\n'.format('-' * 80))
                cfg.write('# addr2line\n')
                cfg.write('#{0}\n\n'.format('-' * 80))
                cfg.write(cmake_cache_option('ENABLE_ADDR2LINE', True))
                cfg.write(cmake_cache_path('ADDR2LINE_EXEC', os.path.join(spec['addr2line'].prefix.bin, 'addr2line')))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Other\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+mathpresso' in spec:
                cfg.write(cmake_cache_option('ENABLE_MATHPRESSO', True))
                cfg.write(cmake_cache_path('MATHPRESSO_DIR', spec['mathpresso'].prefix))
                cfg.write(cmake_cache_option('ENABLE_XML_UPDATES', True))
            else:
                cfg.write(cmake_cache_option('ENABLE_MATHPRESSO', False))
                cfg.write(cmake_cache_option('ENABLE_XML_UPDATES', False))

            if '+grpc' in spec:
                cfg.write(cmake_cache_option('ENABLE_GRPC', True))
                cfg.write(cmake_cache_entry('GRPC_DIR', spec['grpc'].prefix))
                cfg.write(cmake_cache_entry('OPENSSL_DIR', spec['openssl'].prefix))
                cfg.write(cmake_cache_entry('ABSL_DIR', spec['abseil-cpp'].prefix))
                cfg.write(cmake_cache_entry('RE2_DIR', spec['re2'].prefix))
                cfg.write(cmake_cache_entry('C-ARES_DIR', spec['c-ares'].prefix))
                cfg.write(cmake_cache_entry('PROTOBUF_DIR', spec['protobuf'].prefix))
            else:
                cfg.write(cmake_cache_option('ENABLE_GRPC', False))

            if '+shared' in spec:
                cfg.write(cmake_cache_option('GEOS_BUILD_SHARED_LIBS', True))
            else:
                cfg.write(cmake_cache_option('GEOS_BUILD_SHARED_LIBS', False))

            # ATS
            # Dane/Matrix
            if sys_type in ('toss_4_x86_64_ib'):
                cfg.write(cmake_cache_string('ATS_ARGUMENTS', '--machine slurm112'))

    def lvarray_hostconfig(self, spec, prefix, py_site_pkgs_dir=None):
        """
        This method creates a 'host-config' file that specifies
        all of the options used to configure and build LvArray.

        Note:
          The `py_site_pkgs_dir` arg exists to allow a package that
          subclasses this package provide a specific site packages
          dir when calling this function. `py_site_pkgs_dir` should
          be an absolute path or `None`.

          This is necessary because the spack `site_packages_dir`
          var will not exist in the base class. For more details
          on this issue see: https://github.com/spack/spack/issues/6261
        """

        #######################
        # Compiler Info
        #######################
        c_compiler = env["SPACK_CC"]
        cpp_compiler = env["SPACK_CXX"]

        #######################################################################
        # By directly fetching the names of the actual compilers we appear
        # to doing something evil here, but this is necessary to create a
        # 'host config' file that works outside of the spack install env.
        #######################################################################

        sys_type = self._get_sys_type(spec)

        ##############################################
        # Find and record what CMake is used
        ##############################################

        cmake_exe = spec['cmake'].command.path
        cmake_exe = os.path.realpath(cmake_exe)

        host_config_path = self._get_host_config_path(spec, lvarray=True)
        with open(host_config_path, "w") as cfg:
            cfg.write("#{0}\n".format("#" * 80))
            cfg.write("# Generated host-config - Edit at own risk!\n")
            cfg.write("#{0}\n".format("#" * 80))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# SYS_TYPE: {0}\n".format(sys_type))
            cfg.write("# Compiler Spec: {0}\n".format(spec.compiler))
            cfg.write("# CMake executable path: %s\n" % cmake_exe)
            cfg.write("#{0}\n\n".format("-" * 80))

            #######################
            # Compiler Settings
            #######################

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# Compilers\n")
            cfg.write("#{0}\n\n".format("-" * 80))
            cfg.write(cmake_cache_path("CMAKE_C_COMPILER", c_compiler))
            cflags = ' '.join(spec.compiler_flags['cflags'])
            cxxflags = ' '.join(spec.compiler_flags['cxxflags'])
            if '+sanitizers' in spec:
                sanitizer_compile_flags = _sanitizer_compile_flags(spec)
                cflags = _join_flags(cflags, sanitizer_compile_flags)
                cxxflags = _join_flags(cxxflags, sanitizer_compile_flags)
            if cflags:
                cfg.write(cmake_cache_string("CMAKE_C_FLAGS", cflags))

            cfg.write(cmake_cache_path("CMAKE_CXX_COMPILER", cpp_compiler))
            if cxxflags:
                cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS", cxxflags))
            write_sanitizer_cache(cfg, spec)

            release_flags = "-O3 -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELEASE", release_flags))
            reldebinf_flags = "-O2 -g -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELWITHDEBINFO", reldebinf_flags))
            debug_flags = "-g"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_DEBUG", debug_flags))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Cuda\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+cuda' in spec:
                cfg.write(cmake_cache_option('ENABLE_CUDA', True))
                cfg.write(cmake_cache_string('CMAKE_CUDA_STANDARD', spec.variants['cxxstd'].value))

                cudatoolkitdir = spec['cuda'].prefix
                cfg.write(cmake_cache_path('CUDA_TOOLKIT_ROOT_DIR', cudatoolkitdir))
                cudacompiler = '${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc'
                cfg.write(cmake_cache_path('CMAKE_CUDA_COMPILER', cudacompiler))

                cmake_cuda_flags = ('-restrict --allow-unsupported-compiler --extended-lambda -Werror '
                                    'cross-execution-space-call,reorder,'
                                    'deprecated-declarations')

                archSpecifiers = ('-mtune', '-mcpu', '-march', '-qtune', '-qarch')
                for archSpecifier in archSpecifiers:
                    for compilerArg in spec.compiler_flags['cxxflags']:
                        if compilerArg.startswith(archSpecifier):
                            cmake_cuda_flags += ' -Xcompiler ' + compilerArg

                if not spec.satisfies('cuda_arch=none'):
                    cuda_arches = [str(arch) for arch in spec.variants['cuda_arch'].value]
                    cfg.write(cmake_cache_string('CMAKE_CUDA_ARCHITECTURES', ';'.join(cuda_arches)))

                if '+sanitizers' in spec:
                    cmake_cuda_flags += (
                        ' -Xcompiler=-fsanitize=address,-fsanitize=undefined,-fno-omit-frame-pointer'
                    )

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS', cmake_cuda_flags))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELEASE', '-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3'))
                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELWITHDEBINFO', '-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}'))
                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_DEBUG', '-g -G -O0 -Xcompiler -O0'))

            else:
                cfg.write(cmake_cache_option('ENABLE_CUDA', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Performance Portability TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_option('ENABLE_CHAI', True))
            cfg.write(cmake_cache_path('CHAI_DIR', spec['chai'].prefix))

            cfg.write(cmake_cache_path('RAJA_DIR', spec['raja'].prefix))

            cfg.write(cmake_cache_option('ENABLE_UMPIRE', True))
            cfg.write(cmake_cache_path('UMPIRE_DIR', spec['umpire'].prefix))

            cfg.write(cmake_cache_path('CAMP_DIR', spec['camp'].prefix))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# IO TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+caliper' in spec:
                cfg.write(cmake_cache_option('ENABLE_CALIPER', True))
                cfg.write(cmake_cache_path('CALIPER_DIR', spec['caliper'].prefix))
                cfg.write(cmake_cache_path('adiak_DIR', spec['adiak'].prefix + '/lib/cmake/adiak'))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Documentation\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+docs' in spec:
                sphinx_bin_dir = spec['py-sphinx'].prefix.bin
                cfg.write(cmake_cache_path('SPHINX_EXECUTABLE', os.path.join(sphinx_bin_dir, 'sphinx-build')))

                doxygen_bin_dir = spec['doxygen'].prefix.bin
                cfg.write(cmake_cache_path('DOXYGEN_EXECUTABLE', os.path.join(doxygen_bin_dir, 'doxygen')))
            else:
                cfg.write(cmake_cache_option('ENABLE_DOXYGEN', False))
                cfg.write(cmake_cache_option('ENABLE_SPHINX', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Development tools\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+addr2line' in spec:
                cfg.write('#{0}\n'.format('-' * 80))
                cfg.write('# addr2line\n')
                cfg.write('#{0}\n\n'.format('-' * 80))
                cfg.write(cmake_cache_option('ENABLE_ADDR2LINE', True))
                cfg.write(cmake_cache_path('ADDR2LINE_EXEC', os.path.join(spec['addr2line'].prefix.bin, 'addr2line')))

    def cmake_args(self):
        pass
        # spec = self.spec
        # host_config_path = self._get_host_config_path(spec)

        # options = []
        # options.extend(['-C', host_config_path])

        # # Shared libs
        # options.append(self.define_from_variant('BUILD_SHARED_LIBS', 'shared'))

        # if '~tests~examples~benchmarks' in spec:
        #     options.append('-DGEOS_ENABLE_TESTS=OFF')
        # else:
        #     options.append('-DGEOS_ENABLE_TESTS=ON')

        # if '~test' in spec:
        #     options.append('-DDISABLE_UNIT_TESTS=ON')
        # elif "+tests" in spec and ('%intel' in spec or '%xl' in spec):
        #     warnings.warn('The LvArray unit tests take an excessive amount of'
        #                   ' time to build with the Intel or IBM compilers.')

        # options.append(self.define_from_variant('ENABLE_EXAMPLES', 'examples'))
        # options.append(self.define_from_variant('ENABLE_BENCHMARKS',
        #                                         'benchmarks'))
        # options.append(self.define_from_variant('ENABLE_DOCS', 'docs'))

        # return options
