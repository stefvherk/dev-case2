resource "aws_security_group" "collector_sg" {
  name        = "collector-sg"
  description = "Allow syslog and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow syslog from pfSense"
    from_port   = 514
    to_port     = 514
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from your IP for management"
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

  tags = { Name = "collector-sg" }
}

data "aws_ssm_parameter" "amazon_linux_2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "collector" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.collector_sg.id]
  key_name                    = "ec2-keypair-collector"
  iam_instance_profile        = aws_iam_instance_profile.cloudwatch_profile.name

  tags = { Name = "log-collector" }

  user_data = <<-EOF
#!/bin/bash
set -e

yum update -y
yum install -y rsyslog amazon-cloudwatch-agent

# Create log file
mkdir -p /var/log/pfsense
touch /var/log/pfsense/pfsense.log
chmod 644 /var/log/pfsense/pfsense.log

# Configure rsyslog to listen on UDP 514
cat > /etc/rsyslog.d/pfsense.conf << 'RSYSLOG_EOF'
$ModLoad imudp
$UDPServerRun 514

$template PfSenseLogs,"/var/log/pfsense/pfsense.log"
*.* ?PfSenseLogs
& stop
RSYSLOG_EOF

# Restart rsyslog
systemctl enable rsyslog
systemctl restart rsyslog

# Configure CloudWatch agent
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCFG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/pfsense/pfsense.log",
            "log_group_name": "/pfsense/logs",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%b %d %H:%M:%S"
          }
        ]
      }
    }
  }
}
CWCFG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Test log
echo "$(date) Terraform test log" >> /var/log/pfsense/pfsense.log
EOF
}



resource "aws_cloudwatch_log_group" "pfsense_logs" {
  name              = "/pfsense/logs"
  retention_in_days = 14
}

resource "aws_iam_role" "cloudwatch_role" {
  name = "ec2-cloudwatch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_attach" {
  role       = aws_iam_role.cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


resource "aws_iam_instance_profile" "cloudwatch_profile" {
  name = "ec2-cloudwatch-profile"
  role = aws_iam_role.cloudwatch_role.name
}

resource "aws_eip" "collector_eip" {
  vpc = true
  tags = {
    Name = "collector-eip"
  }
}

resource "aws_eip_association" "collector_eip_assoc" {
  instance_id   = aws_instance.collector.id
  allocation_id = aws_eip.collector_eip.id
}