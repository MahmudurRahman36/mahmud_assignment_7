#!/bin/bash

################################################################################
# Three-Tier Application Server - Automated Monitoring Setup Script
#
# This script automates the installation and configuration of monitoring
# exporters on the BMI Health Tracker application server including:
#   - Node Exporter (system metrics)
#   - PostgreSQL Exporter (database metrics)
#   - Nginx Exporter (web server metrics)
#   - BMI Custom Application Exporter (business metrics)
#   - Promtail (log shipping to Loki)
#
# Usage: 
#   1. SSH to your application server (where BMI app is deployed)
#   2. cd to your project directory
#   3. chmod +x monitoring/3-tier-app/scripts/setup-application-server.sh
#   4. sudo ./monitoring/3-tier-app/scripts/setup-application-server.sh
#
# Requirements:
#   - Ubuntu 22.04 LTS
#   - Root or sudo access
#   - Internet connectivity
#
# Auto-installed if missing:
#   - Node.js (v20.x LTS) - Required for BMI custom exporter
#   - PM2 - Required for process management
#   - PostgreSQL - Required for database monitoring
#   - Nginx - Required for web server monitoring
#
# Features:
#   - Fully idempotent - safe to run multiple times
#   - Handles partial installations and updates
#   - Auto-installs missing dependencies
#   - Stops services before updating binaries
#   - Preserves existing configurations
################################################################################

set -e  # Exit on error

# Parse command line options for roles (backend, frontend, database)
ROLE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --role)
            ROLE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Version variables
NODE_EXPORTER_VERSION="1.7.0"
POSTGRES_EXPORTER_VERSION="0.15.0"
NGINX_EXPORTER_VERSION="0.11.0"
PROMTAIL_VERSION="2.9.3"

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/src/backend"
EXPORTER_DIR="$PROJECT_ROOT/monitoring/exporters/bmi-app-exporter"

# Validate project structure
validate_project_structure() {
    if [ "$ROLE" = "database" ]; then
        return 0
    fi
    if [ ! -d "$EXPORTER_DIR" ]; then
        log_error "Exporter directory not found: $EXPORTER_DIR"
        log_error "Current PROJECT_ROOT: $PROJECT_ROOT"
        log_error "Please ensure you're running this script from the project directory"
        log_error "Expected structure: /path/to/project/monitoring/3-tier-app/scripts/setup-application-server.sh"
        exit 1
    fi
    
    if [ ! -f "$EXPORTER_DIR/exporter.js" ]; then
        log_error "Exporter file not found: $EXPORTER_DIR/exporter.js"
        log_error "BMI application exporter is missing"
        exit 1
    fi
}

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
║   BMI Health Tracker - Application Server Monitoring Setup       ║
║                   Three-Tier Application Monitoring              ║
║                                                                  ║
║  This script will install and configure:                         ║
║  • Node Exporter (System Metrics)                                ║
║  • PostgreSQL Exporter (Database Metrics)                        ║
║  • Nginx Exporter (Web Server Metrics)                           ║
║  • BMI Custom Exporter (Application Metrics)                     ║
║  • Promtail (Log Shipping)                                       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Get original user (who ran sudo)
get_original_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# Step 1: Initial checks and setup
initial_setup() {
    log_header "Step 1: Initial System Setup"
    
    log_info "Detecting server IP addresses..."
    PUBLIC_IP=$(get_ec2_public_ip)
    PRIVATE_IP=$(get_ec2_private_ip)
    
    if [ -n "$PUBLIC_IP" ]; then
        log_success "Application Server Public IP: $PUBLIC_IP"
    else
        log_warning "Could not detect public IP (not running on AWS?)"
        PUBLIC_IP="YOUR_PUBLIC_IP"
    fi
    
    if [ -n "$PRIVATE_IP" ]; then
        log_success "Application Server Private IP: $PRIVATE_IP"
    else
        log_warning "Could not detect private IP"
        PRIVATE_IP=$(hostname -I | awk '{print $1}')
        log_info "Using local IP: $PRIVATE_IP"
    fi
    
    # Get monitoring server IP
    echo ""
    log_info "Enter your Monitoring Server Private IP address:"
    read -p "Monitoring Server Private IP: " MONITORING_SERVER_IP
    
    if [ -z "$MONITORING_SERVER_IP" ]; then
        log_error "Monitoring Server IP is required!"
        exit 1
    fi
    
    log_success "Monitoring Server IP: $MONITORING_SERVER_IP"
    
    log_step "Updating system packages..."
    apt update -qq
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq
    log_success "System packages updated"
    
    log_step "Installing essential tools..."
    DEBIAN_FRONTEND=noninteractive apt install -y -qq \
        wget curl git unzip tar jq net-tools
    log_success "Essential tools installed"
}

