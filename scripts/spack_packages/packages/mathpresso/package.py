from spack.package import *
import subprocess
from spack_repo.builtin.build_systems.cmake import CMakePackage

class Mathpresso(CMakePackage):
    """MathPresso is a mathematical expression parser and JIT compiler."""

    homepage = "https://github.com/kobalicek/mathpresso"
    git      = "https://github.com/kobalicek/mathpresso.git"

    version('geos', commit='24d60e5c4d9a887c9ecb11991d07c54b3139ff1e')

    depends_on("cxx", type="build")

    def cmake(self, spec, prefix):
        # Mathpresso requires asmjit source files.
        # Clone the source files and checkout specific commit
        with working_dir(self.stage.source_path):
            git = which('git')
            git('clone', 'https://github.com/asmjit/asmjit.git')
            subprocess.run(['git', 'reset', '--hard', '2e93826348d6cd1325a8b1f7629e193c58332da9'],
                            cwd='./asmjit')

        super().cmake(spec, prefix)

    def cmake_args(self):
        args= [
            '-DMATHPRESSO_STATIC=TRUE',
            '-DCMAKE_CXX_STANDARD=11',
            self.define("ASMJIT_DIR", self.stage.source_path + "/asmjit")
        ]
        return args