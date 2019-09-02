FROM geosx/compiler:LC-toss3

LABEL maintainer="Randolph Settgast <settgast1@llnl.gov>"

ENV CC=/usr/tce/packages/clang/clang-7.0.0/bin/clang
ENV CXX=/usr/tce/packages/clang/clang-7.0.0/bin/clang++
ENV FC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV OMPI_CC=/usr/tce/packages/clang/clang-7.0.0/bin/clang
ENV OMPI_CXX=/usr/tce/packages/clang/clang-7.0.0/bin/clang++
ENV OMPI_MPIFC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV OMPI_MPIF77=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV OMPI_MPIF90=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran
ENV MPICC=/usr/lib64/openmpi/bin/mpicc
ENV MPICXX=/usr/lib64/openmpi/bin/mpicxx
ENV MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV MPIEXEC=/usr/lib64/openmpi/bin/mpirun

USER geosx
WORKDIR /home/geosx

COPY clang-7.0.0-public-1-1.tce.ch6_2.x86_64.rpm /home/geosx/clang-7.0.0-public-1-1.tce.ch6_2.x86_64.rpm
COPY clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm /home/geosx/clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm
COPY thirdPartyLibs /home/geosx/thirdPartyLibs_repo

RUN sudo yum -y install clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm
RUN rm /home/geosx/clang-7.0.0-public-1-1.tce.ch6_2.x86_64.rpm
RUN rm /home/geosx/clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm
RUN cd thirdPartyLibs_repo
RUN python scripts/config-build.py -hc host-configs/default.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-default-release --installpath /home/geosx/thirdPartyLibs/install-default-release
RUN cd /home/geosx/thirdPartyLibs/build-default-release
RUN make
RUN cd ~
RUN rm -rf /home/geosx/thirdPartyLibs_repo
RUN rm -rf /home/geosx/thirdPartyLibs/build-default-release

