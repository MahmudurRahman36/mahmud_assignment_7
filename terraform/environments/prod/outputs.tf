output "app_url" { value = module.alb.app_url }
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "bastion_public_ip" { value = module.bastion.public_ip }
output "frontend_private_ip" { value = module.frontend.private_ip }
output "backend_private_ip" { value = module.backend.private_ip }
output "db_private_ip" { value = module.db.private_ip }

output "ssh_bastion" {
  value = "ssh -i ostad_batch_11_mahmud.pem ubuntu@${module.bastion.public_ip}"
}
output "ssh_backend" {
  value = "ssh -i ostad_batch_11_mahmud.pem -J ubuntu@${module.bastion.public_ip} ubuntu@${module.backend.private_ip}"
}
output "ssh_frontend" {
  value = "ssh -i ostad_batch_11_mahmud.pem -J ubuntu@${module.bastion.public_ip} ubuntu@${module.frontend.private_ip}"
}
output "ssh_db" {
  value = "ssh -i ostad_batch_11_mahmud.pem -J ubuntu@${module.bastion.public_ip} ubuntu@${module.db.private_ip}"
}
output "verify" {
  value = "curl http://${module.alb.alb_dns_name}/health"
}
