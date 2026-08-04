resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-alb"
    }
  )
}

resource "aws_lb_target_group" "booking" {
  name        = "${var.name_prefix}-booking-tg"
  port        = var.booking_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = var.target_type

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(
    var.tags,
    {
      Name  = "${var.name_prefix}-booking-tg"
      Owner = "booking-service-owner"
    }
  )
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.booking.arn
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-http-listener"
    }
  )
}
