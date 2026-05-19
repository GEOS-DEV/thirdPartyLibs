from spack.package import *
from spack_repo.builtin.packages.raja.package import Raja as BuiltinRaja


class Raja(BuiltinRaja):
    version(
        "2026.04.14",
        commit="11dbea102ed609f1319d8990e28e47bc4f4d7f2b",
        submodules=False,
    )

    requires("cxxstd=20", when="@2026.04.14")
