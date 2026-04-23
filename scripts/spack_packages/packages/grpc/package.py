# Copyright 2013-2024 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)
from spack.package import *


class Grpc(CMakePackage):
    """A high performance, open-source universal RPC framework."""

    homepage = "https://grpc.io"
    url = "https://github.com/grpc/grpc/archive/v1.59.1.tar.gz"

    license("Apache-2.0 AND BSD-3-Clause AND MIT")

    # Provide a full clone of the grpc repo with all submodules to avoid
    # download issues when building behind a proxy.
    # Steps to create the tar-ball for a different version (replace 1.64.0 with
    # desired version):
    # $ git clone -b v1.64.0 --recurse-submodules https://github.com/grpc/grpc.git
    # $ mv grpc grpc-1.64.0-full-clone
    # $ tar cfvz grpc-1.64.0-full-clone.tar.gz grpc-1.64.0-full-clone
    # $ sha256sum grpc-1.64.0-full-clone.tar.gz
    # Then place the tar-ball in the mirror directory under grpc subdirectory:
    # $ export SPACK_MIRROR=/workrd/SCR/NUM/GEOS_environment/spack/mirror
    # $ cp grpc-1.64.0-full-clone.tar.gz $SPACK_MIRROR/grpc/
    # And also into the $SPACK_MIRROR/_source-cache/archive directory using the first two
    # charachers of the SHA for naming the subfolder and full SHA for naming the file:
    # $ mkdir $SPACK_MIRROR/_source-cache/archive/a0/
    # $ cp grpc-1.64.0-full-clone.tar.gz $SPACK_MIRROR/_source-cache/archive/a0/a03fa383b885b325277580f9db50bad8608503a68720ebc2eb09474c23c46a36.tar.gz 
    # Finally pass the --mirror $SPACK_MIRROR option to uberenv.py command.
    version("1.64.0-full-clone", sha256="a03fa383b885b325277580f9db50bad8608503a68720ebc2eb09474c23c46a36")
    version("1.65.5-full-clone", sha256="1d0b1432f1984177e9eb52226b77db953c81b60e3f4419d2141cac28fe07a906")

    depends_on("c", type="build")
    depends_on("cxx", type="build")

    variant("shared", default=False, description="Build shared instead of static libraries")
    variant(
        "codegen",
        default=True,
        description="Builds code generation plugins for protobuf " "compiler (protoc)",
    )
    variant(
        "cxxstd",
        default="11",
        values=("11", "14", "17"),
        multi=False,
        description="Use the specified C++ standard when building.",
    )

    depends_on("protobuf")
    depends_on("protobuf@3.22:", when="@1.55:")
    depends_on("openssl")
    depends_on("zlib-api")
    depends_on("c-ares")

    with when("@1.27:"):
        depends_on("abseil-cpp")
        # missing includes: https://github.com/grpc/grpc/commit/bc044174401a0842b36b8682936fc93b5041cf88
        depends_on("abseil-cpp@:20230802", when="@:1.61")

    depends_on("re2+pic@2023-09-01", when="@1.33.1:")

    def cmake_args(self):
        args = [
            self.define_from_variant("BUILD_SHARED_LIBS", "shared"),
            self.define_from_variant("gRPC_BUILD_CODEGEN", "codegen"),
            self.define_from_variant("CMAKE_CXX_STANDARD", "cxxstd"),
            "-DgRPC_BUILD_CSHARP_EXT:Bool=OFF",
            "-DgRPC_INSTALL:Bool=ON",
            # Tell grpc to skip vendoring and look for deps via find_package:
            "-DgRPC_CARES_PROVIDER:String=package",
            "-DgRPC_ZLIB_PROVIDER:String=package",
            "-DgRPC_SSL_PROVIDER:String=package",
            "-DgRPC_PROTOBUF_PROVIDER:String=package",
            "-DgRPC_USE_PROTO_LITE:Bool=OFF",
            "-DgRPC_PROTOBUF_PACKAGE_TYPE:String=CONFIG",
            # Disable tests:
            "-DgRPC_BUILD_TESTS:BOOL=OFF",
            "-DgRPC_GFLAGS_PROVIDER:String=none",
            "-DgRPC_BENCHMARK_PROVIDER:String=none",
        ]
        if self.spec.satisfies("@1.27.0:"):
            args.append("-DgRPC_ABSL_PROVIDER:String=package")
        if self.spec.satisfies("@1.33.1:"):
            args.append("-DgRPC_RE2_PROVIDER:String=package")
        return args
