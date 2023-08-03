
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @@@ LvArray file contents @@@

#######################################################
# lassen-gcc-8-cuda-11.cmake 

#set(CONFIG_NAME "lassen-gcc-8-cuda-11" CACHE PATH "") 
set(CONFIG_NAME "lassen-eas-gcc-11-cuda-11" CACHE PATH "") 

#set(COMPILER_DIR  /usr/tce/packages/gcc/gcc-8.3.1)
set(COMPILER_DIR  /usr/tce/packages/gcc/gcc-11.2.1)
set(CMAKE_C_COMPILER ${COMPILER_DIR}/bin/gcc CACHE PATH "")
set(CMAKE_CXX_COMPILER ${COMPILER_DIR}/bin/g++ CACHE PATH "")

# C++ options
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -mcpu=power9 -mtune=power9" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-g ${CMAKE_CXX_FLAGS_RELEASE}" CACHE STRING "")
set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g" CACHE STRING "")

#######################################################


#######################################################
# llnl-tpl-base.cmake contents

# Set up the tpls
#set(GEOSX_TPL_ROOT_DIR /usr/gapps/GEOSX/thirdPartyLibs CACHE PATH "")
#set(GEOSX_TPL_DIR ${GEOSX_TPL_ROOT_DIR}/2023-07-07/install-${CONFIG_NAME}-release CACHE PATH "")
set(GEOSX_TPL_DIR /usr/workspace/han12/thirdPartyLibs/install-lassen-eas-gcc-11-cuda-11-release CACHE PATH "")
##########################################################


##########################################################
# lassen-base.cmake contents

set(CAMP_DIR ${GEOSX_TPL_DIR}/raja CACHE PATH "")
set(RAJA_DIR ${GEOSX_TPL_DIR}/raja CACHE PATH "")

set(ENABLE_UMPIRE ON CACHE BOOL "")
set(UMPIRE_DIR ${GEOSX_TPL_DIR}/chai CACHE PATH "")

set(ENABLE_CHAI ON CACHE BOOL "")
set(CHAI_DIR ${GEOSX_TPL_DIR}/chai CACHE PATH "")

set(ENABLE_CALIPER ON CACHE BOOL "")
set(ENABLE_ADIAK ON CACHE BOOL "" )
set(CALIPER_DIR ${GEOSX_TPL_DIR}/caliper CACHE PATH "")

set(ENABLE_ADDR2LINE ON CACHE BOOL "")

# Uncomment this line to make nvcc output register usage for each kernel.
# set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --resource-usage" CACHE STRING "" FORCE)

# GTEST options
set(ENABLE_GTEST_DEATH_TESTS OFF CACHE BOOL "")
set(gtest_disable_pthreads ON CACHE BOOL "")

# Documentation
set(ENABLE_UNCRUSTIFY OFF CACHE BOOL "" FORCE)
set(ENABLE_DOXYGEN OFF CACHE BOOL "" FORCE)

####################################################################


####################################################################
# lassen-cuda-11-base.cmake contents

# Cuda options
set(ENABLE_CUDA ON CACHE BOOL "")
set(CUDA_TOOLKIT_ROOT_DIR /usr/tce/packages/cuda/cuda-11.8.0 CACHE STRING "")
set(CMAKE_CUDA_HOST_COMPILER ${CMAKE_CXX_COMPILER} CACHE STRING "")
set(CMAKE_CUDA_COMPILER ${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc CACHE STRING "")
set(CUDA_ARCH sm_70 CACHE STRING "")
set(CMAKE_CUDA_ARCHITECTURES 70 CACHE STRING "")
set(CMAKE_CUDA_STANDARD 17 CACHE STRING "")
set(CMAKE_CUDA_FLAGS "-restrict -arch ${CUDA_ARCH} --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_RELEASE "-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3 -Xcompiler -mcpu=powerpc64le -Xcompiler -mtune=powerpc64le" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_RELWITHDEBINFO "-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_DEBUG "-g -G -O0 -Xcompiler -O0" CACHE STRING "")

set(CHAI_CUDA_FLAGS "-arch ${CUDA_ARCH}" CACHE STRING "" FORCE)
####################################################################

# @@@ LvArray file contents END @@@ 
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @@@ GEOS file contents @@@

####################################################################
# lassen-gcc-8-cuda-11.cmake

# C++
# The "-march=native -mtune=native" which LvArray adds breaks the PVT package.
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_CUDA_FLAGS_RELEASE "-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3" CACHE STRING "" FORCE)

# Fortran
#set(CMAKE_Fortran_COMPILER /usr/tce/packages/gcc/gcc-8.3.1/bin/gfortran CACHE PATH "")
set(CMAKE_Fortran_COMPILER /usr/tce/packages/gcc/gcc-11.2.1/bin/gfortran CACHE PATH "")
set(CMAKE_Fortran_FLAGS_RELEASE "-O3 -DNDEBUG -mcpu=power9 -mtune=power9" CACHE STRING "")
set(FORTRAN_MANGLE_NO_UNDERSCORE OFF CACHE BOOL "")

