# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.caliper.package import Caliper as BuiltinCaliper


class Caliper(BuiltinCaliper):
    # Keep Caliper's UBSan-safe type metadata and startup initialization in
    # sync with the legacy GEOS TPL build.
    patch("patches/caliper-ubsan.patch", when="@2.14.0")
