# Firecrawl Multi-Droplet Scaling Guide

Guide for scaling from single droplet to multiple droplets with load balancing.

## When to Scale

Consider scaling when you see:

- ✅ **High request volume**: > 100 requests/second sustained
- ✅ **CPU/Memory pressure**: Consistently > 80% usage
- ✅ **Queue backlog**: Redis queue > 1000 pending jobs
- ✅ **Slow response times**: p95 latency > 30 seconds
- ✅ **Geographic distribution needs**: Users in multiple regions

**Target**: 70,000 requests/day (~50 req/min) is well within single droplet capacity.
Scale when you reach **200,000+ requests/day** or need redundancy/failover.

## Architecture Overview

### Current (Single Droplet)

```
Internet → Droplet (Firecrawl + Gluetun VPN)
```

### Scaled (Multi-Droplet + Load Balancer)

```
Internet
    ↓
HAProxy Load Balancer
    ↓
┌───────────┬───────────┬───────────┐
│ Droplet 1 │ Droplet 2 │ Droplet 3 │
│ Firecrawl │ Firecrawl │ Firecrawl │
│ Gluetun   │ Gluetun   │ Gluetun   │
└───────────┴───────────┴───────────┘
         ↓
   Shared PostgreSQL (optional)
   Shared Redis (optional)
```

## Scaling Strategy

### Option 1: Horizontal Scaling (Recommended)

**What**: Multiple identical droplets behind load balancer

**Pros**:
- Simple to implement
- Easy to add/remove capacity
- Each droplet has its own VPN
- No single point of failure

**Cons**:
- Need to synchronize data (database)
- More complex deployments

**Best for**: High throughput, redundancy

### Option 2: Database Separation

**What**: Separate database server from API servers

**Pros**:
- Better performance for database-heavy workloads
- Easier backups
- Can scale database independently

**Cons**:
- More expensive
- More complex setup
- Network latency between API and DB

**Best for**: Large datasets, many concurrent users

### Option 3: Geographic Distribution

**What**: Droplets in different regions (NYC, SF, London)

**Pros**:
- Lower latency for users worldwide
- Different VPN IPs per region
- Better reliability

**Cons**:
- Complex routing (GeoDNS or smart load balancer)
- Data synchronization challenges
- Higher cost

**Best for**: Global user base, compliance requirements

## Implementation Steps

### Step 1: Prepare Additional Droplets

For each new droplet:

```bash
# 1. Create DigitalOcean droplet
# - Size: Same as current (or larger)
# - Image: Ubuntu 24.04
# - Region: Same datacenter (NYC3) for latency

# 2. Initial setup
ssh root@NEW_DROPLET_IP

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Clone repository
git clone https://github.com/your-org/firecrawl-production
cd firecrawl-production

# 3. Configure environment
cp .env.example .env
nano .env  # Use SAME credentials (especially database)

# 4. Deploy
chmod +x scripts/*.sh
./scripts/deploy.sh
```

**Important**: All droplets should use the **same PostgreSQL database** for shared state.

### Step 2: Set Up Load Balancer

#### Option A: DigitalOcean Load Balancer (Easiest)

```bash
# Via DigitalOcean Control Panel:

1. Navigate to Networking → Load Balancers → Create
2. Configuration:
   - Name: firecrawl-lb
   - Region: Same as droplets (NYC3)
   - VPC: Same as droplets
   - Forwarding Rules:
     * HTTP port 80 → HTTP port 3002
     * HTTPS port 443 → HTTP port 3002 (if using SSL)

3. Health Checks:
   - Protocol: HTTP
   - Port: 3002
   - Path: /health
   - Interval: 10 seconds
   - Timeout: 5 seconds
   - Unhealthy threshold: 3
   - Healthy threshold: 2

4. Sticky Sessions:
   - Type: Cookies
   - Cookie name: firecrawl_session
   - TTL: 300 seconds

5. Add Droplets:
   - Select all Firecrawl droplets

6. Create Load Balancer
```

