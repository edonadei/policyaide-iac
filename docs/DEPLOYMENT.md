# Firecrawl Production Deployment Guide

This guide walks you through deploying the complete Firecrawl + Gluetun VPN stack with monitoring and auto-recovery.

## Prerequisites

- Ubuntu 24.04 server (DigitalOcean droplet or similar)
- Docker & Docker Compose installed
- Root or sudo access
- Mullvad VPN account with active subscription
- WireGuard credentials from Mullvad

## Quick Start (5 minutes)

### 1. Clone Repository

```bash
cd /root
git clone https://github.com/your-org/firecrawl-production
cd firecrawl-production
```

### 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your values
nano .env
```

**Required values to set:**
- `WIREGUARD_PRIVATE_KEY` - From Mullvad account
- `WIREGUARD_ADDRESSES` - Your WireGuard IP (e.g., `10.156.248.200/32`)
- `POSTGRES_PASSWORD` - Secure database password
- `GRAFANA_ADMIN_PASSWORD` - Grafana admin password
- `SLACK_WEBHOOK_URL` - For alerts (optional but recommended)

### 3. Deploy

```bash
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
```

The deployment script will:
- ✅ Run pre-flight checks
- ✅ Pull all Docker images
- ✅ Create required directories
- ✅ Install systemd timer for VPN rotation
- ✅ Start all services
- ✅ Run health checks
- ✅ Display access information

### 4. Verify Deployment

```bash
# Check all containers are running
docker-compose ps

# Verify VPN connection
curl --proxy http://localhost:8888 https://api.ipify.org

# Test Firecrawl API
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}'

# Access Grafana
# Open http://YOUR_SERVER_IP:3001 in browser
# Login with admin / your_grafana_password
```

## Detailed Setup

### Getting Mullvad WireGuard Credentials

If you don't have WireGuard credentials yet:

```bash
# Install Mullvad CLI
wget https://mullvad.net/download/app/deb/latest -O mullvad.deb
sudo dpkg -i mullvad.deb

# Login to your account
mullvad account login YOUR_ACCOUNT_NUMBER

# Get WireGuard key
mullvad tunnel get
# Look for: Private Key and IPv4 Address
```

### Firewall Configuration

```bash
# Allow required ports
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 3002/tcp    # Firecrawl API
sudo ufw allow 51820/udp   # WireGuard VPN
sudo ufw enable
```

### Service Architecture

After deployment, the following services will be running:

| Service | Port | Purpose |
|---------|------|---------|
| Firecrawl API | 3002 | Main scraping API |
| Gluetun VPN | 8888 (localhost) | HTTP proxy for VPN |
| Grafana | 3001 (localhost) | Monitoring dashboards |
| Prometheus | 9090 (localhost) | Metrics collection |
| Alertmanager | 9093 (localhost) | Alert routing |

All services except Firecrawl API (port 3002) are bound to localhost for security.

### Accessing Services Remotely

If you need to access Grafana/Prometheus remotely, use SSH tunneling:

```bash
# From your local machine
ssh -L 3001:localhost:3001 \
    -L 9090:localhost:9090 \
    root@YOUR_SERVER_IP

# Now access:
# http://localhost:3001 - Grafana
# http://localhost:9090 - Prometheus
```

## Configuration

### VPN Rotation Timing

Default: Every 10-20 minutes (randomized)

To change, edit `scripts/gluetun-rotator.timer`:

```ini
[Timer]
OnBootSec=5min          # First rotation after boot
OnUnitActiveSec=15min   # Base interval
RandomizedDelaySec=10min # Random delay (0-10 min)
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart gluetun-rotator.timer
```

### Rate Limiting

Default: 100 requests/minute per IP

To change, edit `nginx/nginx.conf`:

```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/m;
```

Then restart:

```bash
docker-compose restart nginx
```

### Alert Configuration

Edit `monitoring/alertmanager.yml` to configure Slack/email alerts.

For Slack:
1. Create incoming webhook at https://api.slack.com/messaging/webhooks
2. Add webhook URL to `.env`: `SLACK_WEBHOOK_URL=https://hooks.slack.com/...`
3. Restart alertmanager: `docker-compose restart alertmanager`

