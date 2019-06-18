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

set( ENABLE_UNCRUSTIFY "OFF" CACHE PATH "" FORCE )
include(${BLT_SOURCE_DIR}/SetupBLT.cmake)


################################
# General GEOSX TPL Info
################################
include(ExternalProject)

option( BUILD_SHARED_LIBS "" OFF )
option( RAJA_ENABLE_TBB "" OFF)

option( ENABLE_CALIPER "" OFF )
option( ENABLE_TRILINOS "" ON )

set(NUM_PROC "16" CACHE STRING "")
message(STATUS "Build command = make -j ${NUM_PROC}")
set(TPL_MIRROR_DIR "${CMAKE_SOURCE_DIR}/tplMirror")
set(build_list )

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_RELEASE}" CACHE STRING "" FORCE)

string(REPLACE "-Wall" "" C_FLAGS_NO_WARNINGS ${CMAKE_C_FLAGS})
string(REPLACE "-Wextra" "" C_FLAGS_NO_WARNINGS ${C_FLAGS_NO_WARNINGS})
set(C_FLAGS_NO_WARNINGS "${C_FLAGS_NO_WARNINGS} -w")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_RELEASE}" CACHE STRING "" FORCE)

string(REPLACE "-Wall" "" CXX_FLAGS_NO_WARNINGS ${CMAKE_CXX_FLAGS})
string(REPLACE "-Wextra" "" CXX_FLAGS_NO_WARNINGS ${CXX_FLAGS_NO_WARNINGS})
set(CXX_FLAGS_NO_WARNINGS "${CXX_FLAGS_NO_WARNINGS} -w")

set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_RELEASE}" CACHE STRING "" FORCE)

################################
# LAPACK_SUITE
# It contains also
#   * Level 1, 2, and 3 BLAS; CBLAS, a C interface to the BLAS
#   * CBLAS (C interface to the BLAS)
#   * LAPACKE (C interface to LAPACK)
################################
if (DEFINED ENABLE_LAPACK_SUITE AND NOT ENABLE_LAPACK_SUITE)
    message(STATUS "LAPACK_SUITE disabled")
    set(TRILINOS_DEPENDS "")
else()
    set(LAPACK_SUITE_DIR "${CMAKE_INSTALL_PREFIX}/lapack_suite")
    set(LAPACK_SUITE_URL "${TPL_MIRROR_DIR}/lapack-3.8.0-WITHLAPACKH.tar.gz")

    message(STATUS "Building LAPACK_SUITE found at ${LAPACK_SUITE_URL}")
    message(STATUS "CMAKE_Fortran_FLAGS=${CMAKE_Fortran_FLAGS}")

    ExternalProject_Add( lapack_suite
                         PREFIX ${PROJECT_BINARY_DIR}/lapack_suite
                         URL ${LAPACK_SUITE_URL}
                         INSTALL_DIR ${LAPACK_SUITE_DIR}
                         BUILD_COMMAND make -j ${NUM_PROC} VERBOSE=1
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                    -D CBLAS=ON
                                    -D LAPACKE=ON
                                    -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -D CMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                    -D CMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
                                    -D CMAKE_Fortran_FLAGS=${CMAKE_Fortran_FLAGS}
                                    -D CMAKE_Fortran_COMPILER_ID=${CMAKE_Fortran_COMPILER_ID}
                                    -D CMAKE_EXE_LINKER_FLAGS=${BLT_EXE_LINKER_FLAGS}
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                    )

    # Check if system is using lib or lib64 as default library installation path
    get_property(LIB64 GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS)
    set(LIBSUFFIX "")
    if (${LIB64} STREQUAL TRUE AND ${CMAKE_SYSTEM_PROCESSOR} STREQUAL "x86_64")
        set(LIBSUFFIX 64)
    endif()

    # Use the lapack_suite for trilinos. The last define is a hack.
    set(BLAS_LIBRARY_DIRS ${LAPACK_SUITE_DIR}/lib${LIBSUFFIX} CACHE PATH "")
    set(BLAS_LIBRARY_NAMES blas CACHE STRING "")

    set(LAPACK_LIBRARY_DIRS ${LAPACK_SUITE_DIR}/lib${LIBSUFFIX} CACHE PATH "")
    set(LAPACK_LIBRARY_NAMES lapack CACHE STRING "")

    set(TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                            -D HAVE_dggsvd3_POST=1
                            )

    set(SUPERLU_BLAS_LIBRARIES "-Wl,-rpath -Wl,${BLAS_LIBRARY_DIRS} -l${BLAS_LIBRARY_NAMES}")
    set(SUPERLU_LAPACK_LIBRARIES "-Wl,-rpath -Wl,${LAPACK_LIBRARY_DIRS} -l${LAPACK_LIBRARY_NAMES}")

    set(MATH_LIBRARIES lapack_suite)
    list(APPEND build_list lapack_suite)
