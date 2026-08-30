from glob import glob
import os
import re

from spack.package import *
from spack_repo.builtin.packages.cray_libsci.package import CrayLibsci as BuiltinCrayLibsci


class CrayLibsci(BuiltinCrayLibsci):
    # Builtin recipe only lists versions through 23.02 and looks for unversioned
    # names (libsci_gnu.so). CPE 26.03 on Perlmutter ships compiler-ABI names
    # (libsci_gnu_123.so, libsci_nvidia_*.so) and no unversioned symlink, so
    # spec["blas"].libs is empty and CMake consumers pass -l-l / a space.
    version("26.03.0")

    @property
    def blas_libs(self):
        try:
            libs = super().blas_libs
        except RuntimeError:
            libs = None
        if libs:
            return libs

        candidates = [name for name in self.canonical_names.values() if name in self.prefix]
        if len(candidates) != 1:
            return libs if libs is not None else find_libraries(
                ["libsci_missing"], root=str(self.prefix), shared=True, recursive=False
            )
        tag = candidates[0].lower()

        if self.spec.satisfies("+openmp") and self.spec.satisfies("+mpi"):
            suffixes = ["_mpi_mp", "_mp"]
        elif self.spec.satisfies("+openmp"):
            suffixes = ["_mp"]
        elif self.spec.satisfies("+mpi"):
            suffixes = ["_mpi", ""]
        else:
            suffixes = [""]

        shared = "+shared" in self.spec
        lib_dirs = [p for p in (self.prefix.lib, self.prefix.lib64) if os.path.isdir(p)]
        ext = "so" if shared else "a"

        def ver_key(path):
            base = os.path.basename(path)
            match = re.search(r"_(\d+)\.(?:so|a)", base)
            compiler_abi = int(match.group(1)) if match else 0
            # Prefer the unversioned .so/.a symlink over libfoo.so.6.
            is_devlink = 1 if re.search(r"\.(so|a)$", base) else 0
            return (compiler_abi, is_devlink)

        for suffix in suffixes:
            rx = re.compile(
                r"^libsci_{tag}(_\d+)?{suffix}\.(so|a)(\.\d+)*$".format(
                    tag=re.escape(tag), suffix=re.escape(suffix)
                )
            )
            matches = []
            for lib_dir in lib_dirs:
                for path in glob(os.path.join(lib_dir, f"libsci_{tag}*{suffix}.{ext}*")):
                    if rx.match(os.path.basename(path)):
                        matches.append(path)
            if matches:
                best = sorted(set(matches), key=ver_key)[-1]
                libname = os.path.basename(best).split(".")[0]
                return find_libraries(
                    [libname], root=os.path.dirname(best), shared=shared, recursive=False
                )

        return libs if libs is not None else find_libraries(
            ["libsci_missing"], root=str(self.prefix), shared=True, recursive=False
        )
