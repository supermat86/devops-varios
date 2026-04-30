output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_gateway_ip" {
  value = module.vpc.nat_gateway_ip
}

output "ecr_backend_repository_url" {
  value = module.ecr.backend_repository_url
}

output "ecr_frontend_repository_url" {
  value = module.ecr.frontend_repository_url
}

output "rds_address" {
  value = module.rds.db_address
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.ecs_cluster_name
}

output "backend_service_name" {
  value = module.ecs.backend_service_name
}

output "frontend_service_name" {
  value = module.ecs.frontend_service_name
}
