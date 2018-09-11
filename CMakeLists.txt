cmake_minimum_required(VERSION 3.5)
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

set(NUM_PROC "4" CACHE PATH "")
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
set(HDF5_DIR "${CMAKE_INSTALL_PREFIX}/hdf5")
set(HDF5_URL "${TPL_MIRROR_DIR}/hdf5-1.10.1.tar.gz")

if (EXISTS ${HDF5_DIR})
    message(STATUS "Using existing HDF5 found at ${HDF5_DIR}")
    list(APPEND existing_list hdf5 )
else()
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
                                               CFLAGS=-fPIC
                          BUILD_COMMAND make -j ${NUM_PROC}
                          INSTALL_COMMAND make install )

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
                         DEPENDS hdf5
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
if (ENABLE_TRIBOL)
   set(AXOM_DIR "${CMAKE_INSTALL_PREFIX}/axom")
   set(AXOM_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/axom.git")
   set(AXOM_TAG "ale3d")

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
                            DEPENDS hdf5 conduit
                            CMAKE_ARGS -DENABLE_DOCS=OFF
                                       -DENABLE_BENCHMARKS=OFF
                                       -DENABLE_EXAMPLES=OFF
                                       -DENABLE_FORTRAN=OFF
                                       -DENABLE_TESTS=OFF
                                       -DENABLE_ALL_COMPONENTS=OFF
                                       -DENABLE_LUMBERJACK=ON
                                       -DENABLE_MINT=ON
                                       -DENABLE_PRIMAL=ON
                                       -DENABLE_QUEST=ON
                                       -DENABLE_SIDRE=ON
                                       -DENABLE_SLAM=ON
                                       -DENABLE_SLIC=ON
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
                            BUILD_COMMAND make -j ${NUM_PROC}
                            INSTALL_COMMAND make install )
   endif()
else()
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
                            DEPENDS hdf5 conduit
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
                            BUILD_COMMAND make -j ${NUM_PROC}
                            INSTALL_COMMAND make install )

       list(APPEND build_list axom )
   endif()
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
                         DEPENDS hdf5
                         CONFIGURE_COMMAND ../silo/configure CC=${MPI_C_COMPILER}
                                              CXX=${MPI_CXX_COMPILER}
                                              --prefix=<INSTALL_DIR>
                                              --disable-fortran
                                              --enable-optimization
                                              --with-hdf5=${HDF5_DIR}/include,${HDF5_DIR}/lib
                                              LDFLAGS=-ldl
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
if (ENABLE_TRIBOL)
   set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
   set(CHAI_REPO "ssh://git@rz-stash.llnl.gov:7999/cudale/chai.git")
   set(CHAI_TAG "ale3d")

   if (EXISTS ${CHAI_DIR})
       message(STATUS "Using existing CHAI found at ${CHAI_DIR}")
       list(APPEND existing_list chai )
   else()
       message(STATUS "Building CHAI found at ${CHAI_TAG}")

       ExternalProject_Add( chai
                            PREFIX ${PROJECT_BINARY_DIR}/chai
                            GIT_REPOSITORY ${CHAI_REPO}
                            GIT_TAG ${CHAI_TAG}
                            INSTALL_DIR ${CHAI_DIR}
                            BUILD_COMMAND make -j ${NUM_PROC}
                            INSTALL_COMMAND make install
                            CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                       -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                       -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                       -DCHAI_BLT_REL_DIR=${BLT_SOURCE_DIR}
                                       -DENABLE_CUDA=${CUDA_ENABLED}
                                       -DENABLE_OPENMP=${ENABLE_OPENMP}
                                       -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                       -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                       -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                       -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                           )

       list(APPEND build_list chai )
   endif()
else()
   set(CHAI_DIR "${CMAKE_INSTALL_PREFIX}/chai")
   set(CHAI_URL "${TPL_MIRROR_DIR}/chai-07_16_2018.tar.gz")

   if (EXISTS ${CHAI_DIR})
       message(STATUS "Using existing CHAI found at ${CHAI_DIR}")
       list(APPEND existing_list chai )
   else()
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
                                       -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                           )

       list(APPEND build_list chai )
   endif()
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
    set(CALIPER_URL "${TPL_MIRROR_DIR}/Caliper-1.6.0.zip")

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
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
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
# HYPRE
################################
set(HYPRE_DIR "${CMAKE_INSTALL_PREFIX}/hypre")
set(HYPRE_URL "${TPL_MIRROR_DIR}/hypre-v2.14.0.tar.gz")

if (EXISTS ${HYPRE_DIR})
    message(STATUS "Using existing HYPRE found at ${HYPRE_DIR}")
    list(APPEND existing_list hypre )
