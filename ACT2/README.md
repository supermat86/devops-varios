# devops-interview-ultimate
App full-stack compuesta por un backend Django REST + PostgreSQL y un frontend React, completamente containerizada con Docker.



# 1. Arquitectura y decisiones de despliegue
# Stack de servicios
# Imagenes base y roles

- db: base de datos.
  - Imagen base: postgres:12-alpine.
  - Rol: base de datos relacional local o RDS en AWS.

- backend: API REST.
  - Imagen base: python:3.9-slim.
  - Rol: Django + Gunicorn usando WSGI.

- frontend: aplicación web.
  - Imagen base: node:16-alpine → nginx:1.25-alpine.
  - Rol: build de React, servidor estático y proxy nginx.

# ADR
# Docker Compose es el orquestador elegido para desarrollo local:
- Supervisor: Descartado. Gestiona procesos dentro de un único contenedor/host. No provee redes entre servicios ni control de orden de arranque entre distintos procesos.
- Scripts de shell: Descartados como orquestador principal. No gestionan reinicios automáticos, redes ni volumenes.
- Kubernetes: Sobredimensionado para desarrollo local o despliegue de instancia única. Agrega complejidad operativa (manifests, RBAC, ingress controllers) que no se justifica por lo sencillo de esta aplicación.
- Docker Compose: declarativo, portable, maneja las dependencias (depends_on + healthcheck), volumenes persistentes y redes internas desde un unico archivo.

# ECS Fargate es la plataforma elegida para la nube porque:
- Elimina la gestion de instancias EC2 (serverless de contenedores).
- Escala horizontalmente por servicio de forma independiente.
- Se integra nativamente con ECR, ALB, Secrets Manager y CloudWatch.
- ECS Service Connect provee descubrimiento de servicios interno sin modificar el código de la aplicación.

# Terraform gestiona toda la infraestructura AWS:
- Reproducible: el mismo código produce la misma infraestructura en cualquier cuenta.
- Estado remoto en S3 con locking via DynamoDB, permitiendo que varias personas trabajen sobre la misma infraestructura sin conflictos.
- Modular: cada componente (vpc, ecr, rds, secrets, ecs) tiene su propio modulo.
- Las credenciales sensibles (Django secret key, credenciales de la base de datos, etc) son generadas automaticamente con random_password y almacenadas en AWS Secrets Manager, evitando escribirlas en texto plano en el codigo.



# Decisiones sobre los Dockerfiles
# Backend (backend/Dockerfile)
- Imagen base python:3.9-slim para minimizar el tamaño de imagen.
- Dependencias del sistema instaladas en una sola capa RUN con limpieza del cache APT.
- El entrypoint.sh espera a que PostgreSQL este disponible, aplica migraciones y ejecuta collectstatic antes de iniciar el servidor.
- CMD ejecuta Gunicorn (mas apropiado para ambientes productivos) en lugar del runserver de Django.

# Frontend (frontend/Dockerfile)
- Build multi-stage: la primera etapa usa node:16-alpine para compilar el bundle de React. La segunda etapa usa nginx:1.25-alpine y copia unicmente los archivos estaticos. La imagen final no contiene Node.js ni codigo fuente.
- REACT_APP_API_SERVER se inyecta como argumento en build, configurable desde el paso de CI sin recompilar con parametros distintos.
- Nginx actua como proxy reverso: redirige /api/ al servicio backend:8000.



# 2. Requisitos
# Local
- Docker Engine

# AWS (despliegue en ECS con Terraform)
- Cuenta AWS con permisos necesarios respetando minimo privilegio.
- AWS CLI v2 configurado (aws configure).
- Terraform
- Repositorio en GitHub con acceso a configurar Secrets.


# 3. Variables de entorno
El archivo .env es usado por Docker Compose en local. En AWS las variables no sensibles se definen en la task definition de ECS via Terraform y los secretos son generados y almacenados en Secrets Manager por Terraform al momento del apply.

# Variables de entorno
DATABASE
Motor de base de datos
Valor local sugerido: postgres

SQL_DATABASE 
Nombre de la base de datos
Valor local sugerido: core

POSTGRES_USER  
Usuario de PostgreSQL
Valor local sugerido: user

