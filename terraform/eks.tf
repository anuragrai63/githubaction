provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "eks-vpc" }
}

resource "aws_subnet" "eks_private_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
  tags = { Name = "eks-private-a" }
}

resource "aws_subnet" "eks_private_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false
  tags = { Name = "eks-private-b" }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = { Name = "eks-igw" }
}

resource "aws_nat_gateway" "eks_nat" {
  allocation_id = aws_eip.eks_nat.id
  subnet_id     = aws_subnet.eks_private_a.id
  tags = { Name = "eks-nat" }
  depends_on = [aws_internet_gateway.eks_igw]
}

resource "aws_eip" "eks_nat" {
  vpc = true
  tags = { Name = "eks-nat-eip" }
}

resource "aws_route_table" "eks_private_rt" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = { Name = "eks-private-rt" }
}

resource "aws_route" "eks_private_nat_route" {
  route_table_id         = aws_route_table.eks_private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.eks_nat.id
}

resource "aws_route_table_association" "eks_private_rta_a" {
  subnet_id      = aws_subnet.eks_private_a.id
  route_table_id = aws_route_table.eks_private_rt.id
}

resource "aws_route_table_association" "eks_private_rta_b" {
  subnet_id      = aws_subnet.eks_private_b.id
  route_table_id = aws_route_table.eks_private_rt.id
}

# Security group: only allow 443 and 10250 from within VPC (K8s API and node comms)
resource "aws_security_group" "eks_sg" {
  name        = "eks-sg"
  description = "Allow EKS API and node comms from VPC"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
    description = "Kubernetes API"
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
    description = "Kubelet API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "eks-sg" }
}

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "eks" {
  name     = "eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.32"

  vpc_config {
    subnet_ids         = [aws_subnet.eks_private_a.id, aws_subnet.eks_private_b.id]
    security_group_ids = [aws_security_group.eks_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy]
}

data "aws_iam_policy_document" "eks_node_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node_role" {
  name               = "eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.eks_private_a.id, aws_subnet.eks_private_b.id]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.18.1-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.4"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.32.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}



# Management EC2 Instance IAM Role and Profile for SSM and EKS access
data "aws_iam_policy_document" "mgmt_vm_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mgmt_vm_role" {
  name               = "eks-mgmt-vm-role"
  assume_role_policy = data.aws_iam_policy_document.mgmt_vm_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "mgmt_vm_ssm" {
  role       = aws_iam_role.mgmt_vm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "mgmt_vm_eks_access" {
  role       = aws_iam_role.mgmt_vm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_instance_profile" "mgmt_vm_profile" {
  name = "eks-mgmt-vm-profile"
  role = aws_iam_role.mgmt_vm_role.name
}

# Use latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "eks_mgmt" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.eks_private_a.id
  vpc_security_group_ids = [aws_security_group.eks_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.mgmt_vm_profile.name

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y curl unzip

# Install kubectl
curl -o /usr/local/bin/kubectl -LO "https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.0/2024-06-13/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin

# Setup kubeconfig for EKS cluster
export AWS_REGION=us-east-1
export CLUSTER_NAME=eks-cluster
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
EOF

  tags = { Name = "eks-mgmt-vm" }
