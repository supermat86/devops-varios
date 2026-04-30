variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "backend_image_uri" {
  type        = string
  description = "URI de la imagen del backend en ECR"
}

variable "frontend_image_uri" {
  type        = string
  description = "URI de la imagen del frontend en ECR"
}

variable "backend_task_cpu" {
  type    = number
  default = 512
}

variable "backend_task_memory" {
  type    = number
  default = 1024
}

variable "frontend_task_cpu" {
  type    = number
  default = 256
}

variable "frontend_task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "db_address" {
  type        = string
  description = "Hostname del RDS PostgreSQL"
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "django_secret_key_arn" {
  type        = string
  description = "ARN del secret de Secrets Manager para Django"
}

variable "db_credentials_arn" {
  type        = string
  description = "ARN del secret de Secrets Manager con credenciales de la base de datos
}

variable "alb_sg_id" {
  type        = string
  description = "ID del SG del ALB"
}

variable "frontend_sg_id" {
  type        = string
  description = "ID del SG del servicio frontend ECS"
}

variable "backend_sg_id" {
  type        = string
  description = "ID del SG del servicio backend ECS"
}
