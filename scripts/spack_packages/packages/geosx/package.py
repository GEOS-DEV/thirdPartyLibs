# Copyright 2013-2023 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
import warnings

import socket
import os

from os import environ as env
from os.path import join as pjoin

from spack_repo.builtin.build_systems.cached_cmake import cmake_cache_path

from spack_repo.builtin.build_systems.cmake import CMakePackage
from spack_repo.builtin.build_systems.cuda import CudaPackage

# Tested specs are located at scripts/spack_configs/<$SYS_TYPE>/spack.yaml (e.g. %clang@10.0.1)

# WARNING: +petsc variant is yet to be tested.


def cmake_cache_entry(name, value, comment=""):
    """Generate a string for a cmake cache variable"""

    return 'set(%s "%s" CACHE PATH "%s")\n\n' % (name, value, comment)


def cmake_cache_list(name, value, comment=""):
    """Generate a list for a cmake cache variable"""

    indent = 5 + len(name)
    join_str = '\n' + ' ' * indent
    return 'set(%s %s CACHE STRING "%s")\n\n' % (name, join_str.join(value), comment)


def cmake_cache_string(name, string, comment=""):
    """Generate a string for a cmake cache variable"""

    return 'set(%s "%s" CACHE STRING "%s")\n\n' % (name, string, comment)


