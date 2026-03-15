# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *
from spack_repo.builtin.packages.hypre.package import CMakeBuilder as BuiltinCMakeBuilder
from spack_repo.builtin.packages.hypre.package import Hypre as BuiltinHypre

_hypre_commit = "8b0093306228fef1b92384d9face7fbe5a63b460"
_hypre_archive = f"https://github.com/hypre-space/hypre/archive/{_hypre_commit}.tar.gz"


class Hypre(BuiltinHypre):
    # Use a tarball for the pinned develop source so Docker builds do not hang on
    # an in-build git fetch for hypre.
    version("develop", sha256="9b2334e2e08bb93770271eee1f46f74b3c50d8952033cf1f1ebb6de38baec17d")

    def url_for_version(self, version):
        if str(version) == "develop":
            return _hypre_archive
        return super().url_for_version(version)

    def patch(self):
        if str(self.version) != "develop":
            return

        entries = [
            os.path.join(self.stage.source_path, entry)
            for entry in os.listdir(self.stage.source_path)
            if entry != "spack-src"
        ]
        dirs = [entry for entry in entries if os.path.isdir(entry)]
        if len(dirs) != 1:
            return

        src_dir = dirs[0]
        if os.path.exists(os.path.join(self.stage.source_path, "src", "CMakeLists.txt")):
            return

        for entry in os.listdir(src_dir):
            os.rename(os.path.join(src_dir, entry), os.path.join(self.stage.source_path, entry))


class CMakeBuilder(BuiltinCMakeBuilder):
    root_cmakelists_dir = "src"