# Install Node.js if not present
install_nodejs() {
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log_info "Node.js is already installed: $NODE_VERSION"
        return 0
    fi
    
    log_step "Installing Node.js (required for BMI exporter)..."
    
    # Install Node.js 20.x LTS
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
    
    # Verify installation
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        NPM_VERSION=$(npm --version)
        log_success "Node.js $NODE_VERSION installed successfully"
        log_success "npm $NPM_VERSION installed successfully"
    else
        log_error "Node.js installation failed"
        exit 1
    fi
}

# Install PM2 if not present
install_pm2() {
    if command -v pm2 &> /dev/null; then
        PM2_VERSION=$(pm2 --version)
        log_info "PM2 is already installed: v$PM2_VERSION"
        return 0
    fi
    
    log_step "Installing PM2 (required for process management)..."
    
    npm install -g pm2
    
    # Verify installation
    if command -v pm2 &> /dev/null; then
        PM2_VERSION=$(pm2 --version)
        log_success "PM2 v$PM2_VERSION installed successfully"
    else
        log_error "PM2 installation failed"
        exit 1
    fi
}

# Check and install PostgreSQL if not present
check_postgresql() {
    log_info "PostgreSQL Client check: psql is installed. Skipping local database server installation (using remote database)."
    return 0
}

# Check and install Nginx if not present
check_nginx() {
    if command -v nginx &> /dev/null; then
        NGINX_VERSION=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
        log_info "Nginx is already installed: $NGINX_VERSION"
        
        # Check if Nginx service is running
        if systemctl is-active --quiet nginx; then
            log_success "Nginx service is running"
            return 0
        else
            log_warning "Nginx is installed but not running"
            log_step "Starting Nginx service..."
            systemctl start nginx
            systemctl enable nginx
            log_success "Nginx service started"
            return 0
        fi
    fi
    
    log_warning "Nginx is not installed"
    log_info "Installing Nginx..."
    
    # Install Nginx
    DEBIAN_FRONTEND=noninteractive apt install -y -qq nginx
    
    # Start and enable service
    systemctl start nginx
    systemctl enable nginx
    
    if command -v nginx &> /dev/null; then
        NGINX_VERSION=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
        log_success "Nginx $NGINX_VERSION installed successfully"
    else
        log_error "Nginx installation failed"
        exit 1
    fi
}

# Step 2: Configure firewall
configure_firewall() {
    log_header "Step 2: Configuring Firewall"
    
    log_step "Adding firewall rules for monitoring server..."
    
    # Allow Prometheus to scrape exporters from monitoring server
    ufw allow from "$MONITORING_SERVER_IP" to any port 9100 proto tcp comment 'Node Exporter'
    log_info "Allowed Node Exporter (9100) from monitoring server"
    
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        ufw allow from "$MONITORING_SERVER_IP" to any port 9187 proto tcp comment 'PostgreSQL Exporter'
        log_info "Allowed PostgreSQL Exporter (9187) from monitoring server"
        
        ufw allow from "$MONITORING_SERVER_IP" to any port 9091 proto tcp comment 'BMI App Exporter'
        log_info "Allowed BMI App Exporter (9091) from monitoring server"
    fi
    
    if [ "$ROLE" = "frontend" ] || [ -z "$ROLE" ]; then
        ufw allow from "$MONITORING_SERVER_IP" to any port 9113 proto tcp comment 'Nginx Exporter'
        log_info "Allowed Nginx Exporter (9113) from monitoring server"
    fi
    
    ufw reload
    
    log_success "Firewall configured successfully"
}

