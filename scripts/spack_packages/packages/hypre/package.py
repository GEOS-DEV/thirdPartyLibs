# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.hypre.package import CMakeBuilder as BuiltinHypreCMakeBuilder
from spack_repo.builtin.packages.hypre.package import Hypre as BuiltinHypre


class Hypre(BuiltinHypre):
    # Keep the complete Git history so HYPRE can report its tagged,
    # distance-aware development version (for example, v3.0.2-2-g<sha>).
    version("develop", branch="master", get_full_repo=True, preferred=True)


class CMakeBuilder(BuiltinHypreCMakeBuilder):
    def cmake_args(self):
        args = super().cmake_args()
        spec = self.pkg.spec
        if spec.satisfies("+umpire"):
            # The builtin recipe passes only libumpire to TPL_UMPIRE_LIBRARIES. hypre then links
            # that single archive into libHYPRE.so and never sees Umpire's own dependencies, so a
            # shared libHYPRE.so is left with undefined camp::throw_re and fmt::vformat. Consumers
            # cannot resolve them either: libfmt.a is built with hidden visibility, so an executable
            # link fails with "hidden symbol ... is referenced by DSO". Hand hypre the whole Umpire
            # stack (the last -D on the command line wins) so libHYPRE.so is self-contained.
            umpire_libs = spec["umpire"].libs + spec["camp"].libs + spec["fmt"].libs
            args.append(self.define("TPL_UMPIRE_LIBRARIES", umpire_libs))
        return args
