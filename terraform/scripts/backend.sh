#!/bin/bash
# ==============================================================================
# backend.sh — Backend EC2 User Data
# Installs Node.js 18 + PM2, clones the app, writes DATABASE_URL directly,
# runs migrations, and starts the backend with PM2.
#
# Template variables injected by Terraform templatefile():
#   ${database_url}              — Direct Database Connection URL
#   ${frontend_url}              — CORS allowed origin
#   ${environment}               — dev / staging / prod
#   ${aws_region}                — ap-south-1
# ==============================================================================
set -e
exec > /var/log/user-data.log 2>&1

echo "============================="
echo " BMI Backend — User Data"
echo "============================="

DATABASE_URL="${database_url}"
FRONTEND_URL="${frontend_url}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"

# ------------------------------------------------------------------------------
# System update + dependencies
# ------------------------------------------------------------------------------
apt-get update -y
apt-get install -y curl git unzip software-properties-common

# Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# PM2 — process manager
npm install -g pm2

# PostgreSQL client — for running migrations
apt-get install -y postgresql-client-14 || apt-get install -y postgresql-client

# ------------------------------------------------------------------------------
# Clone repository (Fallback bootstrap)
# ------------------------------------------------------------------------------
APP_DIR="/home/ubuntu/bmi-health-tracker"
# Try cloning the baseline code; the actual CI/CD workflow will overwrite this with the user's repo.
git clone https://github.com/MahmudurRahman36/mahmud_assignment_7.git "$APP_DIR" || true
chown -R ubuntu:ubuntu "$APP_DIR" || true

# ------------------------------------------------------------------------------
# Install backend dependencies
# ------------------------------------------------------------------------------
cd "$APP_DIR/src/backend" || exit 1
npm install --production

# ------------------------------------------------------------------------------
# Write .env (DATABASE_URL injected directly via Terraform)
# ------------------------------------------------------------------------------
cat > "$APP_DIR/src/backend/.env" <<EOF
NODE_ENV=$ENVIRONMENT
PORT=3000
DATABASE_URL=$DATABASE_URL
FRONTEND_URL=$FRONTEND_URL
EOF
chmod 600 "$APP_DIR/src/backend/.env"
chown ubuntu:ubuntu "$APP_DIR/src/backend/.env"

# ------------------------------------------------------------------------------
# Run database migrations (idempotent — safe to re-run)
# ------------------------------------------------------------------------------
echo "Running database migrations..."
for sql_file in $(ls "$APP_DIR/src/backend/migrations/"*.sql 2>/dev/null | sort); do
  echo "  Applying: $(basename $sql_file)"
  psql "$DATABASE_URL" -f "$sql_file" || echo "  Warning: migration may have already run"
done

# ------------------------------------------------------------------------------
# Create log directory and start PM2
# ------------------------------------------------------------------------------
mkdir -p "$APP_DIR/src/backend/logs"
chown -R ubuntu:ubuntu "$APP_DIR/src/backend/logs"

# Start PM2 as ubuntu user
export PM2_HOME=/home/ubuntu/.pm2
sudo -u ubuntu bash -c "export PM2_HOME=/home/ubuntu/.pm2; cd $APP_DIR/src/backend && pm2 start ecosystem.config.js --env production" || \
sudo -u ubuntu bash -c "export PM2_HOME=/home/ubuntu/.pm2; cd $APP_DIR/src/backend && pm2 start src/server.js --name bmi-backend"
sudo -u ubuntu bash -c "export PM2_HOME=/home/ubuntu/.pm2; pm2 save"

# Configure PM2 to start on boot
sudo -u ubuntu bash -c "export PM2_HOME=/home/ubuntu/.pm2; pm2 startup systemd -u ubuntu --hp /home/ubuntu" | grep "sudo env" | bash || true
systemctl enable pm2-ubuntu 2>/dev/null || true

echo ""
echo "====================================="
echo " Backend started on port 3000"
echo " Environment: $ENVIRONMENT"
echo " CORS origin: $FRONTEND_URL"
echo "====================================="
