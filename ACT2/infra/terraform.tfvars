project    = "devops-interview"
aws_region = "us-east-1"

# Configuracion de CIDRs de VPC y Subnets
vpc_cidr = "10.0.0.0/22"

public_subnet_cidrs = [
  "10.0.0.0/26",
  "10.0.0.64/26",
]

private_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
]

availability_zones = [
  "us-east-1a",
  "us-east-1b",
]

# Imagenes a retener en ECR
image_retention_count = 3

# Base de datos
db_name           = "core"
db_username       = "adminuser"
db_instance_class = "db.t3.micro"

# Tamaño de las tasks
backend_task_cpu    = 512
backend_task_memory = 1024
frontend_task_cpu   = 256
frontend_task_memory = 512

# Cantidad de tasks por servicio
desired_count = 1
