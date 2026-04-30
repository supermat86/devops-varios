variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "backend_sg_id" {
  type        = string
  description = "ID del SG del servicio backend ECS"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "kms_key_id" {
  type        = string
  description = "ARN de la CMK para RDS"
}
