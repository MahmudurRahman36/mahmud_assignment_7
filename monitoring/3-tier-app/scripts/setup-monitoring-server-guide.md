# Monitoring Server Setup Guide

Complete step-by-step manual guide to set up the BMI Health Tracker monitoring server.  
Every command is self-contained — no scripts need to be run.

**Server:** BMI Monitoring Server (dedicated server for Prometheus, Grafana, Loki, AlertManager)  
**Run order:** Complete this FIRST, before the Application Server setup.

---

## Prerequisites

| Requirement | Details |
|---|---|
| OS | Ubuntu 22.04 LTS |
| Minimum specs | 2 vCPU, 4 GB RAM, 30 GB disk |
| Access | Root or sudo |
| Internet | Required for downloads |
| Versions | Prometheus 2.48.0, Node Exporter 1.7.0, Loki 2.9.3, AlertManager 0.26.0, Grafana latest |

**You will be prompted once during Step 4 for:**
- Application Server Private IP address

---

## Automated Alternative

If you prefer automation over manual steps, the script `setup-monitoring-server.sh` performs every command in this guide in order. To run it instead:

```bash
# SSH to your monitoring server
ssh -i your-key.pem ubuntu@MONITORING_SERVER_IP

# Clone the repository
git clone https://github.com/sarowar-dev-ops/single-server-3tier-webapp-monitoring.git
cd single-server-3tier-webapp-monitoring

# Make executable and run
chmod +x monitoring/3-tier-app/scripts/setup-monitoring-server.sh
sudo ./monitoring/3-tier-app/scripts/setup-monitoring-server.sh
```

To follow this guide manually instead, continue from Step 1 below.

---

## Step 1 — Initial System Setup

**What this step does:**
- Detects the server's public and private IP via EC2 IMDSv2 metadata
- Runs `apt update && apt upgrade`
- Installs: `wget curl git unzip tar jq net-tools software-properties-common apt-transport-https ca-certificates`

**Commands:**
```bash
# Update and upgrade system packages
sudo apt update -qq
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq

# Install essential tools
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    wget curl git unzip tar jq net-tools \
    software-properties-common apt-transport-https ca-certificates
```

**Verify after step:**
```bash
# Confirm tools installed
which wget curl jq

# Check server IPs via IMDSv2 (IMDSv1 is disabled on modern EC2 instances)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4    # public IP
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4     # private IP
```
✅ **Expected:** All tools found, both IP addresses returned

---

## Step 2 — Configure Firewall

**What this step does:**
- Enables UFW
- Opens only the ports needed for the monitoring stack:

| Port | Service | Source |
|---|---|---|
| 22 | SSH | Anywhere |
| 3001 | Grafana | Anywhere |
| 9090 | Prometheus | Anywhere (debugging) |
| 3100 | Loki | Anywhere (receives logs from app server) |

**Note:** AlertManager (9093) is intentionally NOT opened to the internet — it is only accessed internally on localhost by Prometheus.

**Commands:**
```bash
# Enable UFW
sudo ufw --force enable

# Open required ports
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 3001/tcp comment 'Grafana'
sudo ufw allow 9090/tcp comment 'Prometheus'
sudo ufw allow 3100/tcp comment 'Loki'

# Reload firewall
sudo ufw reload
```

**Verify after step:**
```bash
sudo ufw status
```
✅ **Expected:**
```
22/tcp     ALLOW
3001/tcp   ALLOW
9090/tcp   ALLOW
3100/tcp   ALLOW
```

---

## Step 3 — Install Prometheus (v2.48.0)

**What this step does:**
- Creates `prometheus` system user (no shell, no home)
- Creates directories: `/etc/prometheus`, `/var/lib/prometheus`
- Downloads `prometheus-2.48.0.linux-amd64.tar.gz` from GitHub
- Installs binaries to `/usr/local/bin/prometheus` and `/usr/local/bin/promtool`
- Copies `consoles/` and `console_libraries/` to `/etc/prometheus/`
- Cleans up `/tmp` download files

**Commands:**
```bash
# Create prometheus system user (no login shell, no home directory)
sudo useradd --no-create-home --shell /bin/false prometheus

# Create required directories and set ownership
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Download and extract
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar -xf prometheus-2.48.0.linux-amd64.tar.gz
cd prometheus-2.48.0.linux-amd64

# Install binaries
sudo cp -f prometheus promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Install console assets
sudo cp -rf consoles console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries

# Clean up
cd /tmp && rm -rf prometheus-2.48.0.linux-amd64*
```

