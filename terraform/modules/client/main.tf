locals {
  vpc_cidr  = "10.${var.client_index}.0.0/16"
  web_cidr  = "10.${var.client_index}.1.0/24"
  data_cidr = "10.${var.client_index}.2.0/24"
}

resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "secureaws-${var.client_name}-vpc" }
}

resource "aws_subnet" "web" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.web_cidr
  availability_zone = var.availability_zone
  tags = { Name = "secureaws-${var.client_name}-web" }
}

resource "aws_subnet" "data" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidr
  availability_zone = var.availability_zone
  tags = { Name = "secureaws-${var.client_name}-data" }
}

# Routage PRIVÉ : aucune Internet Gateway (contrainte du sujet)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "secureaws-${var.client_name}-private-rt" }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  subnet_id      = aws_subnet.data.id
  route_table_id = aws_route_table.private.id
}

# La connexion de peering client vers le bastion
resource "aws_vpc_peering_connection" "to_bastion" {
  vpc_id      = aws_vpc.this.id
  peer_vpc_id = var.bastion_vpc_id
  auto_accept = true
  tags = { Name = "secureaws-${var.client_name}-peering" }
}

# ici, le client pour  joindre le bastion, passe par le peering
resource "aws_route" "to_bastion" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.bastion_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.to_bastion.id
}

# le bastion  pour joindre ce client, passe par le peering (une route par table)
resource "aws_route" "from_bastion" {
  count                     = length(var.bastion_route_table_ids)
  route_table_id            = var.bastion_route_table_ids[count.index]
  destination_cidr_block    = local.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.to_bastion.id
}

resource "aws_security_group" "web" {
  name        = "secureaws-${var.client_name}-web-sg"
  description = "Serveur web du client ${var.client_name}"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP depuis le reverse proxy (DMZ)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
  ingress {
    description = "SSH depuis le bastion admin (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.10.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "secureaws-${var.client_name}-web-sg" }

  # Crée le nouveau SG avant de supprimer l'ancien -> casse le deadlock de remplacement
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.web.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "secureaws-key"
  # le serveur reste privé du coup pas de ip publique
  tags = {
    Name   = "secureaws-${var.client_name}-web"
    Role   = "web"
    Client = var.client_name
  }
}
# ===== Tier données du client (tâche 5) =====
# VPC Endpoint S3 (Gateway) : accès S3 sans passer par Internet
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags = { Name = "secureaws-${var.client_name}-s3-endpoint" }
}

# Bucket S3 du client : privé + chiffré KMS
resource "aws_s3_bucket" "data" {
  bucket        = "secureaws-${var.client_name}-data-${var.account_id}"
  force_destroy = true
  tags = { Name = "secureaws-${var.client_name}-data" }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}
