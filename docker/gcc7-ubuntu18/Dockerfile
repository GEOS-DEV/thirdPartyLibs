FROM geosx/compiler:ubuntu18

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"
ENV gccver=7
ENV CC=gcc
ENV CXX=g++
ENV FC=gfortran
ENV OMPI_CC=gcc
ENV OMPI_CXX=g++
ENV OMPI_MPIFC=gfortran
ENV OMPI_MPIF77=gfortran
ENV OMPI_MPIF90=gfortran
ENV MPICC=/usr/bin/mpicc
ENV MPICXX=/usr/bin/mpicxx
ENV MPIFC=/usr/bin/mpifort
ENV MPIEXEC=/usr/bin/mpirun

COPY thirdPartyLibs /home/geosx/thirdPartyLibs_repo

ADD setup.sh /home/geosx/setup.sh
ADD buildtpl.sh /home/geosx/buildtpl.sh

RUN /home/geosx/setup.sh
RUN /home/geosx/buildtpl.sh

USER geosx
WORKDIR /home/geosx