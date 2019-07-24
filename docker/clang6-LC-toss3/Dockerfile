FROM geosx/compiler:LC-toss3

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"

ENV CC=/usr/tce/packages/clang/clang-6.0.1/bin/clang
ENV CXX=/usr/tce/packages/clang/clang-6.0.1/bin/clang++
ENV FC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV OMPI_CC=/usr/tce/packages/clang/clang-6.0.1/bin/clang
ENV OMPI_CXX=/usr/tce/packages/clang/clang-6.0.1/bin/clang++
ENV OMPI_MPIF77=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV OMPI_MPIF90=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV MPICC=/usr/lib64/openmpi/bin/mpicc
ENV MPICXX=/usr/lib64/openmpi/bin/mpicxx
ENV MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV MPIEXEC=/usr/lib64/openmpi/bin/mpirun

ADD setup.sh /home/geosx/setup.sh
ADD buildtpl.sh /home/geosx/buildtpl.sh
ADD clang-6.0.1-public-1-1.tce.ch6_2.x86_64.rpm /home/geosx/clang-6.0.1-public-1-1.tce.ch6_2.x86_64.rpm
ADD clang-6.0.1-1-1.tce.ch6_2.x86_64.rpm /home/geosx/clang-6.0.1-1-1.tce.ch6_2.x86_64.rpm

RUN /home/geosx/setup.sh

USER geosx
WORKDIR /home/geosx