**Cost**: ~$12/month for DigitalOcean Load Balancer

**Pros**: Managed, automatic SSL, built-in monitoring

#### Option B: HAProxy (Self-Hosted)

Create dedicated load balancer droplet:

```bash
# On NEW load balancer droplet
apt update && apt install haproxy

# Edit /etc/haproxy/haproxy.cfg
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  300000
    timeout server  300000

frontend firecrawl_frontend
    bind *:80
    default_backend firecrawl_backend

backend firecrawl_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200

    server droplet1 DROPLET1_IP:3002 check
    server droplet2 DROPLET2_IP:3002 check
    server droplet3 DROPLET3_IP:3002 check

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats auth admin:YOUR_PASSWORD
EOF

# Restart HAProxy
systemctl restart haproxy
systemctl enable haproxy

# Verify
curl http://localhost/health
```

**Cost**: $6/month for smallest droplet

**Pros**: More control, lower cost, stats dashboard

**Cons**: You manage it, need to monitor/update

### Step 3: Database Configuration

#### Shared PostgreSQL (Recommended)

**Option A**: Keep PostgreSQL on one droplet, connect others remotely

On **Droplet 1** (database host):

```bash
# Edit docker-compose.yml
postgres:
  ports:
    - "5432:5432"  # Expose to network

# Restart
docker-compose up -d postgres

# Configure firewall (allow only other droplets)
ufw allow from DROPLET2_IP to any port 5432
ufw allow from DROPLET3_IP to any port 5432
```

On **Droplet 2 & 3**:

```bash
# Edit docker-compose.yml - remove postgres service
# Edit .env
DATABASE_URL=postgresql://user:pass@DROPLET1_IP:5432/firecrawl

# Restart
docker-compose up -d
```

**Option B**: Managed PostgreSQL (DigitalOcean)

```bash
# Create managed database via DO control panel
# Size: 1GB RAM, 10GB storage ($15/month)
# Enable connection pooling

# Update all droplets' .env
DATABASE_URL=postgresql://user:pass@MANAGED_DB_HOST:25060/firecrawl?sslmode=require

# Restart all APIs
docker-compose restart api
```

**Pros**: Automatic backups, high availability, easy scaling

**Cons**: Additional cost ($15+/month)

#### Shared Redis

Similar to PostgreSQL:

```bash
# Option A: Use DigitalOcean Managed Redis ($15/month)
# Option B: Single Redis on Droplet 1, others connect remotely
# Option C: Redis Cluster (complex, only if >100GB data)

# Update .env on all droplets
REDIS_URL=redis://REDIS_HOST:6379

# Restart
docker-compose restart api
```

### Step 4: Update Monitoring

#### Aggregate Prometheus Metrics

Create **monitoring droplet** with Prometheus configured to scrape all droplets:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'firecrawl-droplet-1'
    static_configs:
      - targets: ['DROPLET1_IP:3002']

  - job_name: 'firecrawl-droplet-2'
    static_configs:
      - targets: ['DROPLET2_IP:3002']

  - job_name: 'firecrawl-droplet-3'
    static_configs:
      - targets: ['DROPLET3_IP:3002']

  - job_name: 'haproxy'
    static_configs:
      - targets: ['LOAD_BALANCER_IP:8404']
```

#### Update Grafana Dashboards

Add multi-droplet panels:

```promql
# Total requests across all droplets
sum(rate(http_requests_total[5m])) by (instance)

# Requests per droplet
rate(http_requests_total[5m])

# Droplet comparison
topk(3, rate(http_requests_total[5m]))
```

### Step 5: DNS Configuration

Point your domain to the load balancer:

```bash
# If using DigitalOcean Load Balancer
# Create A record:
api.yourdomain.com → LOAD_BALANCER_IP

# If using HAProxy droplet
api.yourdomain.com → HAPROXY_DROPLET_IP
```

### Step 6: Testing

```bash
# Test load balancing
for i in {1..100}; do
  curl -s http://LOAD_BALANCER_IP/health | jq -r '.droplet_id'
