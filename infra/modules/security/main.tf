############################################
# Security groups
############################################

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allows public HTTP traffic to the Group 8 ALB."
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-alb-sg"
    }
  )
}

resource "aws_security_group" "booking" {
  name        = "${var.name_prefix}-booking-sg"
  description = "Allows approved traffic to Booking service."
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name  = "${var.name_prefix}-booking-sg"
      Owner = "booking-service-owner"
    }
  )
}

resource "aws_security_group" "driver" {
  name        = "${var.name_prefix}-driver-sg"
  description = "Allows approved traffic to Driver service."
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name  = "${var.name_prefix}-driver-sg"
      Owner = "driver-service-owner"
    }
  )
}

resource "aws_security_group" "tracking" {
  name        = "${var.name_prefix}-tracking-sg"
  description = "Allows approved traffic to Tracking service."
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name  = "${var.name_prefix}-tracking-sg"
      Owner = "tracking-service-owner"
    }
  )
}

############################################
# Internet -> ALB:80
############################################

resource "aws_vpc_security_group_ingress_rule" "internet_to_alb" {
  security_group_id = aws_security_group.alb.id

  description = "Allow public HTTP traffic to the ALB."
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = var.alb_port
  to_port     = var.alb_port
  ip_protocol = "tcp"
}

############################################
# ALB -> Booking:3001
############################################

resource "aws_vpc_security_group_ingress_rule" "alb_to_booking" {
  security_group_id = aws_security_group.booking.id

  description                  = "Allow the ALB to reach Booking."
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.booking_port
  to_port                      = var.booking_port
  ip_protocol                  = "tcp"
}

############################################
# Booking -> Driver:3002
############################################

resource "aws_vpc_security_group_ingress_rule" "booking_to_driver" {
  security_group_id = aws_security_group.driver.id

  description                  = "Allow Booking to reach Driver."
  referenced_security_group_id = aws_security_group.booking.id
  from_port                    = var.driver_port
  to_port                      = var.driver_port
  ip_protocol                  = "tcp"
}

############################################
# Driver -> Tracking:3003
############################################

resource "aws_vpc_security_group_ingress_rule" "driver_to_tracking" {
  security_group_id = aws_security_group.tracking.id

  description                  = "Allow Driver to reach Tracking."
  referenced_security_group_id = aws_security_group.driver.id
  from_port                    = var.tracking_port
  to_port                      = var.tracking_port
  ip_protocol                  = "tcp"
}

############################################
# Tracking -> Booking:3001 callback
############################################

resource "aws_vpc_security_group_ingress_rule" "tracking_to_booking" {
  security_group_id = aws_security_group.booking.id

  description                  = "Allow Tracking confirmation callbacks to Booking."
  referenced_security_group_id = aws_security_group.tracking.id
  from_port                    = var.booking_port
  to_port                      = var.booking_port
  ip_protocol                  = "tcp"
}

############################################
# Outbound rules
############################################

resource "aws_vpc_security_group_egress_rule" "alb_to_booking" {
  security_group_id = aws_security_group.alb.id

  description                  = "Allow the ALB to send traffic only to Booking."
  referenced_security_group_id = aws_security_group.booking.id
  from_port                    = var.booking_port
  to_port                      = var.booking_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "booking_outbound" {
  security_group_id = aws_security_group.booking.id

  description = "Allow Booking outbound access through the private-subnet egress path."
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "driver_outbound" {
  security_group_id = aws_security_group.driver.id

  description = "Allow Driver outbound access through the private-subnet egress path."
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "tracking_outbound" {
  security_group_id = aws_security_group.tracking.id

  description = "Allow Tracking outbound access through the private-subnet egress path."
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
