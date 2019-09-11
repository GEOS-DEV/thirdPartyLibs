FROM geosx/compiler:ubuntu18

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"
ENV gccver=8 \
    CC=gcc-8 \
    CXX=g++-8 \
    FC=gfortran-8 \
    OMPI_CC=gcc-8 \
    OMPI_CXX=g++-8 \
    OMPI_MPIFC=gfortran-8 \
    OMPI_MPIF77=gfortran-8 \
    OMPI_MPIF90=gfortran-8 \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIFC=/usr/bin/mpifort \
    MPIEXEC=/usr/bin/mpirun

USER geosx
WORKDIR /home/geosx

RUN sudo apt-get -qq install -y --no-install-recommends g++-${gccver} &&\
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${gccver} 100 &&\
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${gccver} 100 &&\
    sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-${gccver} 100 &&\
    sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-${gccver} 100 &&\
    sudo apt-get --assume-yes install gfortran-8 &&\
    cd /usr/bin &&\
    sudo ln -s gfortran-8 gfortran &&\
    sudo ln -s g77 &&\
    sudo ln -s g90 &&\
    sudo apt-get --assume-yes install openmpi-bin libopenmpi-dev

COPY thirdPartyLibs /home/geosx/thirdPartyLibs_repo
RUN python /home/geosx/thirdPartyLibs_repo/scripts/config-build.py -hc /home/geosx/thirdPartyLibs_repo/host-configs/environment.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-environment-release --installpath /home/geosx/thirdPartyLibs/install-environment-release &&\
    cd /home/geosx/thirdPartyLibs/build-environment-release &&\
    make &&\
    cd ~ &&\
    sudo rm -rf /home/geosx/thirdPartyLibs_repo /home/geosx/thirdPartyLibs/build-environment-release
