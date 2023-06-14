# Retrieve the compilers, standard libraries... from the CPU configuration
include(${CMAKE_CURRENT_LIST_DIR}/pecan-CPU.cmake)

# Now let's add what's dedicated to GPU.
set(ENABLE_CUDA ON CACHE PATH "" FORCE)
set(CUDA_TOOLKIT_ROOT_DIR /hrtc/apps/cuda/11.2.0/x86_64 CACHE PATH "")
set(CMAKE_CUDA_HOST_COMPILER ${CMAKE_CXX_COMPILER} CACHE STRING "")
set(CMAKE_CUDA_COMPILER ${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc CACHE STRING "")

set(CUDA_ARCH sm_75 CACHE STRING "")
set(CMAKE_CUDA_STANDARD 14 CACHE STRING "")
### The inclusion of -std=c++14 is a workaround for a cuda10/gcc8 bug ###
set(CMAKE_CUDA_FLAGS "-restrict -arch ${CUDA_ARCH} --expt-relaxed-constexpr --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations -Xcompiler -std=c++14" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_RELEASE "-O3 -DNDEBUG -Xcompiler -DNDEBUG -Xcompiler -O3" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_RELWITHDEBINFO "-g -lineinfo ${CMAKE_CUDA_FLAGS_RELEASE}" CACHE STRING "")
set(CMAKE_CUDA_FLAGS_DEBUG "-g -G -O0 -Xcompiler -O0" CACHE STRING "")

# Current version of hypre does not build with GPU support inside of docker.
# Hypre's build system awaits to be embedded into a CUDA environment.
# This is a bit tedious to reproduce in docker environment.
# And since most recent version of hypre do build without this constraint.
# Let's wait for an upgrade on our side.
# In the mean time, if you need the GPU support for hypre,
# simply install the classical way, with some `module load cuda`.
#set(ENABLE_HYPRE_CUDA ON CACHE BOOL "" FORCE)
