terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Genera una clave para Django

resource "random_password" "django_key" {
  length  = 50
  special = true
}

resource "aws_secretsmanager_secret" "django_key" {
  name                    = "${var.project}/django-secret-key"
  recovery_window_in_days = 0

  tags = { Name = "${var.project}-django-secret-key" }
}

resource "aws_secretsmanager_secret_version" "django_key" {
  secret_id     = aws_secretsmanager_secret.django_key.id
  secret_string = random_password.django_key.result
}

# Genera las credenciales para la base de datos

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project}/db-credentials"
  recovery_window_in_days = 0

  tags = { Name = "${var.project}-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}