endif()


################################
# MKL
################################
if (DEFINED ENABLE_MKL AND ENABLE_MKL)
    message(STATUS "MKL enabled")

    if (NOT DEFINED MKL_ROOT)
        message(FATAL_ERROR "MKL is enabled but MKL_ROOT is not defined.")
    endif()

    if (NOT DEFINED MKL_LIBRARY_NAMES)
        message(FATAL_ERROR "MKL is enabled but MKL_LIBRARY_NAMES is not defined.")
    endif()

    set(BLAS_LIBRARY_DIRS ${MKL_ROOT}/lib CACHE PATH "")
    set(BLAS_LIBRARY_NAMES ${MKL_LIBRARY_NAMES} CACHE STRING "")

    set(LAPACK_LIBRARY_DIRS ${MKL_ROOT}/lib CACHE PATH "")
    set(LAPACK_LIBRARY_NAMES ${MKL_LIBRARY_NAMES} CACHE STRING "")

    set(TRILINOS_EXTRA_ARGS ${TRILINOS_EXTRA_ARGS}
                            -D TPL_ENABLE_MKL:BOOL=ON
                            -D MKL_LIBRARY_DIRS:FILEPATH=${MKL_ROOT}/lib
                            -D MKL_LIBRARY_NAMES:STRING=${MKL_LIBRARY_NAMES}
                            -D MKL_INCLUDE_DIRS:FILEPATH=${MKL_ROOT}/include
                            )

    set(SUPERLU_BLAS_LIBRARIES ${BLAS_LIBRARY_DIRS}/${BLAS_LIBRARY_NAMES})
    set(SUPERLU_LAPACK_LIBRARIES ${LAPACK_LIBRARY_DIRS}/${LAPACK_LIBRARY_NAMES})
endif()

message(STATUS "BLAS_LIBRARY_DIRS = ${BLAS_LIBRARY_DIRS}")
message(STATUS "BLAS_LIBRARY_NAMES = ${BLAS_LIBRARY_NAMES}")
message(STATUS "LAPACK_LIBRARY_DIRS = ${LAPACK_LIBRARY_DIRS}")
message(STATUS "LAPACK_LIBRARY_NAMES = ${LAPACK_LIBRARY_NAMES}")


################################
# UNCRUSTIFY
################################
set(UNCRUSTIFY_DIR "${CMAKE_INSTALL_PREFIX}/uncrustify")
set(UNCRUSTIFY_URL "${TPL_MIRROR_DIR}/uncrustify-0.69.0.tar.gz")
message(STATUS "Building uncrustify found at ${UNCRUSTIFY_URL}")

