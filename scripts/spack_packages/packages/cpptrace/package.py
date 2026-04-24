# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.cmake import CMakePackage, generator

from spack.package import *


# Modified of the Spack package.py version to add cpptrace's backends
# as variants 
class Cpptrace(CMakePackage):
    """Simple, portable, and self-contained stacktrace library for C++11 and newer."""

    homepage = "https://github.com/jeremy-rifkin/cpptrace"
    url = "https://github.com/jeremy-rifkin/cpptrace/archive/refs/tags/v1.0.0.tar.gz"

    maintainers("RMeli")

    license("MIT", checked_by="RMeli")

    version("1.0.0", sha256="0e11aebb6b9b98ce9134a58532b63982365aadc76533a4fbb7f6fb6edb32de2e")

    variant("shared", default=False, description="Build shared libraries")

    variant("symbols", 
            default="libdwarf",
            values=("libbacktrace", "libdwarf", "addr2line"),
            multi=False,
            description="Symbol resolution backend")

    variant("external_libdwarf",
            default=True,
            description="Use external libdwarf (only relevant with symbols=libdwarf)")

    variant("external_zstd",
            default=True, 
            description="Use external zstd (only relevant with symbols=libdwarf)")

    generator("ninja")

    depends_on("c",   type="build")
    depends_on("cxx", type="build")

    depends_on("libdwarf", when="symbols=libdwarf +external_libdwarf")
    depends_on("zstd",     when="symbols=libdwarf +external_zstd")

    def cmake_args(self):
        args = [
            self.define_from_variant("BUILD_SHARED_LIBS", "shared"),
        ]

        backend = self.spec.variants["symbols"].value
        if backend == "libbacktrace":
            args += [
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBBACKTRACE", True),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBDWARF",     False),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_ADDR2LINE",    False),
            ]
        elif backend == "libdwarf":
            args += [
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBBACKTRACE", False),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBDWARF",     True),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_ADDR2LINE",    False),
                self.define_from_variant("CPPTRACE_USE_EXTERNAL_LIBDWARF", "external_libdwarf"),
                self.define_from_variant("CPPTRACE_USE_EXTERNAL_ZSTD", "external_zstd"),
            ]
        elif backend == "addr2line":
            args += [
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBBACKTRACE", False),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_LIBDWARF",     False),
                self.define("CPPTRACE_GET_SYMBOLS_WITH_ADDR2LINE",    True),
            ]

        return args