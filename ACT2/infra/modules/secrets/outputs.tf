output "django_secret_key_arn" {
  value = aws_secretsmanager_secret.django_key.arn
}

output "db_credentials_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

# Se usa sensitive para evitar que aparezca en el plan

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "db_username" {
  value = var.db_username
}
