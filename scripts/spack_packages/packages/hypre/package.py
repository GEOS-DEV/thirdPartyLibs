from spack.package import *
from spack_repo.builtin.packages.hypre.package import (
    AutotoolsBuilder as BuiltinAutotoolsBuilder,
    CMakeBuilder as BuiltinCMakeBuilder,
    Hypre as BuiltinHypre,
)


class Hypre(BuiltinHypre):
    """GEOS override for hypre package options."""

    pass


def _gpu_umpire_device_only(spec):
    return spec.satisfies("+umpire~unified-memory") and (
        spec.satisfies("+cuda") or spec.satisfies("+rocm") or spec.satisfies("+sycl")
    )


class CMakeBuilder(BuiltinCMakeBuilder):
    def cmake_args(self):
        args = super().cmake_args()

        if _gpu_umpire_device_only(self.pkg.spec):
            args = [
                arg for arg in args
                if not arg.startswith("-DHYPRE_ENABLE_UMPIRE:")
                and not arg.startswith("-DHYPRE_ENABLE_UMPIRE=")
            ]
            args.extend([
                self.define("HYPRE_ENABLE_UMPIRE", False),
                self.define("HYPRE_ENABLE_UMPIRE_DEVICE", True),
                self.define("HYPRE_ENABLE_UMPIRE_UM", False),
            ])

        return args


class AutotoolsBuilder(BuiltinAutotoolsBuilder):
    def configure_args(self):
        args = super().configure_args()

        if _gpu_umpire_device_only(self.pkg.spec):
            args = [arg for arg in args if arg not in ("--with-umpire", "--with-umpire-um")]
            if "--without-umpire" not in args:
                args.append("--without-umpire")
            if "--with-umpire-device" not in args:
                args.append("--with-umpire-device")

        return args
