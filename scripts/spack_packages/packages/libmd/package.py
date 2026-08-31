from spack.package import *
from spack_repo.builtin.packages.libmd.package import Libmd as BuiltinLibmd


class Libmd(BuiltinLibmd):
    # Builtin nvhpc-aliases.patch matches libmd_alias(); 1.1.0 renamed that
    # to libmd_strong_alias(), so the hunk fails. nvc 26 supports aliases.
    patches = []
