# Copyright 2013-2019 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack import *


class Axom(CMakePackage):
    """FIXME: Put a proper description of your package here."""

    # FIXME: Add a proper url for your package's homepage here.
    homepage = "http://lc.llnl.gov/axom"
    url      = "https://github.com/LLNL/axom/releases/download/v0.3.2/Axom-v0.3.2.tar.gz"

    version('0.3.2', sha256='0acbbf0de7154cbd3a204f91ce40f4b756b17cd5a92e75664afac996364503bd')
    version('0.3.1', sha256='fad9964c32d7f843aa6dd144c32a8de0a135febd82a79827b3f24d7665749ac5')

    # FIXME: Add dependencies if required.
    # depends_on('foo')
    depends_on('conduit~test')

    root_cmakelists_dir = "src"

    def cmake_args (self):
    	spec = self.spec
    	options=[]

    	options.append("-DCONDUIT_DIR=%s" % spec["conduit"].prefix)


    	return options
    """
    def install(self, spec, prefix):
        # FIXME: Unknown build system
        make()
        make('install')
    """
