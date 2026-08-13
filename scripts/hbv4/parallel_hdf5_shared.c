#include <hdf5.h>
#include <mpi.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int any_rank_failed(int local_failure)
{
  int global_failure = 0;
  if (MPI_Allreduce(&local_failure, &global_failure, 1, MPI_INT, MPI_MAX,
                    MPI_COMM_WORLD) != MPI_SUCCESS) {
    return 1;
  }
  return global_failure;
}

int main(int argc, char **argv)
{
  hid_t file_access = H5I_INVALID_HID;
  hid_t file = H5I_INVALID_HID;
  hid_t file_space = H5I_INVALID_HID;
  hid_t memory_space = H5I_INVALID_HID;
  hid_t dataset = H5I_INVALID_HID;
  hid_t transfer = H5I_INVALID_HID;
  int mpi_initialized = 0;
  int rank = -1;
  int size = 0;
  int local_failure = 0;
  int global_failure = 0;
  int value = 0;
  int observed = -1;
  hsize_t dimensions[1];
  hsize_t start[1];
  hsize_t count[1] = {1};
  const char *path = NULL;

  if (MPI_Init(&argc, &argv) != MPI_SUCCESS) {
    fputs("MPI_Init failed\n", stderr);
    return EXIT_FAILURE;
  }
  mpi_initialized = 1;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);

  if (argc != 2 || size != 4) {
    if (rank == 0) {
      fprintf(stderr, "usage: %s FILE (must run with exactly four ranks)\n",
              argv[0]);
    }
    local_failure = 1;
    goto cleanup;
  }
  path = argv[1];
  dimensions[0] = (hsize_t)size;
  start[0] = (hsize_t)rank;
  value = 0x48420000 + rank;

  file_access = H5Pcreate(H5P_FILE_ACCESS);
  local_failure = file_access < 0 ||
                  H5Pset_fapl_mpio(file_access, MPI_COMM_WORLD,
                                   MPI_INFO_NULL) < 0;
  if (any_rank_failed(local_failure)) goto cleanup;

  file = H5Fcreate(path, H5F_ACC_TRUNC, H5P_DEFAULT, file_access);
  local_failure = file < 0;
  if (any_rank_failed(local_failure)) goto cleanup;

  file_space = H5Screate_simple(1, dimensions, NULL);
  dataset = file_space < 0
                ? H5I_INVALID_HID
                : H5Dcreate2(file, "rank-values", H5T_NATIVE_INT, file_space,
                             H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
  local_failure = file_space < 0 || dataset < 0;
  if (any_rank_failed(local_failure)) goto cleanup;

  if (H5Sclose(file_space) < 0) local_failure = 1;
  file_space = H5I_INVALID_HID;
  file_space = H5Dget_space(dataset);
  memory_space = H5Screate_simple(1, count, NULL);
  transfer = H5Pcreate(H5P_DATASET_XFER);
  local_failure = local_failure || file_space < 0 || memory_space < 0 ||
                  transfer < 0;
  if (!local_failure) {
    local_failure = H5Sselect_hyperslab(file_space, H5S_SELECT_SET, start, NULL,
                                       count, NULL) < 0 ||
                    H5Pset_dxpl_mpio(transfer, H5FD_MPIO_COLLECTIVE) < 0;
  }
  if (any_rank_failed(local_failure)) goto cleanup;

  local_failure = H5Dwrite(dataset, H5T_NATIVE_INT, memory_space, file_space,
                           transfer, &value) < 0;
  if (any_rank_failed(local_failure)) goto cleanup;
  local_failure = H5Fflush(file, H5F_SCOPE_GLOBAL) < 0;
  if (any_rank_failed(local_failure)) goto cleanup;

  local_failure = H5Dread(dataset, H5T_NATIVE_INT, memory_space, file_space,
                          transfer, &observed) < 0 ||
                  observed != value;
  global_failure = any_rank_failed(local_failure);
  if (global_failure && rank == 0) {
    fputs("collective HDF5 read-back verification failed\n", stderr);
  }

cleanup:
  global_failure = any_rank_failed(local_failure || global_failure);
  if (transfer >= 0 && H5Pclose(transfer) < 0) global_failure = 1;
  if (memory_space >= 0 && H5Sclose(memory_space) < 0) global_failure = 1;
  if (file_space >= 0 && H5Sclose(file_space) < 0) global_failure = 1;
  if (dataset >= 0 && H5Dclose(dataset) < 0) global_failure = 1;
  if (file >= 0 && H5Fclose(file) < 0) global_failure = 1;
  if (file_access >= 0 && H5Pclose(file_access) < 0) global_failure = 1;

  if (mpi_initialized) {
    int close_failure = any_rank_failed(global_failure);
    MPI_Barrier(MPI_COMM_WORLD);
    if (rank == 0 && path != NULL && unlink(path) != 0) {
      perror("unlink shared HDF5 test file");
      close_failure = 1;
    }
    global_failure = any_rank_failed(close_failure);
    MPI_Finalize();
  }

  if (!global_failure && rank == 0) {
    puts("parallel HDF5 shared-file verification passed with four ranks");
  }
  return global_failure ? EXIT_FAILURE : EXIT_SUCCESS;
}
