# Automated Setup: BMI App + Monitoring (Two EC2 Servers)

This guide sets up:
- BMI-ubuntu: BMI application server
- Monitoring-ubuntu: monitoring stack server

Monitoring-ubuntu will monitor BMI-ubuntu through private IP and will also monitor itself (CPU, memory, disk, network).

---

## 1) Architecture

- BMI-ubuntu (App Server)
  - Nginx :80
  - BMI backend API :3010
  - PostgreSQL :5432
  - Node Exporter :9100
  - PostgreSQL Exporter :9187
  - Nginx Exporter :9113
  - BMI Custom Exporter :9091
  - Promtail :9080

- Monitoring-ubuntu (Monitoring Server)
  - Prometheus :9090
  - Grafana :3001
  - Loki :3100
  - AlertManager :9093
  - Node Exporter :9100

---

## 2) Prerequisites

- Both EC2 instances are running and can reach each other using private IP.
- Repository is available and cloneable from both servers.
- BMI app server deployment script is available:
  - IMPLEMENTATION_AUTO.sh
- Monitoring scripts are available:
  - monitoring/3-tier-app/scripts/setup-monitoring-server.sh
  - monitoring/3-tier-app/scripts/setup-application-server.sh

Collect these values first:
- BMI_PUBLIC_IP
- BMI_PRIVATE_IP
- MONITORING_PUBLIC_IP
- MONITORING_PRIVATE_IP
- SSH key path (for example: ostad-batch-08.pem)

---

## 3) Security Group Rules (Best Practice)

Use private IP allow-listing between servers.

### BMI-ubuntu inbound
- 22/tcp from your admin IP
- 80/tcp from users (or restricted CIDR)
- 9100/tcp from MONITORING_PRIVATE_IP
- 9187/tcp from MONITORING_PRIVATE_IP
- 9113/tcp from MONITORING_PRIVATE_IP
- 9091/tcp from MONITORING_PRIVATE_IP
- 9080/tcp from MONITORING_PRIVATE_IP (optional; mainly local, keep restricted)

### Monitoring-ubuntu inbound
- 22/tcp from your admin IP
- 3001/tcp from your admin IP (Grafana)
- 9090/tcp from your admin IP (Prometheus UI, optional)
- 9093/tcp from your admin IP (AlertManager UI, optional)
- 3100/tcp from BMI_PRIVATE_IP (Loki ingest)
- 9100/tcp from localhost/same host only is enough

Notes:
- Do not open exporter ports to 0.0.0.0/0.
- Keep Grafana and Prometheus UI limited to trusted IPs.

---

## 4) Step-by-Step Deployment Order

## Step A: Deploy BMI App on BMI-ubuntu

SSH to BMI-ubuntu and run:

```bash
ssh -i ostad-batch-08.pem ubuntu@BMI_PUBLIC_IP

git clone <your-repo-url> /home/ubuntu/bmi-health-tracker
cd /home/ubuntu/bmi-health-tracker
chmod +x IMPLEMENTATION_AUTO.sh
./IMPLEMENTATION_AUTO.sh
```

What this does:
- Installs prerequisites
- Sets up PostgreSQL database and user
- Applies migrations
- Builds frontend and configures Nginx
- Starts backend service on port 3010

Quick verification on BMI-ubuntu:

```bash
curl http://localhost/health
# Expected: {"status":"ok", ...}
```

## Step B: Install Monitoring Stack on Monitoring-ubuntu

SSH to Monitoring-ubuntu and run:

```bash
ssh -i ostad-batch-08.pem ubuntu@MONITORING_PUBLIC_IP

git clone <your-repo-url> /home/ubuntu/bmi-health-tracker
cd /home/ubuntu/bmi-health-tracker
chmod +x monitoring/3-tier-app/scripts/setup-monitoring-server.sh
sudo ./monitoring/3-tier-app/scripts/setup-monitoring-server.sh
```

When prompted:
- Enter BMI_PRIVATE_IP as the Application Server IP

What this installs:
- Prometheus + scrape config for BMI-ubuntu exporters
- Grafana on port 3001 with auto-provisioned datasources/dashboards
- Loki
- AlertManager
- Node Exporter for Monitoring-ubuntu itself

## Step C: Install Exporters + Log Shipping on BMI-ubuntu

Back on BMI-ubuntu, run:

```bash
cd /home/ubuntu/bmi-health-tracker
chmod +x monitoring/3-tier-app/scripts/setup-application-server.sh
sudo ./monitoring/3-tier-app/scripts/setup-application-server.sh
```

When prompted:
- Enter MONITORING_PRIVATE_IP

What this installs/configures on BMI-ubuntu:
- Node Exporter (system metrics)
- PostgreSQL Exporter (DB metrics)
- Nginx Exporter (web metrics)
- BMI Custom Exporter (business metrics)
- Promtail (ships logs to Loki on Monitoring-ubuntu)

---

## 5) Verification Checklist

## Prometheus Targets

Open:
- http://MONITORING_PUBLIC_IP:9090/targets

All should be UP:
- prometheus (localhost:9090)
- node_exporter_monitoring (localhost:9100)
- node_exporter (BMI_PRIVATE_IP:9100)
- postgresql (BMI_PRIVATE_IP:9187)
- nginx (BMI_PRIVATE_IP:9113)
- bmi-backend (BMI_PRIVATE_IP:9091)

## Grafana

Open:
- http://MONITORING_PUBLIC_IP:3001
- Default login: admin / admin (change password immediately)

Expected:
- Prometheus datasource present
- Loki datasource present
- Dashboards loaded (application + logs)

## Loki Logs

In Grafana Explore (Loki), test queries such as:
- {job="bmi-backend"}
- {job="nginx-access"}
- {job="postgresql"}

You should see logs from BMI-ubuntu.

---

## 6) Operational Best Practices

- Use private IP communication between servers.
- Restrict security groups to least privilege.
- Keep both servers in the same VPC and route table.
- Enable automated backups/snapshots for PostgreSQL data.
- Rotate credentials and do not store secrets in plain text repos.
- Configure AlertManager receivers (email/Slack/PagerDuty) before production.
- Regularly patch OS packages and restart services during maintenance windows.

---

## 7) Re-run / Recovery

The two monitoring scripts are idempotent and can be re-run safely:

```bash
sudo ./monitoring/3-tier-app/scripts/setup-monitoring-server.sh
sudo ./monitoring/3-tier-app/scripts/setup-application-server.sh
```

Use this after updates, partial failures, or host replacement.

---

## 8) Common Troubleshooting

- Prometheus target DOWN:
  - Check service on BMI-ubuntu: systemctl status node_exporter postgres_exporter nginx_exporter
  - Check SG inbound rules for the target port
  - Check private IP used in Prometheus config

- No logs in Loki:
  - Check promtail service on BMI-ubuntu: systemctl status promtail
  - Confirm MONITORING_PRIVATE_IP and port 3100 reachability

- Grafana empty panels:
  - Verify datasource health in Grafana
  - Verify Prometheus targets are UP

- Backend health failing:
  - Check BMI backend service and logs on BMI-ubuntu
  - Validate database connectivity and .env values

---

Deployment order summary:
1. BMI-ubuntu: run IMPLEMENTATION_AUTO.sh
2. Monitoring-ubuntu: run setup-monitoring-server.sh (with BMI private IP)
3. BMI-ubuntu: run setup-application-server.sh (with monitoring private IP)
4. Verify in Prometheus and Grafana

---

## 🧑‍💻 Author
*Md. Sarowar Alam*  
Lead DevOps Engineer, WPP Production - Dhaka  
📧 Email: sarowar@hotmail.com  
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
