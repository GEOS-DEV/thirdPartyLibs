# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.raja.package import Raja as BuiltinRaja


class Raja(BuiltinRaja):
    # RAJA's CUDA and HIP reducer assignment operators need to preserve the
    # ownership of host/device resources used by GEOS kernels.
    patch("patches/raja-reducer-assignment.patch", when="@2026.07.0")
