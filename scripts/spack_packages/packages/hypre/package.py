# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *
from spack_repo.builtin.packages.hypre.package import Hypre as BuiltinHypre


class Hypre(BuiltinHypre):
    # Keep the complete Git history so HYPRE can report its tagged,
    # distance-aware development version (for example, v3.0.2-2-g<sha>).
    version("develop", branch="master", get_full_repo=True, preferred=True)

    # Keep the source fixes used by the legacy GEOS TPL superbuild in the
    # Spack installation path as well.  The HIP-only patches are deliberately
    # restricted to ROCm builds because they change HYPRE's device setup path.
    patch("patches/hypre-mgr-col-lumped-destroy.patch", when="@3.1.0")
    patch("patches/hypre-mixedint-export.patch", when="@develop")
    patch("patches/hypre-tagged-innerprod.patch", when="@develop")
    patch("patches/hypre-rcm-capacity.patch", when="@develop")
    patch("patches/hypre-umpire-wrapper-lifetime.patch", when="@develop")
    patch("patches/hypre-hip-rocsparse-sort.patch", when="@develop+rocm")
    patch("patches/hypre-hip-standard-ilu.patch", when="@develop+rocm")
