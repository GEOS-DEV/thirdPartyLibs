cmake_minimum_required(VERSION 3.9)
################################
# GEOS_TPL
################################
project(geosx_tpl LANGUAGES C CXX)

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
option( RAJA_ENABLE_TBB "" OFF)

option( ENABLE_CALIPER "" OFF )
option( ENABLE_TRILINOS "" ON )

set(NUM_PROC "8" CACHE PATH "")
set(TPL_MIRROR_DIR "${CMAKE_SOURCE_DIR}/tpl_mirror")
set(build_list )
set(existing_list )


################################
# UNCRUSTIFY
################################
set(UNCRUSTIFY_DIR "${CMAKE_INSTALL_PREFIX}/uncrustify")
set(UNCRUSTIFY_URL "${TPL_MIRROR_DIR}/uncrustify-0.67.tar.gz")

if (EXISTS ${UNCRUSTIFY_DIR})
    message(STATUS "Using existing Uncrustify found at ${UNCRUSTIFY_DIR}")
    list(APPEND existing_list uncrustify )
else()
    message(STATUS "Building uncrustify found at ${UNCRUSTIFY_URL}")

    ExternalProject_Add( uncrustify
                         URL ${UNCRUSTIFY_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/uncrustify
                         INSTALL_DIR ${UNCRUSTIFY_DIR}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                     )                                      

    list(APPEND build_list uncrustify )
endif()


################################
# HDF5
################################
set( HDF5_DEPENDENCIES "" )
if (EXISTS ${HDF5_DIR})
    message(STATUS "Using existing HDF5 found at ${HDF5_DIR}")
    list(APPEND existing_list hdf5 )
else()
    set(HDF5_DIR "${CMAKE_INSTALL_PREFIX}/hdf5")
#    set(HDF5_URL "${TPL_MIRROR_DIR}/hdf5-1.8.21.tar.gz")
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
endif()


################################
# Conduit
################################
set(CONDUIT_DIR "${CMAKE_INSTALL_PREFIX}/conduit")
set(CONDUIT_URL "${TPL_MIRROR_DIR}/conduit-0.3.2.tar.gz")

if (EXISTS ${CONDUIT_DIR})
    message(STATUS "Using existing Conduit found at ${CONDUIT_DIR}")
    list(APPEND existing_list conduit )
else()
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

                                    -DENABLE_OPENMP=${ENABLE_OPENMP}
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install )

    list(APPEND build_list conduit )
endif()


################################
# Axom
################################
set(AXOM_DIR "${CMAKE_INSTALL_PREFIX}/axom")
set(AXOM_URL "${TPL_MIRROR_DIR}/axom-0.2.9.tar.gz")

if (EXISTS ${AXOM_DIR})
    message(STATUS "Using existing Axom found at ${AXOM_DIR}")
    list(APPEND existing_list axom )
else()
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
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install )

    list(APPEND build_list axom )
endif()


################################
# SILO
################################
set(SILO_DIR "${CMAKE_INSTALL_PREFIX}/silo")
set(SILO_URL "${TPL_MIRROR_DIR}/silo-4.10.3.mpiposix_patch.tar.gz")

if (EXISTS ${SILO_DIR})
    message(STATUS "Using existing SILO found at ${SILO_DIR}")
    list(APPEND existing_list silo )
else()
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
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install )

    list(APPEND build_list silo )
endif()


################################
# RAJA
################################
set(RAJA_DIR "${CMAKE_INSTALL_PREFIX}/raja")
set(RAJA_URL "${TPL_MIRROR_DIR}/RAJA-0.6.0rc3.tar.gz")

if (EXISTS ${RAJA_DIR})
    message(STATUS "Using existing RAJA found at ${RAJA_DIR}")
    list(APPEND existing_list raja )
