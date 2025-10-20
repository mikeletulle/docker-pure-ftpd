# -------------------------------
# Stage 1 : Builder image
# -------------------------------
FROM debian:bullseye as builder

# Properly setup Debian sources
ENV DEBIAN_FRONTEND=noninteractive
RUN echo "deb http://deb.debian.org/debian bullseye main\n\
deb-src http://deb.debian.org/debian bullseye main\n\
deb http://deb.debian.org/debian bullseye-updates main\n\
deb-src http://deb.debian.org/debian bullseye-updates main\n\
deb http://security.debian.org bullseye-security main\n\
deb-src http://security.debian.org bullseye-security main\n" \
> /etc/apt/sources.list

# Install package-building helpers
RUN apt-get -y update && \
    apt-get -y install dpkg-dev debhelper && \
    apt-get -y build-dep pure-ftpd

# Build from source – remove extra CAP requirements
RUN mkdir /tmp/pure-ftpd && \
    cd /tmp/pure-ftpd && \
    apt-get source pure-ftpd && \
    cd pure-ftpd-* && \
    ./configure --with-tls | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory' && \
    sed -i '/CAP_SYS_NICE,/d; /CAP_DAC_READ_SEARCH/d; s/CAP_SYS_CHROOT,/CAP_SYS_CHROOT/;' src/caps_p.h && \
    dpkg-buildpackage -b -uc | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory'

# -------------------------------
# Stage 2 : Final runtime image
# -------------------------------
FROM debian:bullseye-slim

LABEL maintainer="Andrew Stilliard <andrew.stilliard@gmail.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get -y update && \
    apt-get --no-install-recommends

