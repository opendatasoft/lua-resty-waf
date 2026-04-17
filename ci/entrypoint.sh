#!/usr/bin/env bash
# Starts the storage backends the suite expects, then execs the command.
#
# These run *inside* the test container rather than as sidecars because
# lib/resty/waf.lua:662-665 hardcodes 127.0.0.1:6379 and 127.0.0.1:11211
# as defaults and no .t file overrides the host. Compose services or
# GitHub Actions `services:` would resolve to a different hostname.
#
# Loopback still exists under `docker run --network none`, so this works
# with the network switched off, which is how the suite is meant to run.
set -euo pipefail

redis-server \
    --daemonize yes \
    --bind 127.0.0.1 \
    --port 6379 \
    --save '' \
    --appendonly no \
    --logfile /tmp/redis.log

memcached -d -u nobody -l 127.0.0.1 -p 11211 -m 64

# Wait for both rather than racing the first test that connects.
wait_for() {
    local name=$1 port=$2 tries=50
    while (( tries-- )); do
        if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
            exec 3>&- 2>/dev/null || true
            return 0
        fi
        sleep 0.1
    done
    echo "FATAL: ${name} did not come up on 127.0.0.1:${port}" >&2
    return 1
}

wait_for redis 6379
wait_for memcached 11211

exec "$@"
