terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "ecr" {
  source = "./modules/ecr"

  project               = var.project
  image_retention_count = var.image_retention_count
}

# Genera y almacena en Secrets Manager las credenciales

module "secrets" {
  source = "./modules/secrets"

  project     = var.project
  db_username = var.db_username
}

# KMS — CMK para encriptación del storage RDS

resource "aws_kms_key" "rds" {
  description             = "CMK para encriptación de la RDS de ${var.project}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.project}-kms-rds" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# Security Groups - Se definen aca para evitar dependencia circular

resource "aws_security_group" "alb" {
  name   = "${var.project}-sg-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-alb" }
}

resource "aws_security_group" "frontend" {
  name   = "${var.project}-sg-frontend"
  vpc_id = module.vpc.vpc_id

  ingress {
    description     = "Trafico desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-frontend" }
}

resource "aws_security_group" "backend" {
  name   = "${var.project}-sg-backend"
  vpc_id = module.vpc.vpc_id

  ingress {
    description     = "Trafico desde el frontend"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-backend" }
}

# RDS usa la contraseña generada por el modulo de secret manager

module "rds" {
  source = "./modules/rds"

  project            = var.project
  vpc_id             = module.vpc.vpc_id
  backend_sg_id      = aws_security_group.backend.id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_name            = var.db_name
  db_username        = module.secrets.db_username
  db_password        = module.secrets.db_password
  db_instance_class  = var.db_instance_class
  kms_key_id         = aws_kms_key.rds.arn
}

module "ecs" {
  source = "./modules/ecs"

  project            = var.project
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # El pipeline empuja las imagenes y actualiza la task definition en el primer run
  backend_image_uri  = "${module.ecr.backend_repository_url}:latest"
  frontend_image_uri = "${module.ecr.frontend_repository_url}:latest"

  backend_task_cpu     = var.backend_task_cpu
  backend_task_memory  = var.backend_task_memory
  frontend_task_cpu    = var.frontend_task_cpu
  frontend_task_memory = var.frontend_task_memory
  desired_count        = var.desired_count

  db_address = module.rds.db_address
  db_port    = module.rds.db_port
  db_name    = var.db_name

  django_secret_key_arn = module.secrets.django_secret_key_arn
  db_credentials_arn    = module.secrets.db_credentials_arn

  alb_sg_id      = aws_security_group.alb.id
  frontend_sg_id = aws_security_group.frontend.id
  backend_sg_id  = aws_security_group.backend.id
}