# MPI
#set(MPI_HOME /usr/tce/packages/spectrum-mpi/spectrum-mpi-rolling-release-gcc-8.3.1 CACHE PATH "")
set(MPI_HOME /usr/tce/packages/spectrum-mpi/spectrum-mpi-rolling-release-gcc-11.2.1 CACHE PATH "")
set(MPI_Fortran_COMPILER ${MPI_HOME}/bin/mpifort CACHE PATH "")

#include(${CMAKE_CURRENT_LIST_DIR}/lassen-base.cmake)

####################################################################
# lassen-base.cmake contents

###############################################################################

#
# Base configuration for LC Lassen builds
# Calling configuration file must define the following CMAKE variables:
#
# MPI_HOME
#
###############################################################################

set( GEOSX_BUILD_SHARED_LIBS ON CACHE BOOL "" )
set( GEOSX_BUILD_OBJ_LIBS OFF CACHE BOOL "" )
# Fortran
set(ENABLE_FORTRAN OFF CACHE BOOL "")

# MPI
set(ENABLE_MPI ON CACHE BOOL "")
set(MPI_C_COMPILER ${MPI_HOME}/bin/mpicc CACHE PATH "")
set(MPI_CXX_COMPILER ${MPI_HOME}/bin/mpicxx CACHE PATH "")
set(MPIEXEC lrun CACHE STRING "")
set(MPIEXEC_NUMPROC_FLAG -n CACHE STRING "")
set(ENABLE_WRAP_ALL_TESTS_WITH_MPIEXEC ON CACHE BOOL "")

# OpenMP
set(ENABLE_OPENMP ON CACHE BOOL "" FORCE)

# CUDA
# LvArray sets this to the CMAKE_CXX_COMPILER.
set(CMAKE_CUDA_HOST_COMPILER ${MPI_CXX_COMPILER} CACHE STRING "")

set(ENABLE_CUDA_NVTOOLSEXT OFF CACHE BOOL "")

# ESSL
set(ENABLE_ESSL ON CACHE BOOL "" FORCE )
set(ESSL_INCLUDE_DIRS /usr/tcetmp/packages/essl/essl-6.3.0.2/include CACHE STRING "" FORCE )
#set(ESSL_LIBRARIES /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/libesslsmpcuda.so
#                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcublas.so
#                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcublasLt.so
#                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcudart.so
#                   /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/liblapackforessl.so
#                   /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/liblapackforessl_.so
#                   CACHE PATH "" FORCE )
set(ESSL_LIBRARIES /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/libesslsmpcuda.so
	           /usr/tce/packages/xl/xl-2023.06.28-cuda-11.8.0/alllibs/libxlsmp.so
	           /usr/tce/packages/xl/xl-2023.06.28-cuda-11.8.0/alllibs/libxlfmath.so
	           /usr/tce/packages/xl/xl-2023.06.28-cuda-11.8.0/alllibs/libxlf90_r.so
                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcublas.so
                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcublasLt.so
                   ${CUDA_TOOLKIT_ROOT_DIR}/lib64/libcudart.so
                   /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/liblapackforessl.so
                   /usr/tcetmp/packages/essl/essl-6.3.0.2/lib64/liblapackforessl_.so
                   CACHE PATH "" FORCE )
                   
# TPL
set(ENABLE_PAPI OFF CACHE BOOL "")
set(SILO_BUILD_TYPE powerpc64-unknown-linux-gnu CACHE STRING "")
set(ENABLE_FESAPI OFF CACHE BOOL "" FORCE)

# GEOSX specific options
set(ENABLE_PVTPackage ON CACHE BOOL "")
set(ENABLE_PETSC OFF CACHE BOOL "" FORCE )

set( ENABLE_HYPRE_DEVICE "CUDA" CACHE STRING "" FORCE )
if( ${ENABLE_HYPRE_DEVICE} STREQUAL "HIP" OR ${ENABLE_HYPRE_DEVICE} STREQUAL "CUDA" )
    set(ENABLE_TRILINOS OFF CACHE BOOL "" FORCE )
else()
    set(ENABLE_HYPRE OFF CACHE BOOL "" FORCE )
    set(GEOSX_LA_INTERFACE "Trilinos" CACHE STRING "" FORCE )
endif()

# Documentation
set(ENABLE_UNCRUSTIFY OFF CACHE BOOL "" FORCE)
set(ENABLE_DOXYGEN OFF CACHE BOOL "" FORCE)

# Other
set(ENABLE_MATHPRESSO OFF CACHE BOOL "")

