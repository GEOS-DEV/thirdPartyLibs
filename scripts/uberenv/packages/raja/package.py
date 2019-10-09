# Copyright 2013-2019 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)
#
# Copied from PR #12959 (WIP)  

from spack import *


class Raja(CMakePackage):
    """RAJA Parallel Framework."""

    homepage = "http://software.llnl.gov/RAJA/"
    git      = "https://github.com/LLNL/RAJA.git"

    version('develop', branch='develop', submodules='True')
    version('master',  branch='master',  submodules='True')
    version('0.8.0', tag='v0.8.0', submodules="True")
    version('0.7.0', tag='v0.7.0', submodules="True")
    version('0.6.0', tag='v0.6.0', submodules="True")
    version('0.5.3', tag='v0.5.3', submodules="True")
    version('0.5.2', tag='v0.5.2', submodules="True")
    version('0.5.1', tag='v0.5.1', submodules="True")
    version('0.5.0', tag='v0.5.0', submodules="True")
    version('0.4.1', tag='v0.4.1', submodules="True")
    version('0.4.0', tag='v0.4.0', submodules="True")

    variant('cuda', default=False, description='Build with CUDA backend')
    variant('openmp', default=True, description='Build OpenMP backend')
    variant('targetopenmp', default=False, description='Build target OpenmP backend')
    variant('tbb', default=False, description='Build TBB backend')
    variant('chai', default=False, description='Build with CHAI support')

    depends_on('cuda', when='+cuda')
    depends_on('chai', when='+chai')
    depends_on('chai+cuda', when='+chai+cuda')

    depends_on('cmake@3.8:', type='build')
    depends_on('cmake@3.9:', when='+cuda', type='build')

    def cmake_args(self):
        spec = self.spec

        options = []
        options.append('-DENABLE_OPENMP={0}'.format(
            'On' if '+openmp' in spec else 'Off'))

        if '+cuda' in spec:
            options.extend([
                '-DENABLE_CUDA=On',
                '-DCUDA_TOOLKIT_ROOT_DIR=%s' % (spec['cuda'].prefix)])

        if '+targetopenmp' in spec:
            options.append([
                '-DENABLE_TARGET_OPENMP=On'])

        if '+tbb' in spec:
            options.append([
                '-DENABLE_TBB=On'])

        if '+chai' in spec:
            options.append([
                '-DENABLE_CHAI=On'])

        return options