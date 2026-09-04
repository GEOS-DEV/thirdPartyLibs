from spack.package import *
from spack_repo.builtin.packages.gettext.package import Gettext as BuiltinGettext


class Gettext(BuiltinGettext):
    # Builtin nvhpc-export-symbols.patch targets gettext-tools/intl (0.21 layout).
    # 1.0 moved those files; the hunk fails. nvc is not used for gettext on
    # Perlmutter (packages.yaml require %gcc).
    pass


def _drop_nvhpc_export_symbols_patch(cls):
    # Spack stores patches as {when_spec: [patch, ...]}. Replacing that dict
    # with a list makes concretize raise "'list' object has no attribute 'items'".
    patches = getattr(cls, "patches", None)
    if not isinstance(patches, dict):
        return
    kept = {}
    for when, plist in patches.items():
        filtered = []
        for patch in plist:
            path = (
                getattr(patch, "relative_path", None)
                or getattr(patch, "path", None)
                or str(patch)
            )
            if "nvhpc-export-symbols" in str(path):
                continue
            filtered.append(patch)
        if filtered:
            kept[when] = filtered
    cls.patches = kept


_drop_nvhpc_export_symbols_patch(Gettext)