done | sort | uniq -c

# Expected output (should distribute across droplets):
#   33 droplet-1
#   34 droplet-2
#   33 droplet-3

# Test failover
# Stop one droplet's API
docker-compose stop api

# Verify load balancer routes to healthy droplets
curl http://LOAD_BALANCER_IP/health
# Should still work (served by other droplets)

# Restart
docker-compose start api
```

## Deployment Automation

### Deploy to All Droplets Script

```bash
#!/bin/bash
# deploy-all.sh

DROPLETS=(
  "root@DROPLET1_IP"
  "root@DROPLET2_IP"
  "root@DROPLET3_IP"
)

for DROPLET in "${DROPLETS[@]}"; do
  echo "Deploying to $DROPLET..."
  ssh "$DROPLET" "cd /root/firecrawl-production && \
    git pull && \
    docker-compose pull && \
    docker-compose up -d && \
    echo 'Waiting 30s for health...' && \
    sleep 30 && \
    docker-compose ps"
done

echo "All droplets updated!"
```

## Cost Breakdown

### Single Droplet

- Droplet (4GB RAM, 2 vCPU): **$24/month**
- **Total**: **$24/month**

### 3 Droplets + Load Balancer

- 3× Droplets (4GB RAM, 2 vCPU): **$72/month**
- DigitalOcean Load Balancer: **$12/month**
- Managed PostgreSQL (optional): **$15/month**
- Managed Redis (optional): **$15/month**
- **Total**: **$84-114/month**

### 3 Droplets + Self-Hosted Load Balancer

- 3× Droplets: **$72/month**
- 1× Load Balancer droplet (1GB): **$6/month**
- **Total**: **$78/month**

## Capacity Planning

| Setup | Requests/Day | Requests/Sec | Monthly Cost |
|-------|--------------|--------------|--------------|
| 1 Droplet | 70,000 | ~50 | $24 |
| 1 Droplet | 200,000 | ~140 | $24 (at limit) |
| 3 Droplets | 600,000 | ~420 | $84-114 |
| 5 Droplets | 1,000,000 | ~700 | $132-162 |

## Advanced: Auto-Scaling

For dynamic scaling based on load:

### DigitalOcean Kubernetes (DOKS)

```yaml
# Convert to Kubernetes deployment
# Benefits:
# - Auto-scaling based on CPU/memory
# - Rolling updates
# - Self-healing

# Cost: $12/month + $12/node/month
```

### Terraform + Auto-Scaling Groups

```hcl
# Define infrastructure as code
# Auto-create/destroy droplets based on metrics
# Complex but fully automated
```

## Rollback Plan

If scaling causes issues:

```bash
# 1. Update DNS to point to original droplet
# 2. Disable load balancer
# 3. Stop new droplets
# 4. Verify original droplet is healthy
# 5. Debug issues before retrying
```

## Best Practices

1. **Test thoroughly** - Deploy to 2 droplets first, verify, then add more
2. **Monitor closely** - Watch Grafana for 24 hours after scaling
3. **Database backups** - Backup before migrating to shared database
4. **Gradual rollout** - Don't switch all traffic at once (use DNS TTL)
5. **Cost monitoring** - Set billing alerts on DigitalOcean

## Troubleshooting

### Load balancer not distributing evenly

- Check sticky sessions (may keep users on same droplet)
- Verify all droplets are healthy
- Review HAProxy/LB algorithms

### Database connection errors

- Check connection pool limits
- Verify firewall rules
- Test direct connection: `psql -h DB_HOST -U user -d firecrawl`

### Sessions lost between requests

- Enable sticky sessions on load balancer
- Or: Use Redis for session storage (shared across droplets)

## Next Steps

- [Deployment Guide](./DEPLOYMENT.md) - Reference for setting up new droplets
- [Monitoring Guide](./MONITORING.md) - Monitor multi-droplet deployments
- Consider **[Kubernetes](https://www.digitalocean.com/products/kubernetes)** for auto-scaling (when > 10 droplets)
