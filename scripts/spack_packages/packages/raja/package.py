# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *
from spack_repo.builtin.packages.raja.package import Raja as BuiltinRaja

class Raja(BuiltinRaja):
    depends_on("cxx", type="build")

    # From radiuss-packages (PR #143)
    depends_on("blt@0.7.1:", type="build", when="@2025.09.0:")
    depends_on("blt@0.7.0:", type="build", when="@2025.03.0:")
    depends_on("camp@main", when="@develop")
    depends_on("camp@2025.09.2:", when="@2025.09.0:")
    depends_on("camp@2025.03.0:", when="@2025.03.0:")
    depends_on("camp@2024.07.0:", when="@2024.07.0:")
    depends_on("camp@2024.02.1:", when="@2024.02.1:")

    def initconfig_hardware_entries(self):
        spec = self.spec
        entries = super().initconfig_hardware_entries()

        entries.append("#------------------{0}".format("-" * 30))
        entries.append("# Package custom hardware settings")
        entries.append("#------------------{0}\n".format("-" * 30))

        entries.append(cmake_cache_option("ENABLE_OPENMP", spec.satisfies("+openmp")))
        entries.append(cmake_cache_option("ENABLE_CUDA", spec.satisfies("+cuda")))

        if spec.satisfies("+rocm"):
            entries.append(cmake_cache_option("ENABLE_HIP", True))
            hipcc_flags = []
            if self.spec.satisfies("@2025.09.0:"):
                hipcc_flags.append("-std=c++17")
            elif self.spec.satisfies("@0.14.0:2025.09.0"):
                hipcc_flags.append("-std=c++14")
            entries.append(cmake_cache_string("HIP_HIPCC_FLAGS", " ".join(hipcc_flags)))
        else:
            entries.append(cmake_cache_option("ENABLE_HIP", False))

        return entries

    def initconfig_package_entries(self):
        spec = self.spec
        entries = []

        option_prefix = "RAJA_" if spec.satisfies("@0.14.0:") else ""

        # TPL locations
        entries.append("#------------------{0}".format("-" * 60))
        entries.append("# TPLs")
        entries.append("#------------------{0}\n".format("-" * 60))

        entries.append(cmake_cache_path("BLT_SOURCE_DIR", spec["blt"].prefix))
        if "camp" in self.spec:
            entries.append(cmake_cache_path("camp_DIR", spec["camp"].prefix))

        # Build options
        entries.append("#------------------{0}".format("-" * 60))
        entries.append("# Build Options")
        entries.append("#------------------{0}\n".format("-" * 60))

        entries.append(cmake_cache_string("CMAKE_BUILD_TYPE", spec.variants["build_type"].value))
        entries.append(cmake_cache_option("BUILD_SHARED_LIBS", spec.satisfies("+shared")))

        entries.append(cmake_cache_option("RAJA_ENABLE_DESUL_ATOMICS", spec.satisfies("+desul")))

        entries.append(
            cmake_cache_option("RAJA_ENABLE_VECTORIZATION", spec.satisfies("+vectorization"))
        )

        entries.append(cmake_cache_option("RAJA_ENABLE_OPENMP_TASK", spec.satisfies("+omptask")))

        entries.append(
            cmake_cache_option("RAJA_ENABLE_TARGET_OPENMP", spec.satisfies("+omptarget"))
        )

        entries.append(cmake_cache_option("RAJA_ENABLE_SYCL", spec.satisfies("+sycl")))
        entries.append(
            cmake_cache_option("RAJA_ENABLE_NV_TOOLS_EXT", spec.satisfies("+gpu-profiling +cuda"))
        )
        entries.append(
            cmake_cache_option("RAJA_ENABLE_ROCTX", spec.satisfies("+gpu-profiling +rocm"))
        )

        if spec.satisfies("+lowopttest"):
            entries.append(cmake_cache_string("CMAKE_CXX_FLAGS_RELEASE", "-O1"))

        # C++17
        if (spec.satisfies("@2025.09.0:") or
            (spec.satisfies("@2024.07.0:") and spec.satisfies("+sycl"))):
            entries.append(cmake_cache_string("BLT_CXX_STD", "c++17"))
        # C++14
        elif spec.satisfies("@0.14.0:2025.09.0"):
            entries.append(cmake_cache_string("BLT_CXX_STD", "c++14"))

            if spec.satisfies("+desul"):
                if spec.satisfies("+cuda"):
                    entries.append(cmake_cache_string("CMAKE_CUDA_STANDARD", "14"))

        entries.append(
            cmake_cache_option("RAJA_ENABLE_RUNTIME_PLUGINS", spec.satisfies("+plugins"))
        )

        if spec.satisfies("+omptarget"):
            entries.append(
                cmake_cache_string(
                    "BLT_OPENMP_COMPILE_FLAGS", "-fopenmp;-fopenmp-targets=nvptx64-nvidia-cuda"
                )
            )
            entries.append(
                cmake_cache_string(
                    "BLT_OPENMP_LINK_FLAGS", "-fopenmp;-fopenmp-targets=nvptx64-nvidia-cuda"
                )
            )

        entries.append(
            cmake_cache_option(
                "{}ENABLE_EXAMPLES".format(option_prefix), spec.satisfies("+examples")
            )
        )
        if spec.satisfies("@0.14.0:"):
            entries.append(
                cmake_cache_option(
                    "{}ENABLE_EXERCISES".format(option_prefix), spec.satisfies("+exercises")
                )
            )
        else:
            entries.append(cmake_cache_option("ENABLE_EXERCISES", spec.satisfies("+exercises")))

        # TODO: Treat the workaround when building tests with spack wrapper
        #       For now, removing it to test CI, which builds tests outside of wrapper.
        # Work around spack adding -march=ppc64le to SPACK_TARGET_ARGS which
        # is used by the spack compiler wrapper.  This can go away when BLT
        # removes -Werror from GTest flags
        #
        # if self.spec.satisfies("%clang target=ppc64le:")
        #   or (not self.run_tests and not spec.satisfies("+tests")):
        if not self.run_tests and not spec.satisfies("+tests"):
            entries.append(cmake_cache_option("ENABLE_TESTS", False))
        else:
            entries.append(cmake_cache_option("ENABLE_TESTS", True))
            if not spec.satisfies("+run-all-tests"):
                if spec.satisfies("%clang@12.0.0:13.9.999"):
                    entries.append(
                        cmake_cache_string(
                            "CTEST_CUSTOM_TESTS_IGNORE",
                            "test-algorithm-sort-OpenMP.exe;test-algorithm-stable-sort-OpenMP.exe",
                        )
                    )
                excluded_tests = [
                    "test-algorithm-sort-Cuda.exe",
                    "test-algorithm-stable-sort-Cuda.exe",
                    "test-algorithm-sort-OpenMP.exe",
                    "test-algorithm-stable-sort-OpenMP.exe",
                ]
                if spec.satisfies("+cuda %clang@12.0.0:13.9.999"):
                    entries.append(
                        cmake_cache_string("CTEST_CUSTOM_TESTS_IGNORE", ";".join(excluded_tests))
                    )
                if spec.satisfies("+cuda %xl@16.1.1.12"):
                    entries.append(
                        cmake_cache_string(
                            "CTEST_CUSTOM_TESTS_IGNORE",
                            "test-algorithm-sort-Cuda.exe;test-algorithm-stable-sort-Cuda.exe",
                        )
                    )

        entries.append(cmake_cache_option("RAJA_HOST_CONFIG_LOADED", True))

        return entries
