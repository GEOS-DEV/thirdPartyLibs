from spack.package import *
from spack_repo.builtin.packages.superlu_dist.package import SuperluDist as BuiltinSuperluDist


class SuperluDist(BuiltinSuperluDist):
    # SuperLU_DIST's CMake wants absolute library paths in TPL_*_LIBRARIES.
    # The builtin recipe passes ld_flags (-L/-l). When cray-libsci.libs is
    # empty that becomes a blank, FindBLAS on Cray fills in "-l", and ld
    # fails with "cannot find -l-l".
    def cmake_args(self):
        args = [
            a
            for a in super().cmake_args()
            if "TPL_BLAS_LIBRARIES" not in a and "TPL_LAPACK_LIBRARIES" not in a
        ]

        def abs_libs(virtual):
            libs = self.spec[virtual].libs
            if not libs:
                raise InstallError(
                    "{0} libraries were empty for {1}; "
                    "expected cray-libsci (not nvhpc) as the {0} provider".format(
                        virtual, self.spec[virtual]
                    )
                )
            return libs.joined(";")

        args.append(self.define("TPL_BLAS_LIBRARIES", abs_libs("blas")))
        args.append(self.define("TPL_LAPACK_LIBRARIES", abs_libs("lapack")))
        return args
