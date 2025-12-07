#!/bin/bash
set -euo pipefail

#######################################
# Gluetun VPN Server Rotation Script
# Rotates through Mullvad NYC servers
#######################################

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"
SERVERS_FILE="${SCRIPT_DIR}/nyc-servers.txt"
LOGFILE="/var/log/gluetun-rotation.log"
METRICS_FILE="/var/lib/gluetun/rotation-metrics.prom"

# Prometheus metrics directory
mkdir -p /var/lib/gluetun

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# Validate required variables
if [ -z "${WIREGUARD_PRIVATE_KEY:-}" ] || [ -z "${WIREGUARD_ADDRESSES:-}" ]; then
    echo "ERROR: WIREGUARD_PRIVATE_KEY and WIREGUARD_ADDRESSES must be set in .env"
    exit 1
fi

# Read servers
if [ ! -f "$SERVERS_FILE" ]; then
    echo "ERROR: Servers file not found at $SERVERS_FILE"
    exit 1
fi

mapfile -t SERVERS < "$SERVERS_FILE"
TOTAL_SERVERS=${#SERVERS[@]}

if [ "$TOTAL_SERVERS" -eq 0 ]; then
    echo "ERROR: No servers found in $SERVERS_FILE"
    exit 1
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# Metrics function
update_metric() {
    local metric_name=$1
    local metric_value=$2
    local metric_help=$3

    {
        echo "# HELP ${metric_name} ${metric_help}"
        echo "# TYPE ${metric_name} gauge"
        echo "${metric_name} ${metric_value} $(date +%s)000"
    } > "${METRICS_FILE}.tmp"

    mv "${METRICS_FILE}.tmp" "${METRICS_FILE}"
}

# Pick random server
SERVER=${SERVERS[$RANDOM % $TOTAL_SERVERS]}
SERVER_IP=$(echo "$SERVER" | cut -d: -f1)
SERVER_PORT=$(echo "$SERVER" | cut -d: -f2)

log "=========================================="
log "Starting VPN rotation to: $SERVER"
log "Total servers in pool: $TOTAL_SERVERS"

# Stop and remove old Gluetun container
log "Stopping current Gluetun container..."
if docker ps -a --format '{{.Names}}' | grep -q '^gluetun$'; then
    docker stop gluetun 2>/dev/null || true
    docker rm gluetun 2>/dev/null || true
    log "Old container removed"
fi

# Start new Gluetun container with selected server
log "Starting new Gluetun container..."
docker run -d \
    --name=gluetun \
    --cap-add=NET_ADMIN \
    --device=/dev/net/tun \
    -e VPN_SERVICE_PROVIDER=mullvad \
    -e VPN_TYPE=wireguard \
    -e WIREGUARD_PRIVATE_KEY="$WIREGUARD_PRIVATE_KEY" \
    -e WIREGUARD_ADDRESSES="$WIREGUARD_ADDRESSES" \
    -e WIREGUARD_ENDPOINT_IP="$SERVER_IP" \
    -e WIREGUARD_ENDPOINT_PORT="$SERVER_PORT" \
    -e SERVER_CITIES="New York NY" \
    -e HTTPPROXY=on \
    -e HTTPPROXY_LOG=on \
    -e HTTPPROXY_LISTENING_ADDRESS=:8888 \
    -e TZ=America/New_York \
    -e HEALTH_VPN_DURATION_INITIAL=10s \
    -e HEALTH_VPN_DURATION_ADDITION=5s \
    -p 127.0.0.1:8888:8888 \
    -p 127.0.0.1:8000:8000 \
    -p 127.0.0.1:3000:3000 \
    --network firecrawl_backend \
    --restart=unless-stopped \
    --label autoheal=true \
    qmcgaw/gluetun > /dev/null

if [ $? -ne 0 ]; then
    log "ERROR: Failed to start Gluetun container"
    update_metric "vpn_rotation_failures_total" "1" "Total VPN rotation failures"
    exit 1
fi

# Wait for container to start
log "Waiting for VPN connection to establish..."
sleep 30

# Verify VPN connection
VPN_IP=$(timeout 10 curl -s --proxy http://localhost:8888 https://api.ipify.org 2>/dev/null || echo "")

if [ -n "$VPN_IP" ] && [ "$VPN_IP" != "null" ]; then
    log "✅ VPN rotation successful!"
    log "New VPN IP: $VPN_IP"
    log "Server: $SERVER"

    # Update metrics
    update_metric "vpn_rotation_success_total" "1" "Total successful VPN rotations"
    update_metric "vpn_last_rotation_timestamp" "$(date +%s)" "Timestamp of last VPN rotation"
    update_metric "vpn_current_ip_hash" "$(echo -n "$VPN_IP" | md5sum | cut -d' ' -f1 | tr -d '\n' | od -An -td8 | tr -d ' ')" "Hash of current VPN IP"

    # Restart Playwright to reconnect to new Gluetun container
    log "Restarting Playwright service..."
    cd "$PROJECT_ROOT"
    docker-compose restart playwright-service > /dev/null 2>&1 || {
        log "WARNING: Failed to restart Playwright service"
    }

    log "Rotation complete!"
else
    log "❌ VPN rotation failed - could not verify IP"
    log "Server attempted: $SERVER"
    update_metric "vpn_rotation_failures_total" "1" "Total VPN rotation failures"

    # Try to get container logs
    log "Container logs:"
    docker logs gluetun --tail 20 2>&1 | tee -a "$LOGFILE"
    exit 1
fi

log "=========================================="
