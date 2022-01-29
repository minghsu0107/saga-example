FROM redisfab/rmbuilder:6.0.9-x64-bionic as builder

# Build the source
RUN git clone --branch 2.2 https://github.com/RedisBloom/RedisBloom.git /redisbloom
WORKDIR /redisbloom
RUN set -ex;\
    make clean; \
    make all -j 4;

FROM redis:6.2.6
ENV LIBDIR /usr/lib/redis/modules
WORKDIR /data
RUN set -ex;\
    mkdir -p "$LIBDIR";
COPY --from=builder /redisbloom/redisbloom.so "$LIBDIR"

COPY rediscluster.conf /etc/redis/rediscluster.conf
ENTRYPOINT redis-server /etc/redis/rediscluster.conf
