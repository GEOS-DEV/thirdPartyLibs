from spack.package import *
from spack_repo.builtin.packages.camp.package import Camp as BuiltinCamp


class Camp(BuiltinCamp):
    version(
        "2026.05.18",
        commit="47a3682c3d5ff43b542ad7e29569eb5e157f918e",
        submodules=False,
    )
