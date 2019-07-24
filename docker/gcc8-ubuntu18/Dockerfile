FROM geosx/compiler:ubuntu18

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"
ENV gccver=8
ENV CC=gcc-8
ENV CXX=g++-8
ENV FC=gfortran-8
ENV OMPI_CC=gcc-8
ENV OMPI_CXX=g++-8
ENV OMPI_MPIF77=gfortran-8
ENV OMPI_MPIF90=gfortran-8
ENV MPICC=/usr/bin/mpicc
ENV MPICXX=/usr/bin/mpicxx
ENV MPIFC=/usr/bin/mpifort
ENV MPIEXEC=/usr/bin/mpirun

ADD setup.sh /home/geosx/setup.sh
ADD buildtpl.sh /home/geosx/buildtpl.sh

RUN /home/geosx/setup.sh

USER geosx
WORKDIR /home/geosx