For email:
1. Configure SMTP settings in `.env`
2. For Gmail, use an [App Password](https://support.google.com/accounts/answer/185833)
3. Restart alertmanager: `docker-compose restart alertmanager`

## Maintenance

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f gluetun

# VPN rotation logs
tail -f /var/log/gluetun-rotation.log
sudo journalctl -u gluetun-rotator -f
```

### Manual VPN Rotation

```bash
# Trigger immediate rotation
sudo systemctl start gluetun-rotator.service

# Check rotation status
sudo systemctl status gluetun-rotator.service

# View rotation history
cat /var/log/gluetun-rotation.log | grep "Successfully connected"
```

### Update Services

```bash
cd /root/firecrawl-production

# Pull latest images
docker-compose pull

# Restart with new images (brief downtime)
docker-compose down
docker-compose up -d

# OR: Rolling restart (one service at a time)
docker-compose restart api
docker-compose restart gluetun
# etc.
```

### Backup & Restore

```bash
# Create backup
./scripts/backup.sh

# Backups are stored in ./backups/
ls -lh backups/

# Restore from backup
# 1. Extract config files
tar xzf backups/firecrawl-backup-TIMESTAMP-config.tar.gz

# 2. Import database
docker run --rm -v firecrawl-plus-rotating-vpn_postgres_data:/data \
    -v $(pwd)/backups:/backup alpine \
    tar xzf /backup/firecrawl-backup-TIMESTAMP-postgres.tar.gz -C /data

# 3. Redeploy
./scripts/deploy.sh
```

## Troubleshooting

### API Not Responding

```bash
# Check API container
docker-compose logs api

# Restart API
docker-compose restart api

# Check health
curl http://localhost:3002/health
```

### VPN Not Working

```bash
# Check Gluetun container
docker-compose logs gluetun

# Verify VPN connection
curl --proxy http://localhost:8888 https://api.ipify.org

# Force rotation
sudo systemctl start gluetun-rotator.service

# Check Mullvad account status
mullvad account get
```

### High CPU/Memory Usage

```bash
# Check resource usage
docker stats

# View Grafana dashboards for detailed metrics
# http://YOUR_SERVER_IP:3001

# Scale down if needed (edit docker-compose.yml)
# Reduce MAX_CPU, MAX_RAM environment variables
```

### Container Keeps Restarting

```bash
# Check container logs
docker-compose logs --tail=100 CONTAINER_NAME

# Check autoheal logs
docker logs autoheal

# Disable autoheal temporarily for debugging
docker stop autoheal
```

### Alerts Not Working

```bash
# Check Alertmanager
docker-compose logs alertmanager

# Test Slack webhook manually
curl -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert from Firecrawl"}'

# View alert rules
curl http://localhost:9090/api/v1/rules
```

## Security Best Practices

1. **Change default passwords** - Update all passwords in `.env`
2. **Restrict port 3002** - Use firewall to limit API access to trusted IPs
3. **Enable HTTPS** - Add SSL certificate (see [SSL.md](./SSL.md))
4. **Regular updates** - Update Docker images weekly
5. **Monitor logs** - Review `/var/log/gluetun-rotation.log` regularly
6. **Backup regularly** - Run `./scripts/backup.sh` daily (add to cron)

## Performance Tuning

### For 70,000+ requests/day

Current configuration handles ~50 requests/minute average. For higher throughput:

1. **Increase worker count** (edit `docker-compose.yml`):
   ```yaml
   api:
     environment:
       - WORKER_COUNT=8  # Increase from default
   ```

2. **Increase Playwright sessions**:
   ```yaml
   playwright-service:
     environment:
       - MAX_CONCURRENT_SESSIONS=20  # From 10
   ```

3. **Add Redis memory**:
   ```yaml
   redis:
     command: redis-server --maxmemory 1gb  # From 512mb
   ```

4. **Monitor and scale** - Watch Grafana dashboard "Firecrawl Production Overview"

## Next Steps

- [Monitoring Guide](./MONITORING.md) - Understanding dashboards and alerts
- [Scaling Guide](./SCALING.md) - Adding more droplets + load balancer
- [SSL Setup](./SSL.md) - Enable HTTPS with Let's Encrypt (optional)
