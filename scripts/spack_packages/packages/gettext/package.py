from spack.package import *
from spack_repo.builtin.packages.gettext.package import Gettext as BuiltinGettext


class Gettext(BuiltinGettext):
    # Builtin nvhpc-export-symbols.patch targets gettext-tools/intl (0.21 layout).
    # 1.0 moved those files; the hunk fails. nvc is not used for gettext on
    # Perlmutter (packages.yaml require %gcc).
    pass


def _drop_nvhpc_export_symbols_patch(cls):
    patches = getattr(cls, "patches", None)
    if not patches:
        return
    kept = []
    for patch in patches:
        path = getattr(patch, "relative_path", None) or getattr(patch, "path", None) or str(patch)
        if "nvhpc-export-symbols" in str(path):
            continue
        kept.append(patch)
    cls.patches = kept


_drop_nvhpc_export_symbols_patch(Gettext)
