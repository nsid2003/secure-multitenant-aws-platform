terraform {
  required_version = ">= 1.6"          # uniquement avec les versions sup ou eq a 1.6
  required_providers {
    aws = {
      source  = "hashicorp/aws"        
      version = "~> 5.0"               # on accepte les 5.x
    }
  }
}