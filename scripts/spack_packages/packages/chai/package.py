# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.chai.package import Chai as BuiltinChai

class Chai(BuiltinChai):
    # Bypass llnl_link_helpers failure
    depends_on("fortran")
