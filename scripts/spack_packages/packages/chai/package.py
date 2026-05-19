import os

from spack.package import *
from spack_repo.builtin.packages.chai.package import Chai as BuiltinChai

class Chai(BuiltinChai):
    version(
        "2026.04.13",
        commit="c4de793a61596a6787afb07ed0dd1dfee349f34f",
        submodules=False,
    )

    # Bypass llnl_link_helpers failure
    depends_on("fortran")

    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("BLT_CXX_STD", "c++20"))
        args.append(self.define("CMAKE_CXX_STANDARD", 20))
        args.append(self.define("CMAKE_CUDA_STANDARD", 20))
        args.append(self.define("CMAKE_HIP_STANDARD", 20))
        return args
