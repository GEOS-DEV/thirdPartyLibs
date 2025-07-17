# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)
from spack.package import *
from spack_repo.builtin.build_systems.bundle import BundlePackage

# Recipe for pre-built essl library on blueos machines.
# Defines additonal flags for blueos:
# https://lc.llnl.gov/confluence/display/SIERRA/Math+Libraries
class Essl(BundlePackage):
    """IBM's Engineering and Scientific Subroutine Library (ESSL)."""

    homepage = "https://www.ibm.com/systems/power/software/essl/"

    version("6.3.0.2")

    provides("blas")
    provides("lapack")

    @property
    def blas_libs(self):
        spec = self.spec
        prefix = self.prefix

        essl_root = prefix.lib64
        essl_libs = ["libessl", "liblapackforessl", "liblapackforessl_"]
        all_libs = find_libraries(essl_libs, root=essl_root, shared=True)

        return all_libs

    @property
    def lapack_libs(self):
        spec = self.spec
        prefix = self.prefix

        essl_root = prefix.lib64
        essl_libs = ["libessl", "liblapackforessl", "liblapackforessl_"]
        all_libs = find_libraries(essl_libs, root=essl_root, shared=True)

        return all_libs
