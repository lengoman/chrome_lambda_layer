FROM public.ecr.aws/lambda/provided:al2023
RUN dnf update -y && \
    dnf install -y wget tar gzip make gcc && \
    wget https://ftp.gnu.org/gnu/glibc/glibc-2.29.tar.gz && \
    tar xzf glibc-2.29.tar.gz && \
    cd glibc-2.29 && \
    mkdir build && \
    cd build && \
    ../configure --prefix=/output && \
    make -j$(nproc) && \
    make install
