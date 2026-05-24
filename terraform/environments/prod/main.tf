# ==============================================================================
# Environment: prod
# Composition Orchestrator using Modular, Training-Compatible Configurations
# Uses local backend by default for safe local development.
# Adjusted for restricted training accounts by deploying an EC2-based private DB.
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "mahmud"
    }
  }
}

# ==============================================================================
# NETWORKING
# ==============================================================================
module "vpc" {
  source       = "../../modules/vpc"
  project_name = var.project_name
  environment  = var.environment
}

# ==============================================================================
# SECURITY GROUPS
# ==============================================================================
module "security_groups" {
  source                 = "../../modules/security-group"
  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  frontend_public_access = false # Production: ALB proxies all frontend traffic
}

# ==============================================================================
# DATABASE PASSWORD
# ==============================================================================
resource "random_password" "db_master" {
  length           = 16
  special          = true
  override_special = "!-_=+" # URL-safe special characters only
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# ==============================================================================
# DATABASE (EC2-based Private PostgreSQL Server)
# Replaces RDS to bypass training account CreateDBSubnetGroup permission restrictions
# ==============================================================================
module "db" {
  source             = "../../modules/ec2"
  name               = "${var.project_name}-${var.environment}-db"
  role               = "database"
  instance_type      = "t2.micro"
  subnet_id          = module.vpc.private_app_subnet_ids[0]
  security_group_ids = [module.security_groups.rds_sg_id]
  key_name           = var.key_name

  # Automate PostgreSQL installation and secure configuration on boot
  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1
    
    echo "=========================================="
    echo " Bootstrapping Private PostgreSQL Database"
    echo "=========================================="
    
    # Install PostgreSQL 14
    apt-get update -y
    apt-get install -y postgresql-14 postgresql-contrib-14
    
    # Start and enable PostgreSQL service
    systemctl start postgresql
    systemctl enable postgresql
    
    # Create DB user, database and grant privileges
    sudo -u postgres psql -c "CREATE USER bmi_user WITH PASSWORD '${random_password.db_master.result}';"
    sudo -u postgres psql -c "CREATE DATABASE bmidb OWNER bmi_user;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bmidb TO bmi_user;"
    
    # Find configuration files
    PG_CONF=$(sudo -u postgres psql -tAc "SHOW config_file")
    PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file")
    
    # Configure PostgreSQL to listen on all interfaces (so backend can connect)
    echo "listen_addresses = '*'" >> "$PG_CONF"
    
    # Configure pg_hba.conf to allow password authentication from the VPC CIDR
    echo "host bmidb bmi_user 10.0.0.0/16 md5" >> "$PG_HBA"
    
    # Restart to apply changes
    systemctl restart postgresql
    
    echo "Database setup completed successfully!"
  EOF
}

# ==============================================================================
# COMPUTE TIER (Bastion, Backend, Frontend)
# ==============================================================================
module "bastion" {
  source             = "../../modules/ec2"
  name               = "${var.project_name}-${var.environment}-bastion"
  role               = "bastion"
  instance_type      = "t2.micro"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.bastion_sg_id]
  key_name           = var.key_name
}

module "backend" {
  source             = "../../modules/ec2"
  name               = "${var.project_name}-${var.environment}-backend"
  role               = "backend"
  instance_type      = "t2.micro"
  subnet_id          = module.vpc.private_app_subnet_ids[0]
  security_group_ids = [module.security_groups.backend_sg_id]
  key_name           = var.key_name

  # Injected database credentials directly into backend environment via template
  user_data = templatefile("${path.module}/../../scripts/backend.sh", {
    database_url = "postgresql://bmi_user:${random_password.db_master.result}@${module.db.private_ip}:5432/bmidb"
    frontend_url = "http://${module.alb.alb_dns_name}"
    environment  = var.environment
    aws_region   = var.aws_region
  })

  depends_on = [module.db]
}

module "frontend" {
  source             = "../../modules/ec2"
  name               = "${var.project_name}-${var.environment}-frontend"
  role               = "frontend"
  instance_type      = "t2.micro"
  subnet_id          = module.vpc.private_app_subnet_ids[1]
  security_group_ids = [module.security_groups.frontend_sg_id]
  key_name           = var.key_name

  user_data = templatefile("${path.module}/../../scripts/frontend.sh", {
    backend_private_ip = module.backend.private_ip
    phase              = "production" # Uses Phase 2: routing managed by ALB
  })

  depends_on = [module.backend]
}

# ==============================================================================
# LOAD BALANCER (ALB)
# ==============================================================================
module "alb" {
  source                = "../../modules/alb"
  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_sg_id             = module.security_groups.alb_sg_id
  frontend_instance_ids = [module.frontend.instance_id]
  backend_instance_ids  = [module.backend.instance_id]
}