**At this point Prometheus is installed but not yet configured or started.** Configuration happens in Step 4.

**Verify after step:**
```bash
# Binary installed
prometheus --version

# Promtool available
promtool --version
```
✅ **Expected:** `prometheus, version 2.48.0` printed

---

## Step 4 — Configure Prometheus

**What this step does:**
- Checks if `/etc/prometheus/prometheus.yml` already exists
  - If yes: extracts existing App Server IP and lets you keep or change it
  - If no: prompts you to enter the App Server Private IP
- Writes a full `prometheus.yml` with **9 scrape jobs**:

| Job | Target | Labels |
|---|---|---|
| `prometheus` | localhost:9090 | role: monitoring |
| `node_exporter` | APP_SERVER_IP:9100 | server: bmi-app-server, tier: infrastructure |
| `postgresql` | APP_SERVER_IP:9187 | database: bmidb, tier: data |
| `nginx` | APP_SERVER_IP:9113 | tier: frontend |
| `bmi-backend` | APP_SERVER_IP:9091 | application: bmi-health-tracker, tier: application |
| `node_exporter_monitoring` | localhost:9100 | server: monitoring-server |
| `grafana` | localhost:3001 | role: visualization |
| `loki` | localhost:3100 | role: log-aggregation |
| `alertmanager` | localhost:9093 | role: alerting |

- Writes `/etc/prometheus/alert_rules.yml` with 3 alert groups:
  - `system_alerts`: HighCPUUsage (>80%), HighMemoryUsage (>85%), DiskSpaceLow (<15%)
  - `application_alerts`: ApplicationDown, MonitoringServiceDown, DatabaseDown, NginxDown
  - `database_alerts`: DatabaseConnectionsHigh (>80 connections)
- Creates systemd service with 30-day retention and `--web.enable-lifecycle`
- Starts and enables the service

**You will be prompted:**
```
Please enter your Application Server Private IP address:
Application Server IP: <type it here>
```

> Set `APP_SERVER_IP` at the top of the commands block below. It is used in the generated `prometheus.yml` to point at all exporters on the application server.

**Commands:**
```bash
# Write prometheus.yml  (replace APP_SERVER_IP with your actual value)
APP_SERVER_IP="<your-app-server-private-ip>"

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'bmi-health-tracker'
    environment: 'production'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          role: 'monitoring'

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9100']
        labels:
          server: 'bmi-app-server'
          role: 'system'
          tier: 'infrastructure'

  - job_name: 'postgresql'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9187']
        labels:
          server: 'bmi-app-server'
          database: 'bmidb'
          role: 'database'
          tier: 'data'

  - job_name: 'nginx'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9113']
        labels:
          server: 'bmi-app-server'
          role: 'webserver'
          tier: 'frontend'

  - job_name: 'bmi-backend'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9091']
        labels:
          server: 'bmi-app-server'
          application: 'bmi-health-tracker'
          role: 'backend'
          tier: 'application'

  - job_name: 'node_exporter_monitoring'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          server: 'monitoring-server'
          role: 'monitoring'

  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3001']
        labels:
          server: 'monitoring-server'
          role: 'visualization'

  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']
        labels:
          server: 'monitoring-server'
          role: 'log-aggregation'

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          server: 'monitoring-server'
          role: 'alerting'
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Write alert_rules.yml
sudo tee /etc/prometheus/alert_rules.yml > /dev/null <<'EOF'
groups:
  - name: system_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% on {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk space is below 15% on {{ $labels.instance }}"

  - name: application_alerts
    interval: 30s
    rules:
      - alert: ApplicationDown
        expr: up{job="bmi-backend"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "BMI application is down"
          description: "The BMI application exporter is not responding"

      - alert: MonitoringServiceDown
        expr: up{job=~"prometheus|grafana|loki|alertmanager|node_exporter_monitoring"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Monitoring service down: {{ $labels.job }}"
          description: "{{ $labels.job }} on the monitoring server has been unreachable for 2 minutes."

      - alert: DatabaseDown
        expr: up{job="postgresql"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL database is down"
          description: "PostgreSQL exporter is not responding"

      - alert: NginxDown
        expr: up{job="nginx"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Nginx web server is down"
          description: "Nginx exporter is not responding"

  - name: database_alerts
    interval: 30s
    rules:
      - alert: DatabaseConnectionsHigh
        expr: pg_stat_database_numbackends > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of database connections"
          description: "PostgreSQL has {{ $value }} active connections"
EOF

sudo chown prometheus:prometheus /etc/prometheus/alert_rules.yml

# Create systemd service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start and enable Prometheus
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

**Verify after step:**
```bash
# Service status
sudo systemctl status prometheus

