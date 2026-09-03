# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.hdf5.package import Hdf5 as BuiltinHdf5


class Hdf5(BuiltinHdf5):
    # HDF5 1.12.1 needs the CMake callback and duplicate-byproduct fixes used
    # by the GEOS TPL superbuild.  HDF5 1.14.6 already contains the upstream
    # equivalents, so do not apply this patch to the newer source layout.
    patch("patches/hdf5-cmake-duplicate-byproduct.patch", when="@1.12.1")