POSTGRES_PASSWORD  
Contraseña de PostgreSQL
Valor local sugerido: password

SQL_HOST  
Hostname del servicio PostgreSQL
Valor local sugerido: db

SQL_PORT
Puerto de PostgreSQL
Valor local sugerido: 5432

DJANGO_SECRET_KEY
Clave secreta de Django
Valor local sugerido: SeDebeCambiar

DEBUG
Modo debug de Django
0 = desactivado.  
Valor local sugerido: 0

DJANGO_ALLOWED_HOSTS
Hosts permitidos, separados por espacio
Valor local sugerido: localhost 127.0.0.1

CORS_ALLOWED_ORIGINS
Orígenes CORS permitidos
Valor local sugerido: http://localhost

LOAD_INITIAL_DATA
Carga datos iniciales
1 = si
Valor local sugerido: 0


# Instrucciones de Despliegue Local (Docker Compose)

# 4.1 Clonar el repositorio
git clone url-del-repo
cd devops-interview-ultimate


# 4.2 Configurar variables de entorno
Crear el archivo .env en la carpeta raiz
Asegurarse de que en .gitignore este la entrada para .env

# 4.3 Construir y levantar los servicios
docker compose up --build -d

El comando:
1. Construye las imagenes backend y frontend desde sus respectivos Dockerfile.
2. Levanta db (PostgreSQL) y espera a que este saludable (healthcheck).
3. Levanta backend, aplica migraciones y carga datos iniciales.
4. Levanta frontend (nginx) cuando el backend esta healthy.

# 4.4 Verificar el estado
docker compose ps
docker compose logs -f


# 4.5 Acceder a la aplicación
# Servicios locales
Frontend
URL local: http://localhost

API REST
URL local: http://localhost/api/


# 4.6 Detener los servicios
# Detener sin borrar volúmenes (datos persistidos)
docker compose down

# Detener y borrar todos los volúmenes (reset completo)
docker compose down -v


# 5. Despliegue en AWS con Terraform + ECS + ECR + GitHub Actions
# Arquitectura en AWS

Internet > [ALB] (80) > [ECS Service: frontend] nginx:1.25-alpine (puerto 80, subnet privada) > proxy /api/ a backend:8000 > [ECS Service: backend] gunicorn (puerto 8000, interno) > [RDS PostgreSQL] (puerto 5432, subnet privada)

Imágenes almacenadas en [ECR]
Infraestructura gestionada por [Terraform] con estado en [S3 + DynamoDB]
Build y deploy automatizado desde [GitHub Actions]

ECS Service Connect permite que el contenedor nginx resuelva el hostname backend hacia el servicio ECS de backend dentro del namespace devops-interview.local.

# Estructura de la infraestructura Terraform
- infra/: carpeta principal de infraestructura.
  - bootstrap/: S3 + DynamoDB para el estado remoto. Se aplica una sola vez.
  - modules/: carpeta de modulos de Terraform.
    - vpc/: VPC, subnets publicas/privadas, IGW, NAT Gateway y route tables.
    - ecr/: repositorios ECR para backend y frontend con lifecycle policies.
    - secrets/: genera y almacena credenciales en AWS Secrets Manager.
    - rds/: instancia RDS PostgreSQL en subnets privadas.
    - ecs/: ALB, ECS cluster, task definitions, servicios, IAM y CloudWatch.
  - main.tf: archivo principal de Terraform.
  - variables.tf: definicion de variables.
  - outputs.tf: salidas de Terraform.
  - terraform.tfvars: valores de variables.
  - backend.hcl: configuracion del backend S3.


# 5.1 Bootstrap — estado remoto (una sola vez por cuenta AWS)
El bootstrap crea el bucket S3 y la tabla DynamoDB que Terraform va a usar para guardar y lockear el remote state. Se aplica una unica vez con estado local.

cd ACT2/infra/bootstrap
terraform init
terraform plan
terraform apply


# 5.2 Configurar OIDC para GitHub Actions (una sola vez por cuenta AWS)
El pipeline usa OIDC para obtener credenciales AWS temporales.

# Paso 1 — Registrar GitHub como Identity Provider en AWS

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \

Este paso es unico por cuenta AWS ya que la configuracion IAM es global.