else()
    message(STATUS "Building RAJA found at ${RAJA_URL}")

    ExternalProject_Add( raja
                         URL ${RAJA_URL}
                         PREFIX ${PROJECT_BINARY_DIR}/raja
                         INSTALL_DIR ${RAJA_DIR}
                         PATCH_COMMAND pwd && cp -r ${BLT_SOURCE_DIR} .
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
#                                    -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                    -DRAJA_ENABLE_CUDA=${CUDA_ENABLED}
                                    -DENABLE_TESTS=${RAJA_ENABLE_TESTS}
                                    -DRAJA_ENABLE_TBB=${RAJA_ENABLE_TBB}
                                    -DENABLE_OPENMP=${ENABLE_OPENMP}
                 		            -DRAJA_ENABLE_OPENMP=${ENABLE_OPENMP} 
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                        )

    list(APPEND build_list raja )
endif()


################################
# CHAI
################################
if (EXISTS ${CHAI_DIR})
    message(STATUS "Using existing CHAI found at ${CHAI_DIR}")
    list(APPEND existing_list chai )
else()
    set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
    set(CHAI_URL "${TPL_MIRROR_DIR}/chai-08_01_2018.tar.gz")
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
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DENABLE_CUDA=${CUDA_ENABLED}
                                    -DENABLE_OPENMP=${ENABLE_OPENMP}
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DENABLE_TESTS=OFF
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                        )

    list(APPEND build_list chai )
endif()






################################
# FPARSER
################################
set(FPARSER_DIR "${CMAKE_INSTALL_PREFIX}/fparser")
set(FPARSER_URL "${TPL_MIRROR_DIR}/fparser4.5.2.zip")

if (EXISTS ${FPARSER_DIR})
    message(STATUS "Using existing FPARSER found at ${FPARSER_DIR}")
    list(APPEND existing_list fparser )
else()
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
endif()


################################
# CALIPER
################################
if (NOT ENABLE_CALIPER)
    message(STATUS "CALIPER disabled")
else()
    set(CALIPER_DIR "${CMAKE_INSTALL_PREFIX}/caliper")
    set(CALIPER_URL "${TPL_MIRROR_DIR}/Caliper-08-06-2018.tar.gz")

    if (EXISTS ${CALIPER_DIR})
        message(STATUS "Using existing CALIPER found at ${CALIPER_DIR}")
        list(APPEND existing_list caliper )
    else()
        message(STATUS "Building CALIPER found at ${CALIPER_URL}")

        ExternalProject_Add( caliper
                             URL ${CALIPER_URL}
                             PREFIX ${PROJECT_BINARY_DIR}/caliper
                             INSTALL_DIR ${CALIPER_DIR}
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                        -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        #-DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DWITH_PAPI=${ENABLE_PAPI}
                                        -DPAPI_PREFIX=${PAPI_PREFIX}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

        list(APPEND build_list caliper )
    endif()
endif()


################################
# MATHPRESSO/ASMJIT
################################
set(MATHPRESSO_DIR "${CMAKE_INSTALL_PREFIX}/mathpresso")
set(MATHPRESSO_URL "${TPL_MIRROR_DIR}/mathpresso-2015-12-15.tar.gz")
set(ASMJIT_URL "${TPL_MIRROR_DIR}/asmjit-2016-07-20.tar.gz")

if (EXISTS ${MATHPRESSO_DIR})
    message(STATUS "Using existing MATHPRESSO found at ${MATHPRESSO_DIR}")
    list(APPEND existing_list mathpresso )
else()
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
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
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

if (EXISTS ${PUGIXML_DIR})
    message(STATUS "Using existing PUGIXML found at ${PUGIXML_DIR}")
    list(APPEND existing_list pugixml )
else()
    message(STATUS "Building PUGIXML found at ${PUGIXML_URL}")

    ExternalProject_Add( pugixml
                         PREFIX ${PROJECT_BINARY_DIR}/pugixml
                         URL ${PUGIXML_URL}
                         INSTALL_DIR ${PUGIXML_DIR}
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE} )

    list(APPEND build_list pugixml )
endif()