# Config validation
promtool check config /etc/prometheus/prometheus.yml

# Alert rules validation
promtool check rules /etc/prometheus/alert_rules.yml

# API responding
curl -s http://localhost:9090/-/ready

# Check configured targets (will show DOWN until app server is set up)
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(t['labels']['job'], '->', t['health'])
"
```
✅ **Expected:** Service `active (running)`, config check returns `SUCCESS`, `localhost` targets show `up`

---

## Step 5 — Install Node Exporter (v1.7.0)

**What this step does:**
- Creates `node_exporter` system user
- Downloads Node Exporter binary from GitHub
- Installs to `/usr/local/bin/node_exporter`
- Creates systemd service (runs as `node_exporter` user, no arguments needed)
- Starts and enables the service

This provides system metrics (CPU, memory, disk, network) for the **monitoring server itself**.

**Commands:**
```bash
# Create system user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Download and extract
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xf node_exporter-1.7.0.linux-amd64.tar.gz

# Install binary
sudo cp -f node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Clean up
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Start and enable Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

**Verify after step:**
```bash
# Service status
sudo systemctl status node_exporter

# Metrics endpoint
curl -s http://localhost:9100/metrics | head -10

# Specific metrics
curl -s http://localhost:9100/metrics | grep "node_memory_MemAvailable_bytes"
curl -s http://localhost:9100/metrics | grep "node_cpu_seconds_total" | head -3
```
✅ **Expected:** Service `active (running)`, metrics output with CPU/memory data

---

## Step 6 — Install Grafana (latest)

**What this step does:**
- Adds the Grafana APT repository (if not already added)
- Installs Grafana via `apt`
- Changes the default port from `3000` to `3001` in `/etc/grafana/grafana.ini`
- Creates provisioning directories: `/etc/grafana/provisioning/datasources/`, `/etc/grafana/provisioning/dashboards/`
- Creates `/var/lib/grafana/dashboards/`

**Datasources auto-provisioned (no manual setup needed):**

`/etc/grafana/provisioning/datasources/prometheus.yml`:
- Name: `Prometheus`, URL: `http://localhost:9090`, set as **default**

`/etc/grafana/provisioning/datasources/loki.yml`:
- Name: `Loki`, URL: `http://localhost:3100`

**Dashboard provider configured:**
- Folder: `BMI Health Tracker`
- Watches: `/var/lib/grafana/dashboards/`
- Auto-reloads every 30 seconds

**Dashboards auto-copied from `monitoring/3-tier-app/dashboards/`:**
All `*.json` files are copied dynamically — currently 5 dashboards:
- `three-tier-application-dashboard.json`
- `loki-logs-dashboard.json`
- `nodejs-runtime-dashboard.json`
- `monitoring-server-health-dashboard.json`
- `bmi-business-metrics-dashboard.json`

- Starts and enables the service

**Commands:**
```bash
# Add Grafana APT repository
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository -y "deb https://apt.grafana.com stable main"
sudo apt update -qq

# Install Grafana
sudo DEBIAN_FRONTEND=noninteractive apt install -y grafana

# Change default port from 3000 to 3001
sudo sed -i 's/;http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini
sudo sed -i 's/http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini

# Create provisioning directories
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

# Create Prometheus datasource provisioning file
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
EOF

# Create Loki datasource provisioning file
sudo tee /etc/grafana/provisioning/datasources/loki.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    editable: false
EOF

# Create dashboard provider configuration
sudo tee /etc/grafana/provisioning/dashboards/default.yml > /dev/null <<'EOF'
apiVersion: 1

providers:
  - name: 'BMI Health Tracker'
    orgId: 1
    folder: 'BMI Health Tracker'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

# Copy all dashboard JSON files  (run from repo root)
sudo cp monitoring/3-tier-app/dashboards/*.json /var/lib/grafana/dashboards/

# Fix ownership
sudo chown -R grafana:grafana /etc/grafana/provisioning
sudo chown -R grafana:grafana /var/lib/grafana/dashboards

# Start and enable Grafana
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

**Verify after step:**
```bash
# Service status
sudo systemctl status grafana-server

# Port is 3001 (not 3000)
curl -s http://localhost:3001/api/health

