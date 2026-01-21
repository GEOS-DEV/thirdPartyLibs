# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *
from spack_repo.builtin.packages.camp.package import Camp as BuiltinCamp

class Camp(BuiltinCamp):
    depends_on("cxx", type="build")

    # From radiuss-packages (PR #143)
    depends_on("blt@0.7.1:", type="build", when="@2025.09.0:")
    depends_on("blt@0.7.0:", type="build", when="@2025.03.0:")
