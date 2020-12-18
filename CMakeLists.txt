cmake_minimum_required(VERSION 3.9)
################################
# GEOS_TPL
################################
project(geosx_tpl LANGUAGES C CXX Fortran)

################################
# BLT
################################
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

option( ENABLE_CALIPER "" OFF )
option( ENABLE_TRILINOS "" ON )
option( ENABLE_PETSC "" OFF )
#if( CMAKE_HOST_APPLE )
#    option( ENABLE_PETSC "" OFF )
#else()
#    option( ENABLE_PETSC "" ON )
#endif()
option( ENABLE_SUITESPARSE "" ON )

option( ENABLE_VTK "" ON )

option( ENABLE_NINJA "" OFF )

set(NUM_PROC "16" CACHE STRING "")
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
# ASTYLE
################################
set(ASTYLE_DIR "${CMAKE_INSTALL_PREFIX}/astyle")
set(ASTYLE_URL "${TPL_MIRROR_DIR}/astyle_3.1_linux.tar.gz")
message(STATUS "Building AStyle found at ${ASTYLE_URL}")

ExternalProject_Add( astyle
                     URL ${ASTYLE_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/astyle
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_DIR ${ASTYLE_DIR}
                     INSTALL_COMMAND make DESTDIR=${ASTYLE_DIR} install
                     CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_CXX_STANDARD=11
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                )

list(APPEND build_list astyle )


################################
# Doxygen
################################

if( ENABLE_DOXYGEN )

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
set(HDF5_URL "${TPL_MIRROR_DIR}/hdf5-1.10.5.tar.gz")
message(STATUS "Building HDF5 found at ${HDF5_URL}")

if( ${ENABLE_MPI} )
  set( HDF5_C_COMPILER ${MPI_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${MPI_CXX_COMPILER} )
  set( HDF5_ENABLE_PARALLEL "--enable-parallel")
else()
  set( HDF5_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HDF5_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
  set( HDF5_ENABLE_PARALLEL "")
endif()

set(HDF5_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_RELEASE}")

ExternalProject_Add( hdf5
                     URL ${HDF5_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/hdf5
                     INSTALL_DIR ${HDF5_DIR}
                     CONFIGURE_COMMAND ../hdf5/configure
                                       CC=${HDF5_C_COMPILER}
                                       CXX=${HDF5_CXX_COMPILER}
                                       --enable-build-mode=production
                                       --prefix=<INSTALL_DIR>
                                       ${HDF5_ENABLE_PARALLEL}
                                       --enable-shared=no
                                       CFLAGS=${HDF5_C_FLAGS}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND HDF5_DEPENDENCIES hdf5 )
list(APPEND build_list hdf5 )


################################
# Conduit
################################
set(CONDUIT_DIR "${CMAKE_INSTALL_PREFIX}/conduit")
set(CONDUIT_URL "${TPL_MIRROR_DIR}/conduit-v0.5.0-src-with-blt.tar.gz")
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


if (NOT ENABLE_TRIBOL)
################################
# Axom
################################
set(AXOM_DIR "${CMAKE_INSTALL_PREFIX}/axom")
set(AXOM_URL "${TPL_MIRROR_DIR}/Axom-v0.3.1.tar.gz")

message(STATUS "Building Axom found at ${AXOM_URL}")

if( ${ENABLE_MPI} )
    set( AXOM_ENABLE_LUMBERJACK ON )
else()
    set( AXOM_ENABLE_LUMBERJACK OFF )
endif()

ExternalProject_Add( axom
                     URL ${AXOM_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/axom
                     SOURCE_SUBDIR src
                     INSTALL_DIR ${AXOM_DIR}
                     DEPENDS ${HDF5_DEPENDENCIES} conduit
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D AXOM_ENABLE_DOCS=OFF
                                -D AXOM_ENABLE_BENCHMARKS=OFF
                                -D AXOM_ENABLE_EXAMPLES=OFF
                                -D ENABLE_FORTRAN=OFF
                                -D AXOM_ENABLE_TESTS=OFF
                                -D ENABLE_TESTS:BOOL=OFF
                                -D CMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D BLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                -D HDF5_DIR=${HDF5_DIR}
                                -D CONDUIT_DIR=${CONDUIT_DIR}
                                -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D ENABLE_MPI=${ENABLE_MPI}
                                -D AXOM_ENABLE_ALL_COMPONENTS:BOOL=OFF
                                -D MPI_C_COMPILER=${MPI_C_COMPILER}
                                -D MPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D AXOM_ENABLE_SLIC=ON
                                -D AXOM_ENABLE_LUMBERJACK=${AXOM_ENABLE_LUMBERJACK}
                                -D CMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -D BLT_CXX_STD:STRING=c++11
                                )

list(APPEND build_list axom )
endif (NOT ENABLE_TRIBOL)


################################
# SILO
################################
set(SILO_DIR "${CMAKE_INSTALL_PREFIX}/silo")
set(SILO_URL "${TPL_MIRROR_DIR}/silo-4.10.3.mpiposix_patch.tar.gz")
message(STATUS "Building SILO found at ${SILO_URL}")


ExternalProject_Add( silo
                     URL ${SILO_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/silo
                     INSTALL_DIR ${SILO_DIR}
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
# RAJA + CAMP
################################


# if( NOT EXTERNAL_CAMP_SOURCE_DIR )
#   set(CAMP_DIR "${CMAKE_INSTALL_PREFIX}/camp")
#   set(CAMP_URL "${TPL_MIRROR_DIR}/camp-cef6f71c5e21836eed381f80cb328126202d512e.tar.gz")
#   message(STATUS "Using CAMP found at ${CAMP_URL}")

#   ExternalProject_Add( camp
#                        URL ${CAMP_URL}
#                        PREFIX ${PROJECT_BINARY_DIR}/camp
#                        INSTALL_DIR ${CAMP_DIR}
#                        BUILD_COMMAND ${TPL_BUILD_COMMAND}
#                        INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
#                        CMAKE_GENERATOR ${TPL_GENERATOR}
#                        CMAKE_ARGS -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
#                      )
#   set( EXTERNAL_CAMP_SOURCE_DIR "${PROJECT_BINARY_DIR}/camp/src/camp")
#   set( RAJA_DEPENDS camp )
# endif()


set(RAJA_DIR "${CMAKE_INSTALL_PREFIX}/raja")
set(RAJA_URL "${TPL_MIRROR_DIR}/RAJA-v0.12.1.tar.gz")
message(STATUS "Building RAJA found at ${RAJA_URL}")

ExternalProject_Add( raja
                     URL ${RAJA_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/raja
                     INSTALL_DIR ${RAJA_DIR}
                     DEPENDS ${RAJA_DEPENDS}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER:PATH=${CMAKE_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS:PATH=${CMAKE_CXX_FLAGS}
                                -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CUDA_ARCH:CACHE=${CUDA_ARCH}
                                -D CMAKE_CUDA_FLAGS:STRING=${RAJA_CUDA_FLAGS}
                                -D ENABLE_TESTS:BOOL=OFF
                                -D ENABLE_EXAMPLES:BOOL=OFF
                                -D ENABLE_OPENMP:BOOL=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                # -D EXTERNAL_CAMP_SOURCE_DIR:PATH=${EXTERNAL_CAMP_SOURCE_DIR}
                    )

list(APPEND build_list raja )

if (ENABLE_TRIBOL)

   set(UMPIRE_DIR "${CMAKE_INSTALL_PREFIX}/umpire")
   set(UMPIRE_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/umpire.git")
   set(UMPIRE_TAG "feature/benliu/slideWorld")

   if (EXISTS ${UMPIRE_DIR})
       message(STATUS "Using existing UMPIRE found at ${UMPIRE_DIR}")
       list(APPEND existing_list umpire)
   else()
       message(STATUS "Building UMPIRE found at ${UMPIRE_TAG}")

       ExternalProject_Add( umpire
                            PREFIX ${PROJECT_BINARY_DIR}/umpire
                            GIT_REPOSITORY ${UMPIRE_REPO}
                            GIT_TAG ${UMPIRE_TAG}
                            INSTALL_DIR ${UMPIRE_DIR}
                            DEPENDS raja
                            BUILD_COMMAND make -j ${NUM_PROC}
                            INSTALL_COMMAND make install
                            CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                       -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                       -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                       -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                       -DCMAKE_CXX_FLAGS=${TPL_CXX_GID64}
                                       -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                       -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                       -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                       -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                       -Dcamp_DIR=${RAJA_DIR}/lib/cmake/camp
                                       -DENABLE_CUDA=OFF
                                       -DENABLE_C=ON
                                       -DENABLE_FORTRAN=OFF
                                       -DENABLE_TESTS=OFF
                                       -DENABLE_BENCHMARKS=OFF
                                       -DENABLE_GMOCK=OFF
                                       -DENABLE_EXAMPLES=OFF
                                       -DENABLE_TOOLS=OFF
                                       -DENABLE_OPENMP=OFF
                                       -DCMAKE_DEBUG_POSTFIX=)

       list(APPEND build_list umpire)
   endif()
endif (ENABLE_TRIBOL)


################################
# CHAI
################################
set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
set(CHAI_URL "${TPL_MIRROR_DIR}/chai-0755757.tar.gz")
message(STATUS "Building CHAI found at ${CHAI_URL}")

ExternalProject_Add( chai
                     PREFIX ${PROJECT_BINARY_DIR}/chai
                     URL ${CHAI_URL}
                     INSTALL_DIR ${CHAI_DIR}
                     DEPENDS raja umpire
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                -D CMAKE_CXX_FLAGS_RELEASE:STRING=${CMAKE_CXX_FLAGS_RELEASE}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=${CMAKE_VERBOSE_MAKEFILE}
                                -D ENABLE_CUDA:BOOL=${ENABLE_CUDA}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CMAKE_CUDA_FLAGS:STRING=${RAJA_CUDA_FLAGS}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D ENABLE_PICK=ON
                                -D ENABLE_TESTS=OFF
                                -D ENABLE_BENCHMARKS=OFF
                                -D ENABLE_EXAMPLES=OFF
                                -D ENABLE_DOCS=OFF
                                -D ENABLE_DOXYGEN=OFF
                                -D ENABLE_SPHINX=OFF
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D ENABLE_RAJA_PLUGIN=ON
                                -D RAJA_DIR=${RAJA_DIR}/share/raja/cmake
                                -D camp_DIR=${RAJA_DIR}/lib/cmake/camp
                                -D umpire_DIR=${UMPIRE_DIR}/share/umpire/cmake
                    )

list(APPEND build_list chai )


################################
# FPARSER
################################
set(FPARSER_DIR "${CMAKE_INSTALL_PREFIX}/fparser")
set(FPARSER_URL "${TPL_MIRROR_DIR}/fparser4.5.2.zip")
message(STATUS "Building FPARSER found at ${FPARSER_URL}")

ExternalProject_Add( fparser
                     URL ${FPARSER_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/fparser
                     INSTALL_DIR ${FPARSER_DIR}
                     CONFIGURE_COMMAND ""
                     BUILD_COMMAND ${CMAKE_CXX_COMPILER} -c -DFP_NO_SUPPORT_OPTIMIZER -I../fparser ../fparser/fparser.cc ../fparser/fpoptimizer.cc &&
                                   ar rcs libfparser.a fparser.o fpoptimizer.o
                     INSTALL_COMMAND mkdir -p <INSTALL_DIR>/lib &&
                                     cp libfparser.a <INSTALL_DIR>/lib &&
                                     cd ../fparser &&
                                     mkdir -p <INSTALL_DIR>/include &&
                                     ls  &&
                                     cp fparser.hh fparser_gmpint.hh fparser_mpfr.hh fpconfig.hh <INSTALL_DIR>/include;
                     )

list(APPEND build_list fparser )


################################
# Caliper and Adiak
################################
if (ENABLE_CALIPER)
    set(ADIAK_DIR "${CMAKE_INSTALL_PREFIX}/adiak")
    set(ADIAK_URL "${TPL_MIRROR_DIR}/Adiak-0.2.0.tar.gz")
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
                       )


    set(CALIPER_DIR "${CMAKE_INSTALL_PREFIX}/caliper")
    set(CALIPER_URL "${TPL_MIRROR_DIR}/caliper-2.4.0.tar.gz")
    message(STATUS "Building Caliper found at ${CALIPER_URL}")

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
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D WITH_PAPI:BOOL=${ENABLE_PAPI}
                                    -D PAPI_PREFIX:STRING=${PAPI_PREFIX}
                                    -D WITH_ADIAK:BOOL=ON
                                    -D adiak_DIR:STRING=${ADIAK_DIR}/lib/cmake/adiak/
                                    -D WITH_CUPTI=${ENABLE_CUDA}
                                    -D CUPTI_PREFIX=${CUDA_TOOLKIT_ROOT_DIR}/nvidia/extras/CUPTI
                                    -D WITH_NVPROF=${ENABLE_CUDA}
                       )

    list(APPEND build_list caliper adiak)
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
set(PUGIXML_URL "${TPL_MIRROR_DIR}/pugixml-1.8.0.tar.gz")

message(STATUS "Building PUGIXML found at ${PUGIXML_URL}")

ExternalProject_Add( pugixml
                     PREFIX ${PROJECT_BINARY_DIR}/pugixml
                     URL ${PUGIXML_URL}
                     INSTALL_DIR ${PUGIXML_DIR}
                     BUILD_COMMAND ${TPL_BUILD_COMMAND}
                     INSTALL_COMMAND ${TPL_INSTALL_COMMAND}
                     CMAKE_GENERATOR ${TPL_GENERATOR}
                     CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
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
    set(TRILINOS_URL "${TPL_MIRROR_DIR}/trilinos-release-12-18-1.tar.gz")

    message(STATUS "Building TRILINOS found at ${TRILINOS_URL}")

    if (NOT DEFINED TRILINOS_BUILD_COMMAND)
        set(TRILINOS_BUILD_COMMAND ${TPL_BUILD_COMMAND})
    endif()

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

    message(STATUS "TRILINOS_EXTRA_ARGS = ${TRILINOS_EXTRA_ARGS}")

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
                         BUILD_COMMAND ${TRILINOS_BUILD_COMMAND}
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
                                    -D CMAKE_Fortran_COMPILER:PATH=${CMAKE_Fortran_COMPILER}
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
                       CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
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
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
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
                       CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
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

set(HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre")
set(HYPRE_URL "${TPL_MIRROR_DIR}/hypre-343e31c.tar.gz")

message(STATUS "Building HYPRE found at ${HYPRE_URL}")

set(HYPRE_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_RELEASE}")
set(HYPRE_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS} ${CMAKE_CXX_FLAGS_RELEASE}")
set(HYPRE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_RELEASE}")


if( ${ENABLE_MPI} )
  set( HYPRE_C_COMPILER ${MPI_C_COMPILER} )
  set( HYPRE_CXX_COMPILER ${MPI_CXX_COMPILER} )
  set( HYPRE_Fortran_COMPILER ${MPI_Fortran_COMPILER} )
  set( HYPRE_DEPENDS "superlu_dist" )
  set( HYPRE_SUPERLU_LIBS "${CMAKE_INSTALL_PREFIX}/superlu_dist/${CMAKE_INSTALL_LIBDIR}/libsuperlu_dist.a ${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a ${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a -lstdc++")
else()
  set( HYPRE_C_COMPILER ${CMAKE_C_COMPILER} )
  set( HYPRE_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
  set( HYPRE_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )
  set( HYPRE_SUPERLU_LIBS "${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a -lstdc++")
endif()

if (ENABLE_OPENMP)
    set(HYPRE_OPENMP_FLAG --with-openmp)
    set(HYPRE_C_FLAGS "${HYPRE_C_FLAGS} ${OpenMP_C_FLAGS}")
    set(HYPRE_CXX_FLAGS "${HYPRE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
    set(HYPRE_SUPERLU_LIBS "${HYPRE_SUPERLU_LIBS} ${OpenMP_C_FLAGS}")
endif()

if( CMAKE_HOST_APPLE )
    set(HYPRE_INT_FLAG "bigint")
else()
    set(HYPRE_INT_FLAG "mixedint")
endif()

if( ${ENABLE_MPI} )
  file(WRITE ${PROJECT_BINARY_DIR}/config_hypre_for_geosx "\
  ./configure \
  CC=${MPI_C_COMPILER} \
  CFLAGS=\"${HYPRE_C_FLAGS}\" \
  CXX=${HYPRE_CXX_COMPILER} \
  CXXFLAGS=\"${HYPRE_CXX_FLAGS}\" \
  FC=${HYPRE_Fortran_COMPILER} \
  FCFLAGS=\"${HYPRE_Fortran_FLAGS}\" \
  --prefix=${HYPRE_DIR} \
  --enable-${HYPRE_INT_FLAG} \
  --with-blas-lib=\"${BLAS_LINK_LINE}\" \
  --with-lapack-lib=\"${LAPACK_LINK_LINE}\" \
  --with-dsuperlu \
  --with-dsuperlu-include=${CMAKE_INSTALL_PREFIX}/superlu_dist/include \
  --with-dsuperlu-lib=\"${HYPRE_SUPERLU_LIBS}\" \
  ${HYPRE_OPENMP_FLAG}\n")
else()
  file(WRITE ${PROJECT_BINARY_DIR}/config_hypre_for_geosx "\
  ./configure \
  CC=${MPI_C_COMPILER} \
  CFLAGS=\"${HYPRE_C_FLAGS}\" \
  CXX=${HYPRE_CXX_COMPILER} \
  CXXFLAGS=\"${HYPRE_CXX_FLAGS}\" \
  FC=${HYPRE_Fortran_COMPILER} \
  FCFLAGS=\"${HYPRE_Fortran_FLAGS}\" \
  --prefix=${HYPRE_DIR} \
  --enable-${HYPRE_INT_FLAG} \
  --with-blas-lib=\"${BLAS_LINK_LINE}\" \
  --with-lapack-lib=\"${LAPACK_LINK_LINE}\" \
  ${HYPRE_OPENMP_FLAG}\n")
endif()

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

list(APPEND build_list hypre )

################################
# SUITESPARSE
################################
if(ENABLE_SUITESPARSE)
    set(SUITESPARSE_DIR "${CMAKE_INSTALL_PREFIX}/suitesparse")
    set(SUITESPARSE_URL "${TPL_MIRROR_DIR}/SuiteSparse-5.8.1.tar.gz")

    message(STATUS "Building SUITESPARSE found at ${SUITESPARSE_URL}")

    set( SUITESPARSE_DEPENDS metis )

    set( SUITESPARSE_C_FLAGS "${CMAKE_C_FLAGS_RELEASE}" )
    set( SUITESPARSE_CXX_FLAGS "${CMAKE_CXX_FLAGS_RELEASE}" )
    set( SUITESPARSE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_RELEASE}" )

    set( SUITESPARSE_C_COMPILER ${CMAKE_C_COMPILER} )
    set( SUITESPARSE_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
    set( SUITESPARSE_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )

    if (ENABLE_OPENMP)
        set(SUITESPARSE_OPENMP_FLAG "${OpenMP_C_FLAGS}")
    else()
        set(SUITESPARSE_OPENMP_FLAG "")
    endif()

    set( SUITESPARSE_CONFIG_ARGS "CC=${SUITESPARSE_C_COMPILER} \
CFLAGS=\"${SUITESPARSE_C_FLAGS}\" \
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
# PETSC
################################

if( ENABLE_PETSC )
    set(PETSC_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/petsc")
    set(PETSC_URL "${TPL_MIRROR_DIR}/petsc-lite-3.13.0.tar.gz")
    set(PT_SCOTCH_URL "${TPL_MIRROR_DIR}/petsc-pkg-scotch-v6.0.9.tar.gz")

    message(STATUS "Building PETSC found at ${PETSC_URL}")

    set(PETSC_C_FLAGS "-fPIC ${C_FLAGS_NO_WARNINGS} ${CMAKE_C_FLAGS_RELEASE}")
    set(PETSC_CXX_FLAGS "-fPIC ${CXX_FLAGS_NO_WARNINGS} ${CMAKE_CXX_FLAGS_RELEASE}")
    set(PETSC_Fortran_FLAGS "${CMAKE_Fortran_FLAGS_RELEASE}")

    if (ENABLE_OPENMP)
        set(PETSC_OPENMP_FLAG --with-openmp=1)
        set(PETSC_C_FLAGS "${PETSC_C_FLAGS} ${OpenMP_C_FLAGS}")
        set(PETSC_CXX_FLAGS "${PETSC_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
        set(PETSC_Fortran_FLAGS "${PETSC_Fortran_FLAGS} ${OpenMP_Fortran_FLAGS}")

        if(PETSC_OMP_DIR)
            set(PETSC_OMP_DIR_FLAG --with-openmp-dir=${PETSC_OMP_DIR})
        endif()
    endif()

    if (CMAKE_BUILD_TYPE MATCHES Debug)
        set(PETSC_DEBUG_FLAG --with-debugging=1)
    else()
        set(PETSC_DEBUG_FLAG --with-debugging=0)
    endif()

    if( ${ENABLE_MPI} )
        set( PETSC_C_COMPILER ${MPI_C_COMPILER} )
        set( PETSC_CXX_COMPILER ${MPI_CXX_COMPILER} )
        set( PETSC_Fortran_COMPILER ${MPI_Fortran_COMPILER} )
        set( PETSC_MPI_FLAG "--with-mpi=1 --download-ptscotch=${PT_SCOTCH_URL} --with-superlu_dist-dir=${CMAKE_INSTALL_PREFIX}/superlu_dist --with-parmetis-dir=${CMAKE_INSTALL_PREFIX}/parmetis")
        set( PETSC_DEPENDS parmetis metis superlu_dist )
    else()
        set( PETSC_C_COMPILER ${CMAKE_C_COMPILER} )
        set( PETSC_CXX_COMPILER ${CMAKE_CXX_COMPILER} )
        set( PETSC_Fortran_COMPILER ${CMAKE_Fortran_COMPILER} )
        set( PETSC_MPI_FLAG "--with-mpi=0" )
        set( PETSC_DEPENDS metis )
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
${PETSC_MPI_FLAG}\n")

    ExternalProject_Add( petsc
                         URL ${PETSC_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/petsc #outer petsc directory
                         DEPENDS ${PETSC_DEPENDS}
                         INSTALL_DIR ${PETSC_INSTALL_DIR}
                         CONFIGURE_COMMAND cd ../petsc && cat ${PROJECT_BINARY_DIR}/config_petsc_for_geosx && . ${PROJECT_BINARY_DIR}/config_petsc_for_geosx
                         BUILD_COMMAND cd ../petsc && make -j ${NUM_PROC}
                         INSTALL_COMMAND cd ../petsc && make install
                        )

    list(APPEND build_list petsc )
endif()

################################
# VTK
################################
if(ENABLE_VTK)
    set(VTK_DIR "${CMAKE_INSTALL_PREFIX}/vtk")
    set(VTK_URL "${TPL_MIRROR_DIR}/VTK-v9.0.0.rc3.tar.gz")

    message(STATUS "Building VTK found at ${VTK_URL}")

    ExternalProject_Add( vtk
                         PREFIX ${PROJECT_BINARY_DIR}/vtk
                         URL ${VTK_URL}
                         INSTALL_DIR ${VTK_DIR}
                         BUILD_COMMAND ${TPL_BUILD_COMMAND}
                         INSTALL_COMMAND "${TPL_INSTALL_COMMAND}/strip"
                         CMAKE_GENERATOR ${TPL_GENERATOR}
                         CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D CMAKE_INSTALL_RPATH:PATH=<INSTALL_DIR>/lib
                                    -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                    -D VTK_GROUP_ENABLE_Imaging=NO
                                    -D VTK_GROUP_ENABLE_MPI=NO
                                    -D VTK_GROUP_ENABLE_Qt=NO
                                    -D VTK_GROUP_ENABLE_Rendering=NO
                                    -D VTK_GROUP_ENABLE_StandAlone=NO
                                    -D VTK_GROUP_ENABLE_Views=NO
                                    -D VTK_GROUP_ENABLE_Web=NO
                                    -D VTK_BUILD_ALL_MODULES=OFF
                                    -D VTK_WRAP_PYTHON=OFF
                                    -D VTK_WRAP_JAVA=OFF
                                    -D VTK_MODULE_ENABLE_VTK_vtkm=NO
                                    -D VTK_MODULE_ENABLE_VTK_CommonDataModel=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonCore=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonExecutionModel=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonMath=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonMisc=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonSystem=YES
                                    -D VTK_MODULE_ENABLE_VTK_CommonTransforms=YES
                                    -D VTK_MODULE_ENABLE_VTK_IOXML=YES
                                    -D VTK_MODULE_ENABLE_VTK_IOXMLParser=YES
                                    -D VTK_MODULE_ENABLE_VTK_IOCore=YES
                                    -D VTK_BUILD_TESTING=OFF
                                    -D VTK_LEGACY_REMOVE=ON
                         )

    list(APPEND build_list vtk )
endif(ENABLE_VTK)

################################
# TRIBOL
################################
if (ENABLE_TRIBOL)
   set(TPL_CXX_GID64 ${TPL_CXX_STANDARD})
   list(APPEND TPL_CXX_GID64 -DGLOBALID_IS_64BIT=1)

    set(AXOM_DIR "${CMAKE_INSTALL_PREFIX}/axom")
    set(AXOM_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/axom.git")
    set(AXOM_TAG "feature/benliu/slideWorld")

    if (EXISTS ${AXOM_DIR})
        message(STATUS "Using existing Axom found at ${AXOM_DIR}")
        list(APPEND existing_list axom )
    else()
        message(STATUS "Building Axom found at ${AXOM_TAG}")

        ExternalProject_Add( axom
                             DOWNLOAD_COMMAND git clone ${AXOM_REPO}
                             UPDATE_COMMAND git checkout ${AXOM_TAG}
                             PREFIX ${PROJECT_BINARY_DIR}/axom
                             SOURCE_SUBDIR src
                             INSTALL_DIR ${AXOM_DIR}
                             DEPENDS hdf5 conduit raja
                             CMAKE_ARGS -DENABLE_DOCS=OFF
                                        -DENABLE_BENCHMARKS=OFF
                                        -DENABLE_EXAMPLES=OFF
                                        -DENABLE_FORTRAN=OFF
                                        -DENABLE_TESTS=OFF
                                        -DAXOM_ENABLE_LUMBERJACK=ON
                                        -DAXOM_MINT_USE_SIDRE:BOOL=FALSE
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DENABLE_MPI=${ENABLE_MPI}
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DHDF5_DIR=${HDF5_DIR}
                                        -DCONDUIT_DIR=${CONDUIT_DIR}
                                        -DUMPIRE_DIR=
                                        -DRAJA_DIR=
                                        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_CXX_FLAGS=-std=c++14
                                        -DENABLE_OPENMP=${ENABLE_OPENMP}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install )
        list(APPEND build_list axom )
    endif()

    set(MFEM_DIR "${CMAKE_INSTALL_PREFIX}/mfem")
    set(MFEM_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/mfem.git")
    set(MFEM_TAG "feature/benliu/slideWorld")

    if (EXISTS ${MFEM_DIR})
        message(STATUS "Using existing MFEM found at ${MFEM_DIR}")
        list(APPEND existing_list axom )
    else()
        message(STATUS "Building MFEM found at ${MFEM_TAG}")

        ExternalProject_Add( mfem
                             DOWNLOAD_COMMAND git clone ${MFEM_REPO}
                             UPDATE_COMMAND git checkout ${MFEM_TAG}
                             PREFIX ${PROJECT_BINARY_DIR}/mfem
                             INSTALL_DIR ${MFEM_DIR}
                             DEPENDS hypre
                             CMAKE_ARGS -DHYPRE_INCLUDE_DIRS=${HYPRE_DIR}/include
                                        -DHYPRE_LIBRARIES=${HYPRE_DIR}/lib
                                        -DMFEM_USE_OPENMP=OFF
                                        -DMFEM_USE_GZSTREAM=ON
                                        -DMFEM_USE_LIBUNWIND=OFF
                                        -DMFEM_THREAD_SAFE=OFF
                                        -DMFEM_USE_MEMALLOC=OFF
                                        -DMFEM_USE_SUNDIALS=OFF
                                        -DMFEM_USE_MESQUITE=OFF
                                        -DMFEM_USE_SUITESPARSE=OFF
                                        -DMFEM_USE_SUPERLU=OFF
                                        -DMFEM_USE_STRUMPACK=OFF
                                        -DMFEM_USE_GECKO=OFF
                                        -DMFEM_USE_GNUTLS=OFF
                                        -DMFEM_USE_NETCDF=OFF
                                        -DMFEM_USE_PETSC=OFF
                                        -DMFEM_USE_MPFR=OFF
                                        -DMFEM_USE_SIDRE=OFF
                                        -DMFEM_USE_METIS=OFF
                                        -DMFEM_ENABLE_TESTING=OFF
                                        -DMFEM_ENABLE_EXAMPLES=OFF
                                        -DMFEM_ENABLE_MINIAPPS=OFF
                                        -DMFEM_GIT_STRING="UNKNOWN"
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=ON
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install )
        list(APPEND build_list mfem)
    endif()

    set(TRIBOL_DIR "${CMAKE_INSTALL_PREFIX}/tribol")
    set(TRIBOL_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/tribol.git")
    set(TRIBOL_TAG "feature/benliu/slideWorld")

    if (EXISTS ${TRIBOL_DIR})
        message(STATUS "Using existing TRIBOL found at ${TRIBOL_DIR}")
        list(APPEND existing_list tribol)
    else()
        message(STATUS "Building TRIBOL found at ${TRIBOL_TAG}")

        ExternalProject_Add( tribol
                             PREFIX ${PROJECT_BINARY_DIR}/tribol
                             #DOWNLOAD_COMMAND git clone ${TRIBOL_REPO}
                             #UPDATE_COMMAND git checkout ${TRIBOL_TAG} && git pull
                             GIT_REPOSITORY ${TRIBOL_REPO}
                             GIT_TAG ${TRIBOL_TAG}
                             INSTALL_DIR ${TRIBOL_DIR}
                             DEPENDS axom conduit hdf5 mfem
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_CXX_FLAGS=-std=c++14
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DTRIBOL_USE_EXTERNAL_AXOM:BOOL=TRUE
                                        -DTRIBOL_ENABLE_SIDRE:BOOL=FALSE
                                        -DAXOM_DIR=${AXOM_DIR}
                                        -DCONDUIT_DIR=${CONDUIT_DIR}
                                        -DHDF5_DIR=${HDF5_DIR}
                                        -DRAJA_DIR=${RAJA_DIR}
                                        -DMFEM_DIR=${MFEM_DIR}
                                        -DENABLE_TESTS=OFF
                                        -DENABLE_EXAMPLES=OFF
                                        -DENABLE_DOCS=OFF)

        list(APPEND build_list tribol)
    endif()

    set(LLNL_GLOBALID_DIR "${CMAKE_INSTALL_PREFIX}/LLNL_GlobalID")
    set(LLNL_GLOBALID_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/LLNL_GlobalID.git")
    set(LLNL_GLOBALID_TAG "feature/benliu/slideWorld")

    if (EXISTS ${LLNL_GLOBALID_DIR})
        message(STATUS "Using existing LLNL_GLOBALID found at ${LLNL_GLOBALID_DIR}")
        list(APPEND existing_list LLNL_GlobalID)
    else()
        message(STATUS "Building LLNL_GLOBALID found at ${LLNL_GLOBALID_TAG}")

        ExternalProject_Add( LLNL_GlobalID
                             PREFIX ${PROJECT_BINARY_DIR}/LLNL_GlobalID
                             GIT_REPOSITORY ${LLNL_GLOBALID_REPO}
                             GIT_TAG ${LLNL_GLOBALID_TAG}
                             INSTALL_DIR ${LLNL_GLOBALID_DIR}
                             CONFIGURE_COMMAND pwd
                             BUILD_COMMAND pwd
                             INSTALL_COMMAND mkdir -p <INSTALL_DIR>/include &&
                                             cp <SOURCE_DIR>/LLNL_GlobalID.h <INSTALL_DIR>/include/ &&
                                             cp <SOURCE_DIR>/LLNL_GlobalID_mpi.h <INSTALL_DIR>/include/)
        list(APPEND build_list LLNL_GlobalID)
    endif()

    set(CARE_DIR "${CMAKE_INSTALL_PREFIX}/care")
    set(CARE_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/imports_care.git")
    set(CARE_TAG "feature/benliu/slideWorld")

    if (EXISTS ${CARE_DIR})
        message(STATUS "Using existing CARE found at ${CARE_DIR}")
        list(APPEND existing_list care)
    else()
        message(STATUS "Building CARE found at ${CARE_TAG}")

        ExternalProject_Add( care
                             PREFIX ${PROJECT_BINARY_DIR}/care
                             #GIT_REPOSITORY ${CARE_REPO}
                             #GIT_TAG ${CARE_TAG}
                             DOWNLOAD_COMMAND git clone ${CARE_REPO} care
                             UPDATE_COMMAND git checkout ${CARE_TAG} && git pull
                             INSTALL_DIR ${CARE_DIR}
                             DEPENDS chai raja LLNL_GlobalID
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS=${TPL_CXX_GID64}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -Dcamp_DIR=${RAJA_DIR}/lib/cmake/camp
                                        -DUMPIRE_DIR=${UMPIRE_DIR}
                                        -DCHAI_DIR=${CHAI_DIR}
                                        -DRAJA_DIR=${RAJA_DIR}
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list care)
    endif()

    set(RXB_DIR "${CMAKE_INSTALL_PREFIX}/rxb")
    set(RXB_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/rxb.git")
    set(RXB_TAG "feature/benliu/slideWorld")

    if (EXISTS ${RXB_DIR})
        message(STATUS "Using existing RXB found at ${RXB_DIR}")
        list(APPEND existing_list rxb)
    else()
        message(STATUS "Building RXB found at ${RXB_TAG}")

        ExternalProject_Add( rxb 
                             PREFIX ${PROJECT_BINARY_DIR}/rxb
                             GIT_REPOSITORY ${RXB_REPO}
                             GIT_TAG ${RXB_TAG}
                             INSTALL_DIR ${RXB_DIR}
                             DEPENDS LLNL_GlobalID
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS=${TPL_CXX_GID64}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DENABLE_MPI:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DENABLE_RIB=OFF
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list rxb)
    endif()

    set(VISTA_DIR "${CMAKE_INSTALL_PREFIX}/vista")
    set(VISTA_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/vista.git")
    set(VISTA_TAG "feature/benliu/slideWorld")

    if (EXISTS ${VISTA_DIR})
        message(STATUS "Using existing VISTA found at ${VISTA_DIR}")
        list(APPEND existing_list vista)
    else()
        message(STATUS "Building VISTA found at ${VISTA_TAG}")

        ExternalProject_Add( vista
                             PREFIX ${PROJECT_BINARY_DIR}/vista
                             GIT_REPOSITORY ${VISTA_REPO}
                             GIT_TAG ${VISTA_TAG}
                             INSTALL_DIR ${VISTA_DIR}
                             DEPENDS LLNL_GlobalID chai silo care
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                        -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS=${TPL_CXX_GID64}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DCMAKE_DEBUG_POSTFIX=
                                        -DENABLE_VISTA_TV_DEBUG:BOOL=TRUE
                                        -DEXTERNAL_VISTA_TV_DEBUG:BOOL=TRUE
                                        -DCHAI_DIR=${CHAI_DIR}
                                        -DHDF5_DIR=${HDF5_DIR}
                                        -DRAJA_DIR=${RAJA_DIR}
                                        -DCAMP_DIR=${RAJA_DIR}/lib/cmake/camp
                                        -DCARE_DIR=${CARE_DIR}
                                        -DSILO_DIR=${SILO_DIR}
                                        -DUMPIRE_DIR=${UMPIRE_DIR}
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list vista)
    endif()

    set(WORLDS_CORE_DIR "${CMAKE_INSTALL_PREFIX}/worlds_core")
    set(WORLDS_CORE_REPO "ssh://git@rz-bitbucket.llnl.gov:7999/ale/worlds_core.git")
    set(WORLDS_CORE_TAG "feature/benliu/slideWorld")

    if (EXISTS ${WORLDS_CORE_DIR})
        message(STATUS "Using existing WORLDS_CORE found at ${WORLDS_CORE_DIR}")
        list(APPEND existing_list worlds_core)
    else()
        message(STATUS "Building WORLDS_CORE found at ${WORLDS_CORE_TAG}")

        ExternalProject_Add( worlds_core
                             PREFIX ${PROJECT_BINARY_DIR}/worlds_core
                             GIT_REPOSITORY ${WORLDS_CORE_REPO}
                             GIT_TAG ${WORLDS_CORE_TAG}
                             INSTALL_DIR ${WORLDS_CORE_DIR}
                             DEPENDS rxb vista LLNL_GlobalID chai care
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS=${TPL_CXX_GID64}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DENABLE_MPI:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DRXB_DIR=${RXB_DIR}
                                        -DVISTA_DIR=${VISTA_DIR}
                                        -DCHAI_DIR=${CHAI_DIR}
                                        -DCARE_DIR=${CARE_DIR}
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list worlds_core)
    endif()

endif(ENABLE_TRIBOL)

################################
# Create target that builds all dependencies
################################
message(STATUS "Building= ${build_list}")

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )

add_dependencies( tpl ${build_list}  )

# Clean up
add_custom_command( TARGET tpl POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/config_suitesparse_for_geosx
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/build_suitesparse_for_geosx
                    COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/install_suitesparse_for_geosx )
