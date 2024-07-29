#######################################
#
# Pangea3 - base config for GPU cluster
#
#   - RAJA   GPU
#   - CHAI   GPU
#   - CUDA   ON
#   - OPENMP ON
#
#######################################

#######################################
# SCIENTIFIC LIBRARIES
#######################################

# build minimum TPLs scientific libs since ppc64 is not supported by all TPLs

set( ENABLE_HYPRE       ON  CACHE BOOL "" FORCE )
set( ENABLE_MATHPRESSO  OFF CACHE BOOL "" FORCE )
set( ENABLE_PAMELA      ON  CACHE BOOL "" FORCE )
set( ENABLE_PETSC       OFF CACHE BOOL "" FORCE )
set( ENABLE_PVTPackage  ON  CACHE BOOL "" FORCE )
set( ENABLE_SCOTCH      ON  CACHE BOOL "" FORCE )
set( ENABLE_SUITESPARSE ON  CACHE BOOL "" FORCE )
set( ENABLE_TRILINOS    OFF CACHE BOOL "" FORCE )
set( ENABLE_VTK         ON  CACHE BOOL "" FORCE )

# silo configure script doesn't recognize systype
set(SILO_BUILD_TYPE powerpc64-unknown-linux-gnu CACHE STRING "")

#######################################
# DEVELOPMENT TOOLS
#######################################

set( ENABLE_DOXYGEN           OFF CACHE BOOL "" FORCE )
set( ENABLE_GTEST_DEATH_TESTS OFF CACHE BOOL "" FORCE )
set( ENABLE_SPHINX            ON  CACHE BOOL "" FORCE )
set( ENABLE_UNCRUSTIFY        OFF CACHE BOOL "" FORCE )
set( ENABLE_XML_UPDATES       ON  CACHE BOOL "" FORCE )

#######################################
# PERFORMANCE TOOLS
#######################################

set( ENABLE_BENCHMARKS         ON CACHE BOOL "" FORCE )
set( ENABLE_CALIPER            ON CACHE BOOL "" FORCE )
# enable recording CUDA API calls in Caliper
set( ENABLE_CALIPER_WITH_CUPTI ON CACHE BOOL "" FORCE )


#######################################
# CUDA/OMP SETUP
#######################################

set( ENABLE_OPENMP ON CACHE BOOL "" FORCE )
set( ENABLE_CUDA   ON CACHE BOOL "" FORCE )

#######################################
# PYTHON SETUP
#######################################

set( ENABLE_VTK_WRAP_PYTHON ON CACHE BOOL "" )
