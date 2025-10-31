# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *
from spack_repo.builtin.packages.umpire.package import Umpire as BuiltinUmpire

class Umpire(BuiltinUmpire):
    depends_on("c", type="build")  # generated
    depends_on("cxx", type="build")  # generated
    depends_on("fortran", type="build")  # generated

    # From radiuss-packages (PR #143)
    depends_on("blt@0.7.1:", type="build", when="@2025.09.0:")
    depends_on("camp@2025.09.2:", when="@2025.09.0:")
    depends_on("camp@2025.03.0:", when="@2025.03.0:")

    conflicts("+ipc_shmem", when="+mpi3_shmem @:2025.03.0")