################################
# TRILINOS
################################
if (ENABLE_TRILINOS)
    set(TRILINOS_DIR "${CMAKE_INSTALL_PREFIX}/trilinos")
    set(TRILINOS_URL "${TPL_MIRROR_DIR}/trilinos-12.10.1-Source.tar.gz")

    if (EXISTS ${TRILINOS_DIR})
        message(STATUS "Using existing TRILINOS found at ${TRILINOS_DIR}")
        list(APPEND existing_list trilinos )
    else()
        message(STATUS "Building TRILINOS found at ${TRILINOS_URL}")

        ExternalProject_Add( trilinos
                             PREFIX ${PROJECT_BINARY_DIR}/trilinos
                             URL ${TRILINOS_URL}
                             INSTALL_DIR ${TRILINOS_DIR}
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -D CMAKE_C_COMPILER=${MPI_C_COMPILER}
                                        -D CMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -D CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -D TPL_ENABLE_MPI:BOOL=ON 
                                        -D BUILD_SHARED_LIBS:BOOL=ON
                                        -D CMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                        -D Trilinos_ENABLE_Fortran:BOOL=OFF 
                                        -D Trilinos_WARNINGS_AS_ERRORS_FLAGS:STRING="" 
                                        -D CMAKE_VERBOSE_MAKEFILE:BOOL=TRUE 
                                        -D Trilinos_ENABLE_TESTS:BOOL=OFF 
                                        -D Trilinos_ENABLE_ALL_PACKAGES:BOOL=FALSE 
                                        -D Trilinos_ENABLE_ALL_OPTIONAL_PACKAGES:BOOL=ON 
                                        -D Trilinos_ENABLE_Epetra:BOOL=ON 
                                        -D Trilinos_ENABLE_EpetraExt:BOOL=ON 
                                        -D Trilinos_ENABLE_Tpetra:BOOL=ON 
                                        -D Trilinos_ENABLE_Jpetra:BOOL=ON 
                                        -D Trilinos_ENABLE_Kokkos:BOOL=ON 
                                        -D Trilinos_ENABLE_Mesquite:BOOL=ON 
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
                                        -D Trilinos_ENABLE_Boost=OFF
                                        -D Trilinos_ENABLE_STK=OFF
                                        -D Trilinos_ENABLE_TrilinosCouplings:BOOL=ON
                                        -D TPL_BLAS_LIBRARIES=${TRILINOS_TPL_BLAS_LIBRARIES}
                                        -D TPL_BLAS_INCLUDE_DIRS=${TRILINOS_TPL_BLAS_INCLUDE_DIRS}
                                        -D TPL_LAPACK_LIBRARIES=${TRILINOS_TPL_LAPACK_LIBRARIES}
                                        -D TPL_LAPACK_INCLUDE_DIRS=${TRILINOS_TPL_LAPACK_INCLUDE_DIRS} )

        list(APPEND build_list trilinos )
    endif()
endif()





################################
# PARMETIS
# (also METIS is built; note that the idx_t data type is defined to be 
#  64 bit signed integer)
################################
set(PARMETIS_DIR "${CMAKE_INSTALL_PREFIX}/parmetis")
set(METIS_DIR "${CMAKE_INSTALL_PREFIX}/metis")
set(PARMETIS_URL "${TPL_MIRROR_DIR}/parmetis-4.0.3-IDXTYPEWIDTH_64.tar.gz")

if (EXISTS ${PARMETIS_DIR})
    message(STATUS "Using existing PARMETIS found at ${PARMETIS_DIR}")
    message(STATUS "Using existing METIS found at ${METIS_DIR}")
    list(APPEND existing_list parmetis )
    list(APPEND existing_list metis )
else()
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
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -DMETIS_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

    list(APPEND build_list metis )
endif()


################################
# SUPERLU
################################
set(SUPERLU_DIR "${CMAKE_INSTALL_PREFIX}/superlu_dist")
set(SUPERLU_URL "${TPL_MIRROR_DIR}/superlu_dist-6.0.0-trisolve.tar.gz")

