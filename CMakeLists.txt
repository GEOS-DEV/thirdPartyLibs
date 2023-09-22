cmake_minimum_required(VERSION 3.23.1)
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
set( BLT_CXX_STD c++17 CACHE STRING "" FORCE )

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
option( ENABLE_TRILINOS "" ON )
option( ENABLE_PETSC "" OFF )
option( ENABLE_SCOTCH "" ON )
option( ENABLE_SUITESPARSE "" ON )
option( ENABLE_VTK "" ON )
option( ENABLE_VTK_WRAP_PYTHON "" OFF )
option( ENABLE_FESAPI "" ON )

option( ENABLE_NINJA "" OFF )

include(ProcessorCount)
ProcessorCount(NUM_CORES)
			    
set(NUM_PROC ${NUM_CORES} CACHE STRING "")
message( "Running with NUM_PROC = ${NUM_PROC}")

set(TPL_MIRROR_DIR "${CMAKE_SOURCE_DIR}/tplMirror")
set(build_list )

set( CMAKE_VERBOSE_MAKEFILE BOOL OFF "" )

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

string(TOUPPER ${CMAKE_BUILD_TYPE} BUILD_TYPE_UPPER)

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
# UNCRUSTIFY
################################
set(UNCRUSTIFY_DIR "${CMAKE_INSTALL_PREFIX}/uncrustify")
set(UNCRUSTIFY_URL "${TPL_MIRROR_DIR}/uncrustify-401a409.zip")
message(STATUS "Building uncrustify found at ${UNCRUSTIFY_URL}")

