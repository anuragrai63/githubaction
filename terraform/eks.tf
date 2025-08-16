resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat([for s in aws_subnet.public  : s.id], [for s in aws_subnet.private : s.id])
    endpoint_public_access  = true
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = { Name = var.cluster_name }
}


resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "primary"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  version         = var.kubernetes_version

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  capacity_type  = "ON_DEMAND"
  instance_types = [var.node_instance_type]

  remote_access { # not opening SSH; left unset
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_openid_connect_provider.eks]
}

# Trust policy helper
locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  oidc_url          = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# EBS CSI Driver
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = local.oidc_provider_arn },
      Action   = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ebs_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# EFS CSI Driver
resource "aws_iam_role" "efs_csi" {
  name = "${var.cluster_name}-efs-csi-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = local.oidc_provider_arn },
      Action   = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" : "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "efs_policy" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# CloudWatch logs via aws-for-fluent-bit add-on
resource "aws_iam_role" "fluentbit" {
  name = "${var.cluster_name}-aws-for-fluent-bit-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = local.oidc_provider_arn },
      Action   = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" : "system:serviceaccount:aws-for-fluent-bit:aws-for-fluent-bit"
        }
      }
    }]
  })
}
# Permissions for logs and metrics
resource "aws_iam_role_policy_attachment" "fluentbit_cw" {
  role       = aws_iam_role.fluentbit.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

###############################################
# addons.tf (EKS Managed Add-ons)
###############################################
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-efs-csi-driver"
  service_account_role_arn = aws_iam_role.efs_csi.arn
}

resource "aws_eks_addon" "aws_for_fluent_bit" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-for-fluent-bit"
  service_account_role_arn = aws_iam_role.fluentbit.arn
}

###############################################
# metrics-server via Helm (not an EKS managed add-on)
###############################################
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "kubernetes_namespace" "metrics_server" {
  metadata { name = "kube-system" }
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"
  values     = [yamlencode({
    args = [
      "--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP",
      "--kubelet-insecure-tls"
    ]
  })]
  depends_on = [aws_eks_node_group.this]
}
