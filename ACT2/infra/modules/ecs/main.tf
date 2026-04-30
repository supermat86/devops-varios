data "aws_region" "current" {}
# ALB

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${var.project}-tg-frontend"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/index.html"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${var.project}-tg-frontend" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ECS Cluster

# Namespace de Cloud Map para ECS Service Connect (res. de nombres internos)

resource "aws_service_discovery_http_namespace" "main" {
  name = "${var.project}.local"

  tags = { Name = "${var.project}.local" }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  tags = { Name = "${var.project}-cluster" }
}

# IAM Execution Role
# Rol que usa ECS: descarga de ECR, escribir logs en CloudWatch y leer Secrets Manager

resource "aws_iam_role" "task_execution" {
  name = "${var.project}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Politica de minimo privilegio para secrets especificos

resource "aws_iam_role_policy" "secrets_access" {
  name = "${var.project}-secrets-access"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.django_secret_key_arn, var.db_credentials_arn]
    }]
  })
}

# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project}-backend"
  retention_in_days = 30

  tags = { Name = "${var.project}-backend-logs" }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.project}-frontend"
  retention_in_days = 30

  tags = { Name = "${var.project}-frontend-logs" }
}

# Task Definitions

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_task_cpu
  memory                   = var.backend_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.backend_image_uri
    essential = true

    portMappings = [{
      name          = "backend"
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "DATABASE",             value = "postgres" },
      { name = "SQL_HOST",             value = var.db_address },
      { name = "SQL_PORT",             value = tostring(var.db_port) },
      { name = "SQL_DATABASE",         value = var.db_name },
      { name = "SQL_ENGINE",           value = "django.db.backends.postgresql" },
      { name = "DEBUG",                value = "0" },
      { name = "DJANGO_ALLOWED_HOSTS", value = "localhost backend ${aws_lb.main.dns_name}" },
      { name = "CORS_ALLOWED_ORIGINS", value = "http://${aws_lb.main.dns_name}" },
      { name = "CSRF_TRUSTED_ORIGINS", value = "http://${aws_lb.main.dns_name}" },
      { name = "LOAD_INITIAL_DATA",    value = "0" }
    ]

    # Secretos inyectados desde Secrets Manager en arranque de contenedor
    secrets = [
      {
        name      = "DJANGO_SECRET_KEY"
        valueFrom = var.django_secret_key_arn
      },
      {
        name      = "POSTGRES_USER"
        valueFrom = "${var.db_credentials_arn}:username::"
      },
      {
        name      = "POSTGRES_PASSWORD"
        valueFrom = "${var.db_credentials_arn}:password::"
      },
      {
        name      = "SQL_USER"
        valueFrom = "${var.db_credentials_arn}:username::"
      },
      {
        name      = "SQL_PASSWORD"
        valueFrom = "${var.db_credentials_arn}:password::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import socket; s=socket.create_connection(('127.0.0.1', 8000), 5); s.close()\" || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
  }])

  # El pipeline gestiona las actualizaciones de imagen usando render-task-definition por eso Terraform ignora cambios en container_definitions para no pisar esos deploys.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.frontend_task_cpu
  memory                   = var.frontend_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = var.frontend_image_uri
    essential = true

    portMappings = [{
      name          = "frontend"
      containerPort = 80
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/index.html || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# Servicios ECS
# Servicio del backend — expone el puerto 8000 como "backend" via Service Connect

resource "aws_ecs_service" "backend" {
  name            = "${var.project}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.backend_sg_id]
    assign_public_ip = false
  }

  # Registra el servicio como "backend:8000" en el namespace devops-interview.local
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "backend"
      discovery_name = "backend"

      client_alias {
        port     = 8000
        dns_name = "backend"
      }
    }
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # El pipeline actualiza la task_definition en cada deploy, terraform no debe interferir.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# Servicio del frontend — expuesto a través del ALB, se conecta al backend vía Service Connect
resource "aws_ecs_service" "frontend" {
  name            = "${var.project}-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.frontend_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  # Habilitado como cliente del namespace para poder resolver "backend:8000"
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
