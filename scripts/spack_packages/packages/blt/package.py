from spack.package import *
from spack_repo.builtin.packages.blt.package import Blt as BuiltinBlt


class Blt(BuiltinBlt):
    version(
        "0.7.2",
        sha256="107f2c1d616bcfc629a11d887f0bb1b602aef1fe5e4580db65e592f23925e23f",
    )
