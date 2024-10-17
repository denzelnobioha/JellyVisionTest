provider "aws" {}

# Create a DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform_locks"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }

  hash_key = "LockID"
}

resource "aws_vpc" "simpsons_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.simpsons_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.simpsons_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"  # Use a different AZ
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.simpsons_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.simpsons_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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


##IAM

resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecsExecutionRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_execution_role.name
}



####### ECS Resource

resource "aws_ecs_cluster" "simpsons_cluster" {
  name = "simpsons-cluster"
}

resource "aws_ecs_task_definition" "simpsons_task" {
  family                = "simpsons-task"
  network_mode          = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory               = "512"
  cpu                  = "256"
  execution_role_arn   = aws_iam_role.ecs_execution_role.arn  # Add this line

  container_definitions = <<DEFINITION
  [
    {
      "name": "simpsons-api",
      "image": "216989106329.dkr.ecr.us-east-1.amazonaws.com/simpsons-api:latest",
      "memory": 512,
      "cpu": 256,
      "portMappings": [
        {
          "containerPort": 4567,
          "hostPort": 4567
        }
      ]
    }
  ]
  DEFINITION
}

# resource "aws_ecs_service" "simpsons_service" {
#   name            = "simpsons-service"
#   cluster         = aws_ecs_cluster.simpsons_cluster.id
#   task_definition = aws_ecs_task_definition.simpsons_task.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets         = [aws_subnet.private_subnet.id]
#     security_groups = [aws_security_group.ecs_sg.id]
#   }
# }

resource "aws_ecs_service" "simpsons_service" {
  name            = "simpsons-service"
  cluster         = aws_ecs_cluster.simpsons_cluster.id
  task_definition = aws_ecs_task_definition.simpsons_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_subnet.id]
    security_groups = [aws_security_group.ecs_sg.id]

    # Add this block to attach to the load balancer
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.simpsons_target_group.arn
    container_name   = "simpsons-api"  # Replace with your container name
    container_port   = 4567  # Replace with the port your app listens on
  }
}


##### IGW #################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.simpsons_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.simpsons_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id  # The public subnet for the NAT Gateway
  route_table_id = aws_route_table.public_route_table.id
}


#### NAT GATEWAY ################################# 
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id  # Create a public subnet for the NAT Gateway
}


##### ROUTE TABLE CONFIGURATION #################################
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.simpsons_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}


# Create the Application Load Balancer
resource "aws_lb" "simpsons_lb" {
  name               = "simpsons-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  #subnets            = [aws_subnet.public_subnet.id] # You may want to use public subnets
    subnets            = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id  # Include the new subnet
  ]

  enable_deletion_protection = false
}

# Create a target group for the ECS service
resource "aws_lb_target_group" "simpsons_target_group" {
  name     = "simpsons-target-group"
  port     = 4567
  protocol = "HTTP"
  vpc_id   = aws_vpc.simpsons_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"  # Adjust as necessary
    interval            = 30
    timeout             = 5
    healthy_threshold  = 2
    unhealthy_threshold = 2
  }
}

# Create a listener for the Load Balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.simpsons_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.simpsons_target_group.arn
  }
}


#### witthout lb


resource "aws_ecs_service" "simpsons_service_without_lb" {
  name            = "simpsons-service-no-lb"
  cluster         = aws_ecs_cluster.simpsons_cluster.id
  task_definition = aws_ecs_task_definition.simpsons_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_subnet.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true  # Set to false if you don't want a public IP
  }
}