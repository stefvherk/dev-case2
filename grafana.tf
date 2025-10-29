resource "aws_security_group" "grafana_sg" {
  name        = "grafana-sg"
  description = "Allow HTTP access for Grafana and SSH for admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Grafana Web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from your IP"
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

  tags = { Name = "grafana-sg" }
}

resource "aws_iam_role" "grafana_role" {
  name = "grafana-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_attach" {
  role       = aws_iam_role.grafana_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_instance_profile" "grafana_profile" {
  name = "grafana-ec2-profile"
  role = aws_iam_role.grafana_role.name
}

resource "aws_instance" "grafana" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.grafana_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.grafana_profile.name
  key_name                    = "ec2-keypair-collector"

  user_data = <<-EOF
  #!/bin/bash
  set -e
  yum update -y

  cat > /etc/yum.repos.d/grafana.repo << 'REPO'
[grafana]
name=Grafana Repository
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
REPO

  yum install -y grafana
  systemctl enable grafana-server
  systemctl start grafana-server

echo 'export AWS_DEFAULT_REGION=eu-central-1' >> /etc/profile.d/aws.sh
echo 'export AWS_SDK_LOAD_CONFIG=1' >> /etc/profile.d/aws.sh
EOF

  tags = { Name = "grafana-server" }
}