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
    apt-get --no-install-recommends --yes install \
        libc6 \
        libcap2 \
        libmariadb3 \
        libpam0g \
        libssl1.1 \
        libsodium23 \
        lsb-base \
        openbsd-inetd \
        openssl \
        perl \
        rsyslog


# Copy compiled .deb packages from builder
COPY --from=builder /tmp/pure-ftpd/*.deb /tmp/pure-ftpd/

# Install the new deb files
RUN dpkg -i /tmp/pure-ftpd/pure-ftpd-common*.deb && \
    dpkg -i /tmp/pure-ftpd/pure-ftpd_*.deb && \
    rm -rf /tmp/pure-ftpd

# Prevent auto-upgrade of the built packages
RUN apt-mark hold pure-ftpd pure-ftpd-common

# Setup ftpgroup and ftpuser
RUN groupadd ftpgroup && \
    useradd -g ftpgroup -d /home/ftpusers -s /usr/sbin/nologin ftpuser

# Configure rsyslog logging
RUN echo "" >> /etc/rsyslog.conf && \
    echo "#PureFTP Custom Logging" >> /etc/rsyslog.conf && \
    echo "ftp.* /var/log/pure-ftpd/pureftpd.log" >> /etc/rsyslog.conf

# Copy startup script
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Cleanup
RUN apt-get -y clean && apt-get -y autoclean && apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

# Default public host (overridden by env var)
ENV PUBLICHOST=localhost

# Expose FTP ports
EXPOSE 21 30000-30009

# Volumes for data and passwd
VOLUME ["/home/ftpusers", "/etc/pure-ftpd/passwd"]

# Startup command
CMD ["bash", "-x", "/run.sh", "-c", "5", "-C", "10", "-l", "puredb:/etc/pure-ftpd/pureftpd.pdb", "-E", "-j", "-R", "-P", "${PUBLICHOST}", "-S", "0.0.0.0,${PORT}", "-p", "30000:30009"]


#CMD ["sleep", "3600"]
