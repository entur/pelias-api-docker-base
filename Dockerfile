# base image
FROM ubuntu:22.04 AS baseimage

# configure env
ENV DEBIAN_FRONTEND 'noninteractive'

# update apt, install core apt dependencies and delete the apt-cache
# note: this is done in one command in order to keep down the size of intermediate containers
RUN apt-get update && \
      apt-get install -y locales apt-utils iputils-ping curl wget git-core && \
      rm -rf /var/lib/apt/lists/*

# configure locale
RUN locale-gen 'en_US.UTF-8'
ENV LANG 'en_US.UTF-8'
ENV LANGUAGE 'en_US:en'
ENV LC_ALL 'en_US.UTF-8'

# configure directories
RUN mkdir -p '/data' '/code/pelias'

# configure volumes
VOLUME "/data"

RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# get ready for pelias config with an empty file
ENV PELIAS_CONFIG '/code/pelias.json'
RUN echo '{}' > '/code/pelias.json'

# add a pelias user
RUN useradd -ms /bin/bash pelias

# ensure symlinks, pelias.json, and anything else are owned by pelias user
RUN chown pelias:pelias /data /code -R

# builder image
FROM baseimage AS libpostal_baseimage_builder

# libpostal apt dependencies
# note: this is done in one command in order to keep down the size of intermediate containers
RUN apt-get update && \
    apt-get install -y build-essential autoconf automake libtool pkg-config python3

# clone libpostal
RUN git clone https://github.com/openvenues/libpostal /code/libpostal
WORKDIR /code/libpostal

# install libpostal
RUN ./bootstrap.sh

# https://github.com/openvenues/libpostal/pull/632#issuecomment-1648303654
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      ./configure --datadir='/usr/share/libpostal' --disable-sse2; \
    else \
      ./configure --datadir='/usr/share/libpostal'; \
    fi

# compile
RUN make -j4
RUN DESTDIR=/libpostal make install
RUN ldconfig

# copy address_parser executable
RUN cp /code/libpostal/src/.libs/address_parser /libpostal/usr/local/bin/

# -------------------------------------------------------------

# main image
FROM baseimage

# copy data
COPY --from=libpostal_baseimage_builder /usr/share/libpostal /usr/share/libpostal

# copy build
COPY --from=libpostal_baseimage_builder /libpostal /

# ensure /usr/local/lib is on LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

# test model / executable load correctly
RUN echo '12 example lane, example' | address_parser