# YAPF python formatting
set(YAPF_EXECUTABLE /usr/gapps/GEOSX/thirdPartyLibs/python/lassen-gcc-python/python/bin/yapf CACHE PATH "" FORCE)

# PYGEOSX
set(ENABLE_PYGEOSX ON CACHE BOOL "")
set(PYTHON_EXECUTABLE /usr/gapps/GEOSX/thirdPartyLibs/python/lassen-gcc-python/python/bin/python CACHE PATH "")
set(Python3_ROOT_DIR /usr/gapps/GEOSX/thirdPartyLibs/python/lassen-gcc-python/python CACHE PATH "")
set(Python3_EXECUTABLE /usr/gapps/GEOSX/thirdPartyLibs/python/lassen-gcc-python/python/bin/python3 CACHE PATH "")

# ATS
set(ATS_ARGUMENTS "--ats jsrun_omp --ats jsrun_bind=packed"  CACHE STRING "")
####################################################################

####################################################################
#include(${CMAKE_CURRENT_LIST_DIR}/../tpls.cmake)
# tpls.cmake contents

####################################################################

#
# Performance portability
#
message("in tpls.cmake GEOSX_TPL_DIR=${GEOSX_TPL_DIR}")

if(EXISTS ${GEOSX_TPL_DIR}/raja)
  set(RAJA_DIR ${GEOSX_TPL_DIR}/raja CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/chai)
  set(UMPIRE_DIR ${GEOSX_TPL_DIR}/chai CACHE PATH "" FORCE)
  set(CHAI_DIR ${GEOSX_TPL_DIR}/chai CACHE PATH "" FORCE)
endif()

#
# IO TPLs
#
if(EXISTS ${GEOSX_TPL_DIR}/hdf5)
  set(HDF5_DIR ${GEOSX_TPL_DIR}/hdf5 CACHE PATH "" FORCE)
  message(STATUS "HDF5_DIR = ${HDF5_DIR}")
endif()

if(EXISTS ${GEOSX_TPL_DIR}/conduit)
  set(CONDUIT_DIR ${GEOSX_TPL_DIR}/conduit CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/silo)
  set(SILO_DIR ${GEOSX_TPL_DIR}/silo CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/adiak)
  set(ADIAK_DIR ${GEOSX_TPL_DIR}/adiak CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/caliper)
  set(CALIPER_DIR ${GEOSX_TPL_DIR}/caliper CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/pugixml)
  set(PUGIXML_DIR ${GEOSX_TPL_DIR}/pugixml CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/vtk)
  set(VTK_DIR ${GEOSX_TPL_DIR}/vtk CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/fmt)
  set(FMT_DIR ${GEOSX_TPL_DIR}/fmt CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/fesapi)
  set(FESAPI_DIR ${GEOSX_TPL_DIR}/fesapi CACHE PATH "" FORCE)
endif()

#
# Math TPLs
#
if(EXISTS ${GEOSX_TPL_DIR}/metis)
  set(METIS_DIR ${GEOSX_TPL_DIR}/metis CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/parmetis)
  set(PARMETIS_DIR ${GEOSX_TPL_DIR}/parmetis CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/superlu_dist)
  set(SUPERLU_DIST_DIR ${GEOSX_TPL_DIR}/superlu_dist CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/suitesparse)
  set(SUITESPARSE_DIR ${GEOSX_TPL_DIR}/suitesparse CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/trilinos)
  set(TRILINOS_DIR ${GEOSX_TPL_DIR}/trilinos CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/hypre)
  set(HYPRE_DIR ${GEOSX_TPL_DIR}/hypre CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/scotch)
  set(SCOTCH_DIR ${GEOSX_TPL_DIR}/scotch CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/petsc AND (NOT DEFINED ENABLE_PETSC OR ENABLE_PETSC))
  set(PETSC_DIR ${GEOSX_TPL_DIR}/petsc CACHE PATH "" FORCE)
endif()

#
# Development tools
#
if(EXISTS ${GEOSX_TPL_DIR}/uncrustify/bin/uncrustify)
  set(UNCRUSTIFY_EXECUTABLE ${GEOSX_TPL_DIR}/uncrustify/bin/uncrustify CACHE PATH "" FORCE)
endif()

if(EXISTS ${GEOSX_TPL_DIR}/doxygen/bin/doxygen)
  set(DOXYGEN_EXECUTABLE ${GEOSX_TPL_DIR}/doxygen/bin/doxygen CACHE PATH "" FORCE)
endif()

#
# Other
#
if(EXISTS ${GEOSX_TPL_DIR}/mathpresso)
  set(MATHPRESSO_DIR ${GEOSX_TPL_DIR}/mathpresso CACHE PATH "" FORCE)
endif()
###############################################################################

set(ENABLE_CUDA_NVTOOLSEXT ON CACHE BOOL "")
###############################################################################

# @@@ GEOS file contents END @@@ 
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