if ( false ) #EXISTS ${SUPERLU_DIR})
    message(STATUS "Using existing SUPERLU found at ${SUPERLU_DIR}")
    list(APPEND existing_list superlu_dist )
else()
    message(STATUS "Building SUPERLU found at ${SUPERLU_URL}")

    set( PARMETIS_INCLUDE_DIRS "${CMAKE_INSTALL_PREFIX}/parmetis/include|${CMAKE_INSTALL_PREFIX}/metis/include" )
    set( PARMETIS_LIBRARIES "${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a|${CMAKE_INSTALL_PREFIX}/metis/lib/metis.a" )

#-DTPL_PARMETIS_INCLUDE_DIRS:STRING="${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include"
#                                    -DTPL_PARMETIS_LIBRARIES:STRING="${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/metis.a"
                                    #-DTPL_PARMETIS_INCLUDE_DIRS="${CMAKE_INSTALL_PREFIX}/parmetis/include"
                                    #-DTPL_PARMETIS_LIBRARIES="${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/parmetis/lib/metis.a"

#string(REPLACE ";" "|" CMAKE_PREFIX_PATH_ALT_SEP "${CMAKE_PREFIX_PATH}")

    ExternalProject_Add( superlu_dist
                         PREFIX ${PROJECT_BINARY_DIR}/superlu_dist
                         URL ${SUPERLU_URL}
                         INSTALL_DIR ${SUPERLU_DIR}
                         BUILD_COMMAND make VERBOSE=1
                         INSTALL_COMMAND make install
#                         DEPENDS parmetis metis
			  LIST_SEPARATOR |
                         CMAKE_ARGS -D CMAKE_BUILD_TYPE:STRING=RELEASE
                                    -DXSDK_INDEX_SIZE=64
                                    -DCMAKE_C_COMPILER=${MPI_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -DSUPERLU_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>				    
				    -DTPL_PARMETIS_INCLUDE_DIRS=${PARMETIS_INCLUDE_DIRS}
                                    -DTPL_PARMETIS_LIBRARIES=${PARMETIS_LIBRARIES}
			)
                         #CMAKE_CACHE_ARGS -DTPL_PARMETIS_INCLUDE_DIRS:STRING=" ${CMAKE_INSTALL_PREFIX}/parmetis/include;${CMAKE_INSTALL_PREFIX}/metis/include "
                                    #      -DTPL_PARMETIS_LIBRARIES:STRING="${CMAKE_INSTALL_PREFIX}/parmetis/lib/libparmetis.a;${CMAKE_INSTALL_PREFIX}/metis/lib/metis.a "
                                    #)

    list(APPEND build_list superlu_dist )
endif()





################################
# HYPRE
################################
#set(HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre")
#set(HYPRE_URL "${TPL_MIRROR_DIR}/hypre-2.15.0.tar.gz")
#
#if (EXISTS ${HYPRE_DIR})
#    message(STATUS "Using existing HYPRE found at ${HYPRE_DIR}")
#    list(APPEND existing_list hypre )
#else()
#    message(STATUS "Building HYPRE found at ${HYPRE_URL}")
#
#    ExternalProject_Add( hypre
#                         PREFIX ${PROJECT_BINARY_DIR}/hypre
#                         URL ${HYPRE_URL}
#                         INSTALL_DIR ${HYPRE_DIR}
#                         SOURCE_SUBDIR src
#                         DEPENDS superlu_dist
#                         BUILD_COMMAND make -j ${NUM_PROC}
#                         INSTALL_COMMAND make install
#                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
#                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
#                                    -DMPI_C_COMPILER=${MPI_C_COMPILER}
#                                    -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
#                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
#                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
#                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
#                                    -DHYPRE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
#                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )
#
#    list(APPEND build_list hypre )
#endif()


################################
# Create target that builds all dependencies
################################
message(STATUS "Existing= ${existing_list}")
message(STATUS "Building= ${build_list}")

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )
                    
add_dependencies( tpl ${build_list}  )