# Paso 2 — Crear el rol IAM que sera asumido por GitHub Actions
El trust policy restringe el acceso al repositorio especifico, impidiendo que otros repositorios asuman el mismo rol.

Ejemplo de trust policy:
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::903783978165:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:supermat86/devops-varios:*"
                }
            }
        }
    ]
}


# Paso 3 — Adjuntar permisos al rol
Se adjuntan los permisos necesarios al rol para ejecutar las acciones de despliegue en AWS. La misma utiliza minimo privilegio.

# Paso 4 — Agregar el ARN del rol como secret en GitHub

En el repositorio (Secrets and variables, Actions), agregamos:
AWS_ROLE_ARN: arn:aws:iam::<ACCOUNT_ID>:role/nombre-del-rol


# 5.3 Pipeline de CI/CD

El workflow .github/workflows/deploy-act2.yml del repositorio se activa con cada push a main que modifique archivos dentro de ACT2/, y ejecuta cinco jobs en secuencia:

# Flujo de despliegue

- push a main: dispara el pipeline de CI/CD.
  - security: validaciones iniciales de seguridad.
    - Trivy: escaneo de CVEs y secrets en el repositorio.
    - Checkov: analisis estatico del codigo Terraform.

  - terraform: aprovisiona y actualiza la infraestructura.
    - OIDC: asume un rol IAM con credenciales temporales.
    - terraform init / plan / apply: inicializa, planifica y aplica cambios.
    - outputs: expone ECR URLs, cluster ECS y nombres de servicios.

  - build-and-push: construccion y publicacion de imagenes Docker.
    - Backend: docker build ./backend y push a ECR.
    - Frontend: docker build ./frontend y push a ECR.

  - deploy-backend: despliegue del backend en ECS.
    - Obtiene la task definition actual desde ECS.
    - Reemplaza la imagen por la nueva version.
    - Despliega una nueva revisión y espera estabilizacion.

  - deploy-frontend: despliegue del frontend en ECS.
    - Obtiene la task definition actual desde ECS.
    - Reemplaza la imagen por la nueva versión.
    - Despliega una nueva revisión y espera estabilizacion.


Cada imagen se sube a ECR tageada como latest, sobreescribiendo la version anterior en cada deploy. Terraform gestiona la infraestructura con lifecycle { ignore_changes } en las task definitions y servicios ECS, permitiendo que el pipeline actualice las imagenes sin que el proximo terraform apply revierta esos cambios.


# 5.4 Acceder a la app en AWS

# Obtener el DNS del ALB desde los outputs de Terraform
cd ACT2/infra
terraform output alb_dns_name
Abrir en el navegador: http://<alb_dns_name>


# 5.5 Monitoreo y logs
# Logs del backend en tiempo real
aws logs tail /ecs/devops-interview-backend --follow

# Logs del frontend en tiempo real
aws logs tail /ecs/devops-interview-frontend --follow

# Estado de los servicios ECS
aws ecs describe-services \
  --cluster devops-interview-cluster \
  --services devops-interview-backend-service devops-interview-frontend-service



# 5.6 Destruir la infraestructura

cd ACT2/infra
terraform destroy


# 6. Referencia de servicios
# Local (Docker Compose)
# Puertos y servicios

- db: servicio de base de datos PostgreSQL.
  - Puerto interno: 5432.
  - Puerto host: no expuesto.
  - Notas: solo accesible dentro de la red Docker.

- backend: servicio de API/backend.
  - Puerto interno: 8000.
  - Puerto host: no expuesto.
  - Notas: accedido por nginx vía proxy /api/.

- frontend: servicio web/frontend.
  - Puerto interno: 80.
  - Puerto host: 80.
  - Notas: punto de entrada unico de la app.

# AWS (ECS Fargate)

# Acceso
- RDS PostgreSQL: base de datos PostgreSQL administrada.
  - Exposicion: privada dentro de la VPC.
  - Acceso: solo desde las tasks de ECS en subnets privadas.

- ECS backend: servicio interno de backend.
  - Exposicion: interna mediante Service Connect.
  - Acceso: backend:8000 dentro del namespace devops-interview.local.

- ECS frontend: servicio web frontend.
  - Exposicion: ALB publico.
  - Acceso: http://<alb_dns_name> desde Internet.
