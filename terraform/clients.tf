locals {
  bastion_route_tables = [
    aws_route_table.public.id,
    aws_route_table.admin_private.id,
  ]
}

module "client_a" {
  source       = "./modules/client"
  client_name  = "cybersky"
  client_index = 1

  bastion_vpc_id          = aws_vpc.bastion.id
  bastion_cidr            = aws_vpc.bastion.cidr_block
  bastion_route_table_ids = local.bastion_route_tables
  ami_id                  = data.aws_ami.ubuntu.id
  account_id              = data.aws_caller_identity.current.account_id
  kms_key_arn             = aws_kms_key.main.arn
}

module "client_b" {
  source       = "./modules/client"
  client_name  = "drox360"
  client_index = 2

  bastion_vpc_id          = aws_vpc.bastion.id
  bastion_cidr            = aws_vpc.bastion.cidr_block
  bastion_route_table_ids = local.bastion_route_tables
  ami_id                  = data.aws_ami.ubuntu.id
  account_id              = data.aws_caller_identity.current.account_id
  kms_key_arn             = aws_kms_key.main.arn
}

module "client_c" {
  source       = "./modules/client"
  client_name  = "visuance"
  client_index = 3

  bastion_vpc_id          = aws_vpc.bastion.id
  bastion_cidr            = aws_vpc.bastion.cidr_block
  bastion_route_table_ids = local.bastion_route_tables
  ami_id                  = data.aws_ami.ubuntu.id
  account_id              = data.aws_caller_identity.current.account_id
  kms_key_arn             = aws_kms_key.main.arn
}
