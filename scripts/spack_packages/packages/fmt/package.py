from spack.package import *
from spack_repo.builtin.packages.fmt.package import Fmt as BuiltinFmt


class Fmt(BuiltinFmt):
    # nvcc + clang host compiler cannot parse Clang's _BitInt extension.
    # https://github.com/fmtlib/fmt/pull/4564 (merged after fmt 11.2.0)
    patch("nvcc-clang-bitint.patch", when="@11.1:11.2.0")
