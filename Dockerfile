FROM debian:stretch
MAINTAINER sysadmin@mysociety.org
ENV DEBIAN_FRONTEND noninteractive
ENV VARNISHAPI_VMODDIR=/usr/lib/x86_64-linux-gnu/varnish/vmods/
RUN apt-get update -q && apt-get install -y -qq \
      autotools-dev \
      automake \
      devscripts \
      libtool \
      python-docutils \
      pkg-config \
      libpcre3-dev \
      libeditline-dev \
      libedit-dev \
      make \
      dpkg-dev \
      git \
      libjemalloc-dev \
      libev-dev \
      libncurses-dev \
      python-sphinx \
      graphviz \
      varnish \
      libvarnishapi-dev \
      libhiredis-dev \
      redis-server \
      supervisor

RUN mkdir /home/builder
WORKDIR /home/builder

RUN git clone https://github.com/xcir/vtctrans.git \
      && git clone https://github.com/sagepe/libvmod-redis.git \
      && cd libvmod-redis \
      && git checkout origin/stretch \
      && ./autogen.sh \
      && ./configure --libdir=/usr/lib/x86_64-linux-gnu \
      && make \
      && make install

COPY ./docker/redis.conf /etc/redis/redis.conf
COPY ./docker/supervisor /etc/supervisor/conf.d

EXPOSE 81
CMD ["/usr/bin/supervisord", "--nodaemon"]
