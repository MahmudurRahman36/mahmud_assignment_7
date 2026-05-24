variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "mahmud-health"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "key_name" {
  type    = string
  default = "ostad_batch_11_mahmud"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into Bastion Host"
  type        = string
  default     = "0.0.0.0/0"
}
