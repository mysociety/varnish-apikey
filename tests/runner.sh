#! /bin/bash

##
## Configuration.
##
REDIS_PORT=40000

##
## Cleanup callback.
##
cleanup() {
    set +x

    if [[ -s "$1/redis-master.pid" ]]; then
        kill -9 $(cat "$1/redis-master.pid")
    fi

    rm -rf "$1"
    echo
}

##
## Initializations.
##
set -e
TMP=`mktemp -d`
CONTEXT=""

##
## Register cleanup callback.
##
trap "cleanup $TMP" EXIT

##
## Launch standalone Redis servers
##
cat > "$TMP/redis-master.conf" <<EOF
daemonize yes
port $((REDIS_PORT))
bind 127.0.0.1
unixsocket $TMP/redis-master.sock
pidfile $TMP/redis-master.pid
EOF
redis-server "$TMP/redis-master.conf"
CONTEXT="\
    $CONTEXT \
    -Dredis_master_address=127.0.0.1:$((REDIS_PORT)) \
    -Dredis_master_socket=$TMP/redis-master.sock"

##
## Execute wrapped command
##
set -x
$@ $CONTEXT