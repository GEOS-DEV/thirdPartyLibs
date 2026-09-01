cmake_minimum_required(VERSION 3.23.1)
if( POLICY CMP0135 )
  cmake_policy( SET CMP0135 NEW )
endif()
################################
# GEOS_TPL
################################
project(geosx_tpl LANGUAGES C CXX Fortran)

set( ENABLE_DOXYGEN ON CACHE BOOL "" )
option( GEOSXTPL_ENABLE_DOXYGEN "" ON )
if ( NOT ENABLE_DOXYGEN )
    set( GEOSXTPL_ENABLE_DOXYGEN "OFF" )
endif()
set( ENABLE_DOXYGEN OFF CACHE BOOL "" FORCE )


################################
# BLT
################################
set( CXX_STANDARD 20 )
set( BLT_CXX_STD c++20 CACHE STRING "" FORCE )

# Keep required NVCC options in the common CUDA flags so CMake/BLT, the
# generated GEOS host config, and the external CUDA TPLs use the same behavior.
# CUDA 13.3 rejects newer host compiler versions unless the first option is
# given, and GEOS/LvArray device lambdas require the second one.
if( ENABLE_CUDA )
  foreach( _GEOS_TPL_CUDA_REQUIRED_FLAG IN ITEMS
           --allow-unsupported-compiler
           --extended-lambda )
    string( FIND "${CMAKE_CUDA_FLAGS}" "${_GEOS_TPL_CUDA_REQUIRED_FLAG}" _GEOS_TPL_CUDA_FLAG_POS )
    if( _GEOS_TPL_CUDA_FLAG_POS EQUAL -1 )
      if( CMAKE_CUDA_FLAGS )
        set( CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} ${_GEOS_TPL_CUDA_REQUIRED_FLAG}" CACHE STRING "" FORCE )
      else()
        set( CMAKE_CUDA_FLAGS "${_GEOS_TPL_CUDA_REQUIRED_FLAG}" CACHE STRING "" FORCE )
      endif()
    endif()
  endforeach()
  unset( _GEOS_TPL_CUDA_REQUIRED_FLAG )
  unset( _GEOS_TPL_CUDA_FLAG_POS )
endif()

if (DEFINED BLT_SOURCE_DIR)
    # Support having a shared BLT outside of the repository if given a BLT_SOURCE_DIR

    if (NOT EXISTS ${BLT_SOURCE_DIR}/SetupBLT.cmake)
        message(FATAL_ERROR "Given BLT_SOURCE_DIR does not contain SetupBLT.cmake")
    endif()
else()
    # Use internal BLT if no BLT_SOURCE_DIR is given
    set(BLT_SOURCE_DIR "${PROJECT_SOURCE_DIR}/cmake/blt" CACHE PATH "")
    if (NOT EXISTS ${BLT_SOURCE_DIR}/SetupBLT.cmake)
        message(FATAL_ERROR
            "The BLT submodule is not present. "
            "Run the following two commands in your git repository: \n"
            "    git submodule init\n"
            "    git submodule update" )
    endif()
endif()

include(${BLT_SOURCE_DIR}/SetupBLT.cmake)

################################
# General GEOSX TPL Info
################################
include(ExternalProject)

option( BUILD_SHARED_LIBS "" OFF )

option( ENABLE_CALIPER "" ON )
option( ENABLE_HYPRE "" ON )
option( ENABLE_HYPREDRV "" ON )
option( ENABLE_TRILINOS "" OFF )
option( ENABLE_PETSC "" OFF )
option( ENABLE_SCOTCH "" ON )
option( ENABLE_SUITESPARSE "" ON )
option( ENABLE_SUPERLU_DIST "" ON )
option( ENABLE_HYPRE_GPU_PROFILING "" OFF )
option( ENABLE_VTK "" ON )
option( ENABLE_VTK_WRAP_PYTHON "" OFF )

option( ENABLE_NINJA "" OFF )

include(ProcessorCount)
ProcessorCount(NUM_CORES)

set(NUM_PROC ${NUM_CORES} CACHE STRING "")
message( "Running with NUM_PROC = ${NUM_PROC}")

set(build_list )

set( CMAKE_POSITION_INDEPENDENT_CODE ON )

# Set up C flags
string(REPLACE "-Wall" "" C_FLAGS_NO_WARNINGS ${CMAKE_C_FLAGS})
string(REPLACE "-Wextra" "" C_FLAGS_NO_WARNINGS ${C_FLAGS_NO_WARNINGS})
set(C_FLAGS_NO_WARNINGS "${C_FLAGS_NO_WARNINGS} -w")
string(STRIP ${C_FLAGS_NO_WARNINGS} C_FLAGS_NO_WARNINGS)

# Set up CXX flags
string(REPLACE "-Wall" "" CXX_FLAGS_NO_WARNINGS ${CMAKE_CXX_FLAGS})
string(REPLACE "-Wextra" "" CXX_FLAGS_NO_WARNINGS ${CXX_FLAGS_NO_WARNINGS})
set(CXX_FLAGS_NO_WARNINGS "${CXX_FLAGS_NO_WARNINGS} -w")
string(STRIP ${CXX_FLAGS_NO_WARNINGS} CXX_FLAGS_NO_WARNINGS)

string(TOUPPER "${CMAKE_BUILD_TYPE}" BUILD_TYPE_UPPER)

# Setup Ninja support
if (ENABLE_NINJA)
    message(STATUS "Ninja is enabled")
    set(TPL_BUILD_COMMAND ninja)
    set(TPL_INSTALL_COMMAND ninja install)
    set(TPL_GENERATOR Ninja)
else()
    set(TPL_BUILD_COMMAND make -j ${NUM_PROC} )
    set(TPL_INSTALL_COMMAND make install)
    set(TPL_GENERATOR "Unix Makefiles")
endif()

message(STATUS "Build command = ${TPL_BUILD_COMMAND}")

include(GNUInstallDirs)
include( cmake/thirdparty/FindMathLibraries.cmake )


set( GEOSX_LOCALINDEX_TYPE "std::ptrdiff_t" CACHE STRING "" )
set( GEOSX_GLOBALINDEX_TYPE "long long int" CACHE STRING "" )

if( GEOSX_LOCALINDEX_TYPE STREQUAL "int" )
    set( GEOSX_LOCALINDEX_TYPE_FLAG "0" CACHE STRING "" FORCE )
elseif( GEOSX_LOCALINDEX_TYPE STREQUAL "long int" )
    set( GEOSX_LOCALINDEX_TYPE_FLAG "1" CACHE STRING "" FORCE )
elseif( GEOSX_LOCALINDEX_TYPE STREQUAL "long long int" )
    set( GEOSX_LOCALINDEX_TYPE_FLAG "2" CACHE STRING "" FORCE )
elseif( GEOSX_LOCALINDEX_TYPE STREQUAL "std::ptrdiff_t" )
    set( GEOSX_LOCALINDEX_TYPE_FLAG "3" CACHE STRING "" FORCE )
else( TRUE )
    message( FATAL_ERROR "GEOSX_LOCALINDEX_TYPE_FLAG not set for ${GEOSX_LOCALINDEX_TYPE}" )
endif()

if( GEOSX_GLOBALINDEX_TYPE STREQUAL "int" )
    set( GEOSX_GLOBALINDEX_TYPE_FLAG "0" CACHE STRING "" FORCE )
elseif( GEOSX_GLOBALINDEX_TYPE STREQUAL "long int" )
    set( GEOSX_GLOBALINDEX_TYPE_FLAG "1" CACHE STRING "" FORCE )
elseif( GEOSX_GLOBALINDEX_TYPE STREQUAL "long long int" )
    set( GEOSX_GLOBALINDEX_TYPE_FLAG "2" CACHE STRING "" FORCE )
else( TRUE )
    message( FATAL_ERROR "GEOSX_GLOBALINDEX_TYPE_FLAG not set for ${GEOSX_GLOBALINDEX_TYPE}" )
endif()


################################
# HIP / ROCm
################################
if( ENABLE_HIP )
    if( NOT DEFINED ROCM_PATH )
        if( DEFINED HIP_ROOT )
            set( ROCM_PATH ${HIP_ROOT} )
        elseif( DEFINED ENV{ROCM_PATH} )
            set( ROCM_PATH $ENV{ROCM_PATH} )
        else()
            message( FATAL_ERROR "ENABLE_HIP is ON but neither ROCM_PATH nor HIP_ROOT is defined." )
        endif()
    endif()

    if( NOT DEFINED HIP_ROOT )
        set( HIP_ROOT ${ROCM_PATH} )
    endif()

    if( NOT DEFINED CMAKE_HIP_ARCHITECTURES )
        message( FATAL_ERROR "ENABLE_HIP is ON but CMAKE_HIP_ARCHITECTURES is not defined (e.g. gfx90a, gfx942, gfx1100)." )
    endif()

    # Device-enabled HYPRE/HypreDrive builds need the MPI include directory
    # explicitly when their sources are compiled for the device.
    if( ENABLE_MPI AND NOT DEFINED MPI_INCLUDE_DIR )
        if( DEFINED ENV{MPICH_DIR} )               # set by the cray-mpich module on LC
            set( MPI_INCLUDE_DIR "$ENV{MPICH_DIR}/include" )
        elseif( DEFINED ENV{MPI_ROOT} )
            set( MPI_INCLUDE_DIR "$ENV{MPI_ROOT}/include" )
        elseif( MPI_C_INCLUDE_DIRS )               # set by find_package( MPI ) through BLT
            list( GET MPI_C_INCLUDE_DIRS 0 MPI_INCLUDE_DIR )
        elseif( MPI_C_COMPILER )                   # <prefix>/bin/mpicc -> <prefix>/include
            get_filename_component( MPI_BIN_DIR ${MPI_C_COMPILER} DIRECTORY )
            get_filename_component( MPI_PREFIX_DIR ${MPI_BIN_DIR} DIRECTORY )
            set( MPI_INCLUDE_DIR "${MPI_PREFIX_DIR}/include" )
        else()
            message( FATAL_ERROR "ENABLE_HIP is ON but MPI_INCLUDE_DIR is not defined and cannot be deduced." )
        endif()
        message( STATUS "MPI_INCLUDE_DIR = ${MPI_INCLUDE_DIR}" )
    endif()

    message( STATUS "ROCM_PATH = ${ROCM_PATH}" )
    message( STATUS "CMAKE_HIP_ARCHITECTURES = ${CMAKE_HIP_ARCHITECTURES}" )
endif()


################################
# UNCRUSTIFY
################################
set(UNCRUSTIFY_DIR "${CMAKE_INSTALL_PREFIX}/uncrustify")
set(UNCRUSTIFY_URL "https://github.com/uncrustify/uncrustify/archive/401a409.zip")
set(UNCRUSTIFY_URL_HASH "3d948d9d9047a7749632946f323313b9603f026302c37fb932c8414dfc714207")
message(STATUS "Building uncrustify found at ${UNCRUSTIFY_URL}")

ExternalProject_Add( uncrustify
                     URL ${UNCRUSTIFY_URL}
                     URL_HASH SHA256=${UNCRUSTIFY_URL_HASH}
                     PREFIX ${PROJECT_BINARY_DIR}/uncrustify
                     INSTALL_DIR ${UNCRUSTIFY_DIR}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                                -DCMAKE_CXX_STANDARD=11
                                -DNoGitVersionString:BOOL=ON
                                 )

list(APPEND build_list uncrustify )


################################
# Doxygen
################################

if( GEOSXTPL_ENABLE_DOXYGEN )

  set(DOXYGEN_DIR "${CMAKE_INSTALL_PREFIX}/doxygen")
  set(DOXYGEN_URL "https://github.com/doxygen/doxygen/archive/refs/tags/Release_1_8_20.tar.gz")
  set(DOXYGEN_URL_HASH "3dbdf8814d6e68233d5149239cb1f0b40b4e7b32eef2fd53de8828fedd7aca15")
  message(STATUS "Building Doxygen found at ${DOXYGEN_URL}")

  ExternalProject_Add( doxygen
                       URL ${DOXYGEN_URL}
                       URL_HASH SHA256=${DOXYGEN_URL_HASH}
                       PREFIX ${PROJECT_BINARY_DIR}/doxygen
                       INSTALL_DIR ${DOXYGEN_DIR}
                       BUILD_COMMAND make -j ${NUM_PROC}
                       INSTALL_COMMAND make install
                       CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                  -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                  -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                                  -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                  )

  list(APPEND build_list doxygen )

