# Use ubuntu:20.04 as base for builder stage image
FROM ubuntu:20.04 as builder

# Set Dinastycoin branch/tag to be used for dinastycoind compilation
ARG DINASTYCOIN_BRANCH=release-v0.17

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install dependencies for dinastycoind and dcyblocks compilation
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    cmake \
    miniupnpc \
    graphviz \
    doxygen \
    pkg-config \
    ca-certificates \
    zip \
    libboost-all-dev \
    libunbound-dev \
    libunwind8-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgtest-dev \
    libreadline-dev \
    libzmq3-dev \
    libsodium-dev \
    libhidapi-dev \
    libhidapi-libusb0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set compilation environment variables
ENV CFLAGS='-fPIC'
ENV CXXFLAGS='-fPIC'
ENV USE_SINGLE_BUILDDIR 1
ENV BOOST_DEBUG         1

WORKDIR /root

# Clone and compile dinastycoind with all available threads
ARG NPROC
RUN git clone --recursive --branch ${DINASTYCOIN_BRANCH} https://github.com/dinastycoin-project/dinastycoin.git \
    && cd dinastycoin \
    && test -z "$NPROC" && nproc > /nproc || echo -n "$NPROC" > /nproc && make -j"$(cat /nproc)"


# Copy and cmake/make dcyblocks with all available threads
COPY . /root/onion-dinastycoin-blockchain-explorer/
WORKDIR /root/onion-dinastycoin-blockchain-explorer/build
RUN cmake .. && make -j"$(cat /nproc)"

# Use ldd and awk to bundle up dynamic libraries for the final image
RUN zip /lib.zip $(ldd dcyblocks | grep -E '/[^\ ]*' -o)

# Use ubuntu:20.04 as base for final image
FROM ubuntu:20.04

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install unzip to handle bundled libs from builder stage
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /lib.zip .
RUN unzip -o lib.zip && rm -rf lib.zip

# Add user and setup directories for dinastycoind and dcyblocks
RUN useradd -ms /bin/bash dinastycoin \
    && mkdir -p /home/dinastycoin/.bitdinastycoin \
    && chown -R dinastycoin:dinastycoin /home/dinastycoin/.bitdinastycoin
USER dinastycoin

# Switch to home directory and install newly built dcyblocks binary
WORKDIR /home/dinastycoin
COPY --chown=dinastycoin:dinastycoin --from=builder /root/onion-dinastycoin-blockchain-explorer/build/dcyblocks .
COPY --chown=dinastycoin:dinastycoin --from=builder /root/onion-dinastycoin-blockchain-explorer/build/templates ./templates/

# Expose volume used for lmdb access by dcyblocks
VOLUME /home/dinastycoin/.bitdinastycoin

# Expose default explorer http port
EXPOSE 8081

ENTRYPOINT ["/bin/sh", "-c"]

# Set sane defaults that are overridden if the user passes any commands
CMD ["./dcyblocks --enable-json-api --enable-autorefresh-option  --enable-pusher"]