# Datasources provisioned (wait ~10s after start)
curl -s http://admin:admin@localhost:3001/api/datasources | python3 -m json.tool | grep '"name"'

# Dashboards provisioned
curl -s http://admin:admin@localhost:3001/api/search | python3 -m json.tool | grep '"title"'

# Confirm dashboards were copied
ls -la /var/lib/grafana/dashboards/
```
✅ **Expected:** Health check returns `{"database":"ok","version":"..."}`, both datasources listed, 5 dashboards visible

---

## Step 7 — Install Loki (v2.9.3)

**What this step does:**
- Downloads `loki-linux-amd64.zip` from GitHub
- Installs to `/usr/local/bin/loki`
- Creates `loki` system user, `/etc/loki/`, `/var/lib/loki/`
- Writes `/etc/loki/loki-config.yml`:
  - HTTP port: `3100`, gRPC port: `9096`
  - Storage: filesystem (chunks at `/var/lib/loki/chunks`)
  - Schema: `boltdb-shipper`, `v11`
  - Log retention: **31 days** (`744h`)
  - AlertManager integration: `http://localhost:9093`
- Creates systemd service
- Starts and enables the service

**Commands:**
```bash
# Download and install Loki binary
cd /tmp
wget https://github.com/grafana/loki/releases/download/v2.9.3/loki-linux-amd64.zip
unzip -o loki-linux-amd64.zip
sudo mv -f loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
rm -f loki-linux-amd64.zip

# Create system user and directories
sudo useradd --no-create-home --shell /bin/false loki
sudo mkdir -p /etc/loki /var/lib/loki
sudo chown loki:loki /var/lib/loki

# Write Loki configuration
sudo tee /etc/loki/loki-config.yml > /dev/null <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

limits_config:
  retention_period: 744h
EOF

sudo chown loki:loki /etc/loki/loki-config.yml

# Create systemd service
sudo tee /etc/systemd/system/loki.service > /dev/null <<'EOF'
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start and enable Loki
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki
```

**Verify after step:**
```bash
# Service status
sudo systemctl status loki

# Ready endpoint
curl -s http://localhost:3100/ready

# Metrics (Loki exposes its own metrics)
curl -s http://localhost:3100/metrics | grep "^loki_" | head -5

# Check config
cat /etc/loki/loki-config.yml | grep -E "http_listen_port|retention_period"
```
✅ **Expected:** Service `active (running)`, `/ready` returns `ready`, port 3100 metrics available

---

## Step 8 — Install AlertManager (v0.26.0)

**What this step does:**
- Downloads `alertmanager-0.26.0.linux-amd64.tar.gz` from GitHub
- Installs `alertmanager` and `amtool` to `/usr/local/bin/`
- Creates `alertmanager` system user, `/etc/alertmanager/`, `/var/lib/alertmanager/`
- Writes `/etc/alertmanager/alertmanager.yml`:
  - Default receiver (no notifications by default — add email/Slack later)
  - Repeat interval: 12 hours
  - Inhibit rules: critical suppresses warning for same alert
- Creates systemd service
- Starts and enables the service

**Commands:**
```bash
# Download and extract AlertManager
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xf alertmanager-0.26.0.linux-amd64.tar.gz
cd alertmanager-0.26.0.linux-amd64

# Install binaries
sudo cp -f alertmanager amtool /usr/local/bin/

# Clean up
cd /tmp && rm -rf alertmanager-0.26.0.linux-amd64*

# Create system user and directories
sudo useradd --no-create-home --shell /bin/false alertmanager
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
sudo chown alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

# Write AlertManager configuration
sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default-receiver'

receivers:
  - name: 'default-receiver'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF

sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

# Create systemd service
sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus AlertManager
After=network.target

[Service]
Type=simple
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager/
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start and enable AlertManager
sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager
```

**Verify after step:**
```bash
# Service status
sudo systemctl status alertmanager

# AlertManager API
curl -s http://localhost:9093/-/ready

# View current alerts (empty at first)
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool

# Validate config
amtool check-config /etc/alertmanager/alertmanager.yml
```
✅ **Expected:** Service `active (running)`, ready endpoint responds, config check `SUCCESS`

---

## Step 9 — Verify Grafana Datasources

**What this step does:**
- Waits 10 seconds for Grafana to fully initialize
- Calls the Grafana API to confirm `Prometheus` datasource is registered
- Calls the Grafana API to confirm `Loki` datasource is registered
- Logs warnings (not errors) if not found — provisioning may need another moment

