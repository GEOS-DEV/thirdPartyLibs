# Copyright Spack Project Developers. See LICENSE-APACHE or LICENSE-MIT.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.parmetis.package import Parmetis as BuiltinParmetis


class Parmetis(BuiltinParmetis):
    # GEOS links SuperLU-DIST as a shared library.  Its static ParMETIS
    # dependency therefore has to contain position-independent code; the
    # upstream recipe does not propagate dependency cflags into CMake.
    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("CMAKE_POSITION_INDEPENDENT_CODE", True))
        return args