# Step 3: Install Node Exporter
install_node_exporter() {
    log_header "Step 3: Installing Node Exporter"
    
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
        journalctl -u node_exporter -n 20 --no-pager
        exit 1
    fi
}

# Step 4: Install PostgreSQL Exporter
install_postgres_exporter() {
    log_header "Step 4: Installing PostgreSQL Exporter"
    
    # Check if already installed and running
    if systemctl is-active --quiet postgres_exporter 2>/dev/null; then
        log_info "PostgreSQL Exporter is already running. Stopping for update..."
        systemctl stop postgres_exporter
    fi
    
    log_step "Downloading PostgreSQL Exporter v${POSTGRES_EXPORTER_VERSION}..."
    cd /tmp
    wget -q https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz
    tar -xf postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz
    
    log_step "Installing PostgreSQL Exporter..."
    cp -f postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter /usr/local/bin/
    chmod +x /usr/local/bin/postgres_exporter
    
    rm -rf postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64*
    
    log_step "Creating PostgreSQL user..."
    useradd --no-create-home --shell /bin/false postgres_exporter 2>/dev/null || true
    
    log_step "Reading Database connection from Backend configuration..."
    DATABASE_URL=""
    if [ -f "$BACKEND_DIR/.env" ]; then
        DATABASE_URL=$(grep "^DATABASE_URL=" "$BACKEND_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    if [ -z "$DATABASE_URL" ]; then
        log_warning "Could not parse DATABASE_URL from $BACKEND_DIR/.env, using default local fallback"
        DATABASE_URL="postgresql://postgres_exporter:fallbackpassword@localhost:5432/bmidb?sslmode=disable"
    else
        log_success "Database URL successfully parsed from backend configuration!"
    fi
    
    log_step "Creating environment file..."
    
    cat > /etc/default/postgres_exporter <<EOF
DATA_SOURCE_NAME="$DATABASE_URL"
EOF
    
    chown postgres_exporter:postgres_exporter /etc/default/postgres_exporter
    chmod 600 /etc/default/postgres_exporter
    
    log_step "Creating PostgreSQL Exporter systemd service..."
    
    cat > /etc/systemd/system/postgres_exporter.service <<'EOF'
[Unit]
Description=PostgreSQL Exporter
After=network.target

[Service]
Type=simple
User=postgres_exporter
Group=postgres_exporter
EnvironmentFile=/etc/default/postgres_exporter
ExecStart=/usr/local/bin/postgres_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    log_step "Starting PostgreSQL Exporter..."
    systemctl daemon-reload
    systemctl enable postgres_exporter
    systemctl start postgres_exporter
    
    sleep 2
    
    if systemctl is-active --quiet postgres_exporter; then
        log_success "PostgreSQL Exporter started successfully"
    else
        log_error "PostgreSQL Exporter failed to start"
        journalctl -u postgres_exporter -n 20 --no-pager
        exit 1
    fi
}

# Step 5: Install Nginx Exporter
install_nginx_exporter() {
    log_header "Step 5: Installing Nginx Exporter"
    
    # Check if already installed and running
    if systemctl is-active --quiet nginx_exporter 2>/dev/null; then
        log_info "Nginx Exporter is already running. Stopping for update..."
        systemctl stop nginx_exporter
    fi
    
    log_step "Configuring Nginx stub_status..."
    
    # Find the Nginx configuration file for BMI app
    if [ -f "/etc/nginx/sites-available/bmi-health-tracker" ]; then
        NGINX_CONFIG="/etc/nginx/sites-available/bmi-health-tracker"
    elif [ -f "/etc/nginx/sites-available/bmi-app" ]; then
        NGINX_CONFIG="/etc/nginx/sites-available/bmi-app"
    elif [ -f "/etc/nginx/sites-available/default" ]; then
        NGINX_CONFIG="/etc/nginx/sites-available/default"
    else
        log_error "Could not find Nginx configuration file"
        exit 1
    fi
    
    # Check if stub_status already exists
    if ! grep -q "stub_status" "$NGINX_CONFIG"; then
        log_info "Adding stub_status to Nginx configuration..."
        
        # Backup the original config
        cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add stub_status location block before the last closing brace
        sed -i '/^}$/i \    # Nginx status endpoint for monitoring\n    location /nginx_status {\n        stub_status on;\n        access_log off;\n        allow 127.0.0.1;\n        allow '"$MONITORING_SERVER_IP"';\n        deny all;\n    }\n' "$NGINX_CONFIG"
        
        # Test and reload Nginx
        nginx -t
        systemctl reload nginx
        
        log_success "Nginx stub_status configured"
    else
        log_info "Nginx stub_status already configured"
    fi
    
    log_step "Downloading Nginx Exporter v${NGINX_EXPORTER_VERSION}..."
    cd /tmp
    wget -q https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz
    tar -xf nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz
    
    log_step "Installing Nginx Exporter..."
    mv -f nginx-prometheus-exporter /usr/local/bin/
    chmod +x /usr/local/bin/nginx-prometheus-exporter
    
    rm -f nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz
    
    log_step "Creating Nginx Exporter user..."
    useradd --no-create-home --shell /bin/false nginx_exporter 2>/dev/null || true
    
    log_step "Creating Nginx Exporter systemd service..."
    
    cat > /etc/systemd/system/nginx_exporter.service <<'EOF'
[Unit]
Description=Nginx Prometheus Exporter
After=network.target

[Service]
Type=simple
User=nginx_exporter
Group=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
  -nginx.scrape-uri=http://localhost/nginx_status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    log_step "Starting Nginx Exporter..."
    systemctl daemon-reload
    systemctl enable nginx_exporter
    systemctl start nginx_exporter
    
    sleep 2
    
    if systemctl is-active --quiet nginx_exporter; then
        log_success "Nginx Exporter started successfully"
    else
        log_error "Nginx Exporter failed to start"
        journalctl -u nginx_exporter -n 20 --no-pager
        exit 1
    fi
}

# Step 6: Install BMI Custom Application Exporter
install_bmi_exporter() {
    log_header "Step 6: Installing BMI Custom Application Exporter"
    
    ORIGINAL_USER=$(get_original_user)
    
    log_step "Verifying exporter directory..."
    
    if [ ! -d "$EXPORTER_DIR" ]; then
        log_error "Exporter directory not found: $EXPORTER_DIR"
        log_error "Make sure you're running this script from the project root"
        exit 1
    fi
    
    log_step "Installing exporter dependencies..."
    
    # Fix directory ownership before npm install
    log_step "Setting proper ownership for exporter directory..."
    
    # Get the actual project directory (resolve symlinks if any)
    REAL_PROJECT_ROOT=$(readlink -f "$PROJECT_ROOT")
    REAL_EXPORTER_DIR=$(readlink -f "$EXPORTER_DIR")
    
    # Fix ownership of entire project tree if it's in root's home
    if [[ "$REAL_PROJECT_ROOT" == /root/* ]]; then
        log_warning "Project is in /root directory. Fixing ownership of entire project..."
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$REAL_PROJECT_ROOT"
    else
        # Just fix the needed directories
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$REAL_EXPORTER_DIR"
        
        # Also fix backend directory ownership if it exists
        if [ -d "$BACKEND_DIR" ]; then
            chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$BACKEND_DIR"
        fi
    fi
    
    # Install dependencies as the original user
    cd "$EXPORTER_DIR"
    sudo -u "$ORIGINAL_USER" npm install
    
    log_success "Dependencies installed"
    
    log_step "Verifying backend .env file..."
    
    if [ ! -f "$BACKEND_DIR/.env" ]; then
        log_warning "Backend .env file not found. Creating from .env.example..."
        
        if [ -f "$BACKEND_DIR/.env.example" ]; then
            # Copy .env.example to .env
            cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
            
            # Set default values if not present
            if ! grep -q "DB_HOST" "$BACKEND_DIR/.env"; then
                cat >> "$BACKEND_DIR/.env" <<EOF

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=bmidb
DB_USER=bmi_user
DB_PASSWORD=your_password_here

# Server Configuration
PORT=3010
NODE_ENV=production
EOF
            fi
            
            log_success "Created .env file from template"
            log_warning "Please update database credentials in $BACKEND_DIR/.env if needed"
        else
            # Create minimal .env
            log_warning "Creating minimal .env file..."
            cat > "$BACKEND_DIR/.env" <<EOF
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=bmidb
DB_USER=bmi_user
DB_PASSWORD=your_password_here

# Server Configuration
PORT=3010
NODE_ENV=production

# Exporter Configuration
EXPORTER_PORT=9091
EOF
            log_success "Created minimal .env file"
            log_warning "Please update database credentials in $BACKEND_DIR/.env"
        fi
    fi
    
    # Check if EXPORTER_PORT is set in .env
    if ! grep -q "EXPORTER_PORT" "$BACKEND_DIR/.env"; then
        log_info "Adding EXPORTER_PORT to .env..."
        echo "" >> "$BACKEND_DIR/.env"
        echo "# Exporter Configuration" >> "$BACKEND_DIR/.env"
        echo "EXPORTER_PORT=9091" >> "$BACKEND_DIR/.env"
    fi
    
    # Fix ownership of .env file
    chown "$ORIGINAL_USER:$ORIGINAL_USER" "$BACKEND_DIR/.env"
    
    log_step "Creating PM2 log directory..."
    mkdir -p /var/log/pm2
    chown -R "$ORIGINAL_USER:$ORIGINAL_USER" /var/log/pm2
    
    # Create logs directory in exporter dir
    mkdir -p "$EXPORTER_DIR/logs"
    chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$EXPORTER_DIR/logs"
    
    log_step "Starting BMI exporter with PM2..."
    
    # Check if backend is running (deployed by IMPLEMENTATION_AUTO.sh)
    if sudo -u "$ORIGINAL_USER" -H bash -c "pm2 describe bmi-backend" &>/dev/null; then
        log_info "BMI backend (bmi-backend) is running"
    fi
    
    # Clean up any existing bmi-app-exporter from both root and ubuntu PM2 instances
    log_info "Cleaning up any existing bmi-app-exporter processes..."
    
    # Try to delete from root's PM2 (in case it was started by mistake)
    pm2 delete bmi-app-exporter 2>/dev/null || true
    
    # Try to delete from ubuntu's PM2
    sudo -u "$ORIGINAL_USER" -H bash -c "pm2 delete bmi-app-exporter" 2>/dev/null || true
    
    sleep 2
    
    # Start the exporter with absolute path (don't use ecosystem.config.js)
    cd "$EXPORTER_DIR"
    EXPORTER_ABS_PATH="$EXPORTER_DIR/exporter.js"
    
    # Use sudo -H to set HOME properly, or use su -l for full login shell
    sudo -u "$ORIGINAL_USER" -H bash <<EOF
export HOME=/home/$ORIGINAL_USER
export USER=$ORIGINAL_USER
cd "$EXPORTER_DIR"
pm2 start "$EXPORTER_ABS_PATH" \
    --name bmi-app-exporter \
    --cwd "$EXPORTER_DIR" \
    --error "$EXPORTER_DIR/logs/err.log" \
    --output "$EXPORTER_DIR/logs/out.log" \
    --time \
    --env production
pm2 save
EOF
    
    sleep 3
    
    # Check if exporter is running
    if sudo -u "$ORIGINAL_USER" -H bash -c "pm2 list | grep -q 'bmi-app-exporter.*online'"; then
        log_success "BMI Application Exporter started successfully"
    else
        log_error "BMI Application Exporter failed to start"
        sudo -u "$ORIGINAL_USER" -H bash -c "pm2 logs bmi-app-exporter --lines 50"
        exit 1
    fi
    
    # Configure PM2 to start on boot if not already configured
    if ! systemctl is-enabled pm2-"$ORIGINAL_USER" &>/dev/null; then
        log_step "Configuring PM2 to start on boot..."
        sudo -u "$ORIGINAL_USER" -H bash -c "pm2 startup systemd -u $ORIGINAL_USER --hp /home/$ORIGINAL_USER" | grep "sudo" | bash
        log_success "PM2 startup configured"
    fi
}

# Step 7: Install Promtail
install_promtail() {
    log_header "Step 7: Installing Promtail"
    
    # Check if already installed and running
    if systemctl is-active --quiet promtail 2>/dev/null; then
        log_info "Promtail is already running. Stopping for update..."
        systemctl stop promtail
    fi
    
    log_step "Downloading Promtail v${PROMTAIL_VERSION}..."
    cd /tmp
    wget -q https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip
    unzip -o -q promtail-linux-amd64.zip
    mv -f promtail-linux-amd64 /usr/local/bin/promtail
    chmod +x /usr/local/bin/promtail
    rm -f promtail-linux-amd64.zip
    
    log_step "Creating Promtail user and directories..."
    useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true
    mkdir -p /etc/promtail
    mkdir -p /var/lib/promtail
    chown promtail:promtail /var/lib/promtail
    
    log_step "Adding Promtail to required groups..."
    usermod -aG adm promtail 2>/dev/null || true
    usermod -aG systemd-journal promtail 2>/dev/null || true
    
    log_step "Creating Promtail configuration..."
    
    cat > /etc/promtail/promtail-config.yml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${MONITORING_SERVER_IP}:3100/loki/api/v1/push

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          server: bmi-app-server
          __path__: /var/log/*.log

  # Nginx access logs
  - job_name: nginx-access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx-access
          server: bmi-app-server
          tier: frontend
          __path__: /var/log/nginx/*access.log

  # Nginx error logs
  - job_name: nginx-error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx-error
          server: bmi-app-server
          tier: frontend
          __path__: /var/log/nginx/*error.log

  # PostgreSQL logs
  - job_name: postgresql
    static_configs:
      - targets:
          - localhost
        labels:
          job: postgresql
          server: bmi-app-server
          tier: database
          __path__: /var/log/postgresql/*.log

  # BMI Backend application logs
  - job_name: bmi-backend
    static_configs:
      - targets:
          - localhost
        labels:
          job: bmi-backend
          server: bmi-app-server
          tier: backend
          __path__: /var/log/bmi-backend.log
EOF
    
    chown promtail:promtail /etc/promtail/promtail-config.yml
    
    log_step "Creating Promtail systemd service..."
    
    cat > /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail Log Shipper
After=network.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    log_step "Starting Promtail..."
    systemctl daemon-reload
    systemctl enable promtail
    systemctl start promtail
    
    sleep 2
    
    if systemctl is-active --quiet promtail; then
        log_success "Promtail started successfully"
    else
        log_error "Promtail failed to start"
        journalctl -u promtail -n 20 --no-pager
        exit 1
    fi
}

# Step 8: Verification
final_verification() {
    log_header "Step 8: Final Verification"
    
    log_step "Checking all exporters..."
    
    declare -a checks=()
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        checks+=("node_exporter:9100" "postgres_exporter:9187" "bmi-app-exporter:9091" "promtail:9080")
    elif [ "$ROLE" = "frontend" ]; then
        checks+=("node_exporter:9100" "nginx_exporter:9113" "promtail:9080")
    elif [ "$ROLE" = "database" ]; then
        checks+=("node_exporter:9100" "promtail:9080")
    fi
    
    all_good=true
    
    for check in "${checks[@]}"; do
        name="${check%%:*}"
        port="${check##*:}"
        
        if curl -s http://localhost:$port/metrics > /dev/null 2>&1 || \
           curl -s http://localhost:$port/ready > /dev/null 2>&1; then
            log_success "$name is responding on port $port"
        else
            log_error "$name is NOT responding on port $port"
            all_good=false
        fi
    done
    
    log_step "Checking service status..."
    
    declare -a services=()
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        services+=("node_exporter" "postgres_exporter" "promtail")
    elif [ "$ROLE" = "frontend" ]; then
        services+=("node_exporter" "nginx_exporter" "promtail")
    elif [ "$ROLE" = "database" ]; then
        services+=("node_exporter" "promtail")
    fi
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_error "$service is NOT running"
            all_good=false
        fi
    done
    
    # Check PM2 processes
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        ORIGINAL_USER=$(get_original_user)
        if sudo -u "$ORIGINAL_USER" pm2 list | grep -q "bmi-app-exporter.*online"; then
            log_success "bmi-app-exporter (PM2) is running"
        else
            log_error "bmi-app-exporter (PM2) is NOT running"
            all_good=false
        fi

        if sudo -u "$ORIGINAL_USER" pm2 list | grep -q "bmi-backend.*online"; then
            log_success "bmi-backend (PM2) is running"
        else
            log_error "bmi-backend (PM2) is NOT running"
            all_good=false
        fi
    fi
    
    if [ "$all_good" = true ]; then
        log_success "All role-specific exporters are running successfully!"
    else
        log_error "Some exporters are not running. Check logs for details."
        exit 1
    fi
}

# Step 9: Display summary
display_summary() {
    log_header "Installation Complete!"
    
    ORIGINAL_USER=$(get_original_user)
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Application Server Monitoring Setup Complete!               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Exporters Installed:${NC}"
    echo -e "  ${YELLOW}BMI Backend:${NC}         http://localhost:3010 (logs: /var/log/bmi-backend.log)"
    echo -e "  ${YELLOW}Node Exporter:${NC}       http://localhost:9100/metrics"
    echo -e "  ${YELLOW}PostgreSQL Exporter:${NC} http://localhost:9187/metrics"
    echo -e "  ${YELLOW}Nginx Exporter:${NC}      http://localhost:9113/metrics"
    echo -e "  ${YELLOW}BMI App Exporter:${NC}    http://localhost:9091/metrics"
    echo -e "  ${YELLOW}Promtail:${NC}            http://localhost:9080/ready"
    echo ""
    echo -e "${CYAN}Service Management:${NC}"
    echo -e "  Backend:       ${YELLOW}sudo systemctl status bmi-backend${NC}"
    echo -e "  Backend logs:  ${YELLOW}sudo tail -f /var/log/bmi-backend.log${NC}"
    echo -e "  Check status:  ${YELLOW}sudo systemctl status <service-name>${NC}"
    echo -e "  View logs:     ${YELLOW}sudo journalctl -u <service-name> -f${NC}"
    echo -e "  Restart:       ${YELLOW}sudo systemctl restart <service-name>${NC}"
    echo ""
    echo -e "${CYAN}PM2 Management (BMI Exporter):${NC}"
    echo -e "  Status:        ${YELLOW}pm2 status${NC}"
    echo -e "  Logs:          ${YELLOW}pm2 logs bmi-app-exporter${NC}"
    echo -e "  Restart:       ${YELLOW}pm2 restart bmi-app-exporter${NC}"
    echo ""
    echo -e "${CYAN}Verification Commands:${NC}"
    echo -e "  ${YELLOW}curl http://localhost:9100/metrics | head -20${NC}"
    echo -e "  ${YELLOW}curl http://localhost:9187/metrics | grep pg_ | head -10${NC}"
    echo -e "  ${YELLOW}curl http://localhost:9113/metrics | grep nginx | head -10${NC}"
    echo -e "  ${YELLOW}curl http://localhost:9091/metrics | grep bmi | head -10${NC}"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  Application Server Private IP: ${YELLOW}${PRIVATE_IP}${NC}"
    echo -e "  Monitoring Server IP:          ${YELLOW}${MONITORING_SERVER_IP}${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "  1. Check Prometheus targets on monitoring server"
    echo -e "     http://MONITORING_SERVER_IP:9090/targets"
    echo -e "  2. All targets should show as UP"
    echo -e "  3. Access Grafana dashboards"
    echo -e "     http://MONITORING_SERVER_IP:3001"
    echo -e "  4. Import the pre-configured dashboards"
    echo -e "  5. Verify metrics are being collected"
    echo ""
    echo -e "${GREEN}Your application is now fully monitored!${NC}"
    echo ""
}

# Main execution
main() {
    display_banner
    check_root
    validate_project_structure
    
    # Run all installation steps
    initial_setup
    
    # Check and install dependencies if missing
    log_header "Checking Required Dependencies"
    
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        check_postgresql
        install_nodejs
        install_pm2
    fi
    
    if [ "$ROLE" = "frontend" ] || [ -z "$ROLE" ]; then
        check_nginx
    fi
    
    configure_firewall
    install_node_exporter
    
    if [ "$ROLE" = "backend" ] || [ -z "$ROLE" ]; then
        install_postgres_exporter
        install_bmi_exporter
    fi
    
    if [ "$ROLE" = "frontend" ] || [ -z "$ROLE" ]; then
        install_nginx_exporter
    fi
    
    install_promtail
    final_verification
    display_summary
}

# Run main function
main

exit 0
