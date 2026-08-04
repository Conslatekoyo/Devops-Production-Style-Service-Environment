output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group."
  value       = aws_security_group.alb.id
}

output "booking_security_group_id" {
  description = "ID of the Booking service security group."
  value       = aws_security_group.booking.id
}

output "driver_security_group_id" {
  description = "ID of the Driver service security group."
  value       = aws_security_group.driver.id
}

output "tracking_security_group_id" {
  description = "ID of the Tracking service security group."
  value       = aws_security_group.tracking.id
}

output "alb_security_group_arn" {
  description = "ARN of the Application Load Balancer security group."
  value       = aws_security_group.alb.arn
}

output "booking_security_group_arn" {
  description = "ARN of the Booking service security group."
  value       = aws_security_group.booking.arn
}

output "driver_security_group_arn" {
  description = "ARN of the Driver service security group."
  value       = aws_security_group.driver.arn
}

output "tracking_security_group_arn" {
  description = "ARN of the Tracking service security group."
  value       = aws_security_group.tracking.arn
}
