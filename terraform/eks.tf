resource "aws_eks_cluster" "my-eks-demo" {
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = "true"
  }

  bootstrap_self_managed_addons = "false"
  
  name     = "my-eks-demo"
  role_arn = aws_iam_role.eks_cluster_role.arn

  upgrade_policy {
    support_type = "STANDARD"
  }

  version = "1.32"

  vpc_config {
    endpoint_private_access = "true"
    endpoint_public_access  = "true"  
    subnet_ids              = ["${aws_subnet.eks_pr_a.id}", "${aws_subnet.eks_pr_b.id}"]
  }

  lifecycle {
    ignore_changes = all
  }

}


resource "aws_eks_node_group" "my-eks-ng" {
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  cluster_name    = "${aws_eks_cluster.my-eks-demo.name}"
  disk_size       = "20"
  instance_types  = ["t3.medium"]
  node_group_name = "my-eks-ng"

  node_repair_config {
    enabled = "false"
  }

  node_role_arn   = aws_iam_role.eks_node_role.arn
  release_version = "1.32.7-20250807"

  scaling_config {
    desired_size = "2"
    max_size     = "2"
    min_size     = "2"
  }

  subnet_ids = ["${aws_subnet.eks_pr_a.id}", "${aws_subnet.eks_pr_b.id}"]

  update_config {
    max_unavailable = "1"
  }

  version = "1.32"
  timeouts {
    create = "15m"
    delete = "15m"
    update = "15m"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "vpc-cni"
  addon_version = "v1.15.1-eksbuild.1"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "kube-proxy"
  addon_version      = "v1.32.1-eksbuild.1"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "coredns"
  addon_version      = "v1.11.1-eksbuild.4"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "aws-ebs-csi-driver"
  addon_version      = "v1.26.1-eksbuild.1"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "aws-efs-csi-driver"
  addon_version      = "v1.7.1-eksbuild.1"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}

resource "aws_eks_addon" "container_insights" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "amazon-cloudwatch-observability"
  addon_version      = "v1.1.1-eksbuild.1"
  depends_on = [ aws_eks_node_group.my-eks-ng ]
}


resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "EKS Cluster Security Group"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Allow Kubernetes API from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block] 
  }

  ingress {
    description = "Allow node communication from VPC"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}
