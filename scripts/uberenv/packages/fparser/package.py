# Copyright 2013-2019 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *

class Fparser(Package):
    """fparser offers a class which can be used to parse and evaluate a
    mathematical function from a string"""

    homepage = "warp.povusers.org/FunctionParser/"
    url      = "http://warp.povusers.org/FunctionParser/fparser4.5.2.zip"

    version('4.5.2', sha256='57ef7f03ea49e3f278a715c094933a0f3da4af9118a5f18de809062292be9833')
    
    def install(self, spec, prefix):

        ccompile = Executable(self.compiler.cc)
        ccompile ("-c", "-DFP_NO_SUPPORT_OPTIMIZER",
            join_path(self.stage.source_path,'fparser.cc'), 
            join_path(self.stage.source_path,'fpoptimizer.cc'))

        # Create library
        ar = which ('ar')
        ar ("rcs", "libfparser.a", "fparser.o", "fpoptimizer.o")

        mkdirp (prefix.lib)
        copy ('libfparser.a', prefix.lib)


        mkdirp (prefix.include)
        copy ('fparser.hh', prefix.include)
        copy ('fparser_gmpint.hh', prefix.include)
        copy ('fparser_mpfr.hh', prefix.include)
        copy ('fpconfig.hh', prefix.include)
