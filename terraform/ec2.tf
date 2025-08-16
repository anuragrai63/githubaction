resource "aws_iam_role" "bastion" {
  name = "${var.cluster_name}-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "bastion_eks" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "bastion_ecr_ro" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Bastion access"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-bastion-sg" }
}

# Allow bastion to reach API server SG on 443 (if needed for private endpoint)
resource "aws_security_group_rule" "bastion_to_cp_443" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion.id
  source_security_group_id = aws_security_group.eks_cluster.id
  depends_on               = [aws_security_group.eks_cluster]
}

# Find latest Amazon Linux 2 AMI
data "aws_ami" "al2" {
  owners      = ["137112412989"] # Amazon
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }
}

locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -e
    yum update -y
    yum install -y curl jq unzip bash-completion

    # kubectl v1.32.3 (Linux amd64)
    curl -o /usr/local/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.3/2025-04-17/bin/linux/amd64/kubectl
    chmod +x /usr/local/bin/kubectl

    # Helm latest
    curl -L https://get.helm.sh/helm-$(curl -s https://github.com/helm/helm/releases/latest | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+')-linux-amd64.tar.gz -o /tmp/helm.tgz
    tar -xzf /tmp/helm.tgz -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm

    # bash completion
    echo 'source <(kubectl completion bash)' >> /etc/bashrc
    echo 'source <(helm completion bash)' >> /etc/bashrc
    echo 'complete -C /usr/local/bin/aws_completer aws' >> /etc/bashrc
  EOF
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  user_data                   = local.bastion_user_data

  tags = { Name = "eks-mgmt" }
}
