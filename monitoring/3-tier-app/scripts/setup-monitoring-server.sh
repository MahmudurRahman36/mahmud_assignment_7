#!/bin/bash

################################################################################
# Three-Tier Application Monitoring Server - Automated Setup Script
#
# This script automates the complete setup of a monitoring infrastructure for
# the BMI Health Tracker three-tier application including:
#   - Prometheus (metrics collection and storage)
#   - Grafana (visualization and dashboards)
#   - Loki (log aggregation)
#   - AlertManager (alert handling and notifications)
#   - Node Exporter (system metrics for monitoring server itself)
#
# Usage: 
#   1. SSH to your monitoring server
#   2. Clone the repository
#   3. chmod +x monitoring/3-tier-app/scripts/setup-monitoring-server.sh
#   4. sudo ./monitoring/3-tier-app/scripts/setup-monitoring-server.sh
#
# Requirements:
#   - Ubuntu 22.04 LTS
#   - Minimum 2 vCPU, 4GB RAM, 30GB disk
#   - Root or sudo access
#   - Internet connectivity
#
# Features:
#   - Fully idempotent - safe to run multiple times
#   - Handles partial installations and updates
#   - Stops services before updating binaries
#   - Preserves existing configurations where appropriate
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Version variables
PROMETHEUS_VERSION="2.48.0"
NODE_EXPORTER_VERSION="1.7.0"
LOKI_VERSION="2.9.3"
ALERTMANAGER_VERSION="0.26.0"
GRAFANA_VERSION="latest"

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MONITORING_CONFIG_DIR="$PROJECT_ROOT/monitoring/3-tier-app/config"
DASHBOARD_DIR="$PROJECT_ROOT/monitoring/3-tier-app/dashboards"

