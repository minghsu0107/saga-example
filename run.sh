#!/bin/sh
export REDIS_CLUSTER_IP=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" \
    | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
export REDIS_PASSWD=pass.123

case "$1" in
    "run")
        docker-compose up --scale saga-purchase=2 --scale saga-account=3 --scale saga-product=2 --scale saga-order=2 --scale saga-payment=2 --scale saga-orchestrator=2;;
    "stop")
        docker-compose stop;;
    *)
        echo "command should be 'run' or 'stop'"
        exit 1;;
esac