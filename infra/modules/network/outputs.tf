output "vpc_id" {
  description = "ID of the custom Group 8 VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the custom Group 8 VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets used by the ALB and NAT Gateway."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the two private application subnets used by Fargate tasks."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table."
  value       = aws_route_table.private.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway when enabled."
  value       = try(aws_nat_gateway.this[0].id, null)
}

output "nat_eip_public_ip" {
  description = "Public Elastic IP assigned to the NAT Gateway when enabled."
  value       = try(aws_eip.nat[0].public_ip, null)
}

output "availability_zones" {
  description = "Availability Zones used by the network."
  value       = var.availability_zones
}
