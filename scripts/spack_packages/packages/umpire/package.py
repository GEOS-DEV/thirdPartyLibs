# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.umpire.package import Umpire as BuiltinUmpire


class Umpire(BuiltinUmpire):
    # The standalone Umpire recipe has a different source root than the
    # bundled Umpire copy in CHAI.  This package-local patch uses the
    # standalone path and fixes Judy's unaligned loads under UBSan.
    patch("patches/umpire-judy-ubsan.patch", when="@2026.07.1")
