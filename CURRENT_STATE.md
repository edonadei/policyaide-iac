# Current Infrastructure State - Firecrawl + Mullvad VPN Setup

**Date:** November 3, 2025
**Server:** DigitalOcean Droplet (Ubuntu 24.04)
**IP:** 138.197.91.30
**Location:** NYC3 region

---

# How to connect to the machine
```bash
cd ~
ssh -i priv-key-policyaide.txt root@138.197.91.30
```

## ✅ What's Working

### 1. Gluetun VPN Container
- **Status:** Running and healthy
- **Provider:** Mullvad VPN via WireGuard
- **Container:** `qmcgaw/gluetun` (Docker)
- **HTTP Proxy:** Available on `localhost:8888`
- **Current VPN IP:** Rotating through NYC Mullvad servers
- **Exposed Ports:** 8888 (HTTP proxy), 8000 (Control API), 3000 (Playwright service)

### 2. Automatic Server Rotation
- **Service:** `gluetun-rotator.service` (systemd)
- **Status:** Active and enabled (starts on boot)
- **Rotation:** Every 10-20 minutes (randomized)
- **Server Pool:** 26 Mullvad NYC servers
- **Auto-reconnect:** Maintains firecrawl_backend network connection after rotation

### 3. Firecrawl Integration
- **Status:** ✅ FULLY OPERATIONAL
- **API Endpoint:** `http://localhost:3002`
- **Playwright Service:** Running through Gluetun's network (all traffic via VPN)
- **Network Mode:** Host network mode for all services
- **VPN Routing:** ✅ Confirmed - All scraping requests use VPN IP

### 4. SSH Access
- **Status:** Working normally
- **Network:** Not affected by VPN (on host network)
- **Port:** 22 (protected by UFW firewall)

---

## 🔧 Current Configuration

### Gluetun Container Details
```yaml
Container Name: gluetun
Network Mode: bridge (default) + firecrawl_backend
Ports Exposed:
  - 8888:8888 (HTTP proxy)
  - 8000:8000 (Control API)
  - 3000:3000 (Playwright service passthrough)
VPN Type: WireGuard
Provider: Mullvad
Region: New York NY
```

### Firecrawl Docker Compose Architecture
```yaml
services:
  playwright-service:
    network_mode: "container:gluetun"  # Shares Gluetun's network stack
    # All outbound traffic automatically goes through VPN tunnel

  api:
    network_mode: host  # Can access playwright via localhost:3000

  redis:
    network_mode: host  # Shared on localhost

  nuq-postgres:
    network_mode: host  # Shared on localhost
```

### WireGuard Credentials
```
Account: 2358774729897558
Private Key: AB35D2nZPS7tE9JAJJT4BtaokAV1/BkoywL54B6Ly0I=
IPv4 Address: 10.65.106.136/32
Server Endpoints: 26 NYC servers (rotating)
```

### Key Files & Locations
```
Rotation Script: ~/rotate-gluetun-all-servers.sh
Server List: ~/nyc-servers.txt (26 servers)
Rotation Logs: /var/log/gluetun-rotation.log
Systemd Service: /etc/systemd/system/gluetun-rotator.service
WireGuard Configs: ~/us-nyc-wg-*.conf (26 config files)
Firecrawl Repo: ~/firecrawl/
Firecrawl Backup: ~/firecrawl-backup-20251103-010654.tar.gz (108MB)
Scripts Backup: ~/gluetun-scripts-backup-20251103-010710.tar.gz (1.6KB)
Docker Compose: ~/firecrawl/docker-compose.yaml
Environment: ~/firecrawl/.env
```

---

## 🎯 Implementation Complete!

### ✅ What's Been Achieved

1. ✅ Firecrawl configured with host network mode
2. ✅ Playwright service routes ALL traffic through Gluetun VPN tunnel
3. ✅ Verified scraping requests use VPN IP (not host IP)
4. ✅ Automatic IP rotation working (10-20 minute intervals)
5. ✅ All services properly communicate via localhost
6. ✅ Complete backups created before implementation

### Test Results
```bash
# Current VPN IP
$ curl --proxy http://localhost:8888 https://api.ipify.org
198.44.136.112

# Firecrawl scrape test
$ curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://httpbin.org/ip"}'

# Result: origin": "198.44.136.112" ✅ Using VPN IP!
```

---

## 📊 Network Architecture

```
Internet
    ↓
SSH (port 22) → Droplet (138.197.91.30) ← NOT through VPN
    ↓
Firecrawl API (localhost:3002, host network)
    ↓
Playwright Service (localhost:3000, shares Gluetun network)
    ↓
Gluetun VPN Container
    ↓
Mullvad VPN (WireGuard)
    ↓
NYC Server Pool (26 servers, rotating every 10-20 min)
    ↓
Target Websites (see VPN IP: 198.44.136.112, etc.)
```

---

## 🧪 Verification Commands

### Check VPN Status
```bash
# Check if Gluetun is running
docker ps | grep gluetun

# Check current VPN IP
curl --proxy http://localhost:8888 https://api.ipify.org

# Verify Mullvad connection
curl --proxy http://localhost:8888 https://am.i.mullvad.net/connected

# Check rotation logs
tail -20 /var/log/gluetun-rotation.log

# Check rotation service
sudo systemctl status gluetun-rotator
```

### Check Firecrawl Services
```bash
# Check all containers
docker ps

# Check Firecrawl API logs
docker logs firecrawl-api-1 --tail=50

# Check Playwright service logs
docker logs firecrawl-playwright-service-1 --tail=30

# Test scraping with IP verification
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://httpbin.org/ip"}' | python3 -m json.tool
```

