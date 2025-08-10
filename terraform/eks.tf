resource aws_vpc "eks_vpc" {
  cidr_block = "172.16.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "-eks-vpc"
    "kubernetes.io/cluster/eks-cluster" = "shared"
  }
}

resource "aws_subnet" "eks_subnet-a" {
  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "172.16.10.0/24"
  availability_zone = "us-east-1a"  
  map_public_ip_on_launch = true
  tags = {
    Name = "pub-eks-subnet-a"
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"   = "1"
      Type                     = "Public"
    }
  }

  resource "aws_subnet" "eks_subnet-b" {
  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "172.16.20.0/24"
  availability_zone = "us-east-1b"  
  map_public_ip_on_launch = true
  tags = {
    Name = "pub-eks-subnet-b"
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"  = "1"
      Type     = "Public"
    }
  }

resource "aws_subnet" "eks_subnet-priv-a" {
  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "172.16.30.0/24"
  availability_zone = "us-east-1a"  
  map_public_ip_on_launch = true
  tags = {
    Name = "priv-eks-subnet-a"
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"   = "1"
      Type                     = "Private"
    }
  }

  resource "aws_subnet" "eks_subnet-priv-b" {
  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "172.16.40.0/24"
  availability_zone = "us-east-1b"  
  map_public_ip_on_launch = true
  tags = {
    Name = "priv-eks-subnet-b"
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"  = "1"
      Type     = "Private"
    }
  }

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  } 
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "eks-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc_a" {
  subnet_id      = aws_subnet.eks_subnet-a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_rt_assoc_b" {
  subnet_id      = aws_subnet.eks_subnet-b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_nat_gateway" "nat-gateway_id" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.eks_subnet-a.id

  tags = {
    Name = "eks-nat-gateway"
  }   
  
}
resource "aws_eip" "nat_eip" {

  tags = {
    Name = "eks-nat-eip"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateway_id.id
  }
  tags = {
    Name = "eks-private-rt"
  }
}

resource "aws_route_table_association" "private_rt_assoc_a" {
  subnet_id      = aws_subnet.eks_subnet-priv-a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_rt_assoc_b" {
  subnet_id      = aws_subnet.eks_subnet-priv-b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "eks-cluster-role"
  }     
  
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_VPCResourceController"
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_cluster" "eks-cluster" {
  name     = "eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version = 1.32

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_subnet-a.id,
      aws_subnet.eks_subnet-b.id,
      aws_subnet.eks_subnet-priv-a.id,
      aws_subnet.eks_subnet-priv-b.id
    ]
    endpoint_public_access = true
    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.ssm_policy
  ]

  tags = {
    Name = "eks-cluster"
  }
  
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_cluster_role.arn
  subnet_ids      = [
    aws_subnet.eks_subnet-priv-a.id,
    aws_subnet.eks_subnet-priv-b.id
  ]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  
  instance_types = ["t3.medium"]

  tags = {
    Name = "eks-node-group"
  }
  
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.eks-cluster.name
  addon_name   = "vpc-cni"

  tags = {
    Name = "eks-vpc-cni-addon"
  }
  
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.eks-cluster.name
  addon_name   = "coredns"

  tags = {
    Name = "eks-coredns-addon"
  }
  
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.eks-cluster.name
  addon_name   = "kube-proxy"

  tags = {
    Name = "eks-kube-proxy-addon"
  }
  
}


  
resource "aws_iam_role" "bastion_role" {
  name = "eks-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "eks-bastion-role"
  }     
  
}

resource "aws_iam_policy_attachment" "full_access" {
  name       = "eks-bastion-full-access"
  roles      = [aws_iam_role.bastion_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.eks_subnet-a.id
  iam_instance_profile = aws_iam_role.bastion_role.name

  tags = {
    Name = "eks-bastion-host"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y aws-cli
              curl -LO https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.3/2025-04-17/bin/linux/amd64/kubectl
              chmod +x ./kubectl
              mv ./kubectl /usr/local/bin/kubectl
              yum install -y amazon-ssm-agent
              systemctl start amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              aws eks update-kubeconfig --region us-east-1 --name eks-cluster
              EOF

  depends_on = [aws_iam_role_policy_attachment.full_access, aws_eks_cluster.eks-cluster]
}

resource "aws_security_group" "bastion_sg" {
  name        = "eks-bastion-sg"
  description = "Security group for EKS bastion host"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0/0"] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0/0"]
  }
}