else()
    message(STATUS "Building HYPRE found at ${HYPRE_URL}")

    ExternalProject_Add( hypre
                         PREFIX ${PROJECT_BINARY_DIR}/hypre
                         URL ${HYPRE_URL}
                         INSTALL_DIR ${HYPRE_DIR}
                         SOURCE_SUBDIR src
                         BUILD_COMMAND make -j ${NUM_PROC}
                         INSTALL_COMMAND make install
                         CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                    -DMPI_C_COMPILER=${MPI_C_COMPILER}
                                    -DMPI_CXX_COMPILER=${MPI_CXX_COMPILER}
                                    -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                    -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                    -DHYPRE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> )

    list(APPEND build_list hypre )
endif()

################################
# TRIBOL
################################
if (ENABLE_TRIBOL)
    set(TRIBOL_DIR "${CMAKE_INSTALL_PREFIX}/tribol")
    set(TRIBOL_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/tribol.git")
    set(TRIBOL_TAG "feature/benliu/slideWorld")

    if (EXISTS ${TRIBOL_DIR})
        message(STATUS "Using existing TRIBOL found at ${TRIBOL_DIR}")
        list(APPEND existing_list tribol)
    else()
        message(STATUS "Building TRIBOL found at ${TRIBOL_TAG}")

        ExternalProject_Add( tribol
                             PREFIX ${PROJECT_BINARY_DIR}/tribol
                             DOWNLOAD_COMMAND git clone ${TRIBOL_REPO}
                             UPDATE_COMMAND git checkout ${TRIBOL_TAG} && git pull
                             INSTALL_DIR ${TRIBOL_DIR}
                             DEPENDS axom conduit hdf5
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install &&
                                             mkdir -p <INSTALL_DIR>/include &&
                                             cp -r <SOURCE_DIR>/include/tribol <INSTALL_DIR>/include
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_CXX_FLAGS=${TPL_CXX_STANDARD}
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DTRIBOL_USE_EXTERNAL_AXOM:BOOL=TRUE
                                        -DTRIBOL_ENABLE_SIDRE:BOOL=TRUE
                                        -DAXOM_DIR=${AXOM_DIR}
                                        -DCONDUIT_DIR=${CONDUIT_DIR}
                                        -DHDF5_DIR=${HDF5_DIR}
                                        -DENABLE_TESTS=OFF
                                        -DENABLE_EXAMPLES=OFF
                                        -DENABLE_DOCS=OFF)

        list(APPEND build_list tribol)
    endif()

    set(LLNL_GLOBALID_DIR "${CMAKE_INSTALL_PREFIX}/LLNL_GlobalID")
    set(LLNL_GLOBALID_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/LLNL_GlobalID.git")
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

    set(RXB_DIR "${CMAKE_INSTALL_PREFIX}/rxb")
    set(RXB_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/rxb.git")
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
                                        -DCMAKE_CXX_FLAGS="${TPL_CXX_STANDARD} -DGLOBALID_IS_64BIT=1"
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
    set(VISTA_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/vista.git")
    set(VISTA_TAG "ale3d")

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
                             DEPENDS LLNL_GlobalID chai
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                                        -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS="${TPL_CXX_STANDARD} -DGLOBALID_IS_64BIT=1"
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DVISTA_BLT_REL_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DCHAI_DIR=${CHAI_DIR}
                                        -DHDF5_DIR=${HDF5_DIR}
                                        -DSILO_DIR=${SILO_DIR}
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list vista)
    endif()

    set(WORLDS_CORE_DIR "${CMAKE_INSTALL_PREFIX}/worlds_core")
    set(WORLDS_CORE_REPO "ssh://git@rz-stash.llnl.gov:7999/ale/worlds_core.git")
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
                             DEPENDS rxb vista LLNL_GlobalID chai
                             BUILD_COMMAND make -j ${NUM_PROC}
                             INSTALL_COMMAND make install
                             CMAKE_ARGS -DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}
                                        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                                        -DCMAKE_CXX_FLAGS="${TPL_CXX_STANDARD} -DGLOBALID_IS_64BIT=1"
                                        -DCMAKE_VERBOSE_MAKEFILE:BOOL=TRUE
                                        -DENABLE_MPI:BOOL=TRUE
                                        -DBLT_SOURCE_DIR=${BLT_SOURCE_DIR}
                                        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                                        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
                                        -DCMAKE_POSITION_INDEPENDENT_CODE=${CMAKE_POSITION_INDEPENDENT_CODE}
                                        -DRXB_DIR=${RXB_DIR}
                                        -DVISTA_DIR=${VISTA_DIR}
                                        -DCHAI_DIR=${CHAI_DIR}
                                        -DLLNL_GLOBALID_DIR=${LLNL_GLOBALID_DIR})

        list(APPEND build_list worlds_core)
    endif()

endif()



################################
# Create target that builds all dependencies
################################
message(STATUS "Existing= ${existing_list}")
message(STATUS "Building= ${build_list}")

blt_add_executable( NAME             tpl
                    SOURCES          tpl.cpp )
                    
add_dependencies( tpl ${build_list} )
