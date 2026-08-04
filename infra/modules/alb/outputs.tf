output "alb_arn" {
  description = "ARN of the Group 8 Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_name" {
  description = "Name of the Group 8 Application Load Balancer."
  value       = aws_lb.this.name
}

output "alb_dns_name" {
  description = "Public DNS name of the Group 8 Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the Application Load Balancer."
  value       = aws_lb.this.zone_id
}

output "booking_target_group_arn" {
  description = "ARN of the Booking service target group."
  value       = aws_lb_target_group.booking.arn
}

output "booking_target_group_name" {
  description = "Name of the Booking service target group."
  value       = aws_lb_target_group.booking.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener on port 80."
  value       = aws_lb_listener.http.arn
}
