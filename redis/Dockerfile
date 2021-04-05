FROM redis:5.0.1-alpine

COPY rediscluster.conf /etc/redis/rediscluster.conf
ENTRYPOINT redis-server /etc/redis/rediscluster.conf