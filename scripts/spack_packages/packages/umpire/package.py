from spack.package import *
from spack_repo.builtin.packages.umpire.package import Umpire as BuiltinUmpire


class Umpire(BuiltinUmpire):
    version(
        "2026.03.31",
        commit="5ff0d696d84f1048faf72085743630fcf33c0928",
        submodules=False,
    )

    depends_on("fmt@12.1.0", when="@2026.03.31")

    def cmake_args(self):
        args = super().cmake_args()
        args.append(self.define("CMAKE_CXX_STANDARD", 20))
        return args