ExternalProject_Add( uncrustify
                     URL ${UNCRUSTIFY_URL}
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
  set(DOXYGEN_URL "${TPL_MIRROR_DIR}/doxygen-1.8.20.tar.gz")
  message(STATUS "Building Doxygen found at ${DOXYGEN_URL}")

  ExternalProject_Add( doxygen
                       URL ${DOXYGEN_URL}
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
set(HDF5_URL "${TPL_MIRROR_DIR}/hdf5-1.12.1.tar.gz")
message(STATUS "Building HDF5 found at ${HDF5_URL}")

if( ${ENABLE_MPI} )
  set( HDF5_C_COMPILER ${MPI_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${MPI_CXX_COMPILER} )
else()
  set( HDF5_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
endif()

ExternalProject_Add( hdf5
                     URL ${HDF5_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/hdf5
                     INSTALL_DIR ${HDF5_DIR}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -D CMAKE_C_COMPILER:STRING=${HDF5_C_COMPILER}
                                -D CMAKE_CXX_COMPILER:STRING=${HDF5_CXX_COMPILER}
                                -D CMAKE_C_FLAGS:STRING=${C_FLAGS_NO_WARNINGS}
                                -D CMAKE_C_FLAGS_RELEASE:STRING=${CMAKE_C_FLAGS_RELEASE}
                                -D CMAKE_CXX_FLAGS:STRING=${CXX_FLAGS_NO_WARNINGS}
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D HDF5_ENABLE_PARALLEL:BOOL=${ENABLE_MPI}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS:BOOL=ON
                                -D BUILD_STATIC_LIBS:BOOL=OFF
                                -D BUILD_TESTING:BOOL=OFF
                                -D HDF5_BUILD_EXAMPLES:BOOL=OFF
                                -D HDF5_BUILD_TOOLS:BOOL=OFF
                                -D HDF5_BUILD_UTILS:BOOL=OFF
                                )

list(APPEND HDF5_DEPENDENCIES hdf5 )
list(APPEND build_list hdf5 )


################################
# Conduit
################################
set(CONDUIT_DIR "${CMAKE_INSTALL_PREFIX}/conduit")
set(CONDUIT_URL "${TPL_MIRROR_DIR}/conduit-0.8.2.tar.gz")
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
                                -D BLT_CXX_STD:STRING=c++11
                                )

list(APPEND build_list conduit )


################################
# SILO
################################
set(SILO_DIR "${CMAKE_INSTALL_PREFIX}/silo")
set(SILO_URL "${TPL_MIRROR_DIR}/silo-4.11-bsd.tgz")
message(STATUS "Building SILO found at ${SILO_URL}")


ExternalProject_Add( silo
                     URL ${SILO_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/silo
                     INSTALL_DIR ${SILO_DIR}
                     PATCH_COMMAND patch  src/hdf5_drv/H5FDsilo.c  < ${TPL_MIRROR_DIR}/silo-4.11.patch
                     DEPENDS ${HDF5_DEPENDENCIES}
                     CONFIGURE_COMMAND ../silo/configure
                                          CC=${HDF5_C_COMPILER}
                                          CFLAGS=${HDF5_C_FLAGS}
                                          CXX=${HDF5_CXX_COMPILER}
                                          --prefix=<INSTALL_DIR>
                                          --disable-fortran
                                          --enable-optimization
                                          --with-hdf5=${HDF5_DIR}/include,${HDF5_DIR}/lib
                                          LIBS=-ldl
                                          --disable-silex
                                          --enable-shared=no
                                          --enable-static=yes
                                          --build=${SILO_BUILD_TYPE}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND build_list silo )


################################
# RAJA
################################


set(RAJA_DIR "${CMAKE_INSTALL_PREFIX}/raja")
set(RAJA_URL "${TPL_MIRROR_DIR}/RAJA-v2023.06.1.tar.gz")


message(STATUS "Building RAJA found at ${RAJA_URL}")

ExternalProject_Add( raja
                     URL ${RAJA_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/raja
                     INSTALL_DIR ${RAJA_DIR}
                     DEPENDS ${RAJA_DEPENDS}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND} VERBOSE=1
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER:PATH=${CMAKE_CXX_COMPILER}
                                -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D RAJA_ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}
                                -D CMAKE_CUDA_FLAGS:STRING=${RAJA_CUDA_FLAGS}
                                -D ENABLE_TESTS:BOOL=OFF
                                -D ENABLE_EXAMPLES:BOOL=OFF
                                -D ENABLE_OPENMP:BOOL=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                    )

list(APPEND build_list raja )


################################
# CHAI
################################
set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
set(CHAI_URL "${TPL_MIRROR_DIR}/chai-2023.06.0.tar.gz")
message(STATUS "Building CHAI found at ${CHAI_URL}")

ExternalProject_Add( chai
                     PREFIX ${PROJECT_BINARY_DIR}/chai
                     URL ${CHAI_URL}
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
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CMAKE_CUDA_ARCHITECTURES:STRING=${CMAKE_CUDA_ARCHITECTURES}
                                -D CMAKE_CUDA_FLAGS:STRING=${CHAI_CUDA_FLAGS}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
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
    set(ADIAK_URL "${TPL_MIRROR_DIR}/Adiak-0.2.2.tar.gz")
    message(STATUS "Building Adiak found at ${ADIAK_URL}")

    ExternalProject_Add( adiak
                         URL ${ADIAK_URL}
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
                                    -D BLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                       )


    set(CALIPER_DIR "${CMAKE_INSTALL_PREFIX}/caliper")
    set(CALIPER_URL "${TPL_MIRROR_DIR}/Caliper-2.10.0.tar.gz")
    message(STATUS "Building Caliper found at ${CALIPER_URL}")

    set(CALIPER_WITH_CUPTI OFF)

    if(ENABLE_CALIPER_WITH_CUPTI)
        set(CALIPER_WITH_CUPTI ON)
    endif()

    ExternalProject_Add( caliper
                         URL ${CALIPER_URL}
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
                                    -D WITH_PAPI:BOOL=${ENABLE_PAPI}
                                    -D PAPI_PREFIX:STRING=${PAPI_PREFIX}
                                    -D WITH_ADIAK:BOOL=ON
                                    -D adiak_DIR:STRING=${ADIAK_DIR}/lib/cmake/adiak/
                                    -D WITH_CUPTI=${CALIPER_WITH_CUPTI}
                                    -D WITH_NVPROF=${ENABLE_CUDA}
                       )

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
    set(MATHPRESSO_URL "${TPL_MIRROR_DIR}/mathpresso-2015-12-15.tar.gz")
    set(ASMJIT_URL "${TPL_MIRROR_DIR}/asmjit-2016-07-20.tar.gz")
    message(STATUS "Building MATHPRESSO found at ${MATHPRESSO_URL}")

    ExternalProject_Add( mathpresso
                         URL ${MATHPRESSO_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/mathpresso
                         INSTALL_DIR ${MATHPRESSO_DIR}
                         PATCH_COMMAND cd ${PROJECT_BINARY_DIR} && tar -xzvf ${ASMJIT_URL}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND mkdir -p <INSTALL_DIR>/include &&
                                         mkdir -p <INSTALL_DIR>/lib &&
                                         make INSTALL_DIR=<INSTALL_DIR> install &&
                                         cp libmathpresso.a <INSTALL_DIR>/lib/
                         CMAKE_ARGS -D MATHPRESSO_STATIC=TRUE
                                    -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                    -D ASMJIT_DIR=${PROJECT_BINARY_DIR}/asmjit-master
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
set(PUGIXML_URL "${TPL_MIRROR_DIR}/pugixml-1.13.tar.gz")

message(STATUS "Building PUGIXML found at ${PUGIXML_URL}")

ExternalProject_Add( pugixml
                     PREFIX ${PROJECT_BINARY_DIR}/pugixml
                     URL ${PUGIXML_URL}
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
    set(TRILINOS_URL "${TPL_MIRROR_DIR}/Trilinos-trilinos-release-13-4-1.tar.gz")

    message(STATUS "Building TRILINOS found at ${TRILINOS_URL}")

    set(TRILINOS_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS}")
    set(TRILINOS_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS}")

    if( ENABLE_MKL )
        set( TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                                 -D TPL_ENABLE_MKL:BOOL=ON
                                 -D TPL_MKL_INCLUDE_DIRS:PATH=${MKL_INCLUDE_DIRS}
                                 -D TPL_MKL_LIBRARIES:STRING=${MKL_LIBRARIES})
    endif()

    if ( ENABLE_ESSL )
        set( TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                                 -D HAVE_dggsvd3:BOOL=ON)
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
                                    -D CMAKE_Fortran_FLAGS_RELEASE:STRING=${CMAKE_Fortran_FLAGS_RELEASE}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
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
                                    -D Trilinos_ENABLE_ML:BOOL=ON
                                    -D Trilinos_ENABLE_Thyra:BOOL=ON
                                    -D Trilinos_ENABLE_STK:BOOL=OFF
                                    -D Trilinos_ENABLE_TrilinosCouplings:BOOL=ON
                                    -D Trilinos_ENABLE_EXPLICIT_INSTANTIATION:BOOL=ON
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
set(PARMETIS_URL "${TPL_MIRROR_DIR}/parmetis-4.0.3-IDXTYPEWIDTH_64.tar.gz")

if( ${ENABLE_MPI} )
  message(STATUS "Building PARMETIS found at ${PARMETIS_URL}")

  ExternalProject_Add( parmetis
                       PREFIX ${PROJECT_BINARY_DIR}/parmetis
                       URL ${PARMETIS_URL}
                       INSTALL_DIR ${PARMETIS_DIR}
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
                     INSTALL_DIR ${METIS_DIR}
                     SOURCE_SUBDIR metis
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
if( ENABLE_MPI )
  set(SUPERLU_DIR "${CMAKE_INSTALL_PREFIX}/superlu_dist")
  set(SUPERLU_URL "${TPL_MIRROR_DIR}/superlu_dist-0f6efc3.tar.gz")

  set(PARMETIS_INCLUDE_DIRS ${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include)
  set(PARMETIS_LIBRARIES ${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a)

  message(STATUS "Building SUPERLU found at ${SUPERLU_URL}")
  ExternalProject_Add( superlu_dist
                       PREFIX ${PROJECT_BINARY_DIR}/superlu_dist
                       URL ${SUPERLU_URL}
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
                                  -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                  -D CMAKE_C_FLAGS_RELEASE=${CMAKE_C_FLAGS_RELEASE}
                                  -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                  -D CMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE}
                                  -D CMAKE_Fortran_FLAGS=${CMAKE_Fortran_FLAGS}
                                  -D CMAKE_Fortran_FLAGS_RELEASE=${CMAKE_Fortran_FLAGS_RELEASE}
                                  -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                  -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                  -D enable_openmp=${ENABLE_OPENMP}
          )

  list(APPEND build_list superlu_dist )
endif()

################################
# HYPRE
################################

if( ENABLE_HYPRE )
  set( HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre" )
  set( HYPRE_URL "${TPL_MIRROR_DIR}/hypre-2.29.0.tar.gz")
  set( HYPRE_DEPENDS "" )


  message(STATUS "Building HYPRE found at ${HYPRE_URL}")

  set( HYPRE_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HYPRE_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
  set( HYPRE_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )
  set( HYPRE_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}}" )
  set( HYPRE_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS} ${CMAKE_CXX_FLAGS_${BUILD_TYPE_UPPER}}" )
  set( HYPRE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_${BUILD_TYPE_UPPER}}" )

  if( ENABLE_MPI )
    set( HYPRE_C_COMPILER ${MPI_C_COMPILER} )
    set( HYPRE_CXX_COMPILER ${MPI_CXX_COMPILER} )
    set( HYPRE_Fortran_COMPILER ${MPI_Fortran_COMPILER} )
    set( HYPRE_SUPERLU_LIBS "${SUPERLU_DIR}/lib/libsuperlu_dist.a ${PARMETIS_DIR}/lib/libparmetis.a ${METIS_DIR}/lib/libmetis.a -lstdc++" )
    if( ENABLE_OPENMP )
      set( HYPRE_SUPERLU_LIBS "${HYPRE_SUPERLU_LIBS} ${OpenMP_C_FLAGS}" ) # Sergey: why is this needed?
    endif()
    set( HYPRE_SUPERLU_FLAGS "--with-dsuperlu --with-dsuperlu-include=${SUPERLU_DIR}/include --with-dsuperlu-lib=\"${HYPRE_SUPERLU_LIBS}\"" )
    list( APPEND HYPRE_DEPENDS superlu_dist )
  endif()

  if( ENABLE_OPENMP )
    set( HYPRE_OPENMP_FLAG --with-openmp )
    set( HYPRE_C_FLAGS "${HYPRE_C_FLAGS} ${OpenMP_C_FLAGS}" )
    set( HYPRE_CXX_FLAGS "${HYPRE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}" )
  endif()

  if( ENABLE_HYPRE_DEVICE STREQUAL "CUDA" )
    list( APPEND HYPRE_DEPENDS chai )
    string( SUBSTRING ${CUDA_ARCH} 3 -1 HYPRE_CUDA_SM ) # sm_XY -> XY
    set( HYPRE_CUDA_FLAGS "--with-cuda --with-cuda-home=${CUDA_TOOLKIT_ROOT_DIR} \
    	 		   --enable-cusparse \
			   --enable-unified-memory \
			   --with-gpu-arch=${HYPRE_CUDA_SM} \
    	 		   --with-umpire \
			   --with-umpire-include=${CHAI_DIR}/include \
			   --with-umpire-lib-dirs=${CHAI_DIR}/lib \
  			   --with-umpire-libs=umpire " )

  elseif( ENABLE_HYPRE_DEVICE STREQUAL "HIP" )
    message( FATAL_ERROR "hip tpls build only supported through spack" )
  endif()

  if( CMAKE_HOST_APPLE )
    set( HYPRE_INT_FLAG "--enable-bigint" )
  else()
    set( HYPRE_INT_FLAG "--enable-mixedint" )
  endif()

  if( ENABLE_CALIPER_HYPRE )
    set( HYPRE_CALIPER_FLAGS "--with-caliper --with-caliper-include=\"${CALIPER_DIR}/include\" --with-caliper-lib=\"${CALIPER_DIR}/libs/caliper.a\"" )
    list( APPEND HYPRE_DEPENDS caliper )
  endif()

  if( CMAKE_BUILD_TYPE MATCHES Debug )
    set( HYPRE_DEBUG_FLAG "--enable-debug" )
  endif()

  file( WRITE ${PROJECT_BINARY_DIR}/config_hypre_for_geosx "\
  ./configure \
  CC=${HYPRE_C_COMPILER} \
  CFLAGS=\"${HYPRE_C_FLAGS}\" \
  CXX=${HYPRE_CXX_COMPILER} \
  CXXFLAGS=\"${HYPRE_CXX_FLAGS}\" \
  FC=${HYPRE_Fortran_COMPILER} \
  FCFLAGS=\"${HYPRE_Fortran_FLAGS}\" \
  --prefix=${HYPRE_DIR} \
  ${HYPRE_DEBUG_FLAG} \
  ${HYPRE_INT_FLAG} \
  --with-blas-lib=\"${BLAS_LINK_LINE}\" \
  --with-lapack-lib=\"${LAPACK_LINK_LINE}\" \
  ${HYPRE_SUPERLU_FLAGS} \
  ${HYPRE_OPENMP_FLAG} \
  ${HYPRE_CUDA_FLAGS}\
  ${HYPRE_CALIPER_FLAGS}\n")

  ExternalProject_Add( hypre
                       URL ${HYPRE_URL}
                       PREFIX ${PROJECT_BINARY_DIR}/hypre
                       INSTALL_DIR ${HYPRE_DIR}
                       DEPENDS ${HYPRE_DEPENDS}
                       BINARY_DIR ${PROJECT_BINARY_DIR}/hypre/src/hypre/src
                       CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_hypre_for_geosx && . ${PROJECT_BINARY_DIR}/config_hypre_for_geosx
                       BUILD_COMMAND make -j ${NUM_PROC} VERBOSE=1
                       INSTALL_COMMAND make install
                       )

  list( APPEND build_list hypre )
endif()

################################
# SUITESPARSE
################################
if(ENABLE_SUITESPARSE)
    set(SUITESPARSE_DIR "${CMAKE_INSTALL_PREFIX}/suitesparse")
    set(SUITESPARSE_URL "${TPL_MIRROR_DIR}/SuiteSparse-5.10.1.tar.gz")

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

    file(WRITE ${PROJECT_BINARY_DIR}/config_suitesparse_for_geosx "make config ${SUITESPARSE_CONFIG_ARGS}\n" )
    file(WRITE ${PROJECT_BINARY_DIR}/build_suitesparse_for_geosx ${SUITESPARSE_BUILD_CMD})
    file(WRITE ${PROJECT_BINARY_DIR}/install_suitesparse_for_geosx ${SUITESPARSE_INSTALL_CMD})

    ExternalProject_Add( suitesparse
                         URL ${SUITESPARSE_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/suitesparse
                         INSTALL_DIR ${SUITESPARSE_DIR}
                         DEPENDS ${SUITESPARSE_DEPENDS}
                         BINARY_DIR ${PROJECT_BINARY_DIR}/suitesparse/src/suitesparse
                         CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_suitesparse_for_geosx && . ${PROJECT_BINARY_DIR}/config_suitesparse_for_geosx
                         BUILD_COMMAND cat ${PROJECT_BINARY_DIR}/build_suitesparse_for_geosx && . ${PROJECT_BINARY_DIR}/build_suitesparse_for_geosx
                         INSTALL_COMMAND cat ${PROJECT_BINARY_DIR}/install_suitesparse_for_geosx && . ${PROJECT_BINARY_DIR}/install_suitesparse_for_geosx
                       )

    list(APPEND build_list suitesparse )
endif(ENABLE_SUITESPARSE)

################################
# SCOTCH
################################

if( ENABLE_SCOTCH )
    set( SCOTCH_DIR "${CMAKE_INSTALL_PREFIX}/scotch" )
    set( SCOTCH_URL "${TPL_MIRROR_DIR}/scotch-v7.0.3.tar.gz" )

    message( STATUS "Building SCOTCH found at ${SCOTCH_URL}" )

    if( NOT ENABLE_MPI )
        message( FATAL_ERROR "Building Scotch without MPI is not supported." )
    endif()

    set( SCOTCH_C_FLAGS "${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UPPER}} -fPIC -DINTSIZE64 -DIDXSIZE64 -DCOMMON_RANDOM_FIXED_SEED -DSCOTCH_RENAME -DSCOTCH_METIS_PREFIX -Drestrict=__restrict" )
    set( SCOTCH_LD_FLAGS "-lm" )

    # OSX does not have pthread barriers used by Scotch
    if( NOT CMAKE_HOST_APPLE )
        set( SCOTCH_C_FLAGS "${SCOTCH_C_FLAGS} -DCOMMON_PTHREAD -DSCOTCH_PTHREAD_MPI" )
        set( SCOTCH_LD_FLAGS "${SCOTCH_LD_FLAGS} -pthread" )
    endif()

    set( SCOTCH_CONFIG "\
EXE       =
OBJ       = .o
LIB       = .a
MAKE      = make
AR        = ar
ARFLAGS   = -ruv
CAT       = cat
CCS       = ${MPI_C_COMPILER}
CCP       = ${MPI_C_COMPILER}
CCD       = ${MPI_C_COMPILER}
CFLAGS    = ${SCOTCH_C_FLAGS}
CLIBFLAGS =
LDFLAGS   = ${SCOTCH_LD_FLAGS}
CP        = cp
FLEX      = flex
LN        = ln
MKDIR     = mkdir -p
MV        = mv
RANLIB    = ranlib
BISON     = bison
prefix    = ${SCOTCH_DIR}
" )

    file( WRITE ${PROJECT_BINARY_DIR}/scotch_makefile.inc "${SCOTCH_CONFIG}")
    set( SCOTCH_BUILD_DIR "${PROJECT_BINARY_DIR}/scotch/src/scotch/src" )
    if ( NOT DEFINED SCOTCH_NUM_PROC )
      set( SCOTCH_NUM_PROC 2 )
    endif()
    ExternalProject_Add( scotch
                         URL ${SCOTCH_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/scotch
                         INSTALL_DIR ${SCOTCH_DIR}
                         BINARY_DIR ${SCOTCH_BUILD_DIR}
                         CONFIGURE_COMMAND cp ${PROJECT_BINARY_DIR}/scotch_makefile.inc ${SCOTCH_BUILD_DIR}/Makefile.inc
                         BUILD_COMMAND make -j 2 ptscotch scotch ptesmumps esmumps
                         INSTALL_COMMAND make install
                       )

    list(APPEND build_list scotch )

endif()

################################
# PETSC
################################

if( ENABLE_PETSC )
    set(PETSC_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/petsc")
    set(PETSC_URL "${TPL_MIRROR_DIR}/petsc-3.19.4.tar.gz")

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

    file(WRITE ${PROJECT_BINARY_DIR}/config_petsc_for_geosx "\
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
                         PREFIX ${PROJECT_BINARY_DIR}/petsc #outer petsc directory
                         DEPENDS ${PETSC_DEPENDS}
                         BINARY_DIR ${PROJECT_BINARY_DIR}/petsc/src/petsc
                         INSTALL_DIR ${PETSC_INSTALL_DIR}
                         CONFIGURE_COMMAND cat ${PROJECT_BINARY_DIR}/config_petsc_for_geosx && . ${PROJECT_BINARY_DIR}/config_petsc_for_geosx
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
    set( VTK_URL "${TPL_MIRROR_DIR}/VTK-9.2.6.tar.gz" )

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
                         INSTALL_DIR ${VTK_DIR}
                         PATCH_COMMAND patch -p0 < ${TPL_MIRROR_DIR}/vtkXMLReader-fpe.patch
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND "${TPL_INSTALL_COMMAND}"
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_ARGS -D CMAKE_C_COMPILER=${VTK_C_COMPILER}
                                    -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                    -D CMAKE_CXX_COMPILER=${VTK_CXX_COMPILER}
				    -D CMAKE_CXX_FLAGS:STRING=${CMAKE_CXX_FLAGS}		
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
                                    -D VTK_BUILD_TESTING=OFF
                                    -D VTK_LEGACY_REMOVE=ON )

    list( APPEND build_list vtk )
endif( ENABLE_VTK )

################################
# FMT
################################
set(FMT_DIR "${CMAKE_INSTALL_PREFIX}/fmt")
set(FMT_URL "${TPL_MIRROR_DIR}/fmt-10.0.0.tar.gz")

message(STATUS "Building FMT found at ${FMT_URL}")

ExternalProject_Add( fmt
                     PREFIX ${PROJECT_BINARY_DIR}/fmt
                     URL ${FMT_URL}
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
                                -D CMAKE_CXX_STANDARD=14
                                -D CMAKE_CXX_VISIBILITY_PRESET:STRING=default
                                -D CMAKE_VISIBILITY_INLINES_HIDDEN:BOOL=OFF
                                -D FMT_TEST:BOOL=OFF )

list(APPEND build_list fmt)

################################
# Fesapi
################################

if( ENABLE_FESAPI )

    #
    # ENABLE Boost
    #
    set(BOOST_DIR "${CMAKE_INSTALL_PREFIX}/boost")
    set(BOOST_URL "${TPL_MIRROR_DIR}/boost_1_67_0.tar.gz")
    message(STATUS "Extract Boost found at ${BOOST_URL}")

    set(BOOST_ROOT ${CMAKE_CURRENT_BINARY_DIR}/boost/src/boost/ CACHE STRING "Set the value of BOOST_ROOT to point to the root folder of your boost install." FORCE)

    ExternalProject_Add( boost
                        URL ${BOOST_URL}
                        PREFIX ${PROJECT_BINARY_DIR}/boost
                        INSTALL_DIR ${BOOST_DIR}
                        CONFIGURE_COMMAND ""
                        BUILD_COMMAND ""
                        INSTALL_COMMAND ""
                        BUILD_IN_SOURCE 1)

    list(APPEND build_list boost)


    #
    # ENABLE Minizip
    #

    # Depending on the platform, the install directory could be 'lib' or 'lib64'.
    # Fesapi doesn't use CMake Targets to import Minizip but needs an explicit
    # path thus it has to be fixed regardless of the platform
    set( MINIZIP_CMAKE_INSTALL_LIBDIR "lib" )

    set(MINIZIP_DIR "${CMAKE_INSTALL_PREFIX}/minizip")
    set(MINIZIP_URL "${TPL_MIRROR_DIR}/Minizip-1.1_cmake0.1.tar.gz")
    message(STATUS "Building Minizip found at ${MINIZIP_URL}")

    ExternalProject_Add( minizip
                        URL ${MINIZIP_URL}
                        PREFIX ${PROJECT_BINARY_DIR}/minizip
                        INSTALL_DIR ${MINIZIP_DIR}
                        BUILD_COMMAND make -j ${NUM_PROC}
                        INSTALL_COMMAND make install
                        CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                                -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                -DCMAKE_PREFIX_PATH:PATH=<INSTALL_DIR>
                                -DCMAKE_INSTALL_LIBDIR=${MINIZIP_CMAKE_INSTALL_LIBDIR}
                                )

    list(APPEND build_list minizip)

    if( ENABLE_MPI )
        set( FESAPI_C_COMPILER ${MPI_C_COMPILER} )
        set( FESAPI_CXX_COMPILER ${MPI_CXX_COMPILER} )
    else()
        set( FESAPI_C_COMPILER ${CMAKE_C_COMPILER} )
        set( FESAPI_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
    endif( ENABLE_MPI )

    #
    # Then Fesapi
    #
    set(FESAPI_DIR "${CMAKE_INSTALL_PREFIX}/fesapi")
    set(FESAPI_URL "${TPL_MIRROR_DIR}/fesapi-2.4.0.0.tar.gz")
    message(STATUS "Building Fesapi found at ${FESAPI_URL}")

    ExternalProject_Add( fesapi
                        URL ${FESAPI_URL}
                        PREFIX ${PROJECT_BINARY_DIR}/fesapi
                        INSTALL_DIR ${FESAPI_DIR}
                        BUILD_COMMAND make -j ${NUM_PROC}
                        INSTALL_COMMAND make install
                        DEPENDS hdf5 minizip boost
                        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                                    -DCMAKE_C_COMPILER=${FESAPI_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${FESAPI_CXX_COMPILER}
                                    -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                    -DCMAKE_PREFIX_PATH:PATH=${HDF5_DIR}
                                    -DMINIZIP_INCLUDE_DIR:PATH=${MINIZIP_DIR}/include
                                    -DMINIZIP_LIBRARY_RELEASE:PATH=${MINIZIP_DIR}/lib/libminizip.a
                                    -DBoost_NO_SYSTEM_PATHS:BOOL=TRUE
                                    -DBoost_NO_BOOST_CMAKE:BOOL=TRUE
                                    -DBoost_INCLUDE_DIR:PATH=${CMAKE_CURRENT_BINARY_DIR}/boost/src/boost
                                    -DWITH_EXAMPLE:BOOL=OFF
                                    -DWITH_DOTNET_WRAPPING:BOOL=OFF
                                    -DWITH_JAVA_WRAPPING:BOOL=OFF
                                    -DWITH_PYTHON_WRAPPING:BOOL=OFF
                                    -DWITH_RESQML2_2:BOOL=OFF
                                    -DWITH_TEST:BOOL=OFF
                                    # Next lines prevent compilation
                                    # errors due to an issue with the
                                    # detection of the hdf5 version in
                                    # fesapi < 2.4.0.0 (on CentOS, for
                                    # Release build of hdf5, see
                                    # https://github.com/F2I-Consulting/fesapi/issues/326)
                                    # It should be possible to remove it when
                                    # fesapi-2.9.0.0 will be released
                                    -DWITH_LOCAL_HDF5:BOOL=ON
                                    -DHDF5_INCLUDE_DIRS:PATH=${HDF5_DIR}/include
                                    -DHDF5_LIBRARIES:PATH=${HDF5_DIR}/lib/libhdf5${CMAKE_SHARED_MODULE_SUFFIX}
                                  )

    list(APPEND build_list fesapi )

endif()

################################
# Create target that builds all dependencies
################################
message(STATUS "Building = ${build_list}")

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )

add_dependencies( tpl ${build_list}  )

# Clean up
add_custom_command( TARGET tpl POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/config_suitesparse_for_geosx
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/build_suitesparse_for_geosx
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/install_suitesparse_for_geosx )
