from spack.package import *
from spack_repo.builtin.packages.gsl.package import Gsl as BuiltinGsl


class Gsl(BuiltinGsl):
    def setup_build_environment(self, env):
        # Avoid a cce@20.0.0 optimizer crash in gsl matrix/minmax.c at -O2.
        if self.spec.satisfies("@2.8 %cce@20.0.0"):
            env.append_flags("CFLAGS", "-O1")