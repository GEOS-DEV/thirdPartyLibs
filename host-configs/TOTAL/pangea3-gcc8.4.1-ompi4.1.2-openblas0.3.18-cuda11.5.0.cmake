#######################################
#
# Pangea3 - gcc - openmpi - openblas - cuda
#
#######################################
#
# Requires modules :
#   - cmake                = 3.27.9
#   - python               = 3.11
#   - cuda                 = 11.5.0
#   - openblas             = 0.3.18
#   - ompi                 = 4.1.2
#   - gcc                  = 8.4.1
#
# Load modules this way :
#   - module purge
#   - module load cmake/3.27.9 python/3.11 cuda/11.5.0 openblas/0.3.18 ompi/4.1.2 gcc/8.4.1
#
########################################

set( CONFIG_NAME "pangea3-gcc8.4.1-ompi4.1.2-openblas0.3.18-cuda11.5.0" CACHE PATH "" )

include(${CMAKE_CURRENT_LIST_DIR}/pangea3-base.cmake)

#######################################
# COMPILER SETUP
#######################################

set( COMMON_FLAGS         "-mcpu=power9 -mtune=power9" )
set( RELEASE_FLAGS        "-O3 -DNDEBUG"               )
set( RELWITHDEBINFO_FLAGS "-g"                         )
set( DEBUG_FLAGS          "-O0 -g"                     )

set( CMAKE_C_FLAGS                      ${COMMON_FLAGS}         CACHE STRING "" )
set( CMAKE_CXX_FLAGS                    ${COMMON_FLAGS}         CACHE STRING "" )
set( CMAKE_Fortran_FLAGS                ${COMMON_FLAGS}         CACHE STRING "" )
set( CMAKE_CXX_FLAGS_RELEASE            ${RELEASE_FLAGS}        CACHE STRING "" )
set( CMAKE_C_FLAGS_RELEASE              ${RELEASE_FLAGS}        CACHE STRING "" )
set( CMAKE_Fortran_FLAGS_RELEASE        ${RELEASE_FLAGS}        CACHE STRING "" )
set( CMAKE_CXX_FLAGS_RELWITHDEBINFO     ${RELWITHDEBINFO_FLAGS} CACHE STRING "" )
set( CMAKE_C_FLAGS_RELWITHDEBINFO       ${RELWITHDEBINFO_FLAGS} CACHE STRING "" )
set( CMAKE_Fortran_FLAGS_RELWITHDEBINFO ${RELWITHDEBINFO_FLAGS} CACHE STRING "" )
set( CMAKE_CXX_FLAGS_DEBUG              ${DEBUG_FLAGS}          CACHE STRING "" )
set( CMAKE_C_FLAGS_DEBUG                ${DEBUG_FLAGS}          CACHE STRING "" )
set( CMAKE_Fortran_FLAGS_DEBUG          ${DEBUG_FLAGS}          CACHE STRING "" )

set( CMAKE_CXX_STANDARD 17 CACHE STRING "" )

#######################################
# MPI SETUP
#######################################

if ( DEFINED ENV{MPI_ROOT} )
  set( ENABLE_MPI                         ON CACHE BOOL "" )
  set( ENABLE_WRAP_ALL_TESTS_WITH_MPIEXEC ON CACHE BOOL "" )

  set( MPI_C_COMPILER       $ENV{MPI_ROOT}/bin/mpicc   CACHE PATH   "" )
  set( MPI_CXX_COMPILER     $ENV{MPI_ROOT}/bin/mpicxx  CACHE PATH   "" )
  set( MPI_Fortran_COMPILER $ENV{MPI_ROOT}/bin/mpifort CACHE PATH   "" )
  set( MPIEXEC              $ENV{MPI_ROOT}/bin/mpirun  CACHE STRING "" )
else()
  message( FATAL_ERROR "MPI is not loaded (MPI_ROOT not found). Please load the openmpi/4.1.2 module." )
endif()

#######################################
# CUDA SETUP
#######################################

# Cuda options
if ( DEFINED ENV{CUDA_ROOT} )
  set( ENABLE_CUDA ON CACHE BOOL "")

  set( CUDA_TOOLKIT_ROOT_DIR    $ENV{CUDA_ROOT}                   CACHE PATH   "" )
  set( CMAKE_CUDA_HOST_COMPILER ${CMAKE_CXX_COMPILER}             CACHE STRING "" )
  set( CMAKE_CUDA_COMPILER      ${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc CACHE STRING "" )

  set( CUDA_ARCH                sm_70 CACHE STRING "" )
  set( CMAKE_CUDA_ARCHITECTURES 70    CACHE STRING "" )
  set( CMAKE_CUDA_STANDARD      17    CACHE STRING "" )

  set( CMAKE_CUDA_FLAGS                "-restrict -arch ${CUDA_ARCH} --expt-relaxed-constexpr --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations -Xcompiler -std=c++17" CACHE STRING "" )
  set( CMAKE_CUDA_FLAGS_RELEASE        "-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3 -Xcompiler -mcpu=powerpc64le -Xcompiler -mtune=powerpc64le"                                                            CACHE STRING "" )
  set( CMAKE_CUDA_FLAGS_RELWITHDEBINFO "-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}"                                                                                                                              CACHE STRING "" )
  set( CMAKE_CUDA_FLAGS_DEBUG          "-g -G -O0 -Xcompiler -O0"                                                                                                                                              CACHE STRING "" )

  # Uncomment this line to make nvcc output register usage for each kernel.
  # set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --resource-usage" CACHE STRING "" FORCE)
else()
  message( FATAL_ERROR "CUDA is not loaded (CUDA_ROOT not found).Please load the cuda/11.5.0 module." )
endif()

if ( ENABLE_CUDA )
  set( ENABLE_HYPRE_DEVICE "CUDA" CACHE STRING "" )
endif ()

#######################################
# GTEST SETUP
#######################################

set( gtest_disable_pthreads   ON  CACHE BOOL "" FORCE )

#######################################
# BLAS/LAPACK SETUP
#######################################

if ( DEFINED ENV{OPENBLAS_ROOT} )
  set( BLAS_LIBRARIES   $ENV{OPENBLAS_ROOT}/lib/libopenblas.a )
  set( LAPACK_LIBRARIES $ENV{OPENBLAS_ROOT}/lib/libopenblas.a )
else()
  message( FATAL_ERROR "OPENBLAS is not loaded (OPENBLAS_ROOT not found).Please load the openblas/0.3.18 module." )
endif()

#######################################
# MISC
#######################################

set( PETSC_OMP_DIR   ${GEOSX_TPL_ROOT_DIR}/omp-links-for-petsc CACHE STRING "" )
set( SCOTCH_NUM_PROC 1                                         CACHE STRING "" )
