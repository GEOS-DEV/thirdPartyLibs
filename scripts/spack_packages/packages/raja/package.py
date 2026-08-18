from spack.package import *
from spack_repo.builtin.packages.raja.package import Raja as BuiltinRaja


class Raja(BuiltinRaja):
    version(
        "2026.05.19",
        commit="d9a03fd56f7fb81540aeacbf082eb35dbb840b9c",
        submodules=False,
    )

    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("BLT_CXX_STD", "c++20"))
        args.append(self.define("CMAKE_CXX_STANDARD", 20))
        args.append(self.define("CMAKE_CUDA_STANDARD", 20))
        args.append(self.define("CMAKE_HIP_STANDARD", 20))
        return args
