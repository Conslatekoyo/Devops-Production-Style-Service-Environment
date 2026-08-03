run "network_contract" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.8.0.0/16"
    error_message = "The VPC must use the approved Group 8 CIDR 10.8.0.0/16."
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "The network must create exactly two public subnets."
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "The network must create exactly two private application subnets."
  }

  assert {
    condition = alltrue([
      for subnet in aws_subnet.public :
      subnet.map_public_ip_on_launch == true
    ])
    error_message = "Public subnets must allow public IP assignment."
  }

  assert {
    condition = alltrue([
      for subnet in aws_subnet.private :
      subnet.map_public_ip_on_launch == false
    ])
    error_message = "Private application subnets must not assign public IPs."
  }

  assert {
    condition     = length(distinct(var.availability_zones)) == 2
    error_message = "The network must span two distinct Availability Zones."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "The lab design requires one NAT Gateway."
  }
}
