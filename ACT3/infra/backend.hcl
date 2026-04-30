bucket         = "cft-nginx-app-tfstate"
key            = "cft-nginx-app/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "cft-nginx-app-tfstate-lock"
encrypt        = true
