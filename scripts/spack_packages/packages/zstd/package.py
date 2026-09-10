from spack.package import *
from spack_repo.builtin.packages.zstd.package import MakefileBuilder as BuiltinZstdMakefileBuilder
from spack_repo.builtin.packages.zstd.package import Zstd as BuiltinZstd


class Zstd(BuiltinZstd):
    pass


class MakefileBuilder(BuiltinZstdMakefileBuilder):
    def install(self, pkg, spec, prefix):
        args = ["VERBOSE=1", "PREFIX=" + prefix]

        # Builtin uses DEPFLAGS=-MT $@ -MMD -MF for %nvhpc (no -MP). nvc 26.x
        # still requires -MF <file>; the makefile then passes -o, which nvc
        # treats as a missing -MF argument.
        if spec.satisfies("%nvhpc"):
            args.append("DEPFLAGS=")

        lib_args = ["-C", "lib"] + args + ["install-pc", "install-includes"]
        if "libs=shared" in spec:
            lib_args.append("install-shared")
        if "libs=static" in spec:
            lib_args.append("install-static")
        make(*lib_args)

        if "+programs" in spec:
            programs_args = ["-C", "programs"] + args
            if "compression=zlib" not in spec:
                programs_args.append("HAVE_ZLIB=0")
            if "compression=lzma" not in spec:
                programs_args.append("HAVE_LZMA=0")
            if "compression=lz4" not in spec:
                programs_args.append("HAVE_LZ4=0")
            programs_args.append("install")
            make(*programs_args)
