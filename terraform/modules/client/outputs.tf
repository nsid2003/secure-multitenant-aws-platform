output "vpc_id" {
  value = aws_vpc.this.id
}
output "vpc_cidr" {
  value = local.vpc_cidr
}
output "route_table_id" {
  value = aws_route_table.private.id
}
output "web_subnet_id" {
  value = aws_subnet.web.id
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}