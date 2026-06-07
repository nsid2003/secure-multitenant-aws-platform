variable "client_name" {
  description = "Nom du client"
  type        = string
}

variable "client_index" {
  description = "Index = 2e octet du /16"
  type        = number
}

variable "availability_zone" {
  type    = string
  default = "eu-west-3a"
}

variable "bastion_vpc_id" {
  type = string
}

variable "bastion_cidr" {
  type = string
}

variable "bastion_route_table_ids" {
  description = "Tables de routage du bastion qui doivent router vers ce client"
  type        = list(string)
}

variable "ami_id" {
  type = string
}
variable "aws_region" {
  type    = string
  default = "eu-west-3"
}
variable "account_id" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
