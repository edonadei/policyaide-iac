# Firecrawl Production with Rotating VPN

Production-ready Infrastructure-as-Code for self-hosted Firecrawl with automatic VPN rotation, monitoring, and auto-recovery.

## Features

- ✅ **Firecrawl API** - Self-hosted web scraping with Playwright
- ✅ **Rotating VPN** - Automatic Mullvad VPN server rotation (10-20 min intervals)
- ✅ **Monitoring** - Prometheus + Grafana dashboards with pre-built alerts
- ✅ **Auto-Recovery** - Automatic restart of unhealthy containers
- ✅ **Rate Limiting** - Nginx reverse proxy with request throttling
- ✅ **Alerting** - Slack/Email notifications for critical issues
- ✅ **Production-Ready** - 99% uptime target, handles 70k+ requests/day
- ✅ **Scalable** - Clear path to multi-droplet deployment

## Quick Start

### Prerequisites

- Ubuntu 24.04 server (DigitalOcean recommended)
- Docker & Docker Compose installed
- Mullvad VPN account with active subscription

### 5-Minute Deployment

```bash
# 1. Clone repository
git clone https://github.com/your-org/firecrawl-production
cd firecrawl-production

# 2. Configure environment
cp .env.example .env
nano .env  # Add your Mullvad credentials

# 3. Deploy everything
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
```

### Verify Deployment

```bash
# Check VPN is working
curl --proxy http://localhost:8888 https://api.ipify.org

# Test Firecrawl API
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}'

# Access Grafana (via SSH tunnel)
ssh -L 3001:localhost:3001 root@YOUR_SERVER_IP
# Open http://localhost:3001 in browser
```

## Architecture

```
Internet
    ↓
Nginx Reverse Proxy (Rate Limiting: 100 req/min)
    ↓
Firecrawl API (Node.js)
    ↓
Playwright Service ────→ Gluetun VPN (Mullvad WireGuard)
    ↓                            ↓
Redis + PostgreSQL         Rotating NYC Servers
                          (10-20 minute intervals)

Monitoring Stack:
- Prometheus (Metrics)
- Grafana (Dashboards)
- Alertmanager (Slack/Email alerts)
- Autoheal (Auto-recovery)
```

## Services

| Service | Port | Purpose | Access |
|---------|------|---------|--------|
| Firecrawl API | 3002 | Web scraping API | Public |
| Gluetun HTTP Proxy | 8888 | VPN proxy (testing) | Localhost |
| Grafana | 3001 | Monitoring dashboards | Localhost (SSH tunnel) |
| Prometheus | 9090 | Metrics database | Localhost |
| Alertmanager | 9093 | Alert routing | Localhost |

## Configuration

### Required Environment Variables

```bash
# VPN Configuration
WIREGUARD_PRIVATE_KEY=your_mullvad_private_key
WIREGUARD_ADDRESSES=your_wireguard_ip/32

# Database
POSTGRES_PASSWORD=secure_random_password

# Monitoring
GRAFANA_ADMIN_PASSWORD=secure_grafana_password

# Alerting (Optional but recommended)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK
```

See [.env.example](.env.example) for all available options.

### VPN Rotation

VPN automatically rotates through 26 Mullvad NYC servers every 10-20 minutes.

**Configuration**: `scripts/gluetun-rotator.timer`

```bash
# Manual rotation
sudo systemctl start gluetun-rotator.service

# View rotation logs
tail -f /var/log/gluetun-rotation.log
```

### Rate Limiting

Default: **100 requests/minute per IP**

To change, edit `nginx/nginx.conf`:

```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/m;
```

## Monitoring

### Grafana Dashboards

Pre-built dashboard: **Firecrawl Production Overview**

Metrics tracked:
- API uptime and status
- VPN connection status
- Request rate (req/sec)
- Success/error rates
- Response time (p50, p95, p99)
- CPU and memory usage
- Container health

### Alerts

**Critical** (Slack + Email):
- API down > 2 minutes
- VPN disconnected > 3 minutes
- Database offline
- Disk space < 10%

**Warning** (Slack):
- Error rate > 5%
- High latency > 30s
- VPN rotation failures
- High resource usage

See [MONITORING.md](docs/MONITORING.md) for complete alert list.

## Management

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f gluetun

# VPN rotation
tail -f /var/log/gluetun-rotation.log
```

### Restart Services

```bash
# All services
docker-compose restart

# Specific service
docker-compose restart api
docker-compose restart gluetun
```

### Force VPN Rotation

```bash
sudo systemctl start gluetun-rotator.service
```

### Backup

```bash
# Create backup
./scripts/backup.sh

# Backups stored in ./backups/
ls -lh backups/
```

### Update

```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose down
docker-compose up -d
```

## Performance

### Current Capacity (Single Droplet)

- **Handles**: 70,000 requests/day (~50 req/min average)
- **Burst**: Up to 100 req/min
- **Response Time**: < 10s (p95)
- **Uptime Target**: 99% (7 hours downtime/month)

### When to Scale

Scale to multi-droplet when:
- Request volume > 200,000/day
- CPU/Memory consistently > 80%
- Queue backlog > 1000 jobs
- Need geographic distribution

See [SCALING.md](docs/SCALING.md) for multi-droplet setup guide.

## Documentation

- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Complete deployment guide
- **[MONITORING.md](docs/MONITORING.md)** - Monitoring and alerting guide
- **[SCALING.md](docs/SCALING.md)** - Multi-droplet scaling guide

## Troubleshooting

### API Not Responding

```bash
docker-compose logs api
docker-compose restart api
curl http://localhost:3002/health
```

### VPN Not Working

```bash
docker-compose logs gluetun
curl --proxy http://localhost:8888 https://api.ipify.org
sudo systemctl start gluetun-rotator.service
```

### High Resource Usage

```bash
# Check usage
docker stats

# View Grafana dashboard
ssh -L 3001:localhost:3001 root@YOUR_SERVER_IP
# Open http://localhost:3001
```

### Container Restarting

```bash
docker-compose logs --tail=100 CONTAINER_NAME
docker logs autoheal
```

## Security

- ✅ All monitoring ports bound to localhost only
- ✅ Firewall configured (UFW)
- ✅ Rate limiting enabled
- ✅ VPN prevents IP tracking
- ✅ Passwords stored in .env (not committed)

**Ports exposed**:
- 22 (SSH)
- 3002 (Firecrawl API)
- 51820 (WireGuard UDP)

## Cost

### Single Droplet (Current)

- DigitalOcean Droplet (4GB RAM, 2 vCPU): **$24/month**
- Mullvad VPN: **$5/month**
- **Total**: **$29/month**

### Multi-Droplet (Future)

- 3× Droplets: **$72/month**
- Load Balancer: **$12/month**
- Mullvad VPN: **$5/month**
- **Total**: **$89/month** (200k+ requests/day capacity)

## Support & Contributions

- **Issues**: Report bugs via GitHub Issues
- **Documentation**: PRs welcome for improvements
- **Questions**: Check [docs/](docs/) folder first

## License

MIT

## Acknowledgments

- [Firecrawl](https://github.com/mendableai/firecrawl) - Web scraping API
- [Gluetun](https://github.com/qdm12/gluetun) - VPN client container
- [Mullvad](https://mullvad.net/) - Privacy-focused VPN provider
