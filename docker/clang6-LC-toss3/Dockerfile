FROM geosx/compiler:LC-toss3

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"

#ARG GEOSXCI_GITHUB_PAT=local TRAVIS_COMMIT=local
ENV CC=/usr/tce/packages/clang/clang-6.0.1/bin/clang \
    CXX=/usr/tce/packages/clang/clang-6.0.1/bin/clang++ \
    FC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran \
    OMPI_CC=/usr/tce/packages/clang/clang-6.0.1/bin/clang \
    OMPI_CXX=/usr/tce/packages/clang/clang-6.0.1/bin/clang++ \
    OMPI_MPIFC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran \
    OMPI_MPIF77=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran \
    OMPI_MPIF90=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIFC=/usr/lib64/openmpi/bin/mpifort \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun 
#    GEOSXCI_GITHUB_PAT ${GEOSXCI_GITHUB_PAT} \
#    TRAVIS_COMMIT ${TRAVIS_COMMIT}

USER geosx
WORKDIR /home/geosx

COPY clang-6.0.1-public-1-1.tce.ch6_2.x86_64.rpm clang-6.0.1-1-1.tce.ch6_2.x86_64.rpm /home/geosx/

RUN sudo yum -y install clang-6.0.1-1-1.tce.ch6_2.x86_64.rpm &&\
    rm /home/geosx/clang-6.0.1-public-1-1.tce.ch6_2.x86_64.rpm &&\
    rm /home/geosx/clang-6.0.1-1-1.tce.ch6_2.x86_64.rpm

COPY thirdPartyLibs /home/geosx/thirdPartyLibs_repo
RUN python /home/geosx/thirdPartyLibs_repo/scripts/config-build.py -hc /home/geosx/thirdPartyLibs_repo/host-configs/environment.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-environment-release --installpath /home/geosx/thirdPartyLibs/install-environment-release &&\
    cd /home/geosx/thirdPartyLibs/build-environment-release &&\
    make &&\
    cd ~ &&\
    sudo rm -rf /home/geosx/thirdPartyLibs_repo /home/geosx/thirdPartyLibs/build-environment-release 