endif()

################################
# HDF5
################################
set( HDF5_DEPENDENCIES "" )
set(HDF5_DIR "${CMAKE_INSTALL_PREFIX}/hdf5")
set(HDF5_URL "https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5-1_12_1.tar.gz")
set(HDF5_URL_HASH "e6dde173c2d243551922d23a0387a79961205b018502e6a742acb30b61bc2d5f")
message(STATUS "Building HDF5 found at ${HDF5_URL}")

if( ${ENABLE_MPI} )
  set( HDF5_C_COMPILER ${MPI_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${MPI_CXX_COMPILER} )
else()
  set( HDF5_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
endif()

# Build hdf5 in RelWithDebInfo mode to avoid errors when compiling
# Silo: Silo's autogen script fails to find the hdf5 library if it is
# built in Debug mode with CMake due to hdf5 naming convention (see
# https://github.com/LLNL/Silo/issues/369).
if( CMAKE_BUILD_TYPE MATCHES Debug )
  set( HDF5_CMAKE_BUILD_TYPE RelWithDebInfo )
else()
  set( HDF5_CMAKE_BUILD_TYPE CMAKE_BUILD_TYPE )
endif()

ExternalProject_Add( hdf5
                     URL ${HDF5_URL}
                     URL_HASH SHA256=${HDF5_URL_HASH}
                     PREFIX ${PROJECT_BINARY_DIR}/hdf5
                     INSTALL_DIR ${HDF5_DIR}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER:STRING=${HDF5_C_COMPILER}
                                -D CMAKE_CXX_COMPILER:STRING=${HDF5_CXX_COMPILER}
                                -D CMAKE_C_FLAGS:STRING=${C_FLAGS_NO_WARNINGS}
                                -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                -D CMAKE_CXX_FLAGS:STRING=${CXX_FLAGS_NO_WARNINGS}
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_BUILD_TYPE:STRING=${HDF5_CMAKE_BUILD_TYPE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D HDF5_ENABLE_PARALLEL:BOOL=${ENABLE_MPI}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS:BOOL=ON
                                -D BUILD_STATIC_LIBS:BOOL=OFF
                                -D BUILD_TESTING:BOOL=OFF
                                -D HDF5_BUILD_EXAMPLES:BOOL=OFF
                                -D HDF5_BUILD_TOOLS:BOOL=ON
                                -D HDF5_BUILD_UTILS:BOOL=OFF
                                )

list(APPEND HDF5_DEPENDENCIES hdf5 )
list(APPEND build_list hdf5 )


################################
# Conduit
################################
set(CONDUIT_DIR "${CMAKE_INSTALL_PREFIX}/conduit")
set(CONDUIT_URL "https://github.com/LLNL/conduit/releases/download/v0.9.5/conduit-v0.9.5-src-with-blt.tar.gz")
set(CONDUIT_URL_HASH "d93294efbf0936da5a27941e13486aa1a04a74a59285786a2303eed19a24265a")
message(STATUS "Building Conduit found at ${CONDUIT_URL}")

if( ${ENABLE_MPI} )
  set( CONDUIT_C_COMPILER ${MPI_C_COMPILER} )
  set( CONDUIT_CXX_COMPILER ${MPI_CXX_COMPILER} )
else()
  set( CONDUIT_C_COMPILER ${CMAKE_C_COMPILER} )
  set( CONDUIT_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
endif()

ExternalProject_Add( conduit
                     URL ${CONDUIT_URL}
                     URL_HASH SHA256=${CONDUIT_URL_HASH}
                     PREFIX ${PROJECT_BINARY_DIR}/conduit
                     SOURCE_SUBDIR src
                     INSTALL_DIR ${CONDUIT_DIR}
                     DEPENDS ${HDF5_DEPENDENCIES}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D ENABLE_DOCS=OFF
                                -D ENABLE_EXAMPLES=OFF
                                -D ENABLE_FORTRAN=OFF
                                -D ENABLE_TESTS=OFF
                                -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                -D ENABLE_MPI=${ENABLE_MPI}
                                -D BLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                -D HDF5_DIR=${HDF5_DIR}

# This is to work around a bug in how hdf5 is used in conduit (it exposes an MPI header)
# Once this is fixed remove the next three lines (ENABLE_FIND_MPI and using the MPI wrappers)
# and uncomment out the 4 after (using serial compilers and MPI wrappers separately)
                                -D ENABLE_FIND_MPI=OFF
                                -D CMAKE_C_COMPILER=${CONDUIT_C_COMPILER}
                                -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                -D CMAKE_CXX_COMPILER=${CONDUIT_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
#                                    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
#                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
#                                    -DMPI_C_COMPILER=${MPI_C_COMPILER}
#                                    -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D BLT_CXX_STD:STRING=${BLT_CXX_STD}
                                )

list(APPEND build_list conduit )


################################
# SILO
################################
set(SILO_DIR "${CMAKE_INSTALL_PREFIX}/silo")
set(SILO_URL "https://github.com/LLNL/Silo/releases/download/4.11.1/silo-4.11.1-bsd.tar.xz")
set(SILO_URL_HASH "51ccfdf3c09dfc98c7858a0a6f08cc3b2a07ee3c4142ee6482ba7b24e314c2aa")
message(STATUS "Building SILO found at ${SILO_URL}")

string(REPLACE ";" " " HDF5_C_FLAGS_STR "${HDF5_C_FLAGS}")

# -Wno-error=xxx flags are needed to build Silo release 4.11 with
# AppleClang or regular Clang due to implicit declaration of 'zfp_init_zfp'.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/config_silo_for_geos "\
../silo/configure \
CC=\"${HDF5_C_COMPILER}\" \
CXX=\"${HDF5_CXX_COMPILER}\" \
CFLAGS=\"${HDF5_C_FLAGS_STR} ${C_FLAGS_NO_WARNINGS} -Wno-error=implicit-function-declaration -Wno-error=int-conversion\" \
LIBS=\"-ldl\" \
--prefix=${SILO_DIR} \
--build=${SILO_BUILD_TYPE} \
--with-hdf5=${HDF5_DIR}/include,${HDF5_DIR}/lib \
--disable-fortran \
--enable-optimization \
--disable-silex \
--enable-shared=no \
--enable-static=yes \
--with-pic=yes\n")

ExternalProject_Add( silo
                     URL ${SILO_URL}
                     URL_HASH SHA256=${SILO_URL_HASH}
                     PREFIX ${PROJECT_BINARY_DIR}/silo
                     INSTALL_DIR ${SILO_DIR}
                     DEPENDS ${HDF5_DEPENDENCIES}
                     CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_silo_for_geos && . ${PROJECT_BINARY_DIR}/config_silo_for_geos
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND build_list silo )


################################
# RAJA
################################


set(RAJA_DIR "${CMAKE_INSTALL_PREFIX}/raja")
set(RAJA_URL "https://github.com/LLNL/RAJA/releases/download/v2026.07.0/RAJA-v2026.07.0.tar.gz")
set(RAJA_URL_HASH "2774a569f19a7d8e37d1e166d197c828c6b614e7f8ef6d16ccbfb144b8284d02")


message(STATUS "Building RAJA found at ${RAJA_URL}")

# RDNA GPUs use 32-lane wavefronts, while the CDNA GPUs targeted by the
# default RAJA configuration use 64-lane wavefronts.  Keep this override
# configurable so callers can select the wave size explicitly when needed.
if( ENABLE_HIP )
    set( RAJA_HIP_WAVESIZE_DEFAULT 64 )
    if( CMAKE_HIP_ARCHITECTURES MATCHES "(^|;)gfx(10|11)" )
        set( RAJA_HIP_WAVESIZE_DEFAULT 32 )
    endif()
    set( RAJA_HIP_WAVESIZE "${RAJA_HIP_WAVESIZE_DEFAULT}" CACHE STRING
         "RAJA HIP wavefront size (32 for RDNA, 64 for CDNA)" )
    message( STATUS "RAJA HIP wavefront size = ${RAJA_HIP_WAVESIZE}" )
endif()

# RAJA's vectorization layer does not compile with the ROCm toolchain.
if( ENABLE_HIP )
    set( RAJA_ENABLE_VECTORIZATION OFF )
else()
    set( RAJA_ENABLE_VECTORIZATION ON )
endif()

if( ENABLE_CUDA )
    set( RAJA_CUDA_FLAGS "${RAJA_CUDA_FLAGS} ${CMAKE_CUDA_FLAGS}" )
    set( CHAI_CUDA_FLAGS "${CHAI_CUDA_FLAGS} ${CMAKE_CUDA_FLAGS}" )
endif()

ExternalProject_Add( raja
                     URL ${RAJA_URL}
                     URL_HASH SHA256=${RAJA_URL_HASH}
                     PREFIX ${PROJECT_BINARY_DIR}/raja
                     INSTALL_DIR ${RAJA_DIR}
                     DEPENDS ${RAJA_DEPENDS}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER:PATH=${CMAKE_CXX_COMPILER}
                                -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D RAJA_ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D RAJA_ENABLE_NV_TOOLS_EXT:BOOL=${ENABLE_CUDA_NVTOOLSEXT}
                                -D RAJA_ENABLE_ROCTX:BOOL=${ENABLE_ROCTX}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CMAKE_CUDA_HOST_COMPILER:FILEPATH=${CMAKE_CUDA_HOST_COMPILER}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CUB_DIR:PATH=${CUB_DIR}
                                -D CMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}
                                -D CMAKE_CUDA_FLAGS:STRING=${RAJA_CUDA_FLAGS}
                                -D ENABLE_HIP:BOOL=${ENABLE_HIP}
                                -D RAJA_ENABLE_HIP:BOOL=${ENABLE_HIP}
                                -D CMAKE_HIP_COMPILER=${CMAKE_HIP_COMPILER}
                                -D RAJA_ENABLE_VECTORIZATION:BOOL=${RAJA_ENABLE_VECTORIZATION}
                                -D hip_DIR=${HIP_ROOT}/lib/cmake/hip
                                -D ROCPRIM_DIR=${HIP_ROOT}
                                -D CMAKE_HIP_ARCHITECTURES:STRING=${CMAKE_HIP_ARCHITECTURES}
                                -D RAJA_HIP_WAVESIZE:STRING=${RAJA_HIP_WAVESIZE}
                                -D ENABLE_TESTS:BOOL=OFF
                                -D ENABLE_EXAMPLES:BOOL=OFF
                                -D ENABLE_OPENMP:BOOL=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D CMAKE_INSTALL_LIBDIR:PATH=lib
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D RAJA_ENABLE_EXERCISES:BOOL=OFF
                    )

list(APPEND build_list raja )


################################
# CHAI
################################
set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
set(CHAI_URL "https://github.com/LLNL/CHAI/releases/download/v2026.07.0/chai-v2026.07.0.tar.gz")
set(CHAI_URL_HASH "a03616ab5488d9d816d2ef007559c2ad7da988f82c0b7d7ddf9f8931518d99d8")
message(STATUS "Building CHAI found at ${CHAI_URL}")

ExternalProject_Add( chai
                     PREFIX ${PROJECT_BINARY_DIR}/chai
                     URL ${CHAI_URL}
                     URL_HASH SHA256=${CHAI_URL_HASH}
                     INSTALL_DIR ${CHAI_DIR}
                     DEPENDS raja
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D CHAI_ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CMAKE_CUDA_HOST_COMPILER:FILEPATH=${CMAKE_CUDA_HOST_COMPILER}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}
                                -D CMAKE_CUDA_FLAGS:STRING=${CHAI_CUDA_FLAGS}
                                -D ENABLE_HIP:BOOL=${ENABLE_HIP}
                                -D CHAI_ENABLE_HIP:BOOL=${ENABLE_HIP}
                                -D CMAKE_HIP_COMPILER=${CMAKE_HIP_COMPILER}
                                -D hip_DIR=${HIP_ROOT}/lib/cmake/hip
                                -D CMAKE_HIP_ARCHITECTURES:STRING=${CMAKE_HIP_ARCHITECTURES}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D CMAKE_INSTALL_LIBDIR:PATH=lib
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D ENABLE_TESTS=OFF
                                -D ENABLE_BENCHMARKS=OFF
                                -D ENABLE_EXAMPLES=OFF
                                -D ENABLE_DOCS=OFF
                                -D ENABLE_DOXYGEN=OFF
                                -D ENABLE_SPHINX=OFF
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D CHAI_ENABLE_RAJA_PLUGIN=ON
                                -D RAJA_DIR=${RAJA_DIR}/lib/cmake/raja
                                -D UMPIRE_ENABLE_C=ON
                    )

list(APPEND build_list chai )


################################
# Caliper and Adiak
################################
if (ENABLE_CALIPER)
    set(ADIAK_DIR "${CMAKE_INSTALL_PREFIX}/adiak")
    set(ADIAK_URL "https://github.com/LLNL/Adiak/releases/download/v0.4.0/adiak-0.4.0.tar.gz")
    set(ADIAK_URL_HASH "5f789998004a68f540d5d787a2062d8aa6a828f4787064221c5081f287a7b334")
    message(STATUS "Building Adiak found at ${ADIAK_URL}")

    ExternalProject_Add( adiak
                         URL ${ADIAK_URL}
                         URL_HASH SHA256=${ADIAK_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/adiak
                         INSTALL_DIR ${ADIAK_DIR}
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_ARGS -D CMAKE_C_COMPILER:STRING=${CMAKE_C_COMPILER}
                                    -D CMAKE_C_FLAGS:STRING=${C_FLAGS_NO_WARNINGS}
                                    -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                    -D CMAKE_CXX_COMPILER:STRING=${CMAKE_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS:STRING=${CXX_FLAGS_NO_WARNINGS}
                                    -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                    -D WITH_MPI:BOOL=${ENABLE_MPI}
                                    -D MPI_C_COMPILER:STRING=${MPI_C_COMPILER}
                                    -D MPI_CXX_COMPILER:STRING=${MPI_CXX_COMPILER}
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_INSTALL_LIBDIR:PATH=lib
                                    -D BLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                       )


    set(CALIPER_DIR "${CMAKE_INSTALL_PREFIX}/caliper")
    set(CALIPER_URL "https://github.com/LLNL/Caliper/archive/refs/tags/v2.14.0.tar.gz")
    set(CALIPER_URL_HASH "b42c35dfbe485960dd326033893dae37ac00d9807c5c3e6b5b1f396bc4af273f")
    message(STATUS "Building Caliper found at ${CALIPER_URL}")

    set(CALIPER_WITH_CUPTI OFF)

    if(ENABLE_CALIPER_WITH_CUPTI)
        set(CALIPER_WITH_CUPTI ON)
    endif()

    ExternalProject_Add( caliper
                         URL ${CALIPER_URL}
                         URL_HASH SHA256=${CALIPER_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/caliper
                         INSTALL_DIR ${CALIPER_DIR}
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         DEPENDS adiak
                         CMAKE_ARGS -D CMAKE_C_COMPILER:STRING=${CMAKE_C_COMPILER}
                                    -D CMAKE_C_FLAGS:STRING=${C_FLAGS_NO_WARNINGS}
                                    -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                    -D CMAKE_CXX_COMPILER:STRING=${CMAKE_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS:STRING=${CXX_FLAGS_NO_WARNINGS}
                                    -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                    -D WITH_MPI:BOOL=${ENABLE_MPI}
                                    -D MPI_C_COMPILER:STRING=${MPI_C_COMPILER}
                                    -D MPI_CXX_COMPILER:STRING=${MPI_CXX_COMPILER}
                                    -D CUDA_TOOLKIT_ROOT_DIR:PATH=${CUDA_TOOLKIT_ROOT_DIR}
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_INSTALL_LIBDIR:PATH=lib
                                    -D WITH_PAPI:BOOL=${ENABLE_PAPI}
                                    -D PAPI_PREFIX:STRING=${PAPI_PREFIX}
                                    -D WITH_ADIAK:BOOL=ON
                                    -D adiak_DIR:STRING=${ADIAK_DIR}/lib/cmake/adiak/
                                    -D WITH_CUPTI=${CALIPER_WITH_CUPTI}
                                    -D WITH_NVPROF=${ENABLE_CUDA}
                                    -D WITH_ROCM=${ENABLE_ROCTX}
                                    -D ROCM_PREFIX:PATH=${ROCM_PATH}
                       )

    if( BUILD_SHARED_LIBS )
        set( CALIPER_LIB "libcaliper.so" )
    else()
        set( CALIPER_LIB "libcaliper.a" )
    endif()

    list(APPEND build_list caliper adiak)
else()
    set( ENABLE_CALIPER_HYPRE OFF CACHE BOOL "" FORCE )
endif()


################################
# MATHPRESSO/ASMJIT
################################
if (DEFINED ENABLE_MATHPRESSO AND NOT ENABLE_MATHPRESSO)
    message(STATUS "MATHPRESSO disabled")
else()
    set(MATHPRESSO_DIR "${CMAKE_INSTALL_PREFIX}/mathpresso")
    set(MATHPRESSO_URL "https://github.com/kobalicek/mathpresso/archive/24d60e5c4d9a887c9ecb11991d07c54b3139ff1e.zip")
    set(MATHPRESSO_URL_HASH "6f46abaf2bd2ae97edf5bc338093bcb296800241b3e17242e22b4b44fe8c9d80")
    set(ASMJIT_URL "https://github.com/asmjit/asmjit/archive/2e93826348d6cd1325a8b1f7629e193c58332da9.zip")
    set(ASMJIT_URL_HASH "6e35cd3cfe58aec65b12aa4fd46fe5ed33cfb4023173e5a449a8f40a08daaf47")
    set(ASMJIT_DIR "${PROJECT_BINARY_DIR}/asmjit-master")
    message(STATUS "Building MATHPRESSO found at ${MATHPRESSO_URL}")

    ExternalProject_Add( asmjit
                         URL ${ASMJIT_URL}
                         URL_HASH SHA256=${ASMJIT_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/asmjit
                         SOURCE_DIR ${ASMJIT_DIR}
                         CONFIGURE_COMMAND ""
                         BUILD_COMMAND ""
                         INSTALL_COMMAND ""
                       )

    ExternalProject_Add( mathpresso
                         URL ${MATHPRESSO_URL}
                         URL_HASH SHA256=${MATHPRESSO_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/mathpresso
                         INSTALL_DIR ${MATHPRESSO_DIR}
                         DEPENDS asmjit
                         BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --parallel ${NUM_PROC}
                         INSTALL_COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR>
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_ARGS -D MATHPRESSO_STATIC=TRUE
                                    -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                    -D ASMJIT_DIR=${ASMJIT_DIR}
                                    -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                    -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                    -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                    -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_CXX_STANDARD=11
                                    -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                        )

    list(APPEND build_list mathpresso )
endif()


################################
# PUGIXML
################################
set(PUGIXML_DIR "${CMAKE_INSTALL_PREFIX}/pugixml")
set(PUGIXML_URL "https://github.com/zeux/pugixml/archive/refs/tags/v1.13.tar.gz")
set(PUGIXML_URL_HASH "5c5ad5d7caeb791420408042a7d88c2c6180781bf218feca259fd9d840a888e1")

message(STATUS "Building PUGIXML found at ${PUGIXML_URL}")

ExternalProject_Add( pugixml
                     PREFIX ${PROJECT_BINARY_DIR}/pugixml
                     URL ${PUGIXML_URL}
                     URL_HASH SHA256=${PUGIXML_URL_HASH}
                     INSTALL_DIR ${PUGIXML_DIR}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE} )

list(APPEND build_list pugixml )

################################
# TRILINOS
################################
if (ENABLE_TRILINOS)
    set(TRILINOS_DIR "${CMAKE_INSTALL_PREFIX}/trilinos")
    set(TRILINOS_URL "https://github.com/trilinos/Trilinos/archive/refs/tags/trilinos-release-16-1-0.tar.gz")
    set(TRILINOS_URL_HASH "e9651c88f581049457036cfc01b527a9d3903c257338eeeab942befd7452f23a")

    message(STATUS "Building TRILINOS found at ${TRILINOS_URL}")

    if ( CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 16.0 )
      set(TRILINOS_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS}")
      set(TRILINOS_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS} -include cstdint")
      set(TRILINOS_Fortran_FLAGS "-fPIC ${CMAKE_Fortran_FLAGS}")
    else()
      set(TRILINOS_C_FLAGS "${C_FLAGS_NO_WARNINGS}")
      set(TRILINOS_CXX_FLAGS "${CXX_FLAGS_NO_WARNINGS} -include cstdint")
      set(TRILINOS_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}")
    endif()



    if( ENABLE_MKL )
        set( TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                                 -D TPL_ENABLE_MKL:BOOL=ON
                                 -D TPL_MKL_INCLUDE_DIRS:PATH=${MKL_INCLUDE_DIRS}
                                 -D TPL_MKL_LIBRARIES:STRING=${MKL_LIBRARIES})
    endif()

    if ( DEFINED OpenMP_Fortran_FLAGS )
        set( TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                                 -D OpenMP_Fortran_FLAGS:STRING=${OpenMP_Fortran_FLAGS})
    endif()

    if ( DEFINED OpenMP_Fortran_LIB_NAMES )
        set( TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                                 -D OpenMP_Fortran_LIB_NAMES:STRING=${OpenMP_Fortran_LIB_NAMES})
    endif()

    if( ${ENABLE_MPI} )
      set( TRILINOS_C_COMPILER ${MPI_C_COMPILER} )
      set( TRILINOS_CXX_COMPILER ${MPI_CXX_COMPILER} )
      set( TRILINOS_Fortran_COMPILER ${MPI_Fortran_COMPILER} )
    else()
      set( TRILINOS_C_COMPILER ${CMAKE_C_COMPILER} )
      set( TRILINOS_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
      set( TRILINOS_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )
    endif()

    ExternalProject_Add( trilinos
                         PREFIX ${PROJECT_BINARY_DIR}/trilinos
                         URL ${TRILINOS_URL}
                         URL_HASH SHA256=${TRILINOS_URL_HASH}
                         INSTALL_DIR ${TRILINOS_DIR}
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_CACHE_ARGS -DTPL_BLAS_LIBRARIES:STRING=${BLAS_LIBRARIES}
                                          -DTPL_LAPACK_LIBRARIES:STRING=${LAPACK_LIBRARIES}
                         CMAKE_ARGS -D CMAKE_C_COMPILER:PATH=${TRILINOS_C_COMPILER}
                                    -D CMAKE_C_FLAGS:STRING=${TRILINOS_C_FLAGS}
                                    -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                    -D CMAKE_CXX_COMPILER:PATH=${TRILINOS_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS:STRING=${TRILINOS_CXX_FLAGS}
                                    -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                    -D CMAKE_Fortran_COMPILER:PATH=${TRILINOS_Fortran_COMPILER}
                                    -D CMAKE_Fortran_FLAGS:STRING=${TRILINOS_Fortran_FLAGS}
                                    -D CMAKE_Fortran_FLAGS_RELEASE:STRING=${CMAKE_Fortran_FLAGS_RELEASE}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_INSTALL_LIBDIR:PATH=lib64
                                    -D TPL_ENABLE_MPI:BOOL=${ENABLE_MPI}
                                    -D BUILD_SHARED_LIBS:BOOL=ON
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D Trilinos_ENABLE_OpenMP:BOOL=${ENABLE_OPENMP}
                                    -D Trilinos_ENABLE_Fortran:BOOL=ON
                                    -D Trilinos_WARNINGS_AS_ERRORS_FLAGS:STRING=""
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                    -D Trilinos_ENABLE_TESTS:BOOL=OFF
                                    -D Trilinos_ENABLE_Gtest:BOOL=OFF
                                    -D Trilinos_ENABLE_ALL_PACKAGES:BOOL=OFF
                                    -D Trilinos_ENABLE_ALL_OPTIONAL_PACKAGES:BOOL=OFF
                                    -D Trilinos_ENABLE_Epetra:BOOL=ON
                                    -D Trilinos_ENABLE_EpetraExt:BOOL=ON
                                    -D Trilinos_ENABLE_Tpetra:BOOL=ON
                                    -D Trilinos_ENABLE_Kokkos:BOOL=ON
                                    -D Trilinos_ENABLE_Stratimikos:BOOL=ON
                                    -D Trilinos_ENABLE_Amesos:BOOL=ON
                                    -D Trilinos_ENABLE_AztecOO:BOOL=ON
                                    -D Trilinos_ENABLE_Ifpack:BOOL=ON
                                    -D Trilinos_ENABLE_Teuchos:BOOL=ON
                                    -D Trilinos_ENABLE_Zoltan:BOOL=ON
                                    -D Trilinos_ENABLE_ML:BOOL=ON
                                    -D Trilinos_ENABLE_Thyra:BOOL=ON
                                    -D Trilinos_ENABLE_STK:BOOL=OFF
                                    -D Trilinos_ENABLE_TrilinosCouplings:BOOL=ON
                                    -D Trilinos_ENABLE_EXPLICIT_INSTANTIATION:BOOL=ON
                                    -D Epetra_SHOW_DEPRECATED_WARNINGS::BOOL=OFF
                                    -D EpetraExt_SHOW_DEPRECATED_WARNINGS::BOOL=OFF
                                    -D ML_SHOW_DEPRECATED_WARNINGS::BOOL=OFF
                                    -D AztecOO_SHOW_DEPRECATED_WARNINGS::BOOL=OFF
                                    -D Ifpack_SHOW_DEPRECATED_WARNINGS::BOOL=OFF
                                    ${TRILINOS_EXTRA_ARGS}
                        )

    list(APPEND build_list trilinos )
endif()


################################
# PARMETIS
# (also METIS is built; note that the idx_t data type is defined to be
#  64 bit signed integer)
################################

set(PARMETIS_DIR "${CMAKE_INSTALL_PREFIX}/parmetis")
set(METIS_DIR "${CMAKE_INSTALL_PREFIX}/metis")
set(PARMETIS_URL "https://ftp.mcs.anl.gov/pub/pdetools/spack-pkgs/parmetis-4.0.3.tar.gz")
set(PARMETIS_URL_HASH "f2d9a231b7cf97f1fee6e8c9663113ebf6c240d407d3c118c55b3633d6be6e5f")

if( ${ENABLE_MPI} )
  message(STATUS "Building PARMETIS found at ${PARMETIS_URL}")

  ExternalProject_Add( parmetis
                       PREFIX ${PROJECT_BINARY_DIR}/parmetis
                       URL ${PARMETIS_URL}
                       URL_HASH SHA256=${PARMETIS_URL_HASH}
                       INSTALL_DIR ${PARMETIS_DIR}
                       PATCH_COMMAND patch --forward -p1 < ${CMAKE_SOURCE_DIR}/patch/parmetis-idx64.patch
                       BUILD_COMMAND ${TPL_BUILD_COMMAND}
                       INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                       CMAKE_GENERATOR ${TPL_GENERATOR}
                       CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                  -D GKLIB_PATH=../parmetis/metis/GKlib
                                  -D METIS_PATH=../parmetis/metis
                                  -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                  -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                  -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                  -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                  -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                  -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                  -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                  -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                  )

  list(APPEND build_list parmetis )
endif()

message(STATUS "Building METIS found at ${PARMETIS_URL}")

ExternalProject_Add( metis
                     PREFIX ${PROJECT_BINARY_DIR}/metis
                     URL ${PARMETIS_URL}
                     URL_HASH SHA256=${PARMETIS_URL_HASH}
                     INSTALL_DIR ${METIS_DIR}
                     SOURCE_SUBDIR metis
                     PATCH_COMMAND patch --forward -p1 < ${CMAKE_SOURCE_DIR}/patch/parmetis-idx64.patch
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D GKLIB_PATH=../metis/metis/GKlib
                                -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                )

list(APPEND build_list metis )


################################
# SUPERLU --
################################
if( ENABLE_MPI AND ENABLE_SUPERLU_DIST )
  set(SUPERLU_DIR "${CMAKE_INSTALL_PREFIX}/superlu_dist")
  set(SUPERLU_URL "https://github.com/xiaoyeli/superlu_dist/archive/0f6efc3.tar.gz")
  set(SUPERLU_URL_HASH "49cd47da22fe72a37011e8dfaf94bd63ad8d61cc8144eac7a571bcbd0a2edf58")

  if ( CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 16.0 )
    set(SUPERLU_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS}")
    set(SUPERLU_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS}")
    set(SUPERLU_Fortran_FLAGS "-fPIC ${CMAKE_Fortran_FLAGS}")
  else()
    set(SUPERLU_C_FLAGS "${C_FLAGS_NO_WARNINGS}")
    set(SUPERLU_CXX_FLAGS "${CXX_FLAGS_NO_WARNINGS}")
    set(SUPERLU_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}")
  endif()


  set(PARMETIS_INCLUDE_DIRS ${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include)
  set(PARMETIS_LIBRARIES ${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a)

  message(STATUS "Building SUPERLU found at ${SUPERLU_URL}")
  ExternalProject_Add( superlu_dist
                       PREFIX ${PROJECT_BINARY_DIR}/superlu_dist
                       URL ${SUPERLU_URL}
                       URL_HASH SHA256=${SUPERLU_URL_HASH}
                       INSTALL_DIR ${SUPERLU_DIR}
                       BUILD_COMMAND ${TPL_BUILD_COMMAND}
                       INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                       CMAKE_GENERATOR ${TPL_GENERATOR}
                       DEPENDS parmetis metis
                       CMAKE_CACHE_ARGS -DTPL_PARMETIS_INCLUDE_DIRS:STRING=${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include
                                        -DTPL_PARMETIS_LIBRARIES:STRING=${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a
                                        -DTPL_BLAS_LIBRARIES:STRING=${BLAS_LIBRARIES}
                                        -DTPL_LAPACK_LIBRARIES:STRING=${LAPACK_LIBRARIES}
                       CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                  -D XSDK_INDEX_SIZE=64
                                  -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                  -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                  -D CMAKE_Fortran_COMPILER=${MPI_Fortran_COMPILER}
                                  -D MPI_C_COMPILER=${MPI_C_COMPILER}
                                  -D MPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                  -D CMAKE_C_STANDARD=99
                                  -D CMAKE_C_FLAGS=${SUPERLU_C_FLAGS}
                                  -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                  -D CMAKE_CXX_FLAGS=${SUPERLU_CXX_FLAGS}
                                  -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                  -D CMAKE_Fortran_FLAGS=${SUPERLU_Fortran_FLAGS}
                                  -D CMAKE_Fortran_FLAGS_RELEASE=${CMAKE_Fortran_FLAGS_RELEASE}
                                  -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                  -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                  -D CMAKE_INSTALL_LIBDIR:PATH=lib
                                  -D enable_openmp=${ENABLE_OPENMP}
          )

  list(APPEND build_list superlu_dist )
endif()

################################
# HYPRE
################################

if( ENABLE_HYPRE )
  set( HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre" )
  set( HYPRE_URL "https://github.com/hypre-space/hypre/archive/53927ee4fb68e5caf6be1957af2c3d75905b6b3d.tar.gz" )
  set( HYPRE_URL_HASH "d418846bc1466616cc22e71c4d3b855127846307bb4f4a2f4d37f046ac9c3355" )
  set( HYPRE_DEPENDS "" )

  message(STATUS "Building HYPRE found at ${HYPRE_URL}")

  # HYPRE's CMake project is rooted in its src directory.  Keep the HYPRE
  # build tree separate from the extracted source tree; in-source CMake
  # builds are not supported by HYPRE.
  set( HYPRE_CMAKE_ARGS
       "-DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}"
       "-DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}"
       "-DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}"
       "-DCMAKE_C_STANDARD:STRING=99"
       "-DCMAKE_C_STANDARD_REQUIRED:BOOL=ON"
       "-DCMAKE_CXX_STANDARD:STRING=${CMAKE_CXX_STANDARD}"
       "-DCMAKE_CXX_STANDARD_REQUIRED:BOOL=ON"
       "-DCMAKE_C_FLAGS:STRING=-fPIC ${C_FLAGS_NO_WARNINGS}"
       "-DCMAKE_CXX_FLAGS:STRING=-fPIC ${CXX_FLAGS_NO_WARNINGS}"
       "-DCMAKE_C_FLAGS_${BUILD_TYPE_UPPER}:STRING=${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}}"
       "-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=${CMAKE_POSITION_INDEPENDENT_CODE}"
       "-DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>"
       "-DCMAKE_INSTALL_LIBDIR:STRING=lib"
       "-DBUILD_SHARED_LIBS:BOOL=${BUILD_SHARED_LIBS}"
       "-DHYPRE_ENABLE_MPI:BOOL=${ENABLE_MPI}"
       "-DHYPRE_ENABLE_OPENMP:BOOL=${ENABLE_OPENMP}"
       "-DHYPRE_ENABLE_FORTRAN:BOOL=OFF"
       "-DHYPRE_ENABLE_PRINT_ERRORS:BOOL=ON"
       "-DHYPRE_BUILD_EXAMPLES:BOOL=OFF"
       "-DHYPRE_BUILD_TESTS:BOOL=OFF"
       "-DHYPRE_ENABLE_HYPRE_BLAS:BOOL=OFF"
       "-DHYPRE_ENABLE_HYPRE_LAPACK:BOOL=OFF"
       "-DHYPRE_ENABLE_CUDA:BOOL=OFF"
       "-DHYPRE_ENABLE_HIP:BOOL=OFF"
       "-DHYPRE_ENABLE_BIGINT:BOOL=OFF"
       "-DHYPRE_ENABLE_MIXEDINT:BOOL=OFF"
       "-DHYPRE_ENABLE_UNIFIED_MEMORY:BOOL=OFF"
       "-DHYPRE_ENABLE_UMPIRE:BOOL=OFF"
       "-DHYPRE_ENABLE_DSUPERLU:BOOL=OFF"
       "-DHYPRE_ENABLE_CALIPER:BOOL=OFF"
       "-DHYPRE_ENABLE_GPU_AWARE_MPI:BOOL=OFF"
       "-DHYPRE_ENABLE_GPU_PROFILING:BOOL=OFF" )

  if( ENABLE_MPI )
    # Use the host compilers for the HYPRE project.  FindMPI is given the
    # wrappers separately, which is important for CUDA: HYPRE's CUDA setup
    # uses CMAKE_CXX_COMPILER as nvcc's host compiler.
    list( APPEND HYPRE_CMAKE_ARGS
          "-DMPI_C_COMPILER:FILEPATH=${MPI_C_COMPILER}"
          "-DMPI_CXX_COMPILER:FILEPATH=${MPI_CXX_COMPILER}" )
  endif()

  if( ENABLE_MPI AND ENABLE_SUPERLU_DIST )
    list( APPEND HYPRE_DEPENDS superlu_dist )
    list( APPEND HYPRE_CMAKE_ARGS "-DHYPRE_ENABLE_DSUPERLU:BOOL=ON"
          "-DTPL_DSUPERLU_INCLUDE_DIRS:STRING=${SUPERLU_DIR}/include" )

    if( BUILD_SHARED_LIBS )
      set( HYPRE_SUPERLU_LIBRARY_SUFFIX so )
    else()
      set( HYPRE_SUPERLU_LIBRARY_SUFFIX a )
    endif()
    set( HYPRE_TPL_DSUPERLU_LIBRARIES
         "${SUPERLU_DIR}/lib/libsuperlu_dist.${HYPRE_SUPERLU_LIBRARY_SUFFIX}"
         "${PARMETIS_DIR}/lib/libparmetis.${HYPRE_SUPERLU_LIBRARY_SUFFIX}"
         "${METIS_DIR}/lib/libmetis.${HYPRE_SUPERLU_LIBRARY_SUFFIX}" )
    string( REPLACE ";" "^" HYPRE_TPL_DSUPERLU_LIBRARIES_ARG
            "${HYPRE_TPL_DSUPERLU_LIBRARIES}" )
    list( APPEND HYPRE_CMAKE_ARGS
          "-DTPL_DSUPERLU_LIBRARIES:STRING=${HYPRE_TPL_DSUPERLU_LIBRARIES_ARG}" )
  endif()

  if( ENABLE_HYPRE_DEVICE STREQUAL "CUDA" )
    if( NOT ENABLE_CUDA )
      message( FATAL_ERROR "Non-compatible options: HYPRE device cannot be set to CUDA when ENABLE_CUDA is OFF" )
    endif()

    list( APPEND HYPRE_DEPENDS chai )
    if( NOT DEFINED CMAKE_CUDA_HOST_COMPILER OR CMAKE_CUDA_HOST_COMPILER STREQUAL "" )
      set( HYPRE_CUDA_HOST_COMPILER "${CMAKE_CXX_COMPILER}" )
    else()
      set( HYPRE_CUDA_HOST_COMPILER "${CMAKE_CUDA_HOST_COMPILER}" )
    endif()
    list( APPEND HYPRE_CMAKE_ARGS
          "-DHYPRE_ENABLE_CUDA:BOOL=ON"
          "-DHYPRE_ENABLE_UNIFIED_MEMORY:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE_DEVICE:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE_UM:BOOL=ON"
          "-DHYPRE_ENABLE_CUDA_STREAMS:BOOL=ON"
          "-DHYPRE_ENABLE_CUSPARSE:BOOL=ON"
          "-DHYPRE_ENABLE_CUSOLVER:BOOL=ON"
          "-DHYPRE_ENABLE_CUBLAS:BOOL=ON"
          "-DHYPRE_ENABLE_CURAND:BOOL=ON"
          "-DCMAKE_CUDA_COMPILER:FILEPATH=${CMAKE_CUDA_COMPILER}"
          "-DCMAKE_CUDA_HOST_COMPILER:FILEPATH=${HYPRE_CUDA_HOST_COMPILER}"
          "-DCMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}"
          "-DCMAKE_CUDA_STANDARD:STRING=${CMAKE_CUDA_STANDARD}"
          "-DCMAKE_CUDA_STANDARD_REQUIRED:BOOL=ON"
          "-DCMAKE_CUDA_FLAGS:STRING=${CMAKE_CUDA_FLAGS}"
          "-DCUDAToolkit_ROOT:PATH=${CUDA_TOOLKIT_ROOT_DIR}"
          "-DCUDA_TOOLKIT_ROOT_DIR:PATH=${CUDA_TOOLKIT_ROOT_DIR}" )
  elseif( ENABLE_HYPRE_DEVICE STREQUAL "HIP" )
    if( NOT ENABLE_HIP )
      message( FATAL_ERROR "Non-compatible options: HYPRE device cannot be set to HIP when ENABLE_HIP is OFF" )
    endif()

    list( APPEND HYPRE_DEPENDS chai )
    if( NOT DEFINED CMAKE_HIP_STANDARD OR CMAKE_HIP_STANDARD STREQUAL "" )
      set( HYPRE_HIP_STANDARD "${CMAKE_CXX_STANDARD}" )
    else()
      set( HYPRE_HIP_STANDARD "${CMAKE_HIP_STANDARD}" )
    endif()
    list( APPEND HYPRE_CMAKE_ARGS
          "-DHYPRE_ENABLE_HIP:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE_DEVICE:BOOL=ON"
          "-DHYPRE_ENABLE_UMPIRE_UM:BOOL=OFF"
          "-DHYPRE_ENABLE_ROCBLAS:BOOL=ON"
          "-DHYPRE_ENABLE_ROCSPARSE:BOOL=ON"
          "-DHYPRE_ENABLE_ROCSOLVER:BOOL=ON"
          "-DHYPRE_ENABLE_ROCRAND:BOOL=ON"
          "-DCMAKE_HIP_COMPILER:FILEPATH=${CMAKE_HIP_COMPILER}"
          "-DCMAKE_HIP_ARCHITECTURES:STRING=${CMAKE_HIP_ARCHITECTURES}"
          "-DCMAKE_HIP_STANDARD:STRING=${HYPRE_HIP_STANDARD}"
          "-DCMAKE_HIP_STANDARD_REQUIRED:BOOL=ON"
          "-DROCM_PATH:PATH=${ROCM_PATH}" )
  endif()

  if( ENABLE_HYPRE_DEVICE STREQUAL "CUDA" OR ENABLE_HYPRE_DEVICE STREQUAL "HIP" )
    if( ENABLE_HYPRE_GPU_AWARE_MPI )
      list( APPEND HYPRE_CMAKE_ARGS "-DHYPRE_ENABLE_GPU_AWARE_MPI:BOOL=ON" )
    endif()
    if( ENABLE_HYPRE_GPU_PROFILING )
      list( APPEND HYPRE_CMAKE_ARGS "-DHYPRE_ENABLE_GPU_PROFILING:BOOL=ON" )
    endif()

    if( BUILD_SHARED_LIBS )
      set( HYPRE_UMPIRE_LIBRARY_SUFFIX so )
    else()
      set( HYPRE_UMPIRE_LIBRARY_SUFFIX a )
    endif()
    set( HYPRE_TPL_UMPIRE_INCLUDE_DIRS "${CHAI_DIR}/include" )
    set( HYPRE_TPL_UMPIRE_LIBRARIES
         "${CHAI_DIR}/lib/libumpire.${HYPRE_UMPIRE_LIBRARY_SUFFIX}"
         "${CHAI_DIR}/lib/libcamp.${HYPRE_UMPIRE_LIBRARY_SUFFIX}"
         "${CHAI_DIR}/lib/libfmt.${HYPRE_UMPIRE_LIBRARY_SUFFIX}" )
    string( REPLACE ";" "^" HYPRE_TPL_UMPIRE_LIBRARIES_ARG
            "${HYPRE_TPL_UMPIRE_LIBRARIES}" )
    list( APPEND HYPRE_CMAKE_ARGS
          "-DTPL_UMPIRE_INCLUDE_DIRS:STRING=${HYPRE_TPL_UMPIRE_INCLUDE_DIRS}"
          "-DTPL_UMPIRE_LIBRARIES:STRING=${HYPRE_TPL_UMPIRE_LIBRARIES_ARG}" )
  endif()

  if( CMAKE_HOST_APPLE )
    list( APPEND HYPRE_CMAKE_ARGS "-DHYPRE_ENABLE_BIGINT:BOOL=ON" )
  else()
    list( APPEND HYPRE_CMAKE_ARGS "-DHYPRE_ENABLE_MIXEDINT:BOOL=ON" )
  endif()

  string( REPLACE ";" "^" HYPRE_TPL_BLAS_LIBRARIES_ARG "${BLAS_LIBRARIES}" )
  string( REPLACE ";" "^" HYPRE_TPL_LAPACK_LIBRARIES_ARG "${LAPACK_LIBRARIES}" )
  list( APPEND HYPRE_CMAKE_ARGS
        "-DTPL_BLAS_LIBRARIES:STRING=${HYPRE_TPL_BLAS_LIBRARIES_ARG}"
        "-DTPL_LAPACK_LIBRARIES:STRING=${HYPRE_TPL_LAPACK_LIBRARIES_ARG}" )

  if( ENABLE_CALIPER_HYPRE )
    list( APPEND HYPRE_DEPENDS caliper )
    list( APPEND HYPRE_CMAKE_ARGS
          "-DHYPRE_ENABLE_CALIPER:BOOL=ON"
          "-DTPL_CALIPER_INCLUDE_DIRS:STRING=${CALIPER_DIR}/include"
          "-DTPL_CALIPER_LIBRARIES:STRING=${CALIPER_DIR}/lib/${CALIPER_LIB}" )
  endif()

  ExternalProject_Add( hypre
                       URL ${HYPRE_URL}
                       URL_HASH SHA256=${HYPRE_URL_HASH}
                       UPDATE_COMMAND ""  # Skip git pull/update since this is a snapshot
                       PREFIX ${PROJECT_BINARY_DIR}/hypre
                       SOURCE_DIR ${PROJECT_BINARY_DIR}/hypre/src/hypre
                       BINARY_DIR ${PROJECT_BINARY_DIR}/hypre-build
                       SOURCE_SUBDIR src
                       INSTALL_DIR ${HYPRE_DIR}
                       DEPENDS ${HYPRE_DEPENDS}
                       LIST_SEPARATOR "^"
                       CMAKE_GENERATOR ${TPL_GENERATOR}
                       CMAKE_ARGS ${HYPRE_CMAKE_ARGS}
                       BUILD_COMMAND ${TPL_BUILD_COMMAND}
                       INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                       )

  list( APPEND build_list hypre )
endif()

################################
# HYPREDRIVE
################################

if( ENABLE_HYPREDRV )
  if( NOT ENABLE_HYPRE )
    message( FATAL_ERROR "ENABLE_HYPREDRV requires ENABLE_HYPRE=ON" )
  endif()

  set( HYPREDRV_DIR "${CMAKE_INSTALL_PREFIX}/hypredrive" )
  set( HYPREDRV_URL "https://github.com/hypre-space/hypredrive/archive/00cdb36800d6754b01467a4ef62e0e4ae19e6897.tar.gz" )
  set( HYPREDRV_URL_HASH "c33212d5fb7391c81ae22ae801d387f41c2c3f293f48ccd8153845d97ba5150c" )
  set( HYPREDRV_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HYPREDRV_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}}" )
  set( HYPREDRV_HYPRE_INCLUDE_DIRS "${HYPRE_DIR}/include" )
  set( HYPREDRV_HYPRE_LIBRARY "${HYPRE_DIR}/lib/libHYPRE.a" )
  set( HYPREDRV_HYPRE_LIBRARIES "${HYPREDRV_HYPRE_LIBRARY}" )
  list( APPEND HYPREDRV_HYPRE_LIBRARIES ${BLAS_LIBRARIES} ${LAPACK_LIBRARIES} )
  if( ENABLE_MPI AND ENABLE_SUPERLU_DIST )
    list( APPEND HYPREDRV_HYPRE_LIBRARIES
          "${SUPERLU_DIR}/lib/libsuperlu_dist.a"
          "${PARMETIS_DIR}/lib/libparmetis.a"
          "${METIS_DIR}/lib/libmetis.a" )
  endif()
  set( HYPREDRV_MPI_ARGS )
  set( HYPREDRV_ACCELERATOR_ARGS )
  set( HYPREDRV_ENABLE_CUDA OFF )
  set( HYPREDRV_ENABLE_HIP OFF )

  if( ENABLE_MPI )
    set( HYPREDRV_C_COMPILER ${MPI_C_COMPILER} )
    list( APPEND HYPREDRV_MPI_ARGS
          -D MPI_C_COMPILER:FILEPATH=${MPI_C_COMPILER}
          -D MPI_CXX_COMPILER:FILEPATH=${MPI_CXX_COMPILER} )
  endif()

  if( ENABLE_HYPRE_DEVICE STREQUAL "CUDA" )
    set( HYPREDRV_ENABLE_CUDA ON )
    # The legacy HYPRE build uses Umpire for device memory.  Its generated
    # headers include Umpire headers, and its static archive leaves the
    # Umpire/CUDA dependencies to consumers, so propagate both explicitly.
    list( APPEND HYPREDRV_HYPRE_INCLUDE_DIRS "${CHAI_DIR}/include" )
    list( APPEND HYPREDRV_HYPRE_LIBRARIES
          "${CHAI_DIR}/lib/libumpire.a"
          "${CHAI_DIR}/lib/libcamp.a"
          "${CHAI_DIR}/lib/libfmt.a"
          "-L${CUDA_TOOLKIT_ROOT_DIR}/lib64"
          -lcudart -lcusparse -lcublas -lcurand -lcusolver
          -ldl -lstdc++ )
    list( APPEND HYPREDRV_ACCELERATOR_ARGS
          -D CMAKE_CUDA_COMPILER:FILEPATH=${CMAKE_CUDA_COMPILER}
          -D CMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}
          -D CUDA_TOOLKIT_ROOT_DIR:PATH=${CUDA_TOOLKIT_ROOT_DIR} )
  elseif( ENABLE_HYPRE_DEVICE STREQUAL "HIP" )
    set( HYPREDRV_ENABLE_HIP ON )
    list( APPEND HYPREDRV_HYPRE_INCLUDE_DIRS "${CHAI_DIR}/include" )
    list( APPEND HYPREDRV_HYPRE_LIBRARIES
          "${CHAI_DIR}/lib/libumpire.a"
          "${CHAI_DIR}/lib/libcamp.a"
          "${CHAI_DIR}/lib/libfmt.a"
          -ldl -lstdc++ )
    list( APPEND HYPREDRV_ACCELERATOR_ARGS
          -D CMAKE_HIP_COMPILER:FILEPATH=${CMAKE_HIP_COMPILER}
          -D CMAKE_HIP_ARCHITECTURES:STRING=${CMAKE_HIP_ARCHITECTURES}
          -D ROCM_PATH:PATH=${ROCM_PATH} )
  endif()

  set( HYPREDRV_CALIPER_ARGS )
  set( HYPREDRV_ENABLE_CALIPER OFF )
  if( DEFINED ENABLE_CALIPER_HYPRE AND ENABLE_CALIPER_HYPRE )
    set( HYPREDRV_ENABLE_CALIPER ON )
    list( APPEND HYPREDRV_CALIPER_ARGS
          -D TPL_CALIPER_INCLUDE_DIRS:PATH=${CALIPER_DIR}/include
          -D TPL_CALIPER_LIBRARIES:FILEPATH=${CALIPER_DIR}/lib/${CALIPER_LIB} )
  endif()

  message( STATUS "Building HYPREDRIVE found at ${HYPREDRV_URL}" )

  string( REPLACE ";" "^" HYPREDRV_HYPRE_INCLUDE_DIRS_ARG
          "${HYPREDRV_HYPRE_INCLUDE_DIRS}" )
  string( REPLACE ";" "^" HYPREDRV_HYPRE_LIBRARIES_ARG
          "${HYPREDRV_HYPRE_LIBRARIES}" )

  # Pass the superbuild's HYPRE include/library paths explicitly so
  # HypreDrive does not fetch and build a second copy of HYPRE.
  ExternalProject_Add( hypredrive
                       URL ${HYPREDRV_URL}
                       URL_HASH SHA256=${HYPREDRV_URL_HASH}
                       UPDATE_COMMAND ""
                       LIST_SEPARATOR "^"
                       PREFIX ${PROJECT_BINARY_DIR}/hypredrive
                       INSTALL_DIR ${HYPREDRV_DIR}
                       DEPENDS hypre
                       BUILD_COMMAND ${TPL_BUILD_COMMAND}
                       INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                       CMAKE_GENERATOR ${TPL_GENERATOR}
                       CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                  -D CMAKE_C_COMPILER:FILEPATH=${HYPREDRV_C_COMPILER}
                                  -D CMAKE_C_FLAGS:STRING=${HYPREDRV_C_FLAGS}
                                  -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                  -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                  -D CMAKE_INSTALL_LIBDIR:STRING=lib
                                  -D BUILD_SHARED_LIBS:BOOL=${BUILD_SHARED_LIBS}
                                  -D CMAKE_POSITION_INDEPENDENT_CODE:BOOL=${CMAKE_POSITION_INDEPENDENT_CODE}
                                  -D HYPRE_INCLUDE_DIRS:PATH=${HYPREDRV_HYPRE_INCLUDE_DIRS_ARG}
                                  -D HYPRE_LIBRARIES:STRING=${HYPREDRV_HYPRE_LIBRARIES_ARG}
                                  -D HYPREDRV_ENABLE_TESTING:BOOL=OFF
                                  -D HYPREDRV_ENABLE_ALL_TESTS:BOOL=OFF
                                  -D HYPREDRV_ENABLE_DATA:BOOL=OFF
                                  -D HYPREDRV_ENABLE_DOCS:BOOL=OFF
                                  -D HYPREDRV_ENABLE_EXAMPLES:BOOL=OFF
                                  -D HYPREDRV_BUILD_DSUPERLU:BOOL=OFF
                                  -D HYPREDRV_ENABLE_CALIPER:BOOL=${HYPREDRV_ENABLE_CALIPER}
                                  -D HYPREDRV_ENABLE_CUDA:BOOL=${HYPREDRV_ENABLE_CUDA}
                                  -D HYPREDRV_ENABLE_HIP:BOOL=${HYPREDRV_ENABLE_HIP}
                                  ${HYPREDRV_MPI_ARGS}
                                  ${HYPREDRV_ACCELERATOR_ARGS}
                                  ${HYPREDRV_CALIPER_ARGS} )

  list( APPEND build_list hypredrive )
endif()

################################
# SUITESPARSE
################################
if(ENABLE_SUITESPARSE)
    set(SUITESPARSE_DIR "${CMAKE_INSTALL_PREFIX}/suitesparse")
    set(SUITESPARSE_URL "https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/v5.10.1.tar.gz")
    set(SUITESPARSE_URL_HASH "acb4d1045f48a237e70294b950153e48dce5b5f9ca8190e86c2b8c54ce00a7ee")

    message(STATUS "Building SUITESPARSE found at ${SUITESPARSE_URL}")

    set( SUITESPARSE_DEPENDS metis )

    if( GEOSX_GLOBALINDEX_TYPE_FLAG EQUAL 0 )
        set( SUITESPARSE_LONG_INT_FLAGS "-DSuiteSparse_long=int -DSuiteSparse_long_max=2147483647 -DSuiteSparse_long_idd=\\\"d\\\" -D\'SuiteSparse_long_id=\\\"%d\\\"\'" )
    elseif( GEOSX_GLOBALINDEX_TYPE_FLAG EQUAL 2 )
        set( SUITESPARSE_LONG_INT_FLAGS "-D\'SuiteSparse_long=long long int\' -DSuiteSparse_long_max=2147483647 -DSuiteSparse_long_idd=\\\"d\\\" -D\'SuiteSparse_long_id=\\\"%d\\\"\'" )
    endif()

    set( SUITESPARSE_C_FLAGS "${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}}" )
    set( SUITESPARSE_CXX_FLAGS "${CMAKE_CXX_FLAGS_${BUILD_TYPE_UPPER}}" )
    set( SUITESPARSE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_${BUILD_TYPE_UPPER}}" )

    set( SUITESPARSE_C_COMPILER ${CMAKE_C_COMPILER} )
    set( SUITESPARSE_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
    set( SUITESPARSE_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )

    if (ENABLE_OPENMP)
        set(SUITESPARSE_OPENMP_FLAG "${OpenMP_C_FLAGS}")
    endif()

    set( SUITESPARSE_CONFIG_ARGS "CC=${SUITESPARSE_C_COMPILER} \
CFLAGS=\"${SUITESPARSE_C_FLAGS} ${SUITESPARSE_LONG_INT_FLAGS}\" \
CXX=${SUITESPARSE_CXX_COMPILER} \
CXXFLAGS=\"${SUITESPARSE_CXX_FLAGS}\" \
FC=${SUITESPARSE_Fortran_COMPILER} \
FCFLAGS=\"${SUITESPARSE_Fortran_FLAGS}\" \
JOBS=${NUM_PROC} \
CFOPENMP=${SUITESPARSE_OPENMP_FLAG} \
INSTALL=${SUITESPARSE_DIR} \
BLAS=\"${BLAS_LINK_LINE}\" \
LAPACK=\"${LAPACK_LINK_LINE}\" \
MY_METIS_LIB=\"${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a\" \
MY_METIS_INC=\"${CMAKE_INSTALL_PREFIX}/metis/include\" \
CUDA=no")

    # UMFPACK dependencies
    set( SUITESPARSE_PACKAGES "SuiteSparse_config;AMD;BTF;CAMD;CCOLAMD;COLAMD;CHOLMOD;KLU;UMFPACK" )

    set( SUITESPARSE_BUILD_CMD "" )
    foreach( PKG ${SUITESPARSE_PACKAGES} )
        set( SUITESPARSE_BUILD_CMD "${SUITESPARSE_BUILD_CMD}cd ${PKG} && \
make ${SUITESPARSE_CONFIG_ARGS} library && \
cd ..\n" )
    endforeach()

    set( SUITESPARSE_INSTALL_CMD "" )
    foreach( PKG ${SUITESPARSE_PACKAGES} )
        set( SUITESPARSE_INSTALL_CMD "${SUITESPARSE_INSTALL_CMD}cd ${PKG} && \
make ${SUITESPARSE_CONFIG_ARGS} install && \
cd ..\n" )
    endforeach()

    file(WRITE ${PROJECT_BINARY_DIR}/config_suitesparse_for_geos "make config ${SUITESPARSE_CONFIG_ARGS}\n")
    file(WRITE ${PROJECT_BINARY_DIR}/build_suitesparse_for_geos ${SUITESPARSE_BUILD_CMD})
    file(WRITE ${PROJECT_BINARY_DIR}/install_suitesparse_for_geos ${SUITESPARSE_INSTALL_CMD})

    ExternalProject_Add( suitesparse
                         URL ${SUITESPARSE_URL}
                         URL_HASH SHA256=${SUITESPARSE_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/suitesparse
                         INSTALL_DIR ${SUITESPARSE_DIR}
                         DEPENDS ${SUITESPARSE_DEPENDS}
                         BINARY_DIR ${PROJECT_BINARY_DIR}/suitesparse/src/suitesparse
                         CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_suitesparse_for_geos && . ${PROJECT_BINARY_DIR}/config_suitesparse_for_geos
                         BUILD_COMMAND cat ${PROJECT_BINARY_DIR}/build_suitesparse_for_geos && . ${PROJECT_BINARY_DIR}/build_suitesparse_for_geos
                         INSTALL_COMMAND cat ${PROJECT_BINARY_DIR}/install_suitesparse_for_geos && . ${PROJECT_BINARY_DIR}/install_suitesparse_for_geos
                       )

    list(APPEND build_list suitesparse )
endif(ENABLE_SUITESPARSE)

################################
# SCOTCH
################################

if( ENABLE_SCOTCH )
    set( SCOTCH_DIR "${CMAKE_INSTALL_PREFIX}/scotch" )
    set( SCOTCH_URL "https://gitlab.inria.fr/scotch/scotch/-/archive/v7.0.8/scotch-v7.0.8.tar.gz" )
    set( SCOTCH_URL_HASH "21f48ac85c7991a5eb5fae9232dd68584556ccc500f85e2ebd6b5b275617e11a" )

    message( STATUS "Building SCOTCH found at ${SCOTCH_URL}" )

    if( NOT ENABLE_MPI )
        message( FATAL_ERROR "Building Scotch without MPI is not supported." )
    endif()

    # OSX does not have pthread barriers used by Scotch
    set( SCOTCH_THREADS ON )
    if( CMAKE_HOST_APPLE )
        set( SCOTCH_THREADS OFF )
    endif()

    ExternalProject_Add( scotch
                        PREFIX ${PROJECT_BINARY_DIR}/scotch
                        URL ${SCOTCH_URL}
                        URL_HASH SHA256=${SCOTCH_URL_HASH}
                        INSTALL_DIR ${SCOTCH_DIR}
                        BINARY_DIR ${PROJECT_BINARY_DIR}/scotch/src/scotch-make-build
                        BUILD_COMMAND make -j ${NUM_PROC}
                        INSTALL_COMMAND make install
                        CMAKE_GENERATOR "Unix Makefiles"
                        CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D BUILD_PTSCOTCH:BOOL=ON
                                    -D BUILD_LIBSCOTCHMETIS:BOOL=OFF
                                    -D THREADS:BOOL=${SCOTCH_THREADS}
                                    -D INTSIZE:STRING=64
                                    -D SCOTCH_DETERMINISTIC:STRING=FULL
                                    -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                    -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                    -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                    -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                    -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                    -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    )

    list(APPEND build_list scotch )

endif()

################################
# PETSC
################################

if( ENABLE_PETSC )
    set(PETSC_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/petsc")
    set(PETSC_URL "https://gitlab.com/petsc/petsc/-/archive/v3.19.4/petsc-v3.19.4.tar.gz")
    set(PETSC_URL_HASH "f22413832558575f784ad927ad21b9b45cae91d90ca686802c45c6fd48b04b2c")

    message(STATUS "Building PETSC found at ${PETSC_URL}")

    set( PETSC_C_COMPILER ${CMAKE_C_COMPILER} )
    set( PETSC_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
    set( PETSC_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )
    set( PETSC_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}}" )
    set( PETSC_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS} ${CMAKE_CXX_FLAGS_${BUILD_TYPE_UPPER}}" )
    set( PETSC_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_${BUILD_TYPE_UPPER}}" )

    if( ENABLE_OPENMP )
        set(PETSC_OPENMP_FLAG "--with-openmp=1")
        set(PETSC_C_FLAGS "${PETSC_C_FLAGS} ${OpenMP_C_FLAGS}")
        set(PETSC_CXX_FLAGS "${PETSC_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
        set(PETSC_Fortran_FLAGS "${PETSC_Fortran_FLAGS} ${OpenMP_Fortran_FLAGS}")

        if( PETSC_OMP_DIR )
            set(PETSC_OMP_DIR_FLAG "--with-openmp-dir=${PETSC_OMP_DIR}")
        endif()
    endif()

    if( CMAKE_BUILD_TYPE MATCHES Debug )
        set(PETSC_DEBUG_FLAG "--with-debugging=1")
    else()
        set(PETSC_DEBUG_FLAG "--with-debugging=0")
    endif()

    set( PETSC_DEPENDS )
    set( PETSC_DEP_FLAG "" )

    if( ENABLE_MPI )
        set( PETSC_C_COMPILER ${MPI_C_COMPILER} )
        set( PETSC_CXX_COMPILER ${MPI_CXX_COMPILER} )
        set( PETSC_Fortran_COMPILER ${MPI_Fortran_COMPILER} )
        set( PETSC_MPI_FLAG "--with-mpi=1" )
        set( PETSC_DEP_FLAGS "${PETSC_DEP_FLAG} --with-parmetis-dir=${PARMETIS_DIR} --with-superlu_dist-dir=${SUPERLU_DIR}")
        list( APPEND PETSC_DEPENDS parmetis metis superlu_dist )
    else()
        set( PETSC_MPI_FLAG "--with-mpi=0" )
    endif()

    if( ENABLE_SCOTCH )
        set( PETSC_DEP_FLAGS "${PETSC_DEP_FLAG} --with-ptscotch-dir=${SCOTCH_DIR}" )
        list( APPEND PETSC_DEPENDS scotch )
    endif()

    string(REPLACE ";" " " PETSC_BLAS_LIBS "${BLAS_LIBRARIES}")
    string(REPLACE ";" " " PETSC_LAPACK_LIBS "${LAPACK_LIBRARIES}")

    file(WRITE ${PROJECT_BINARY_DIR}/config_petsc_for_geos "\
./configure \
--prefix=${PETSC_INSTALL_DIR} \
--CC=${PETSC_C_COMPILER} \
--CFLAGS=\"${PETSC_C_FLAGS}\" \
--CXX=${PETSC_CXX_COMPILER} \
--CXXFLAGS=\"${PETSC_CXX_FLAGS}\" \
--FC=${PETSC_Fortran_COMPILER} \
--FFLAGS=\"${PETSC_Fortran_FLAGS}\" \
--with-fortran-bindings=0 \
--with-metis-dir=${CMAKE_INSTALL_PREFIX}/metis \
--with-64-bit-indices=1 \
--known-mpi-int64_t=0 \
--with-blas-lib=\"${PETSC_BLAS_LIBS}\" \
--with-lapack-lib=\"${PETSC_LAPACK_LIBS}\" \
${PETSC_DEBUG_FLAG} \
${PETSC_OPENMP_FLAG} \
${PETSC_OMP_DIR_FLAG} \
${PETSC_MPI_FLAG} \
${PETSC_DEP_FLAG}\n")

    ExternalProject_Add( petsc
                         URL ${PETSC_URL}
                         URL_HASH SHA256=${PETSC_URL_HASH}
                         PREFIX ${PROJECT_BINARY_DIR}/petsc #outer petsc directory
                         DEPENDS ${PETSC_DEPENDS}
                         BINARY_DIR ${PROJECT_BINARY_DIR}/petsc/src/petsc
                         INSTALL_DIR ${PETSC_INSTALL_DIR}
                         CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_petsc_for_geos && . ${PROJECT_BINARY_DIR}/config_petsc_for_geos
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                        )

    list(APPEND build_list petsc )
endif()

################################
# VTK
################################
if( ENABLE_VTK )
    set( VTK_DIR "${CMAKE_INSTALL_PREFIX}/vtk" )
    set( VTK_URL "https://www.vtk.org/files/release/9.7/VTK-9.7.0.tar.gz" )
    set( VTK_URL_HASH "affdb7a15ec34ee0174407f911ab70b646c7af01161818bbab4e1160b7eff720" )

    message( STATUS "Building VTK found at ${VTK_URL}" )

    # Depending on the platform, the install directory could be 'lib' or 'lib64'.
    # This makes the 'rpath' task more complicated to deal with a single script ('CMAKE_INSTALL_RPATH' option).
    # Defining explicitly 'lib' deals with this issue.
    # I'm no cmake expert and I do not know if there was a better way to deal with it.
    set( VTK_CMAKE_INSTALL_LIBDIR "lib" )

if( ENABLE_MPI )
    set( VTK_C_COMPILER ${MPI_C_COMPILER} )
    set( VTK_CXX_COMPILER ${MPI_CXX_COMPILER} )
    set( VTK_USE_MPI ON )
    set( VTK_MODULE_ENABLE_VTK_IOParallelXML YES )
    set( VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2 YES )
else()
    set( VTK_C_COMPILER ${CMAKE_C_COMPILER} )
    set( VTK_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
    set( VTK_USE_MPI OFF )
    set( VTK_MODULE_ENABLE_VTK_IOParallelXML NO )
    set( VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2 NO )
endif( ENABLE_MPI )

    ExternalProject_Add( vtk
                         PREFIX ${PROJECT_BINARY_DIR}/vtk
                         URL ${VTK_URL}
                         URL_HASH SHA256=${VTK_URL_HASH}
                         INSTALL_DIR ${VTK_DIR}
                         PATCH_COMMAND patch --forward -p0 < ${CMAKE_SOURCE_DIR}/patch/vtkCellGridReader.cxx.patch &&
                                       patch --forward -p0 < ${CMAKE_SOURCE_DIR}/patch/vtkLegacyCellGridReader.cxx.patch
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND "${TPL_INSTALL_COMMAND}"
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_ARGS -D CMAKE_C_COMPILER=${VTK_C_COMPILER}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_CXX_COMPILER=${VTK_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS:STRING=${CMAKE_CXX_FLAGS}
                                    -D CMAKE_CXX_STANDARD:STRING=${CXX_STANDARD}
                                    -D CMAKE_CXX_STANDARD_REQUIRED:BOOL=ON
                                    -D VTK_IGNORE_CMAKE_CXX17_CHECKS:BOOL=ON
                                    -D VTK_USE_MPI=${VTK_USE_MPI}
                                    -D VTK_MODULE_ENABLE_VTK_IOParallelXML=${VTK_MODULE_ENABLE_VTK_IOParallelXML}
                                    -D VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2=${VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_INSTALL_LIBDIR=${VTK_CMAKE_INSTALL_LIBDIR}
                                    -D CMAKE_INSTALL_RPATH:PATH=<INSTALL_DIR>/${VTK_CMAKE_INSTALL_LIBDIR}
                                    -D VTK_GROUP_ENABLE_Imaging=DONT_WANT
                                    -D VTK_GROUP_ENABLE_MPI=DONT_WANT
                                    -D VTK_GROUP_ENABLE_Qt=DONT_WANT
                                    -D VTK_GROUP_ENABLE_Rendering=DONT_WANT
                                    -D VTK_GROUP_ENABLE_StandAlone=DONT_WANT
                                    -D VTK_GROUP_ENABLE_Views=DONT_WANT
                                    -D VTK_GROUP_ENABLE_Web=DONT_WANT
                                    -D VTK_BUILD_ALL_MODULES=OFF
                                    -D VTK_WRAP_PYTHON=${ENABLE_VTK_WRAP_PYTHON}
                                    -D VTK_WRAP_JAVA=OFF
                                    -D VTK_MODULE_ENABLE_VTK_vtkm=DONT_WANT
                                    -D VTK_MODULE_ENABLE_VTK_IOXML=YES
                                    -D VTK_MODULE_ENABLE_VTK_IOLegacy=YES
                                    -D VTK_BUILD_TESTING=OFF )

    list( APPEND build_list vtk )
endif( ENABLE_VTK )

################################
# FMT
################################
set(FMT_DIR "${CMAKE_INSTALL_PREFIX}/fmt")
set(FMT_URL "https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz")
set(FMT_URL_HASH "ea7de4299689e12b6dddd392f9896f08fb0777ac7168897a244a6d6085043fea")

message(STATUS "Building FMT found at ${FMT_URL}")

ExternalProject_Add( fmt
                     PREFIX ${PROJECT_BINARY_DIR}/fmt
                     URL ${FMT_URL}
                     URL_HASH SHA256=${FMT_URL_HASH}
                     INSTALL_DIR ${FMT_DIR}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D CMAKE_CXX_STANDARD=${CXX_STANDARD}
                                -D CMAKE_CXX_VISIBILITY_PRESET:STRING=default
                                -D CMAKE_VISIBILITY_INLINES_HIDDEN:BOOL=OFF
                                -D FMT_TEST:BOOL=OFF )

list(APPEND build_list fmt)


################################
# Create target that builds all dependencies
################################
message(STATUS "Building = ${build_list}")

# Generate a self-contained configuration for a downstream GEOS build.  The
# file is generated during configuration and copied to the install prefix by
# the `tpl` target after all external projects have been built.
set(GEOS_TPL_HOST_CONFIG_TPL_DIR "${CMAKE_INSTALL_PREFIX}")
set(GEOS_TPL_HOST_CONFIG_CAMP_DIR "${CMAKE_INSTALL_PREFIX}/raja")

# Include the toolchain identity in the host-config name so that an install
# directory makes its compiler/backend requirements visible without opening
# the file.  Use the C++ compiler because it is the compiler used by GEOS and
# is also the host compiler for CUDA builds.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  set(GEOS_TPL_HOST_CONFIG_COMPILER gcc)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
  set(GEOS_TPL_HOST_CONFIG_COMPILER appleclang)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  set(GEOS_TPL_HOST_CONFIG_COMPILER clang)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "IntelLLVM")
  set(GEOS_TPL_HOST_CONFIG_COMPILER intelllvm)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
  set(GEOS_TPL_HOST_CONFIG_COMPILER intel)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "NVHPC")
  set(GEOS_TPL_HOST_CONFIG_COMPILER nvhpc)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "PGI")
  set(GEOS_TPL_HOST_CONFIG_COMPILER pgi)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Cray")
  set(GEOS_TPL_HOST_CONFIG_COMPILER cray)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "XL")
  set(GEOS_TPL_HOST_CONFIG_COMPILER xl)
else()
  string(TOLOWER "${CMAKE_CXX_COMPILER_ID}" GEOS_TPL_HOST_CONFIG_COMPILER)
endif()
if(GEOS_TPL_HOST_CONFIG_COMPILER STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_COMPILER unknown)
endif()

set(GEOS_TPL_HOST_CONFIG_COMPILER_VERSION "${CMAKE_CXX_COMPILER_VERSION}")
if(GEOS_TPL_HOST_CONFIG_COMPILER_VERSION STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_COMPILER_VERSION unknown)
endif()
string(REGEX REPLACE "[^A-Za-z0-9._+-]" "_"
       GEOS_TPL_HOST_CONFIG_COMPILER_VERSION
       "${GEOS_TPL_HOST_CONFIG_COMPILER_VERSION}")

set(GEOS_TPL_HOST_CONFIG_BACKEND cpu)
set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "")
if(ENABLE_CUDA)
  set(GEOS_TPL_HOST_CONFIG_BACKEND cuda)
  if(DEFINED CUDAToolkit_VERSION AND NOT CUDAToolkit_VERSION STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${CUDAToolkit_VERSION}")
  elseif(DEFINED CMAKE_CUDA_COMPILER_VERSION AND NOT CMAKE_CUDA_COMPILER_VERSION STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${CMAKE_CUDA_COMPILER_VERSION}")
  elseif(DEFINED CUDA_VERSION_STRING AND NOT CUDA_VERSION_STRING STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${CUDA_VERSION_STRING}")
  endif()
elseif(ENABLE_HIP)
  set(GEOS_TPL_HOST_CONFIG_BACKEND hip)
  if(DEFINED hip_VERSION AND NOT hip_VERSION STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${hip_VERSION}")
  elseif(DEFINED ROCM_VERSION AND NOT ROCM_VERSION STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${ROCM_VERSION}")
  elseif(DEFINED CMAKE_HIP_COMPILER_VERSION AND NOT CMAKE_HIP_COMPILER_VERSION STREQUAL "")
    set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION "${CMAKE_HIP_COMPILER_VERSION}")
  endif()
endif()
if(NOT GEOS_TPL_HOST_CONFIG_BACKEND STREQUAL "cpu"
   AND GEOS_TPL_HOST_CONFIG_BACKEND_VERSION STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_BACKEND_VERSION unknown)
endif()
string(REGEX REPLACE "[^A-Za-z0-9._+-]" "_"
       GEOS_TPL_HOST_CONFIG_BACKEND_VERSION
       "${GEOS_TPL_HOST_CONFIG_BACKEND_VERSION}")

set(GEOS_TPL_HOST_CONFIG_FILENAME
    "host-config-${GEOS_TPL_HOST_CONFIG_COMPILER}@${GEOS_TPL_HOST_CONFIG_COMPILER_VERSION}-${GEOS_TPL_HOST_CONFIG_BACKEND}")
if(NOT GEOS_TPL_HOST_CONFIG_BACKEND STREQUAL "cpu")
  string(APPEND GEOS_TPL_HOST_CONFIG_FILENAME "@${GEOS_TPL_HOST_CONFIG_BACKEND_VERSION}")
endif()
string(APPEND GEOS_TPL_HOST_CONFIG_FILENAME ".cmake")
message(STATUS "Generated GEOS TPL host config name: ${GEOS_TPL_HOST_CONFIG_FILENAME}")

if(NOT DEFINED CMAKE_CXX_STANDARD OR CMAKE_CXX_STANDARD STREQUAL "")
  set(CMAKE_CXX_STANDARD "${CXX_STANDARD}")
endif()
set(GEOS_TPL_HOST_CONFIG_CXX_STANDARD "${CMAKE_CXX_STANDARD}")

if(DEFINED MPIEXEC_EXECUTABLE AND NOT MPIEXEC_EXECUTABLE STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC "${MPIEXEC_EXECUTABLE}")
elseif(DEFINED MPIEXEC AND NOT MPIEXEC STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC "${MPIEXEC}")
elseif(DEFINED MPI_C_COMPILER AND NOT MPI_C_COMPILER STREQUAL "")
  get_filename_component(GEOS_TPL_HOST_CONFIG_MPI_BIN "${MPI_C_COMPILER}" DIRECTORY)
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC "${GEOS_TPL_HOST_CONFIG_MPI_BIN}/mpirun")
else()
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC "")
endif()
if(DEFINED MPIEXEC_NUMPROC_FLAG AND NOT MPIEXEC_NUMPROC_FLAG STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC_NUMPROC_FLAG "${MPIEXEC_NUMPROC_FLAG}")
else()
  set(GEOS_TPL_HOST_CONFIG_MPIEXEC_NUMPROC_FLAG "-np")
endif()

if(DEFINED ENABLE_HYPRE_DEVICE AND NOT ENABLE_HYPRE_DEVICE STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_HYPRE_DEVICE "${ENABLE_HYPRE_DEVICE}")
else()
  set(GEOS_TPL_HOST_CONFIG_HYPRE_DEVICE CPU)
endif()

if(DEFINED ENABLE_HYPRE_GPU_AWARE_MPI)
  set(GEOS_TPL_HOST_CONFIG_HYPRE_GPU_AWARE_MPI "${ENABLE_HYPRE_GPU_AWARE_MPI}")
else()
  set(GEOS_TPL_HOST_CONFIG_HYPRE_GPU_AWARE_MPI OFF)
endif()
if(DEFINED ENABLE_CALIPER_HYPRE)
  set(GEOS_TPL_HOST_CONFIG_CALIPER_HYPRE "${ENABLE_CALIPER_HYPRE}")
else()
  set(GEOS_TPL_HOST_CONFIG_CALIPER_HYPRE OFF)
endif()

if(ENABLE_HYPRE)
  set(GEOS_TPL_HOST_CONFIG_LA_INTERFACE Hypre)
elseif(ENABLE_TRILINOS)
  set(GEOS_TPL_HOST_CONFIG_LA_INTERFACE Trilinos)
elseif(ENABLE_PETSC)
  set(GEOS_TPL_HOST_CONFIG_LA_INTERFACE Petsc)
else()
  set(GEOS_TPL_HOST_CONFIG_LA_INTERFACE Hypre)
endif()

if(ENABLE_MPI)
  set(GEOS_TPL_HOST_CONFIG_PARMETIS ON)
else()
  set(GEOS_TPL_HOST_CONFIG_PARMETIS OFF)
endif()
set(GEOS_TPL_HOST_CONFIG_METIS ON)
set(GEOS_TPL_HOST_CONFIG_SILO ON)
set(GEOS_TPL_HOST_CONFIG_UNCRUSTIFY ON)
if(CMAKE_HOST_APPLE)
  set(GEOS_TPL_HOST_CONFIG_HYPRE_MIXINT OFF)
else()
  set(GEOS_TPL_HOST_CONFIG_HYPRE_MIXINT ON)
endif()
if(DEFINED MATHPRESSO_DIR AND NOT MATHPRESSO_DIR STREQUAL "")
  set(GEOS_TPL_HOST_CONFIG_MATHPRESSO ON)
else()
  set(GEOS_TPL_HOST_CONFIG_MATHPRESSO OFF)
endif()
set(GEOS_TPL_HOST_CONFIG_DOXYGEN_EXECUTABLE "${CMAKE_INSTALL_PREFIX}/doxygen/bin/doxygen")
set(GEOS_TPL_HOST_CONFIG_UNCRUSTIFY_EXECUTABLE "${CMAKE_INSTALL_PREFIX}/uncrustify/bin/uncrustify")

# CUDA 13 no longer ships nvToolsExt.  Do not propagate a stale superbuild
# option to GEOS when the library is absent from the selected toolkit.
set(GEOS_TPL_HOST_CONFIG_CUDA_NVTOOLSEXT OFF)
if(ENABLE_CUDA)
  find_library(GEOS_TPL_NVTOOLSEXT_LIBRARY
               NAMES nvToolsExt
               PATHS "${CUDA_TOOLKIT_ROOT_DIR}/lib64" "${CUDA_TOOLKIT_ROOT_DIR}/lib"
               NO_DEFAULT_PATH)
  if(GEOS_TPL_NVTOOLSEXT_LIBRARY)
    set(GEOS_TPL_HOST_CONFIG_CUDA_NVTOOLSEXT ON)
  elseif(ENABLE_CUDA_NVTOOLSEXT)
    message(WARNING "ENABLE_CUDA_NVTOOLSEXT is ON, but nvToolsExt was not found; disabling it in the generated GEOS host config")
  endif()
  unset(GEOS_TPL_NVTOOLSEXT_LIBRARY CACHE)
endif()

set(GEOS_TPL_HOST_CONFIG_PREFIX_PATH
    "${CMAKE_INSTALL_PREFIX}/adiak;${CMAKE_INSTALL_PREFIX}/caliper;${CMAKE_INSTALL_PREFIX}/chai;${CMAKE_INSTALL_PREFIX}/conduit;${CMAKE_INSTALL_PREFIX}/fmt;${CMAKE_INSTALL_PREFIX}/hdf5;${CMAKE_INSTALL_PREFIX}/hypre;${CMAKE_INSTALL_PREFIX}/hypredrive;${CMAKE_INSTALL_PREFIX}/mathpresso;${CMAKE_INSTALL_PREFIX}/metis;${CMAKE_INSTALL_PREFIX}/parmetis;${CMAKE_INSTALL_PREFIX}/pugixml;${CMAKE_INSTALL_PREFIX}/raja;${CMAKE_INSTALL_PREFIX}/scotch;${CMAKE_INSTALL_PREFIX}/silo;${CMAKE_INSTALL_PREFIX}/suitesparse;${CMAKE_INSTALL_PREFIX}/superlu_dist;${CMAKE_INSTALL_PREFIX}/vtk")

set(GEOS_TPL_HOST_CONFIG_BUILD "${PROJECT_BINARY_DIR}/${GEOS_TPL_HOST_CONFIG_FILENAME}")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/cmake/geos-host-config.cmake.in"
               "${GEOS_TPL_HOST_CONFIG_BUILD}" @ONLY)
install(FILES "${GEOS_TPL_HOST_CONFIG_BUILD}" DESTINATION .)

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )

add_dependencies( tpl ${build_list}  )

# Keep the installed copy current even when the `tpl` executable itself is
# already up to date after a CMake reconfigure.
set(GEOS_TPL_HOST_CONFIG_INSTALL "${CMAKE_INSTALL_PREFIX}/${GEOS_TPL_HOST_CONFIG_FILENAME}")
add_custom_command(
  OUTPUT "${GEOS_TPL_HOST_CONFIG_INSTALL}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_INSTALL_PREFIX}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${GEOS_TPL_HOST_CONFIG_BUILD}"
          "${GEOS_TPL_HOST_CONFIG_INSTALL}"
  DEPENDS "${GEOS_TPL_HOST_CONFIG_BUILD}"
  COMMENT "Installing generated GEOS host config")
add_custom_target( geos_tpl_host_config ALL
                   DEPENDS "${GEOS_TPL_HOST_CONFIG_INSTALL}" )
add_dependencies( geos_tpl_host_config tpl )

# Clean up
add_custom_command( TARGET tpl POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/config_silo_for_geos
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/config_suitesparse_for_geos
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/build_suitesparse_for_geos
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/install_suitesparse_for_geos
                    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                            ${GEOS_TPL_HOST_CONFIG_BUILD}
                            ${GEOS_TPL_HOST_CONFIG_INSTALL}
                    COMMENT "Installing generated GEOS host config")
