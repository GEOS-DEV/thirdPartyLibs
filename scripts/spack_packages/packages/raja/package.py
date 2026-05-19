from spack.package import *
from spack_repo.builtin.packages.raja.package import Raja as BuiltinRaja


class Raja(BuiltinRaja):
    version(
        "2026.05.19",
        commit="d9a03fd56f7fb81540aeacbf082eb35dbb840b9c",
        submodules=False,
    )

    requires("cxxstd=20", when="@2026.05.19")
