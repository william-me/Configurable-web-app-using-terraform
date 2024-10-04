resource "aws_vpc" "myvpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}
resource "aws_subnet" "firstsubnet" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "us-east-1a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
}
resource "aws_subnet" "secondsubnet" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "us-east-1b"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "myigw" {
  vpc_id = aws_vpc.myvpc.id
}
resource "aws_route_table" "myroutetable" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myigw.id
  }
}
resource "aws_route_table_association" "associate1" {
  subnet_id      = aws_subnet.firstsubnet.id
  route_table_id = aws_route_table.myroutetable.id
}
resource "aws_route_table_association" "associate2" {
  subnet_id      = aws_subnet.secondsubnet.id
  route_table_id = aws_route_table.myroutetable.id
}
resource "aws_security_group" "name" {
  name   = "allow http"
  vpc_id = aws_vpc.myvpc.id
  tags = {
    Name = "Allow HTTPS"
  }
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
data "aws_ami" "ubuntu_1" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.name.id]
  subnet_id              = aws_subnet.firstsubnet.id


  tags = {
    Name = "server1"
  }
  user_data = <<-EOF
              #!/bin/bash
              # Update the system
              apt-get update -y
              apt-get upgrade -y

              # Install Apache HTTP Server
              apt-get install -y apache2

              # Enable Apache to start on boot
              systemctl enable apache2

              # Start Apache service
              systemctl start apache2

              # Create a simple index.html to verify the setup
              echo "<html><body><h1>Welcome to the WebServer-B</h1></body></html>" > /var/www/html/index.html
              EOF
}
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.name.id]
  subnet_id              = aws_subnet.secondsubnet.id


  tags = {
    Name = "server2"
  }
  user_data = <<-EOF
              #!/bin/bash
              # Update the system
              apt-get update -y
              apt-get upgrade -y

              # Install Apache HTTP Server
              apt-get install -y apache2

              # Enable Apache to start on boot
              systemctl enable apache2

              # Start Apache service
              systemctl start apache2

              # Create a simple index.html to verify the setup
              echo "<html><body><h1>Welcome to the WebServer-A</h1></body></html>" > /var/www/html/index.html
              EOF
}
resource "aws_lb" "mylb" {
  name               = "test-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.name.id]
  subnets            = [aws_subnet.firstsubnet.id, aws_subnet.secondsubnet.id]

  tags = {
    Name = "web"
  }
}
resource "aws_lb_target_group" "test" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id

  health_check {
    path = "/"
    port = "traffic-port"
  }
}
resource "aws_lb_target_group_attachment" "test1" {
  target_group_arn = aws_lb_target_group.test.arn
  target_id        = aws_instance.web.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "test2" {
  target_group_arn = aws_lb_target_group.test.arn
  target_id        = aws_instance.web2.id
  port             = 80
}
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mylb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}