# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.hypre.package import Hypre as BuiltinHypre


class Hypre(BuiltinHypre):
    # Keep the complete Git history so HYPRE can report its tagged,
    # distance-aware development version (for example, v3.0.2-2-g<sha>).
    version("develop", branch="master", get_full_repo=True)
