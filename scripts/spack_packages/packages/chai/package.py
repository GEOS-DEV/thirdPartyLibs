# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *
from spack_repo.builtin.packages.chai.package import Chai as BuiltinChai

class Chai(BuiltinChai):
    # Bypass llnl_link_helpers failure
    depends_on("fortran")

    # From radiuss-packages (PR #143)
    depends_on("blt@0.7.1:", type="build", when="@2025.09.0:")
    depends_on("blt@0.7.0:", type="build", when="@2025.03.0:")
    depends_on("umpire@2025.09.0:", when="@2025.09.0:")
    depends_on("umpire@2025.03.0:", when="@2025.03.0:")
    depends_on("umpire@2024.07.0", when="@2024.07.0")
