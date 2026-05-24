# 🚀 Master Project Documentation

### Course Reference: Ostad DevOps Batch 11 — Assignment Module 7
**Engineer**: Mahmudur Rahman  
**Key Pair Reference**: `ostad_batch_11_mahmud`

---

## 📂 1. Directory Structure & Application Anatomy

The repository consolidates both the infrastructure provisioning configurations (IaC) and the application codebase. This ensures the environment and the software evolve together dynamically.

```
mahmud_assignment_7/
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions CI/CD Pipeline (Build, Test, Deploy, Verify)
├── src/
│   ├── backend/
│   │   ├── migrations/         # PostgreSQL DB Schema migration scripts (.sql)
│   │   ├── src/
│   │   │   ├── calculations.js # Core business logic (BMI & Health calculations)
│   │   │   ├── db.js           # Database client initializer & connection pool
│   │   │   ├── routes.js       # Express REST API endpoint definitions
│   │   │   └── server.js       # Main server bootstrap, CORS, and Express app config
│   │   ├── .env.example        # Reference environment configuration
│   │   ├── package.json        # Node dependencies, scripts, and PM2 commands
│   │   └── ecosystem.config.js # Process Manager (PM2) clustering configuration
│   └── frontend/
│       ├── src/
│       │   ├── components/     # Reusable React UI elements (History logs, Input forms)
│       │   ├── App.jsx         # Main dashboard orchestration & UI state handlers
│       │   ├── api.js          # Centralized Axios client with path base '/api'
│       │   ├── index.css       # Design System CSS (Modern dark glassmorphism styling)
│       │   └── main.jsx        # React DOM mounting orchestrator
│       ├── index.html          # Shell HTML wrapper
│       ├── package.json        # Frontend NPM dependencies & scripts
│       └── vite.config.js      # Vite config with dev-proxy for local development
├── terraform/
│   ├── modules/
│   │   ├── vpc/                # Multi-AZ VPC network module with public/private subnets
│   │   ├── security-group/     # Firewalls (ALB, Bastion, Frontend, Backend, RDS)
│   │   ├── ec2/                # Generic EC2 compute instance builder (User Data supported)
│   │   └── alb/                # Application Load Balancer, listeners, and target groups
│   └── environments/
│       └── prod/
│           ├── main.tf         # Master orchestrator combining VPC, ALB, and EC2 modules
│           ├── outputs.tf      # Deployment results (DNS names, Host IPs, SSH connections)
│           ├── variables.tf    # Environmental variables configuration
│           └── terraform.tfvars# Parameter definitions
└── monitoring/                 # Setup scripts and configs for Prometheus, Grafana, Loki
```

---

## 📐 2. System Architecture Topology

The physical infrastructure uses isolated network layers to block direct internet traffic to our database and compute servers, keeping them completely safe inside private subnets:

```mermaid
graph TD
    %% External Ingress
    User([🌐 End Users]) -->|HTTP Port 80| ALB[⚖️ Application Load Balancer - Public Subnets]
    Developer([💻 DevOps / Developers]) -->|SSH Port 22| Bastion[🛡️ Bastion Host / Monitoring Node]
    
    subgraph VPC ["AWS Custom VPC (10.0.0.0/16)"]
        
        subgraph Public_Subnets ["Public Subnets (10.0.1.0/24 & 10.0.2.0/24)"]
            ALB
            Bastion
            NAT[🔌 NAT Gateway - Outbound updates]
        end
        
        subgraph Private_App_Subnets ["Private App Subnets (10.0.3.0/24 & 10.0.4.0/24)"]
            Frontend["🖥️ Frontend EC2 (Nginx) - 10.0.4.241"]
            Backend["⚙️ Backend EC2 (PM2 Node) - 10.0.3.14"]
        end

        subgraph Private_DB_Subnet ["Private Subnet (10.0.3.0/24)"]
            DB["🗄️ EC2 Private Database (PostgreSQL) - 10.0.3.116"]
        end
        
    end

    %% Routing
    ALB -->|/api/* or /health| Backend
    ALB -->|Default /*| Frontend
    
    %% NAT Outbound
    Frontend -->|Outbound traffic| NAT
    Backend -->|Outbound traffic| NAT
    
    %% DB connection
    Backend -->|TCP Port 5432| DB
    
    %% SSH management
    Bastion -->|SSH Port 22 - ProxyJump| Frontend
    Bastion -->|SSH Port 22 - ProxyJump| Backend
    
    %% Observability Scrape Loops
    subgraph Telemetry_Stack ["Observability Suite (Bastion Host)"]
        Prom[🔥 Prometheus - Port 9090]
        Grafana[📊 Grafana - Port 3001]
        Loki[🪵 Grafana Loki - Port 3100]
    end

    Prom -.->|Scrapes Node Stats :9100| Frontend
    Prom -.->|Scrapes App & Node Stats :9100, :9091| Backend
    Prom -.->|Scrapes DB metrics remotely :9187| Backend
    Backend -.->|Logs shipped via Promtail| Loki
    Frontend -.->|Logs shipped via Promtail| Loki
    
    Grafana -->|Query Metrics| Prom
    Grafana -->|Query Logs| Loki
```

