# Copyright Spack Project Developers. See LICENSE-APACHE or LICENSE-MIT.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.parmetis.package import Parmetis as BuiltinParmetis


class Parmetis(BuiltinParmetis):
    # The GEOS superbuild compiles the bundled METIS with 64-bit indices.
    # Spack's standalone metis package already performs the equivalent header
    # update for +int64; this patch is for ParMETIS's bundled copy.
    patch("patches/parmetis-idx64.patch", when="@4.0.3+int64")

    # GEOS links SuperLU-DIST as a shared library.  Its static ParMETIS
    # dependency therefore has to contain position-independent code; the
    # upstream recipe does not propagate dependency cflags into CMake.
    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("CMAKE_POSITION_INDEPENDENT_CODE", True))
        return args