**Verify manually:**
```bash
# Both datasources via API
curl -s http://admin:admin@localhost:3001/api/datasources | python3 -c "
import json,sys
for ds in json.load(sys.stdin):
    print(ds['name'], '->', ds['url'], '(default:', ds.get('isDefault', False), ')')
"

# Test Prometheus datasource
curl -s "http://admin:admin@localhost:3001/api/datasources/proxy/1/api/v1/query?query=up" | python3 -m json.tool | grep '"status"'
```
✅ **Expected:** `Prometheus -> http://localhost:9090 (default: True)` and `Loki -> http://localhost:3100`

---

## Step 10 — Final Verification

**What this step does:**
- Checks each of the 5 installed services with `systemctl is-active`:
  - `prometheus`, `grafana-server`, `loki`, `alertmanager`, `node_exporter`
- Fails with exit code 1 if any service is not running

**Run the same check manually:**
```bash
for svc in prometheus grafana-server loki alertmanager node_exporter; do
  status=$(systemctl is-active $svc)
  echo "$svc: $status"
done
```
✅ **Expected:** All 5 services show `active`

---

## What Gets Installed — Summary

| Component | Binary | Config | Port | Manager |
|---|---|---|---|---|
| Prometheus | `/usr/local/bin/prometheus` | `/etc/prometheus/prometheus.yml` | 9090 | systemd |
| Node Exporter | `/usr/local/bin/node_exporter` | none | 9100 | systemd |
| Grafana | apt package | `/etc/grafana/grafana.ini` | 3001 | systemd |
| Loki | `/usr/local/bin/loki` | `/etc/loki/loki-config.yml` | 3100 | systemd |
| AlertManager | `/usr/local/bin/alertmanager` | `/etc/alertmanager/alertmanager.yml` | 9093 | systemd |

---

## Access Points After Completion

After completing all steps, access the following services:

| Service | URL | Credentials |
|---|---|---|
| Grafana | `http://PUBLIC_IP:3001` | admin / admin (change on first login) |
| Prometheus | `http://PUBLIC_IP:9090` | none |
| AlertManager | `http://PUBLIC_IP:9093` | none |
| Loki | `http://PUBLIC_IP:3100` | none |

---

## Troubleshooting

**Prometheus targets show DOWN:**
```bash
# Check targets
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    if t['health'] != 'up':
        print('DOWN:', t['labels']['job'], t['scrapeUrl'], t.get('lastError',''))
"

# Verify app server IP in config
grep -E "APP_SERVER_IP|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" /etc/prometheus/prometheus.yml

# Reload after fixing config
curl -X POST http://localhost:9090/-/reload
```

**Grafana dashboards not showing:**
```bash
# Check dashboards were copied
ls -la /var/lib/grafana/dashboards/

# Copy them manually if missing
sudo cp /home/ubuntu/single-server-3tier-webapp-monitoring/monitoring/3-tier-app/dashboards/*.json /var/lib/grafana/dashboards/
sudo chown grafana:grafana /var/lib/grafana/dashboards/*.json

# Trigger reload without restart
curl -s -X POST http://admin:admin@localhost:3001/api/admin/provisioning/dashboards/reload
```

**Loki not receiving logs:**
```bash
# Check Loki is ready
curl http://localhost:3100/ready

# Check firewall allows port 3100 from app server
sudo ufw status | grep 3100

# Confirm Promtail on app server has correct Loki URL
ssh ubuntu@APP_SERVER_IP "grep url /etc/promtail/promtail-config.yml"
```

**AlertManager not receiving alerts from Prometheus:**
```bash
# Verify AlertManager is in Prometheus config
grep -A 3 "alertmanagers:" /etc/prometheus/prometheus.yml

# Check AlertManager is running
sudo systemctl status alertmanager
curl http://localhost:9093/-/ready
```

**Grafana can't query Prometheus:**
```bash
# Test Prometheus API directly
curl "http://localhost:9090/api/v1/query?query=up"

# Test from Grafana datasource proxy
curl http://admin:admin@localhost:3001/api/datasources/1/health
```

---

## Next Step

Once monitoring server setup is complete, follow the **Application Server Setup Guide** (`setup-application-server-guide.md`) on the **App Server**.

After that, verify all 9 Prometheus targets are UP:
```
http://MONITORING_SERVER_PUBLIC_IP:9090/targets
```

---

## 🧑‍💻 Author
*Md. Sarowar Alam*  
Lead DevOps Engineer, WPP Production - Dhaka  
📧 Email: sarowar@hotmail.com  
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