---

## 💻 3. Running the Application Locally (Development Environment)

Follow these steps to run the complete stack locally on your computer for rapid development and testing.

### Prerequisites
- **Node.js**: `v18.x` or later installed.
- **PostgreSQL**: Local PostgreSQL running or via Docker.
- **Git**: Installed.

### Step 1: Set Up the Database
Create a database user and a database named `bmidb` locally:
```sql
CREATE USER bmi_user WITH PASSWORD 'mysecurepassword';
CREATE DATABASE bmidb OWNER bmi_user;
GRANT ALL PRIVILEGES ON DATABASE bmidb TO bmi_user;
```

### Step 2: Run the Backend API
1. Navigate to the backend folder:
   ```bash
   cd src/backend
   ```
2. Install npm dependencies:
   ```bash
   npm install
   ```
3. Create a local `.env` configuration:
   ```bash
   # Create a file named .env and paste the following:
   PORT=3000
   NODE_ENV=development
   DATABASE_URL=postgresql://bmi_user:mysecurepassword@localhost:5432/bmidb
   FRONTEND_URL=http://localhost:5173
   ```
4. Run the database migrations (optional, Express automatically bootstraps tables if absent):
   Apply any migration scripts found in `src/backend/migrations/*.sql` to your local DB.
5. Start the server in development mode:
   ```bash
   npm run dev
   ```
   You should see: `🚀 Server running on port 3000` & `✅ Database connected successfully`.

### Step 3: Run the Frontend UI
1. Open a new terminal and navigate to the frontend folder:
   ```bash
   cd src/frontend
   ```
2. Install npm packages:
   ```bash
   npm install
   ```
3. Start the Vite React development server:
   ```bash
   npm run dev
   ```
4. Open your browser and navigate to `http://localhost:5173`. 
   
> [!NOTE]
> During local development, the Vite server uses the proxy configuration in `vite.config.js` to automatically forward all requests made to `/api` directly to your local Express server running on port `3000`.

---

## 🌐 4. Running the Application in AWS (Production IaC + CI/CD)

Deploying a fully secure, scalable, and observed multi-server environment in AWS using the automated configurations.

### Phase A: Local Infrastructure Provisioning (Terraform)
1. Navigate to the production environment folder:
   ```bash
   cd terraform/environments/prod
   ```
2. Initialize, validate, and deploy:
   ```bash
   terraform init
   terraform validate
   terraform apply -auto-approve
   ```
3. Keep the CLI output details handy. Note down the public/private IPs and the generated `alb_dns_name`.

### Phase B: Configure GitHub Actions Secrets
Go to your GitHub repository under **Settings > Secrets and Variables > Actions > Secrets** and save these 7 repository secrets:

| Secret Name | Value |
|-------------|-------|
| `EC2_SSH_KEY` | Paste the *entire* raw text content of your `ostad_batch_11_mahmud.pem` private key. |
| `EC2_BASTION_HOST` | The public IP of the Bastion host (e.g. `13.207.55.124`). |
| `EC2_FRONTEND_HOST` | The private IP of the Frontend instance (e.g. `10.0.4.241`). |
| `EC2_BACKEND_HOST` | The private IP of the Backend instance (e.g. `10.0.3.14`). |
| `DB_PRIVATE_IP` | The private IP of the PostgreSQL instance (e.g. `10.0.3.116`). |
| `DB_PASSWORD` | The master database password (generated randomly by Terraform, see your tfstate or custom). |
| `ALB_DNS_NAME` | The exact ALB DNS name without any prefixes (e.g. `mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com`). |