# Functions for colored output
log_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${MAGENTA}>>> $1${NC}\n"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Get EC2 Public IP (IMDSv2)
get_ec2_public_ip() {
    local TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 2 2>/dev/null)
    
    if [ -n "$TOKEN" ]; then
        local PUBLIC_IP=$(curl -s \
            -H "X-aws-ec2-metadata-token: $TOKEN" \
            --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    else
        local PUBLIC_IP=$(curl -s --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    fi
    
    echo "$PUBLIC_IP" | tr -d '[:space:]'
}

# Get EC2 Private IP
get_ec2_private_ip() {
    local TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 2 2>/dev/null)
    
    if [ -n "$TOKEN" ]; then
        local PRIVATE_IP=$(curl -s \
            -H "X-aws-ec2-metadata-token: $TOKEN" \
            --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
    else
        local PRIVATE_IP=$(curl -s --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
    fi
    
    echo "$PRIVATE_IP" | tr -d '[:space:]'
}

# Banner
display_banner() {
    clear || true
    echo -e "${GREEN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     BMI Health Tracker - Monitoring Server Setup Script          ║
║                   Three-Tier Application Monitoring              ║
║                                                                  ║
║  This script will install and configure:                         ║
║  • Prometheus (Metrics Collection)                               ║
║  • Grafana (Visualization & Dashboards)                          ║
║  • Loki (Log Aggregation)                                        ║
║  • AlertManager (Alert Management)                               ║
║  • Node Exporter (System Metrics)                                ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Step 1: Initial checks and setup
initial_setup() {
    log_header "Step 1: Initial System Setup"
    
    log_info "Detecting server IP addresses..."
    PUBLIC_IP=$(get_ec2_public_ip)
    PRIVATE_IP=$(get_ec2_private_ip)
    
    if [ -n "$PUBLIC_IP" ]; then
        log_success "Monitoring Server Public IP: $PUBLIC_IP"
    else
        log_warning "Could not detect public IP (not running on AWS?)"
        PUBLIC_IP="YOUR_PUBLIC_IP"
    fi
    
    if [ -n "$PRIVATE_IP" ]; then
        log_success "Monitoring Server Private IP: $PRIVATE_IP"
    else
        log_warning "Could not detect private IP"
        PRIVATE_IP=$(hostname -I | awk '{print $1}')
        log_info "Using local IP: $PRIVATE_IP"
    fi
    
    log_step "Updating system packages..."
    apt update -qq
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq
    log_success "System packages updated"
    
    log_step "Installing essential tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y -qq \
        wget curl git unzip tar jq net-tools \
        software-properties-common apt-transport-https ca-certificates
    log_success "Essential tools installed"
}

# Step 2: Configure firewall
configure_firewall() {
    log_header "Step 2: Configuring Firewall"
    
    log_step "Setting up UFW firewall rules..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow 22/tcp comment 'SSH'
    log_info "Allowed SSH (22)"
    
    # Allow Grafana
    ufw allow 3001/tcp comment 'Grafana'
    log_info "Allowed Grafana (3001)"
    
    # Allow Prometheus (optional, for debugging)
    ufw allow 9090/tcp comment 'Prometheus'
    log_info "Allowed Prometheus (9090)"
    
    # Allow Loki (optional)
    ufw allow 3100/tcp comment 'Loki'
    log_info "Allowed Loki (3100)"
    
    # Reload firewall
    ufw reload
    
    log_success "Firewall configured successfully"
    
    # Display firewall status
    log_info "Current firewall status:"
    ufw status
}

# Step 3: Install Prometheus
install_prometheus() {
    log_header "Step 3: Installing Prometheus"
    
    # Check if already installed and running
    if systemctl is-active --quiet prometheus 2>/dev/null; then
        log_info "Prometheus is already running. Stopping for update..."
        systemctl stop prometheus
    fi
    
    log_step "Creating Prometheus user and directories..."
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    
    mkdir -p /etc/prometheus
    mkdir -p /var/lib/prometheus
    chown prometheus:prometheus /etc/prometheus
    chown prometheus:prometheus /var/lib/prometheus
    
    log_step "Downloading Prometheus v${PROMETHEUS_VERSION}..."
    cd /tmp
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    tar -xf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    cd prometheus-${PROMETHEUS_VERSION}.linux-amd64
    
    log_step "Installing Prometheus binaries..."
    cp -f prometheus /usr/local/bin/
    cp -f promtool /usr/local/bin/
    chown prometheus:prometheus /usr/local/bin/prometheus
    chown prometheus:prometheus /usr/local/bin/promtool
    
    cp -rf consoles /etc/prometheus/
    cp -rf console_libraries /etc/prometheus/
    chown -R prometheus:prometheus /etc/prometheus/consoles
    chown -R prometheus:prometheus /etc/prometheus/console_libraries
    
    log_step "Cleaning up..."
    cd /tmp
    rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*
    
    log_success "Prometheus installed successfully"
}

# Step 4: Configure Prometheus
configure_prometheus() {
    log_header "Step 4: Configuring Prometheus"
    
    # Check if configuration already exists
    if [ -f /etc/prometheus/prometheus.yml ]; then
        log_info "Prometheus configuration already exists"
        # Try to extract existing APP_SERVER_IP from config
        EXISTING_IP=$(grep -oP '(?<=- )[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?=:9100)' /etc/prometheus/prometheus.yml 2>/dev/null | head -1)
        if [ -n "$EXISTING_IP" ]; then
            log_info "Found existing Application Server IP: $EXISTING_IP"
            read -p "Keep this IP or enter new one (press Enter to keep): " NEW_IP
            if [ -z "$NEW_IP" ]; then
                APP_SERVER_IP="$EXISTING_IP"
                log_success "Using existing IP: $APP_SERVER_IP"
            else
                APP_SERVER_IP="$NEW_IP"
            fi
        else
            log_info "Please enter your Application Server Private IP address:"
            read -p "Application Server IP: " APP_SERVER_IP
        fi
    else
        log_info "Please enter your Application Server Private IP address:"
        read -p "Application Server IP: " APP_SERVER_IP
    fi
    
    if [ -z "$APP_SERVER_IP" ]; then
        log_error "Application Server IP is required!"
        exit 1
    fi
    
    log_step "Creating Prometheus configuration..."
    
    cat > /etc/prometheus/prometheus.yml <<EOF
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
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          role: 'monitoring'

  # Node Exporter - Application Server (System Metrics)
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9100']
        labels:
          server: 'bmi-app-server'
          role: 'system'
          tier: 'infrastructure'

  # PostgreSQL Exporter - Database Layer
  - job_name: 'postgresql'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9187']
        labels:
          server: 'bmi-app-server'
          database: 'bmidb'
          role: 'database'
          tier: 'data'

  # Nginx Exporter - Frontend Layer
  - job_name: 'nginx'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9113']
        labels:
          server: 'bmi-app-server'
          role: 'webserver'
          tier: 'frontend'

  # BMI Custom Application Exporter - Backend Layer
  - job_name: 'bmi-backend'
    static_configs:
      - targets: ['${APP_SERVER_IP}:9091']
        labels:
          server: 'bmi-app-server'
          application: 'bmi-health-tracker'
          role: 'backend'
          tier: 'application'

  # Node Exporter - Monitoring Server (Self-monitoring)
  - job_name: 'node_exporter_monitoring'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          server: 'monitoring-server'
          role: 'monitoring'

  # Grafana - Monitoring Server
  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3001']
        labels:
          server: 'monitoring-server'
          role: 'visualization'

  # Loki - Monitoring Server
  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']
        labels:
          server: 'monitoring-server'
          role: 'log-aggregation'

  # AlertManager - Monitoring Server
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          server: 'monitoring-server'
          role: 'alerting'
EOF
    
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    log_success "Prometheus configuration created"
    
    log_step "Creating alert rules..."
    
    cat > /etc/prometheus/alert_rules.yml <<'EOF'
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
    
    chown prometheus:prometheus /etc/prometheus/alert_rules.yml
    log_success "Alert rules created"
    
    log_step "Creating Prometheus systemd service..."
    
    cat > /etc/systemd/system/prometheus.service <<'EOF'
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
    
    log_step "Starting Prometheus..."
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    sleep 3
    
    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus started successfully"
    else
        log_error "Prometheus failed to start"
        journalctl -u prometheus -n 20 --no-pager
        exit 1
    fi
}

# Step 5: Install Node Exporter
install_node_exporter() {
    log_header "Step 5: Installing Node Exporter"
    
    # Check if already installed and running
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        log_info "Node Exporter is already running. Stopping for update..."
        systemctl stop node_exporter
    fi
    
    log_step "Creating Node Exporter user..."
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
    
    log_step "Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
    cd /tmp
    wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
    tar -xf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
    
    log_step "Installing Node Exporter..."
    cp -f node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
    
    log_step "Creating Node Exporter systemd service..."
    
    cat > /etc/systemd/system/node_exporter.service <<'EOF'
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
    
    log_step "Starting Node Exporter..."
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    sleep 2
    
    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter started successfully"
    else
        log_error "Node Exporter failed to start"
        exit 1
    fi
}

# Step 6: Install Grafana
install_grafana() {
    log_header "Step 6: Installing Grafana"
    
    # Check if already installed and running
    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        log_info "Grafana is already running. Will restart after configuration..."
        systemctl stop grafana-server
    fi
    
    log_step "Adding Grafana repository..."
    if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
        wget -q -O - https://apt.grafana.com/gpg.key | apt-key add -
        add-apt-repository -y "deb https://apt.grafana.com stable main"
        apt update -qq
    else
        log_info "Grafana repository already configured"
    fi
    
    log_step "Installing Grafana..."
    DEBIAN_FRONTEND=noninteractive apt install -y -qq grafana
    
    log_step "Configuring Grafana to use port 3001..."
    sed -i 's/;http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini
    sed -i 's/http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini
    
    log_step "Setting up Grafana provisioning for datasources..."
    mkdir -p /etc/grafana/provisioning/datasources
    mkdir -p /etc/grafana/provisioning/dashboards
    mkdir -p /var/lib/grafana/dashboards
    
    # Create Prometheus datasource provisioning
    cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
EOF
    
    # Create Loki datasource provisioning
    cat > /etc/grafana/provisioning/datasources/loki.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    editable: false
EOF
    
    # Create dashboard provider configuration
    cat > /etc/grafana/provisioning/dashboards/default.yml <<'EOF'
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
    
    log_step "Copying dashboards to Grafana..."
    DASHBOARD_COUNT=0
    if [ -d "$DASHBOARD_DIR" ]; then
        for dashboard_file in "$DASHBOARD_DIR"/*.json; do
            if [ -f "$dashboard_file" ]; then
                cp "$dashboard_file" /var/lib/grafana/dashboards/
                DASHBOARD_COUNT=$((DASHBOARD_COUNT + 1))
                log_success "Copied $(basename "$dashboard_file")"
            fi
        done
    fi

    if [ "$DASHBOARD_COUNT" -eq 0 ]; then
        log_warning "No dashboards found in $DASHBOARD_DIR"
    else
        log_success "Copied $DASHBOARD_COUNT dashboard(s)"
    fi
    
    chown -R grafana:grafana /etc/grafana/provisioning
    chown -R grafana:grafana /var/lib/grafana/dashboards
    
    log_step "Starting Grafana..."
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server
    
    sleep 3
    
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana started successfully"
    else
        log_error "Grafana failed to start"
        exit 1
    fi
}

# Step 7: Install Loki
install_loki() {
    log_header "Step 7: Installing Loki"
    
    # Check if already installed and running
    if systemctl is-active --quiet loki 2>/dev/null; then
        log_info "Loki is already running. Stopping for update..."
        systemctl stop loki
    fi
    
    log_step "Downloading Loki v${LOKI_VERSION}..."
    cd /tmp
    wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip
    unzip -o -q loki-linux-amd64.zip
    mv -f loki-linux-amd64 /usr/local/bin/loki
    chmod +x /usr/local/bin/loki
    rm -f loki-linux-amd64.zip
    
    log_step "Creating Loki user and directories..."
    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
    mkdir -p /etc/loki
    mkdir -p /var/lib/loki
    chown loki:loki /var/lib/loki
    
    log_step "Creating Loki configuration..."
    
    cat > /etc/loki/loki-config.yml <<'EOF'
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
    
    chown loki:loki /etc/loki/loki-config.yml
    
    log_step "Creating Loki systemd service..."
    
    cat > /etc/systemd/system/loki.service <<'EOF'
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
    
    log_step "Starting Loki..."
    systemctl daemon-reload
    systemctl enable loki
    systemctl start loki
    
    sleep 3
    
    if systemctl is-active --quiet loki; then
        log_success "Loki started successfully"
    else
        log_error "Loki failed to start"
        exit 1
    fi
}

# Step 8: Install AlertManager
install_alertmanager() {
    log_header "Step 8: Installing AlertManager"
    
    # Check if already installed and running
    if systemctl is-active --quiet alertmanager 2>/dev/null; then
        log_info "AlertManager is already running. Stopping for update..."
        systemctl stop alertmanager
    fi
    
    log_step "Downloading AlertManager v${ALERTMANAGER_VERSION}..."
    cd /tmp
    wget -q https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
    tar -xf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
    cd alertmanager-${ALERTMANAGER_VERSION}.linux-amd64
    
    log_step "Installing AlertManager binaries..."
    cp -f alertmanager /usr/local/bin/
    cp -f amtool /usr/local/bin/
    
    cd /tmp
    rm -rf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64*
    
    log_step "Creating AlertManager user and directories..."
    useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true
    mkdir -p /etc/alertmanager
    mkdir -p /var/lib/alertmanager
    chown alertmanager:alertmanager /etc/alertmanager
    chown alertmanager:alertmanager /var/lib/alertmanager
    chown alertmanager:alertmanager /usr/local/bin/alertmanager
    chown alertmanager:alertmanager /usr/local/bin/amtool
    
    log_step "Creating AlertManager configuration..."
    
    local config_src="$PROJECT_ROOT/monitoring/alertmanager/alertmanager.yml"
    local config_dest="/etc/alertmanager/alertmanager.yml"
    
    if [ -f "$config_src" ]; then
        log_info "Found AlertManager template at $config_src. Copying..."
        cp "$config_src" "$config_dest"
        
        # Load env vars or use defaults
        local smarthost="${SMTP_SMARTHOST:-smtp.gmail.com:587}"
        local from_email="${SMTP_FROM:-alerts@yourcompany.com}"
        local auth_user="${SMTP_AUTH_USERNAME:-alerts@yourcompany.com}"
        local auth_pass="${SMTP_AUTH_PASSWORD:-your-app-password}"
        local to_email="${ALERT_EMAIL_TO:-oncall@yourcompany.com}"
        
        log_info "Substituting SMTP configuration parameters..."
        sed -i "s|smtp_smarthost: .*|smtp_smarthost: '$smarthost'|g" "$config_dest"
        sed -i "s|smtp_from: .*|smtp_from: '$from_email'|g" "$config_dest"
        sed -i "s|smtp_auth_username: .*|smtp_auth_username: '$auth_user'|g" "$config_dest"
        sed -i "s|smtp_auth_password: .*|smtp_auth_password: '$auth_pass'|g" "$config_dest"
        sed -i "s|to: .*|to: '$to_email'|g" "$config_dest"
        
        log_success "AlertManager configuration initialized from repository template with custom/default SMTP settings."
    else
        log_warning "No AlertManager template found at $config_src. Creating default configuration..."
        cat > "$config_dest" <<'EOF'
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
    fi
    
    chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
    
    log_step "Creating AlertManager systemd service..."
    
    cat > /etc/systemd/system/alertmanager.service <<'EOF'
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
    
    log_step "Starting AlertManager..."
    systemctl daemon-reload
    systemctl enable alertmanager
    systemctl start alertmanager
    
    sleep 3
    
    if systemctl is-active --quiet alertmanager; then
        log_success "AlertManager started successfully"
    else
        log_error "AlertManager failed to start"
        exit 1
    fi
}

# Step 9: Configure Grafana data sources
configure_grafana() {
    log_header "Step 9: Verifying Grafana Configuration"
    
    log_info "Waiting for Grafana to be fully ready..."
    sleep 10
    
    log_step "Verifying Prometheus datasource..."
    if curl -s http://localhost:3001/api/datasources | grep -q "Prometheus"; then
        log_success "Prometheus datasource configured via provisioning"
    else
        log_warning "Prometheus datasource not found - check provisioning files"
    fi
    
    log_step "Verifying Loki datasource..."
    if curl -s http://localhost:3001/api/datasources | grep -q "Loki"; then
        log_success "Loki datasource configured via provisioning"
    else
        log_warning "Loki datasource not found - check provisioning files"
    fi
    
    log_success "Grafana datasources and dashboards configured via provisioning"
}

# Step 10: Final verification
final_verification() {
    log_header "Step 10: Final Verification"
    
    log_step "Checking service status..."
    
    declare -a services=("prometheus" "grafana-server" "loki" "alertmanager" "node_exporter")
    all_good=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_error "$service is NOT running"
            all_good=false
        fi
    done
    
    if [ "$all_good" = true ]; then
        log_success "All services are running successfully!"
    else
        log_error "Some services are not running. Check logs with: journalctl -u <service-name>"
        exit 1
    fi
}

# Step 11: Display summary
display_summary() {
    log_header "Installation Complete!"
    
    PUBLIC_IP=$(get_ec2_public_ip)
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Monitoring Server Setup Complete!                      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Access Points:${NC}"
    echo -e "  ${YELLOW}Grafana:${NC}       http://${PUBLIC_IP}:3001"
    echo -e "                 Username: admin"
    echo -e "                 Password: admin (change on first login)"
    echo ""
    echo -e "  ${YELLOW}Prometheus:${NC}    http://${PUBLIC_IP}:9090"
    echo -e "  ${YELLOW}AlertManager:${NC}  http://${PUBLIC_IP}:9093"
    echo -e "  ${YELLOW}Loki:${NC}          http://${PUBLIC_IP}:3100"
    echo ""
    echo -e "${CYAN}Service Management:${NC}"
    echo -e "  Check status:  ${YELLOW}sudo systemctl status <service-name>${NC}"
    echo -e "  View logs:     ${YELLOW}sudo journalctl -u <service-name> -f${NC}"
    echo -e "  Restart:       ${YELLOW}sudo systemctl restart <service-name>${NC}"
    echo ""
    echo -e "${CYAN}Services Installed:${NC}"
    echo -e "  • prometheus"
    echo -e "  • grafana-server"
    echo -e "  • loki"
    echo -e "  • alertmanager"
    echo -e "  • node_exporter"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "  1. Access Grafana at http://${PUBLIC_IP}:3001"
    echo -e "  2. Login with admin/admin and change password"
    echo -e "  3. ${GREEN}Datasources pre-configured:${NC} Prometheus (default) and Loki"
    echo -e "  4. ${GREEN}Dashboards pre-loaded:${NC} Check 'BMI Health Tracker' folder"
    echo -e "  5. Run the application server setup script on your app server"
    echo -e "  6. Check Prometheus targets at http://${PUBLIC_IP}:9090/targets"
    echo ""
    echo -e "${CYAN}Application Server IP configured:${NC} ${YELLOW}${APP_SERVER_IP}${NC}"
    echo ""
    echo -e "${GREEN}Monitoring infrastructure is ready!${NC}"
    echo ""
}

# Main execution
main() {
    display_banner
    check_root
    
    # Run all installation steps
    initial_setup
    configure_firewall
    install_prometheus
    configure_prometheus
    install_node_exporter
    install_grafana
    install_loki
    install_alertmanager
    configure_grafana
    final_verification
    display_summary
}

# Run main function
main

exit 0