### Check Host Network
```bash
# Verify SSH still works (real IP)
curl https://api.ipify.org
# Should return: 138.197.91.30
```

---

## 🚧 Working Configuration

### Gluetun Docker Run Command (from rotation script)
```bash
docker run -d \
  --name=gluetun \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -e VPN_SERVICE_PROVIDER=mullvad \
  -e VPN_TYPE=wireguard \
  -e WIREGUARD_PRIVATE_KEY="$PRIVATE_KEY" \
  -e WIREGUARD_ADDRESSES="$ADDRESS" \
  -e WIREGUARD_ENDPOINT_IP=$(echo $SERVER | cut -d: -f1) \
  -e WIREGUARD_ENDPOINT_PORT=$(echo $SERVER | cut -d: -f2) \
  -e SERVER_CITIES="New York NY" \
  -e HTTPPROXY=on \
  -e HTTPPROXY_LOG=on \
  -e HTTPPROXY_LISTENING_ADDRESS=:8888 \
  -e TZ=America/New_York \
  -p 8888:8888 \
  -p 8000:8000 \
  -p 3000:3000 \
  --restart=unless-stopped \
  qmcgaw/gluetun
```

### Firecrawl Docker Compose Commands
```bash
# Start Firecrawl
cd ~/firecrawl && docker compose up -d

# Stop Firecrawl
cd ~/firecrawl && docker compose down

# View logs
docker compose logs -f

# Restart specific service
docker compose restart api
```

---

## ⚠️ Important Notes

1. **SSH is protected:** Never gets routed through VPN
2. **Firewall (UFW) is active:** Only port 22, 3002, and 51820/udp are allowed
3. **Rotation is automatic:** Service restarts container every 10-20 minutes
4. **Proxy works:** Tested and verified with `curl --proxy`
5. **Firecrawl is LIVE:** All scraping requests use rotating VPN IPs
6. **Host network mode:** All Firecrawl services use host networking for simplicity
7. **Playwright isolation:** Runs in Gluetun's network namespace for VPN routing
8. **Backups created:** Full backups before implementation changes

---

## 📦 Software Installed

- Docker (latest) + Docker Compose
- Gluetun container (qmcgaw/gluetun:latest)
- Firecrawl (self-hosted, latest from GitHub)
- Mullvad CLI (installed but not actively used - using Gluetun instead)
- UFW Firewall (active)
- Node.js (for Firecrawl)
- Python 3 (system default)

---

## 🔄 Service Management

### Rotation Service
```bash
sudo systemctl status gluetun-rotator   # Check status
sudo systemctl restart gluetun-rotator  # Force new rotation
sudo systemctl stop gluetun-rotator     # Stop rotation
sudo systemctl start gluetun-rotator    # Start rotation
sudo journalctl -u gluetun-rotator -f   # Follow service logs
```

### Firecrawl Services
```bash
cd ~/firecrawl

# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart all services
docker compose restart

# View service status
docker compose ps

# View logs
docker compose logs -f
```

### Manual Container Control
```bash
docker stop gluetun      # Stop VPN
docker start gluetun     # Start VPN
docker restart gluetun   # Restart VPN
docker logs gluetun      # View logs
```

---

## 🎪 Usage Examples

### Basic Scraping
```bash
# Scrape a website through VPN
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}'
```

### Verify VPN is Being Used
```bash
# Check current VPN IP
curl --proxy http://localhost:8888 https://api.ipify.org

# Scrape httpbin to see the IP Firecrawl uses
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://httpbin.org/ip"}' | grep origin

# Both should show the same VPN IP!
```

### Monitor IP Rotation
```bash
# Watch rotation logs in real-time
tail -f /var/log/gluetun-rotation.log

# Check rotation history
cat /var/log/gluetun-rotation.log | grep "Successfully connected"
```

---

## 🐛 Troubleshooting Reference

### If VPN stops working
```bash
sudo systemctl restart gluetun-rotator
curl --proxy http://localhost:8888 https://api.ipify.org
docker logs gluetun --tail=50
```

### If Firecrawl isn't responding
```bash
cd ~/firecrawl
docker compose ps  # Check container status
docker compose logs -f  # View logs
docker compose restart  # Restart all services
```

### If scraping returns host IP instead of VPN IP
```bash
# Check if playwright service is using Gluetun's network
docker inspect firecrawl-playwright-service-1 | grep NetworkMode
# Should show: "container:gluetun" or similar

# Restart services
cd ~/firecrawl && docker compose restart
```

### If SSH is affected (shouldn't happen)
```bash
# Access via DigitalOcean console
docker stop gluetun  # Stop VPN
```

### Check rotation history
```bash
cat /var/log/gluetun-rotation.log
```

### Restore from backup
```bash
# Stop current services
cd ~/firecrawl && docker compose down

# Restore from backup
cd ~
tar -xzf firecrawl-backup-20251103-010654.tar.gz

# Restart services
cd ~/firecrawl && docker compose up -d
```

---

## 🎉 Success Metrics

- ✅ VPN rotation: Every 10-20 minutes
- ✅ IP pool: 26 NYC Mullvad servers
- ✅ Firecrawl scraping: Uses VPN IP (verified)
- ✅ Playwright browser: Routes through VPN tunnel
- ✅ SSH access: Unaffected by VPN
- ✅ Automatic reconnection: Services survive rotation
- ✅ Zero downtime: Rotation happens in background

---

**End of State Document**
**Status: FULLY OPERATIONAL** 🎉
