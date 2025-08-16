resource "aws_eks_cluster" "my-eks-demo" {
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = "true"
  }

  bootstrap_self_managed_addons = "false"

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = "false"
    }

    ip_family         = "ipv4"
    service_ipv4_cidr = aws_vpc.eks_vpc.cidr_block
  }

  name     = "my-eks-demo"
  role_arn = aws_iam_role.eks_cluster_role.arn

  upgrade_policy {
    support_type = "STANDARD"
  }

  version = "1.32"

  vpc_config {
    endpoint_private_access = "true"
    endpoint_public_access  = "true"
    public_access_cidrs     = ["0.0.0.0/0"]
    subnet_ids              = ["${aws_subnet.eks_pr_a.id}", "${aws_subnet.eks_pr_b.id}"]
  }

  zonal_shift_config {
    enabled = "false"
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
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "vpc-cni"
  addon_version = "v1.15.1-eksbuild.1"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "kube-proxy"
  addon_version      = "v1.32.1-eksbuild.1"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "coredns"
  addon_version      = "v1.11.1-eksbuild.4"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "aws-ebs-csi-driver"
  addon_version      = "v1.26.1-eksbuild.1"
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "aws-efs-csi-driver"
  addon_version      = "v1.7.1-eksbuild.1"
}

resource "aws_eks_addon" "container_insights" {
  cluster_name = aws_eks_cluster.my-eks-demo.name
  addon_name   = "amazon-cloudwatch-observability"
  addon_version      = "v1.1.1-eksbuild.1"
}