# Copyright 2013-2019 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *

class Mathpresso(CMakePackage):
    """MathPresso is a C++ library designed to parse mathematical
    expressions and compile them into machine code."""

    homepage = "https://github.com/kobalicek/mathpresso"
    url="mathpresso-2015-12-15.tar.gz"

    version('2015-12-15',sha256='e238366926839eb20f962942ccc02a275273ab5af15ae031be886063f53d5f2d')

    resource(
       name='asmjit',
       url='asmjit-2016-07-20.tar.gz',
       sha256='b9432f9c26d498a18b1261d7db85b9ad5f9422a76b4533338fdd2f35cee967bb',
    )

    def cmake_args (self):
        args=[]
        args.append ("-DASMJIT_DIR=%s" % (join_path(self.stage.source_path, 'asmjit-master')))
        return args