def cmake_cache_option(name, boolean_value, comment=""):
    """Generate a string for a cmake configuration option"""

    value = "ON" if boolean_value else "OFF"
    return 'set(%s %s CACHE BOOL "%s")\n\n' % (name, value, comment)


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
    variant('trilinos', default=True, description='Build Trilinos support.')
    variant('hypre', default=True, description='Build HYPRE support.')
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

    # SPHINX_BEGIN_DEPENDS
    depends_on("c", type="build")
    depends_on("cxx", type="build")
    depends_on("fortran", type="build")

    depends_on('cmake@3.24:', type='build')

    depends_on('blt')

    #
    # Virtual packages
    #
    depends_on('mpi')
    depends_on('blas')
    depends_on('lapack')

    #
    # Performance portability
    #
    depends_on('raja ~examples~exercises~shared')
    depends_on("raja~openmp", when="~openmp")
    depends_on("raja+openmp", when="+openmp")

    depends_on('umpire +c~examples+fortran~device_alloc~shared')
    depends_on("umpire~openmp", when="~openmp")
    depends_on("umpire+openmp", when="+openmp")

    depends_on('chai +raja~examples~shared')
    depends_on("chai~openmp", when="~openmp")
    depends_on("chai+openmp", when="+openmp")

    depends_on('camp')

    #
    # GPUs
    #
    with when('+cuda'):
        for sm_ in CudaPackage.cuda_arch_values:
            depends_on('raja+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('umpire+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('chai+cuda~separable_compilation cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('camp+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))
            depends_on('hypre+cuda cuda_arch={0}'.format(sm_), when='cuda_arch={0}'.format(sm_))

    with when('+rocm'):
        for gfx_ in ROCmPackage.amdgpu_targets:
            depends_on(f"raja+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"umpire+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"chai+rocm~separable_compilation amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"camp+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")
            depends_on(f"hypre+rocm amdgpu_target={gfx_}", when=f"amdgpu_target={gfx_}")

    #
    # IO
    #
    depends_on('hdf5@1.12.1')
    depends_on('silo@4.11.1-bsd~fortran~shared~python')

    depends_on('conduit~test~fortran~hdf5_compat+shared')

    depends_on('adiak@0.4.0 ~shared', when='+caliper')
    depends_on('caliper~gotcha~sampler~libunwind~libdw', when='+caliper')

    depends_on('pugixml@1.13 ~shared')

    depends_on('fmt@10.0.0 cxxstd=14')
    depends_on('vtk@9.4.2', when='+vtk')

    #
    # Math
    #
    depends_on("parmetis@4.0.3+int64~shared cflags='-fPIC' cxxflags='-fPIC'")
    depends_on("metis +int64~shared cflags='-fPIC' cxxflags='-fPIC'")

    depends_on("superlu-dist +int64  fflags='-fPIC'")
    depends_on("superlu-dist~openmp", when="~openmp")
    depends_on("superlu-dist+openmp", when="+openmp")

    # -Wno-error=implicit-function-declaration needed for 'METIS_PartMeshDual' error
    depends_on("scotch@7.0.8 ~compression +mpi +esmumps +int64 determinism=FULL ~shared ~metis build_system=cmake cflags='-fPIC' cxxflags='-fPIC'", when='+scotch')

    depends_on('suite-sparse@5.10.1')
    depends_on("suite-sparse~openmp", when="~openmp")
    depends_on("suite-sparse+openmp", when="+openmp")

    with when("+trilinos"):
        trilinos_packages = '+aztec+stratimikos~amesos2~anasazi~belos~ifpack2~muelu~sacado+thyra+zoltan'
        depends_on("trilinos@16.1.0 cflags='-fPIC' cxxflags='-fPIC -include cstdint' fflags='-fPIC'" + trilinos_packages)
        depends_on("trilinos~openmp", when="~openmp")
        depends_on("trilinos+openmp", when="+openmp")

    with when("+hypre"):
        depends_on("hypre +superlu-dist+mixedint+mpi~shared+pic", when='~cuda~rocm')
        depends_on("hypre +cuda+superlu-dist+mixedint+mpi+umpire+unified-memory~shared+pic", when='+cuda')
        depends_on("hypre +rocm+superlu-dist+mixedint+mpi+umpire+unified-memory~shared+pic", when='+rocm')
        depends_on("hypre ~openmp", when="~openmp")
        depends_on("hypre +openmp", when="+openmp")

    depends_on('petsc@3.19.4~hdf5~hypre+int64', when='+petsc')
    depends_on('petsc+ptscotch', when='+petsc+scotch')

    #
    # Python
    #
    depends_on('python')


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

    # SPHINX_END_DEPENDS

    #
    # Conflicts
    #
    conflicts('~trilinos lai=trilinos', msg='To use Trilinos as the Linear Algebra Interface you must build it.')
    conflicts('~hypre lai=hypre', msg='To use HYPRE as the Linear Algebra Interface you must build it.')
    conflicts('~petsc lai=petsc', msg='To use PETSc as the Linear Algebra Interface you must build it.')

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
        var = ''

        if '+cuda' in spec:
            var = '-'.join([var, 'cuda'])
            var += "@" + str(spec['cuda'].version)
        elif '+rocm' in spec:
            var = '-'.join([var, 'rocm'])
            var += "@" + str(spec['hip'].version)


        hostname = socket.gethostname().rstrip('1234567890')

        if lvarray:
            hostname = "lvarray-" + hostname

        host_config_path = "%s-%s-%s@%s%s.cmake" % (hostname, self._get_sys_type(spec), (str(spec.compiler.name)), str(spec.compiler.version),var)

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
            cfg.write(cmake_cache_entry("CMAKE_C_COMPILER", c_compiler))
            cflags = ' '.join(spec.compiler_flags['cflags'])
            if cflags:
                cfg.write(cmake_cache_entry("CMAKE_C_FLAGS", cflags))

            cfg.write(cmake_cache_entry("CMAKE_CXX_COMPILER", cpp_compiler))
            cxxflags = ' '.join(spec.compiler_flags['cxxflags'])
            if cxxflags:
                cfg.write(cmake_cache_entry("CMAKE_CXX_FLAGS", cxxflags))

            release_flags = "-O3 -DNDEBUG"
            if "clang" in self.compiler.cxx:
                release_flags += " -march=native -mtune=native"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELEASE", release_flags))
            reldebinf_flags = "-O2 -g -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELWITHDEBINFO", reldebinf_flags))
            debug_flags = "-g"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_DEBUG", debug_flags))

            if "%clang arch=linux-rhel7-ppc64le" in spec:
                cfg.write(cmake_cache_entry("CMAKE_EXE_LINKER_FLAGS", "-Wl,--no-toc-optimize"))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# CMake Standard\n")
            cfg.write("#{0}\n\n".format("-" * 80))

            cfg.write(cmake_cache_string("BLT_CXX_STD", "c++17"))

            cfg.write("#{0}\n".format("-" * 80))
            cfg.write("# MPI\n")
            cfg.write("#{0}\n\n".format("-" * 80))

            cfg.write(cmake_cache_option('ENABLE_MPI', True))
            cfg.write(cmake_cache_entry('MPI_C_COMPILER', spec['mpi'].mpicc))
            cfg.write(cmake_cache_entry('MPI_CXX_COMPILER', spec['mpi'].mpicxx))

            hostname = socket.gethostname().rstrip('1234567890')

            if sys_type in ('linux-rhel7-ppc64le', 'linux-rhel8-ppc64le', 'blueos_3_ppc64le_ib_p9') \
               and hostname != 'p3dev':
                cfg.write(cmake_cache_option('ENABLE_WRAP_ALL_TESTS_WITH_MPIEXEC', True))
                if hostname in ('lassen', 'rzansel'):
                    cfg.write(cmake_cache_entry('MPIEXEC', 'lrun'))
                    cfg.write(cmake_cache_entry('MPIEXEC_NUMPROC_FLAG', '-n'))
                else:
                    cfg.write(cmake_cache_entry('MPIEXEC', 'jsrun'))
                    cfg.write(cmake_cache_list('MPIEXEC_NUMPROC_FLAG', ['-g1', '--bind', 'rs', '-n']))
            elif sys_type in ('toss_4_x86_64_ib_cray'):
                cfg.write(cmake_cache_entry('MPIEXEC', 'srun'))
                cfg.write(cmake_cache_entry('MPIEXEC_NUMPROC_FLAG', '-n'))
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
                cfg.write(cmake_cache_entry('CMAKE_CUDA_STANDARD', 17))

                cudatoolkitdir = spec['cuda'].prefix
                cfg.write(cmake_cache_entry('CUDA_TOOLKIT_ROOT_DIR', cudatoolkitdir))
                cudacompiler = '${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc'
                cfg.write(cmake_cache_entry('CMAKE_CUDA_COMPILER', cudacompiler))

                cmake_cuda_flags = ('-restrict --expt-extended-lambda -Werror '
                                    'cross-execution-space-call,reorder,'
                                    'deprecated-declarations')

                archSpecifiers = ('-mtune', '-mcpu', '-march', '-qtune', '-qarch')
                for archSpecifier in archSpecifiers:
                    for compilerArg in spec.compiler_flags['cxxflags']:
                        if compilerArg.startswith(archSpecifier):
                            cmake_cuda_flags += ' -Xcompiler ' + compilerArg

                if not spec.satisfies('cuda_arch=none'):
                    cuda_arch = spec.variants['cuda_arch'].value
                    cmake_cuda_flags += ' -arch sm_{0}'.format(cuda_arch[0])
                    cfg.write(cmake_cache_string('CMAKE_CUDA_ARCHITECTURES', cuda_arch[0]))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS', cmake_cuda_flags))

                # System specific flags
                if sys_type in ('linux-rhel7-ppc64le', 'linux-rhel8-ppc64le', 'blueos_3_ppc64le_ib_p9'):
                    cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELEASE', '-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3 -Xcompiler -mcpu=powerpc64le -Xcompiler -mtune=powerpc64le'))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELWITHDEBINFO', '-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}'))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_DEBUG', '-g -G -O0 -Xcompiler -O0'))

                cuda_stack_size = int(spec.variants['cuda_stack_size'].value)
                if 0 < cuda_stack_size:
                    cfg.write(cmake_cache_option('ENABLE_CUDA_STACK_SIZE', True, "Adjust the CUDA stack size limit"))
                    cfg.write(cmake_cache_entry('CUDA_STACK_SIZE', cuda_stack_size, "CUDA stack size in KB"))

            else:
                cfg.write(cmake_cache_option('ENABLE_CUDA', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# ROCm/HIP\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+rocm' in spec:
                cfg.write(cmake_cache_option('ENABLE_HIP', True))
                cfg.write(cmake_cache_string('CMAKE_HIP_STANDARD', 17))
                cfg.write(cmake_cache_entry('CMAKE_HIP_COMPILER', spec['hip'].prefix.bin.hipcc))

                if not spec.satisfies('amdgpu_target=none'):
                    cmake_hip_archs = ";".join(spec.variants["amdgpu_target"].value)
                    cfg.write(cmake_cache_string('CMAKE_HIP_ARCHITECTURES', cmake_hip_archs))

                cfg.write(cmake_cache_entry('ROCM_PATH', spec['hip'].prefix))
            else:
                cfg.write(cmake_cache_option('ENABLE_HIP', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Performance Portability TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_option('ENABLE_CHAI', True))
            cfg.write(cmake_cache_entry('CHAI_DIR', spec['chai'].prefix))

            cfg.write(cmake_cache_entry('RAJA_DIR', spec['raja'].prefix))

            cfg.write(cmake_cache_option('ENABLE_UMPIRE', True))
            cfg.write(cmake_cache_entry('UMPIRE_DIR', spec['umpire'].prefix))

            cfg.write(cmake_cache_entry('CAMP_DIR', spec['camp'].prefix))

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
                cfg.write(cmake_cache_entry('CALIPER_DIR', spec['caliper'].prefix))
                cfg.write(cmake_cache_entry('ADIAK_DIR', spec['adiak'].prefix))

            for tpl, cmake_name, enable in io_tpls:
                if enable:
                    cfg.write(cmake_cache_entry('{}_DIR'.format(cmake_name), spec[tpl].prefix))
                else:
                    cfg.write(cmake_cache_option('ENABLE_{}'.format(cmake_name), False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# System Math Libraries\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if spec["blas"].name == "intel-oneapi-mkl":
                cfg.write(cmake_cache_option('ENABLE_MKL', True))
                cfg.write(cmake_cache_entry('MKL_INCLUDE_DIRS', spec['intel-oneapi-mkl'].prefix.include))
                cfg.write(cmake_cache_list('MKL_LIBRARIES', spec['intel-oneapi-mkl'].libs))
            elif spec["blas"].name == "mkl":
                cfg.write(cmake_cache_option('ENABLE_MKL', True))
                cfg.write(cmake_cache_entry('MKL_INCLUDE_DIRS', spec['intel-mkl'].prefix.include))
                cfg.write(cmake_cache_list('MKL_LIBRARIES', spec['intel-mkl'].libs))
            elif spec["blas"].name == "essl":
                cfg.write(cmake_cache_option('ENABLE_ESSL', True))
                cfg.write(cmake_cache_entry('ESSL_INCLUDE_DIRS', spec['essl'].prefix.include))
                cfg.write(cmake_cache_list('ESSL_LIBRARIES', spec['blas'].libs))

                cfg.write(cmake_cache_option('FORTRAN_MANGLE_NO_UNDERSCORE', True))
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
                ('petsc', 'PETSC', '+petsc' in spec)
            )
            # yapf: enable

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Math TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            for tpl, cmake_name, enable in math_tpls:
                if enable:
                    cfg.write(cmake_cache_entry('{}_DIR'.format(cmake_name), spec[tpl].prefix))

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

            cfg.write(cmake_cache_entry('Python3_ROOT_DIR', os.path.join(spec['python'].prefix)))
            cfg.write(cmake_cache_entry('Python3_EXECUTABLE', os.path.join(spec['python'].prefix.bin, 'python3')))

            if '+pygeosx' in spec:
                cfg.write(cmake_cache_option('ENABLE_PYGEOSX', True))
            else:
                cfg.write(cmake_cache_option('ENABLE_PYGEOSX', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Documentation\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+docs' in spec:
                sphinx_bin_dir = spec['py-sphinx'].prefix.bin
                cfg.write(cmake_cache_entry('SPHINX_EXECUTABLE', os.path.join(sphinx_bin_dir, 'sphinx-build')))

                doxygen_bin_dir = spec['doxygen'].prefix.bin
                cfg.write(cmake_cache_entry('DOXYGEN_EXECUTABLE', os.path.join(doxygen_bin_dir, 'doxygen')))
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
                    cmake_cache_entry('UNCRUSTIFY_EXECUTABLE', os.path.join(spec['uncrustify'].prefix.bin, 'uncrustify')))

            if '+addr2line' in spec:
                cfg.write('#{0}\n'.format('-' * 80))
                cfg.write('# addr2line\n')
                cfg.write('#{0}\n\n'.format('-' * 80))
                cfg.write(cmake_cache_option('ENABLE_ADDR2LINE', True))
                cfg.write(cmake_cache_entry('ADDR2LINE_EXEC ', '/usr/bin/addr2line'))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Other\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+mathpresso' in spec:
                cfg.write(cmake_cache_option('ENABLE_MATHPRESSO', True))
                cfg.write(cmake_cache_entry('MATHPRESSO_DIR', spec['mathpresso'].prefix))
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
            # Lassen
            if sys_type in ('blueos_3_ppc64le_ib_p9'):
                cfg.write(cmake_cache_string('ATS_ARGUMENTS', '--ats jsrun_omp --ats jsrun_bind=packed'))
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
            cfg.write(cmake_cache_entry("CMAKE_C_COMPILER", c_compiler))
            cflags = ' '.join(spec.compiler_flags['cflags'])
            if cflags:
                cfg.write(cmake_cache_entry("CMAKE_C_FLAGS", cflags))

            cfg.write(cmake_cache_entry("CMAKE_CXX_COMPILER", cpp_compiler))
            cxxflags = ' '.join(spec.compiler_flags['cxxflags'])
            if cxxflags:
                cfg.write(cmake_cache_entry("CMAKE_CXX_FLAGS", cxxflags))

            release_flags = "-O3 -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELEASE", release_flags))
            reldebinf_flags = "-O2 -g -DNDEBUG"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_RELWITHDEBINFO", reldebinf_flags))
            debug_flags = "-g"
            cfg.write(cmake_cache_string("CMAKE_CXX_FLAGS_DEBUG", debug_flags))

            if "%clang arch=linux-rhel7-ppc64le" in spec:
                cfg.write(cmake_cache_entry("CMAKE_EXE_LINKER_FLAGS", "-Wl,--no-toc-optimize"))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Cuda\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+cuda' in spec:
                cfg.write(cmake_cache_option('ENABLE_CUDA', True))
                cfg.write(cmake_cache_entry('CMAKE_CUDA_STANDARD', 17))

                cudatoolkitdir = spec['cuda'].prefix
                cfg.write(cmake_cache_entry('CUDA_TOOLKIT_ROOT_DIR', cudatoolkitdir))
                cudacompiler = '${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc'
                cfg.write(cmake_cache_entry('CMAKE_CUDA_COMPILER', cudacompiler))

                cmake_cuda_flags = ('-restrict --expt-extended-lambda -Werror '
                                    'cross-execution-space-call,reorder,'
                                    'deprecated-declarations')

                archSpecifiers = ('-mtune', '-mcpu', '-march', '-qtune', '-qarch')
                for archSpecifier in archSpecifiers:
                    for compilerArg in spec.compiler_flags['cxxflags']:
                        if compilerArg.startswith(archSpecifier):
                            cmake_cuda_flags += ' -Xcompiler ' + compilerArg

                if not spec.satisfies('cuda_arch=none'):
                    cuda_arch = spec.variants['cuda_arch'].value
                    cmake_cuda_flags += ' -arch sm_{0}'.format(cuda_arch[0])
                    cfg.write(cmake_cache_string('CMAKE_CUDA_ARCHITECTURES', cuda_arch[0]))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS', cmake_cuda_flags))

                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELEASE', '-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3 -Xcompiler -mcpu=powerpc64le -Xcompiler -mtune=powerpc64le'))
                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_RELWITHDEBINFO', '-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}'))
                cfg.write(cmake_cache_string('CMAKE_CUDA_FLAGS_DEBUG', '-g -G -O0 -Xcompiler -O0'))

            else:
                cfg.write(cmake_cache_option('ENABLE_CUDA', False))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Performance Portability TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            cfg.write(cmake_cache_option('ENABLE_CHAI', True))
            cfg.write(cmake_cache_entry('CHAI_DIR', spec['chai'].prefix))

            cfg.write(cmake_cache_entry('RAJA_DIR', spec['raja'].prefix))

            cfg.write(cmake_cache_option('ENABLE_UMPIRE', True))
            cfg.write(cmake_cache_entry('UMPIRE_DIR', spec['umpire'].prefix))

            cfg.write(cmake_cache_entry('CAMP_DIR', spec['camp'].prefix))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# IO TPLs\n')
            cfg.write('#{0}\n\n'.format('-' * 80))

            if '+caliper' in spec:
                cfg.write(cmake_cache_option('ENABLE_CALIPER', True))
                cfg.write(cmake_cache_entry('CALIPER_DIR', spec['caliper'].prefix))
                cfg.write(cmake_cache_entry('adiak_DIR', spec['adiak'].prefix + '/lib/cmake/adiak'))

            cfg.write('#{0}\n'.format('-' * 80))
            cfg.write('# Documentation\n')
            cfg.write('#{0}\n\n'.format('-' * 80))
            if '+docs' in spec:
                sphinx_bin_dir = spec['py-sphinx'].prefix.bin
                cfg.write(cmake_cache_entry('SPHINX_EXECUTABLE', os.path.join(sphinx_bin_dir, 'sphinx-build')))

                doxygen_bin_dir = spec['doxygen'].prefix.bin
                cfg.write(cmake_cache_entry('DOXYGEN_EXECUTABLE', os.path.join(doxygen_bin_dir, 'doxygen')))
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
