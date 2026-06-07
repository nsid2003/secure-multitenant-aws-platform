provider "aws" {
  region = "eu-west-3"     
  default_tags {
    tags = {
      Project   = "secure-multitenant-aws-platform"
      ManagedBy = "Terraform"
    }
  }
}