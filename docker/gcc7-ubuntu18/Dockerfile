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
ARG GEOSXCI_GITHUB_PAT=local
ENV GEOSXCI_GITHUB_PAT ${GEOSXCI_GITHUB_PAT}
ARG TRAVIS_COMMIT=local
ENV TRAVIS_COMMIT ${TRAVIS_COMMIT}

USER geosx
WORKDIR /home/geosx

RUN sudo apt-get --assume-yes install gfortran-7 &&\
    cd /usr/bin &&\
    sudo ln -s gfortran-7 gfortran &&\
    sudo ln -s g77 &&\
    sudo ln -s g90 &&\
    sudo apt-get --assume-yes install openmpi-bin libopenmpi-dev

RUN git clone --depth=50  https://${GEOSXCI_GITHUB_PAT}@github.com/GEOSX/thirdPartyLibs.git  /home/geosx/thirdPartyLibs_repo &&\
    cd /home/geosx/thirdPartyLibs_repo  &&\
    git fetch origin +refs/pull/*:refs/origin/pull/* &&\
    git checkout -f ${TRAVIS_COMMIT} &&\
    git submodule update --init --recursive

RUN python /home/geosx/thirdPartyLibs_repo/scripts/config-build.py -hc /home/geosx/thirdPartyLibs_repo/host-configs/default.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-default-release --installpath /home/geosx/thirdPartyLibs/install-default-release &&\
    cd /home/geosx/thirdPartyLibs/build-default-release &&\
    make &&\
    cd ~ &&\
    sudo rm -rf /home/geosx/thirdPartyLibs_repo /home/geosx/thirdPartyLibs/build-default-release

