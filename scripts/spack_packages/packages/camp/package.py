from spack.package import *
from spack_repo.builtin.packages.camp.package import Camp as BuiltinCamp


class Camp(BuiltinCamp):
    version(
        "2026.05.18",
        commit="47a3682c3d5ff43b542ad7e29569eb5e157f918e",
        submodules=False,
    )

    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("BLT_CXX_STD", "c++20"))
        args.append(self.define("CMAKE_CXX_STANDARD", 20))
        args.append(self.define("CMAKE_CUDA_STANDARD", 20))
        args.append(self.define("CMAKE_HIP_STANDARD", 20))
        return args