ExternalProject_Add( uncrustify
                     URL ${UNCRUSTIFY_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/uncrustify
                     INSTALL_DIR ${UNCRUSTIFY_DIR}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                                -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                 )

list(APPEND build_list uncrustify )

################################
# ASTYLE
################################
set(ASTYLE_DIR "${CMAKE_INSTALL_PREFIX}/astlye")
set(ASTYLE_URL "${TPL_MIRROR_DIR}/astyle_3.1_linux.tar.gz")
message(STATUS "Building uncrustify found at ${ASTYLE_URL}")

ExternalProject_Add( astyle
                     URL ${ASTYLE_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/astyle
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_DIR ${ASTYLE_DIR}
                     INSTALL_COMMAND make DESTDIR=${ASTYLE_DIR} install
                     CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                )
                                 
list(APPEND build_list astyle )


################################
# HDF5
################################
set( HDF5_DEPENDENCIES "" )
set(HDF5_DIR "${CMAKE_INSTALL_PREFIX}/hdf5")
set(HDF5_URL "${TPL_MIRROR_DIR}/hdf5-1.10.3.tar.gz")
message(STATUS "Building HDF5 found at ${HDF5_URL}")

ExternalProject_Add( hdf5
                     URL ${HDF5_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/hdf5
                     INSTALL_DIR ${HDF5_DIR}
                     CONFIGURE_COMMAND ../hdf5/configure CC=${MPI_C_COMPILER}
                                          CXX=${MPI_CXX_COMPILER}
                                          --enable-build-mode=production
                                          --prefix=<INSTALL_DIR>
                                          --enable-parallel
                                          --enable-shared=no
                                          CFLAGS=-fPIC
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND HDF5_DEPENDENCIES hdf5 )
list(APPEND build_list hdf5 )


################################
# Conduit
################################
set(CONDUIT_DIR "${CMAKE_INSTALL_PREFIX}/conduit")
set(CONDUIT_URL "${TPL_MIRROR_DIR}/conduit-0.3.2.tar.gz")
message(STATUS "Building Conduit found at ${CONDUIT_URL}")

ExternalProject_Add( conduit
                     URL ${CONDUIT_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/conduit
                     SOURCE_SUBDIR src
                     INSTALL_DIR ${CONDUIT_DIR}
                     DEPENDS ${HDF5_DEPENDENCIES}
                     CMAKE_ARGS -DENABLE_DOCS=OFF
                                -DENABLE_EXAMPLES=OFF
                                -DENABLE_FORTRAN=OFF
                                -DENABLE_TESTS=OFF
                                -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DENABLE_MPI=${ENABLE_MPI}
                                -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                -DHDF5_DIR=${HDF5_DIR}

# This is to work around a bug in how hdf5 is used in conduit (it exposes an MPI header)
# Once this is fixed remove the next three lines (ENABLE_FIND_MPI and using the MPI wrappers)
# and uncomment out the 4 after (using serial compilers and MPI wrappers separately)
                                -DENABLE_FIND_MPI=OFF
                                -DCMAKE_C_COMPILER=${MPI_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
#                                    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
#                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
#                                    -DMPI_C_COMPILER=${MPI_C_COMPILER}
#                                    -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DENABLE_OPENMP=${ENABLE_OPENMP}
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND build_list conduit )


################################
# Axom
################################
set(AXOM_DIR "${CMAKE_INSTALL_PREFIX}/axom")
set(AXOM_URL "${TPL_MIRROR_DIR}/axom-10-5-2018.tar.gz")

message(STATUS "Building Axom found at ${AXOM_URL}")

ExternalProject_Add( axom
                     URL ${AXOM_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/axom
                     SOURCE_SUBDIR src
                     INSTALL_DIR ${AXOM_DIR}
                     DEPENDS ${HDF5_DEPENDENCIES} conduit
                     CMAKE_ARGS -DENABLE_DOCS=OFF
                                -DENABLE_BENCHMARKS=OFF
                                -DENABLE_EXAMPLES=OFF
                                -DENABLE_FORTRAN=OFF
                                -DENABLE_TESTS=OFF
                                -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DENABLE_MPI=${ENABLE_MPI}
                                -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                -DHDF5_DIR=${HDF5_DIR}
                                -DCONDUIT_DIR=${CONDUIT_DIR}
                                -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -DENABLE_OPENMP=${ENABLE_OPENMP}
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -DAXOM_ENABLE_LUMBERJACK=ON
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install )

list(APPEND build_list axom )


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
                     CONFIGURE_COMMAND ../silo/configure CC=${MPI_C_COMPILER}
                                          CXX=${MPI_CXX_COMPILER}
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
set(RAJA_URL "${TPL_MIRROR_DIR}/RAJA-v0.8.0.tar.gz")
message(STATUS "Building RAJA found at ${RAJA_URL}")

ExternalProject_Add( raja
                     URL ${RAJA_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/raja
                     INSTALL_DIR ${RAJA_DIR}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -D CMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -D RAJA_ENABLE_CUDA=${ENABLE_CUDA}
                                -D CUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -D CMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -D CUDA_ARCH=${CUDA_ARCH}
                                -D ENABLE_TESTS=${RAJA_ENABLE_TESTS}
                                -D RAJA_ENABLE_TBB=${RAJA_ENABLE_TBB}
                                -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                -D RAJA_ENABLE_OPENMP=${ENABLE_OPENMP} 
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                    )

list(APPEND build_list raja )


################################
# CHAI
################################
set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
set(CHAI_URL "${TPL_MIRROR_DIR}/chai-bugfix-corbett-memory-leak-4-5-19.tar.gz")
message(STATUS "Building CHAI found at ${CHAI_URL}")

ExternalProject_Add( chai
                     PREFIX ${PROJECT_BINARY_DIR}/chai
                     URL ${CHAI_URL}
                     INSTALL_DIR ${CHAI_DIR}
                     PATCH_COMMAND pwd && cp -r blt src/tpl/umpire
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DENABLE_CUDA=${ENABLE_CUDA}
                                -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR}
                                -DCMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
                                -DCUDA_ARCH=${CUDA_ARCH}
                                -DENABLE_OPENMP=${ENABLE_OPENMP}
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -DENABLE_TESTS=OFF
                                -DENABLE_DOCS=OFF
                                -DENABLE_DOXYGEN=OFF
                                -DENABLE_SPHINX=OFF
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
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
# CALIPER
################################
if (DEFINED ENABLE_CALIPER AND NOT ENABLE_CALIPER)
    message(STATUS "CALIPER disabled")
else()
    set(CALIPER_DIR "${CMAKE_INSTALL_PREFIX}/caliper")
    set(CALIPER_URL "${TPL_MIRROR_DIR}/Caliper-08-06-2018.tar.gz")

    message(STATUS "Building CALIPER found at ${CALIPER_URL}")

    ExternalProject_Add( caliper
                         URL ${CALIPER_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/caliper
                         INSTALL_DIR ${CALIPER_DIR}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                    -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                    #-DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DWITH_PAPI=${ENABLE_PAPI}
                                    -DWITH_MPI=true
                                    -DPAPI_PREFIX=${PAPI_PREFIX}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

    list(APPEND build_list caliper )
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
                         CMAKE_ARGS -DMATHPRESSO_STATIC=TRUE
                                    -DASMJIT_DIR=${PROJECT_BINARY_DIR}/asmjit-master
                                    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
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
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE} )

list(APPEND build_list pugixml )

################################
# TRILINOS
################################
if (ENABLE_TRILINOS)
    set(TRILINOS_DIR "${CMAKE_INSTALL_PREFIX}/trilinos")
    set(TRILINOS_URL "${TPL_MIRROR_DIR}/trilinos-release-12-14-1.tar.gz")

    message(STATUS "Building TRILINOS found at ${TRILINOS_URL}")
    message(STATUS "TRILINOS_EXTRA_ARGS = ${TRILINOS_EXTRA_ARGS}")

    string(REPLACE "-Wall" "" TRILINOS_CXX_FLAGS ${CMAKE_CXX_FLAGS})
    string(REPLACE "-Wextra" "" TRILINOS_CXX_FLAGS ${TRILINOS_CXX_FLAGS})
    set(TRILINOS_CXX_FLAGS "${TRILINOS_CXX_FLAGS} -w")

    ExternalProject_Add( trilinos
                         PREFIX ${PROJECT_BINARY_DIR}/trilinos
                         URL ${TRILINOS_URL}
                         INSTALL_DIR ${TRILINOS_DIR}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         DEPENDS ${MATH_LIBRARIES}
                         CMAKE_ARGS -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                    -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                    -D CMAKE_CXX_FLAGS=${TRILINOS_CXX_FLAGS}
                                    -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -D TPL_ENABLE_MPI:BOOL=ON
                                    -D BUILD_SHARED_LIBS:BOOL=ON
                                    -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                    -D ENABLE_OPENMP=${ENABLE_OPENMP}
                                    -D Trilinos_ENABLE_Fortran:BOOL=OFF
                                    -D Trilinos_WARNINGS_AS_ERRORS_FLAGS:STRING=""
                                    -D CMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -D Trilinos_ENABLE_TESTS:BOOL=OFF
                                    -D Trilinos_ENABLE_Gtest:BOOL=OFF
                                    -D Trilinos_ENABLE_ALL_PACKAGES:BOOL=OFF
                                    -D Trilinos_ENABLE_ALL_OPTIONAL_PACKAGES:BOOL=ON
                                    -D Trilinos_ENABLE_Epetra:BOOL=ON
                                    -D Trilinos_ENABLE_EpetraExt:BOOL=ON
                                    -D Trilinos_ENABLE_Tpetra:BOOL=ON
                                    -D Trilinos_ENABLE_Jpetra:BOOL=ON
                                    -D Trilinos_ENABLE_Kokkos:BOOL=ON
                                    -D Trilinos_ENABLE_Sacado:BOOL=ON
                                    -D Trilinos_ENABLE_Stratimikos:BOOL=ON
                                    -D Trilinos_ENABLE_Amesos:BOOL=ON
                                    -D Trilinos_ENABLE_AztecOO:BOOL=ON
                                    -D Trilinos_ENABLE_Ifpack:BOOL=ON
                                    -D Trilinos_ENABLE_Teuchos:BOOL=ON
                                    -D Trilinos_ENABLE_ML:BOOL=ON
                                    -D Trilinos_ENABLE_Intrepid:BOOL=ON
                                    -D Trilinos_ENABLE_Shards:BOOL=ON
                                    -D Trilinos_ENABLE_Pamgen:BOOL=ON
                                    -D Trilinos_ENABLE_Thyra:BOOL=ON
                                    -D Trilinos_ENABLE_STK=OFF
                                    -D Trilinos_ENABLE_TrilinosCouplings:BOOL=ON
                                    -D BLAS_LIBRARY_DIRS:FILEPATH=${BLAS_LIBRARY_DIRS}
                                    -D BLAS_LIBRARY_NAMES:STRING=${BLAS_LIBRARY_NAMES}
                                    -D LAPACK_LIBRARY_DIRS:FILEPATH=${LAPACK_LIBRARY_DIRS}
                                    -D LAPACK_LIBRARY_NAMES:STRING=${LAPACK_LIBRARY_NAMES}
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

message(STATUS "Building PARMETIS found at ${PARMETIS_URL}")

ExternalProject_Add( parmetis
                     PREFIX ${PROJECT_BINARY_DIR}/parmetis
                     URL ${PARMETIS_URL}
                     INSTALL_DIR ${PARMETIS_DIR}
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                -DGKLIB_PATH=../parmetis/metis/GKlib
                                -DMETIS_PATH=../parmetis/metis
                                -DCMAKE_C_COMPILER=${MPI_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
                                -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -DMPIEXEC_EXECUTABLE=${MPIEXEC_EXECUTABLE}
                                -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DCMAKE_Fortran_FLAGS=${CMAKE_Fortran_FLAGS}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -DPARMETIS_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

list(APPEND build_list parmetis )

message(STATUS "Building METIS found at ${PARMETIS_URL}")

ExternalProject_Add( metis
                     PREFIX ${PROJECT_BINARY_DIR}/metis
                     URL ${PARMETIS_URL}
                     INSTALL_DIR ${METIS_DIR}
                     SOURCE_SUBDIR metis
                     BUILD_COMMAND make -j ${NUM_PROC}
                     INSTALL_COMMAND make install
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                -DGKLIB_PATH=../metis/metis/GKlib
                                -DCMAKE_C_COMPILER=${MPI_C_COMPILER}
                                -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
                                -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
                                -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -DMETIS_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

list(APPEND build_list metis )


################################
# SUPERLU --
################################
set(SUPERLU_DIR "${CMAKE_INSTALL_PREFIX}/superlu_dist")
set(SUPERLU_URL "${TPL_MIRROR_DIR}/superlu_dist-6.0.0-trisolve.tar.gz")

message(STATUS "Building SUPERLU found at ${SUPERLU_URL}")
ExternalProject_Add( superlu_dist
                     PREFIX ${PROJECT_BINARY_DIR}/superlu_dist
                     URL ${SUPERLU_URL}
                     INSTALL_DIR ${SUPERLU_DIR}
                     BUILD_COMMAND make -j VERBOSE=1
                     INSTALL_COMMAND make install
                     DEPENDS parmetis metis ${MATH_LIBRARIES}
                     CMAKE_CACHE_ARGS -DTPL_PARMETIS_INCLUDE_DIRS:STRING=${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include
                                      -DTPL_PARMETIS_LIBRARIES:STRING=${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/libmetis.a
                     CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                -D XSDK_INDEX_SIZE=64
                                -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -D CMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
                                -D MPI_C_COMPILER=${MPI_C_COMPILER}
                                -D MPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                -D CMAKE_C_FLAGS=${C_FLAGS_NO_WARNINGS}
                                -D CMAKE_CXX_FLAGS=${CXX_FLAGS_NO_WARNINGS}
                                -D CMAKE_Fortran_FLAGS=${CMAKE_Fortran_FLAGS}
                                -D CMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                -D SUPERLU_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                -D TPL_BLAS_LIBRARIES=${SUPERLU_BLAS_LIBRARIES}
                                -D TPL_LAPACK_LIBRARIES=${SUPERLU_LAPACK_LIBRARIES}
        )

list(APPEND build_list superlu_dist )


################################
# HYPRE
################################

set(HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre")
set(HYPRE_URL "${TPL_MIRROR_DIR}/hypre-2.15.0.tar.gz")

message(STATUS "Building HYPRE found at ${HYPRE_URL}")

set(HYPRE_C_FLAGS "-fPIC ${CMAKE_C_FLAGS}")
set(HYPRE_CXX_FLAGS "-fPIC ${CMAKE_CXX_FLAGS}")
set(HYPRE_Fortran_FLAGS "-fPIC ${CMAKE_Fortran_FLAGS}")

ExternalProject_Add( hypre
                     URL ${HYPRE_URL}
                     PREFIX ${PROJECT_BINARY_DIR}/hypre
                     INSTALL_DIR ${HYPRE_DIR}
                     DEPENDS superlu_dist ${MATH_LIBRARIES}
                     BINARY_DIR ${PROJECT_BINARY_DIR}/hypre/src/hypre/src
                     CONFIGURE_COMMAND ./configure CC=${MPI_C_COMPILER}
                                          CXX=${MPI_CXX_COMPILER}
                                          FC=${CMAKE_Fortran_COMPILER}
                                          --prefix=<INSTALL_DIR>
                                          --enable-bigint
                                          --with-blas-lib-dirs=${BLAS_LIBRARY_DIRS}
                                          --with-blas-libs=${BLAS_LIBRARY_NAMES}
                                          --with-lapack-lib-dirs=${LAPACK_LIBRARY_DIRS}
                                          --with-lapack-libs=${LAPACK_LIBRARY_NAMES}
                                          --with-dsuperlu
                                          --with-dsuperlu-include=${CMAKE_INSTALL_PREFIX}/superlu_dist/include
                                          --with-dsuperlu-lib=${CMAKE_INSTALL_PREFIX}/superlu_dist/lib64/libsuperlu_dist.a
                                          CFLAGS=${HYPRE_C_FLAGS}
                                          CXXFLAGS=${HYPRE_CXX_FLAGS}
                                          FCFLAGS=${HYPRE_Fortran_FLAGS}
                     BUILD_COMMAND make -j ${NUM_PROC} VERBOSE=1
                     INSTALL_COMMAND make install
                  )

list(APPEND build_list hypre )


################################
# Create target that builds all dependencies
################################
message(STATUS "Building= ${build_list}")

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )

add_dependencies( tpl ${build_list}  )