### Phase C: Triggering CI/CD Pipelines
Push the code to your repository on the `main` branch:
```bash
git add .
git commit -m "feat: infrastructure deployed and secrets verified"
git push origin main
```
The automated runner will execute `.github/workflows/deploy.yml` completely. It:
1. Validates code integrity and sets up the secure SSH agent proxy.
2. Clones the code to the Frontend and Backend private EC2 instances via Bastion ProxyJump.
3. Automatically runs schema migrations and launches/restarts backend processes under PM2.
4. Builds Vite React static bundles and deploys them to Nginx.
5. Installs monitoring stacks (Prometheus, Grafana, Loki, Exporters) automatically.
6. Verifies system readiness via the Load Balancer health checks.

---

## 🧪 5. Verified Active URLs & Endpoints

You can access the live resources globally using the active endpoints listed below:

- **Application Web Portal (ALB)**: [http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com](http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com)
- **Application Health check (ALB)**: [http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com/health](http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com/health)
- **Grafana Metrics Dashboard**: [http://13.207.55.124:3001](http://13.207.55.124:3001) *(Login: `admin` / `admin`)*
- **Prometheus Core Targets**: [http://13.207.55.124:9090/targets](http://13.207.55.124:9090/targets)

---

## 🛡️ 6. Proof of Solution Working (Evidence Catalog)

Below is the verified evidence demonstrating that the deployment, application, database connectivity, and telemetry metrics are fully operational.

### A. API Health Check Verification
To verify backend connectivity from any local terminal, run the following `curl` command:
```bash
curl -i http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com/health
```
**Expected Response**:
```http
HTTP/1.1 200 OK
Connection: keep-alive
Content-Type: application/json; charset=utf-8
Access-Control-Allow-Origin: http://mahmud-health-prod-alb-94897266.ap-south-1.elb.amazonaws.com

{"status":"ok","environment":"production"}
```

### B. Database Schema & Measurement Persistence Proof
To verify that records persist securely in the private PostgreSQL database, connect to the database from the Backend server and run this SQL query:
```bash
# Connect to PostgreSQL from Backend instance
psql -h 10.0.3.116 -U bmi_user -d bmidb

# Check measurements table
SELECT id, weight_kg, height_cm, bmi, measurement_date FROM measurements ORDER BY measurement_date DESC LIMIT 3;
```
**Expected Output**:
```
 id | weight_kg | height_cm |  bmi  |      measurement_date      
----+-----------+-----------+-------+----------------------------
  1 |     72.00 |    175.00 | 23.51 | 2026-05-24 10:45:12.346392
```

### C. Visual Evidence

````carousel
![Successful Terraform Execution](Screenshot/Successful_Teraform_Execution.png)
<!-- slide -->
![GitHub Actions Run](Screenshot/Successfull_Github_Action_Run.png)
<!-- slide -->
![Web Application UI](Screenshot/Working_Web_Project.png)
<!-- slide -->
![Prometheus Targets Scrapers](Screenshot/Grafana%20and%20Prometheus/Prometheus_Targets.png)
<!-- slide -->
![Grafana Live Telemetry](Screenshot/Grafana%20and%20Prometheus/Grafana%20Dashboard.png)
````

1. **Successful Terraform Provisioning**: The Infrastructure-as-Code modules initialized, validated, and deployed the 3-tier AWS infrastructure automatically with zero resource conflicts or errors.
2. **Successful CI/CD Pipeline**: GitHub Actions executes every task in under 2 minutes, completing database migrations, server deployments, and load-balancer status verifications with 0 errors.
3. **Dynamic UI App**: The React application runs via the Application Load Balancer endpoint, calculating indices and storing health history records instantly in PostgreSQL.
4. **Operational Prometheus Targets**: All 9 scrape loops (including Node, Nginx, PostgreSQL, and custom app exporters) report as **UP** on port `9090`.
5. **Grafana Dashboards**: Real-time graphs visualize server CPU, memory, active Nginx routing connections, and log streams securely processed via Promtail.

---

## 🧹 7. Project Clean Up (Destruction)

To avoid any unwanted charges on your AWS account after evaluation is completed, run this command to safely destroy all resources:
```bash
cd terraform/environments/prod
terraform destroy -auto-approve
```
*(All provisioned VPC, Subnets, NAT Gateways, EC2 Servers, Target groups, and Load Balancers will be terminated cleanly)*
