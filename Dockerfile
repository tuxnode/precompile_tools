FROM alpine:latest AS builder

LABEL maintainer="Static Build Environment"
LABEL description="Alpine-based universal environment for compiling statically linked binaries"

RUN apk add --no-cache \
    build-base \
    linux-headers \
    cmake \
    git \
    wget \
    curl \
    file \
    openssl-dev openssl-libs-static \
    readline-dev readline-static \
    ncurses-dev ncurses-static \
    zlib-dev zlib-static

WORKDIR /out
CMD ["/bin/sh"]
