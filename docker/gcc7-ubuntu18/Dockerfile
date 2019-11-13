FROM geosx/compiler:ubuntu18

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"
ENV gccver=7 \
    CC=gcc \
    CXX=g++ \
    FC=gfortran \
    OMPI_CC=gcc \
    OMPI_CXX=g++ \
    OMPI_MPIFC=gfortran \
    OMPI_MPIF77=gfortran \
    OMPI_MPIF90=gfortran \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIFC=/usr/bin/mpifort \
    MPIEXEC=/usr/bin/mpirun

RUN sudo apt-get update

USER geosx
WORKDIR /home/geosx

RUN sudo apt-get --assume-yes install gfortran-7 &&\
    cd /usr/bin &&\
    sudo ln -s gfortran-7 gfortran &&\
    sudo ln -s g77 &&\
    sudo ln -s g90 &&\
    sudo apt-get --assume-yes install openmpi-bin libopenmpi-dev

#RUN git clone --depth=50  https://${GEOSXCI_GITHUB_PAT}@github.com/GEOSX/thirdPartyLibs.git  /home/geosx/thirdPartyLibs_repo &&\
#    cd /home/geosx/thirdPartyLibs_repo  &&\
#    git lfs install &&\
#    git fetch origin +refs/pull/*:refs/origin/pull/* &&\
#    git checkout -f ${TRAVIS_COMMIT} &&\
#    git submodule update --init --recursive

COPY thirdPartyLibs /home/geosx/thirdPartyLibs_repo
RUN python /home/geosx/thirdPartyLibs_repo/scripts/config-build.py -hc /home/geosx/thirdPartyLibs_repo/host-configs/environment.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-environment-release --installpath /home/geosx/thirdPartyLibs/install-environment-release &&\
    cd /home/geosx/thirdPartyLibs/build-environment-release &&\
    make &&\
    cd ~ &&\
    sudo rm -rf /home/geosx/thirdPartyLibs_repo /home/geosx/thirdPartyLibs/build-environment-release

