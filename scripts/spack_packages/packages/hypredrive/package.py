# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.cmake import CMakePackage
from spack_repo.builtin.build_systems.cuda import CudaPackage
from spack_repo.builtin.build_systems.rocm import ROCmPackage

from spack.package import *


class Hypredrive(CMakePackage, CudaPackage, ROCmPackage):
    """Hypredrive is a high-level interface to the hypre library for solving
    sparse linear systems of equations. It provides a command-line driver
    (hypredrive-cli) accepting YAML input files and a C API library
    (libHYPREDRV)."""

    homepage = "https://hypredrive.readthedocs.io"
    url = "https://github.com/hypre-space/hypredrive/archive/v0.1.0.tar.gz"
    git = "https://github.com/hypre-space/hypredrive.git"

    maintainers("victorapm")

    license("MIT", checked_by="victorapm")

    version("develop", branch="master")
    version("0.2.0", sha256="2fe6c5b2779de41fbd294cb4647c7bbd210ec95934639117e56a790e56c32e41")
    version("0.1.0", sha256="39db73b75e37457035c64b4c8831abe716bf2f596c4ca79a32293d9bd51ca8d6")

    variant("shared", default=False, description="Build shared libraries")
    variant("pic", default=False, description="Build position independent code")
    variant("examples", default=False, description="Build and install example programs")
    variant("openmp", default=False, description="Enable OpenMP assembly in example programs")
    variant("hwloc", default=False, description="Enable hwloc support for system topology")
    variant("caliper", default=False, description="Enable Caliper performance profiling")
    variant("compression", default=False, description="Enable lossless compression backends")
    variant("sycl", default=False, description="Enable SYCL support")
    variant("cpp", default=False, description="Build the C++ interface")
    variant("fortran", default=False, description="Build the Fortran interface")
    variant("python", default=False, description="Build the Python interface")
    variant("matlab", default=False, description="Build the MATLAB/Octave MEX interface")
    variant("julia", default=False, description="Build the Julia interface")
    variant("superlu-dist", default=False, description="Enable SuperLU_DIST support in hypre")

    depends_on("c", type="build")
    for feature in ("caliper", "cuda", "rocm", "sycl", "cpp"):
        depends_on("cxx", type="build", when="+{0}".format(feature))
    depends_on("fortran", type="build", when="+fortran")

    depends_on("cmake@3.23:", type="build")
    depends_on("mpi")
    depends_on("hypre@2.20.0: +mpi")
    depends_on("hypre+shared", when="+shared")
    depends_on("hypre@2.21:+pic~shared", when="+pic~shared")
    depends_on("hypre+caliper", when="+caliper")
    depends_on("hypre+cuda", when="+cuda")
    depends_on("hypre+rocm", when="+rocm")
    depends_on("hypre@2.24:+sycl", when="+sycl")
    depends_on("hypre+superlu-dist", when="+superlu-dist")

    for feature in ("fortran", "matlab", "julia", "superlu-dist"):
        depends_on("hypre precision=double", when="+{0}".format(feature))
    for feature in ("matlab", "julia"):
        depends_on("hypre~complex", when="+{0}".format(feature))

    requires(
        "%c,cxx=oneapi",
        when="+sycl",
        msg="The SYCL backend must be compiled with oneAPI compilers",
    )

    for arch in CudaPackage.cuda_arch_values:
        depends_on(
            "hypre+cuda cuda_arch={0}".format(arch), when="+cuda cuda_arch={0}".format(arch)
        )
        depends_on(
            "superlu-dist@9.2.1:+cuda cuda_arch={0}".format(arch),
            when="+superlu-dist+cuda cuda_arch={0}".format(arch),
        )

    for target in ROCmPackage.amdgpu_targets:
        depends_on(
            "hypre+rocm amdgpu_target={0}".format(target),
            when="+rocm amdgpu_target={0}".format(target),
        )
        depends_on(
            "superlu-dist@9.2.1:+rocm amdgpu_target={0}".format(target),
            when="+superlu-dist+rocm amdgpu_target={0}".format(target),
        )

    depends_on("hwloc", when="+hwloc")
    depends_on("caliper", when="+caliper")
    depends_on("zlib-api", when="+compression")
    depends_on("zstd", when="+compression")
    depends_on("lz4", when="+compression")
    depends_on("c-blosc", when="+compression")
    depends_on("python@3.9:", type=("build", "link", "run"), when="+python")
    depends_on("py-cython@3:", type="build", when="+python")
    depends_on("py-numpy@1.20:", type=("build", "run"), when="+python")
    depends_on("octave", type=("build", "run"), when="+matlab")
    depends_on("julia", type=("build", "run"), when="+julia")
    depends_on("superlu-dist@9.2.1:", when="+superlu-dist")

    conflicts("+rocm", when="+cuda", msg="CUDA and ROCm are mutually exclusive")
    conflicts("+sycl", when="+cuda", msg="CUDA and SYCL are mutually exclusive")
    conflicts("+sycl", when="+rocm", msg="ROCm and SYCL are mutually exclusive")
    conflicts("~examples", when="+openmp", msg="OpenMP support applies only to examples")

    for interface in ("python", "matlab", "julia"):
        conflicts(
            "~pic~shared",
            when="+{0}".format(interface),
            msg="The {0} interface requires position independent code".format(interface),
        )

    def cmake_args(self):
        spec = self.spec
        from_variant = self.define_from_variant
        pic_enabled = "+pic" in spec or "+shared" in spec
        testing_enabled = self.run_tests

        args = [
            from_variant("BUILD_SHARED_LIBS", "shared"),
            from_variant("HYPREDRV_ENABLE_EXAMPLES", "examples"),
            from_variant("HYPREDRV_ENABLE_EXAMPLE_OMP", "openmp"),
            from_variant("HYPREDRV_ENABLE_HWLOC", "hwloc"),
            from_variant("HYPREDRV_ENABLE_CALIPER", "caliper"),
            from_variant("HYPREDRV_ENABLE_COMPRESSION", "compression"),
            from_variant("HYPREDRV_ENABLE_CUDA", "cuda"),
            from_variant("HYPREDRV_ENABLE_HIP", "rocm"),
            from_variant("HYPREDRV_ENABLE_SYCL", "sycl"),
            from_variant("HYPREDRV_ENABLE_CPP", "cpp"),
            from_variant("HYPREDRV_ENABLE_FORTRAN", "fortran"),
            from_variant("HYPREDRV_ENABLE_PYTHON", "python"),
            from_variant("HYPREDRV_ENABLE_MATLAB", "matlab"),
            from_variant("HYPREDRV_ENABLE_JULIA", "julia"),
            self.define("CMAKE_POSITION_INDEPENDENT_CODE", pic_enabled),
            self.define("HYPRE_ROOT", spec["hypre"].prefix),
            self.define("HYPREDRV_ENABLE_TESTING", testing_enabled),
            self.define("HYPREDRV_ENABLE_ALL_TESTS", False),
            self.define("HYPREDRV_ENABLE_COVERAGE", False),
            self.define("HYPREDRV_ENABLE_ANALYSIS", False),
            self.define("HYPREDRV_ENABLE_DATA", testing_enabled),
            self.define("HYPREDRV_ENABLE_DOCS", False),
            # Spack owns this dependency; never let CMake fetch another copy.
            self.define("HYPREDRV_BUILD_DSUPERLU", False),
            from_variant("HYPRE_ENABLE_DSUPERLU", "superlu-dist"),
        ]

        if "+python" in spec:
            args.append(self.define("Python_EXECUTABLE", spec["python"].command.path))
        if "+superlu-dist" in spec:
            superlu_dist = spec["superlu-dist"]
            args.extend(
                [
                    self.define("SUPERLU_DIST_ROOT", superlu_dist.prefix),
                    self.define("TPL_DSUPERLU_INCLUDE_DIRS", superlu_dist.prefix.include),
                    self.define("TPL_DSUPERLU_LIBRARIES", superlu_dist.libs),
                ]
            )

        return args

    def setup_run_environment(self, env):
        if "+python" in self.spec:
            env.prepend_path("PYTHONPATH", self.prefix.python)
        if "+matlab" in self.spec:
            env.prepend_path("MATLABPATH", self.prefix.lib.matlab)
            env.prepend_path("OCTAVE_PATH", self.prefix.lib.octave)
        if "+julia" in self.spec:
            env.prepend_path("JULIA_LOAD_PATH", self.prefix.share.julia)

    @property
    def headers(self):
        """Export the main HYPREDRV header.
        Sample usage: spec['hypredrive'].headers.cpp_flags
        """
        hdrs = find_headers("HYPREDRV", self.prefix.include, recursive=False)
        return hdrs or None

    @property
    def libs(self):
        """Export the HYPREDRV library.
        Sample usage: spec['hypredrive'].libs.ld_flags
        """
        is_shared = self.spec.satisfies("+shared")
        libs = find_libraries("libHYPREDRV", root=self.prefix, shared=is_shared, recursive=True)
        return libs or None

    def test_installed_binary(self):
        """verify hypredrive-cli binary exists"""
        hypredrive_cli = which(self.prefix.bin.join("hypredrive-cli"))
        if hypredrive_cli is None:
            raise SkipTest("hypredrive-cli not found in install prefix")

    def test_installed_library(self):
        """verify HYPREDRV library is findable"""
        if not self.libs:
            raise RuntimeError("Could not find libHYPREDRV in install prefix")

    def test_laplacian_example(self):
        """run the laplacian example (requires +examples)"""
        if not self.spec.satisfies("+examples"):
            raise SkipTest("Package must be installed with +examples")

        laplacian = which(self.prefix.bin.laplacian)
        if laplacian is None:
            raise SkipTest("laplacian example binary not found")

        mpirun = which("mpirun", "mpiexec", required=True)
        mpirun("-np", "1", laplacian, "-n", "6", "6", "6", "-s", "7", "-ns", "1", "-v", "1")
