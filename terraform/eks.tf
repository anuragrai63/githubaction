resource "aws_iam_role" "eks_cluster" {
  name = "num-mgmt-prod-eks-cluster-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}



resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonSQSFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "aws_eks" {
  name     = "num-mgmt-prod-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  enabled_cluster_log_types = ["audit"]
  version  = 1.32
  vpc_config {
    subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    endpoint_private_access   = true
    endpoint_public_access    = false
    security_group_ids = [aws_security_group.eks_cluster.id]
  }
 
 depends_on = [
             aws_iam_role.eks_cluster
]
  tags = {
      Name = "mgmt-eks-cluster"
  }  
  
}

data "tls_certificate" "cluster" {
  count = 1
  url   = join("", aws_eks_cluster.aws_eks.*.identity.0.oidc.0.issuer)
}

resource "aws_iam_openid_connect_provider" "default" {
  count = 1
  url   = join("", aws_eks_cluster.aws_eks.*.identity.0.oidc.0.issuer)
  

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [join("", data.tls_certificate.cluster.*.certificates.0.sha1_fingerprint)]
}

resource "aws_iam_role" "eks_nodes" {
  name = "num-mgmt-prod-eks-node-group"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}
resource "aws_iam_role_policy_attachment" "AmazonS3FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.eks_nodes.name
}
resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonSQSFull-Access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy" "sm_policy" {
  name = "SecretsManager_readaccess"
  role = aws_iam_role.eks_nodes.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
                "secretsmanager:GetRandomPassword",
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds",
                "secretsmanager:ListSecrets"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })  

}      

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.aws_eks.name
  node_group_name = "num-mgmt-prod-node"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  instance_types  = ["t3.medium"]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  launch_template {
   name = aws_launch_template.eks_launch_template.name
   version = aws_launch_template.eks_launch_template.latest_version
  }    

  tags = {
      Name = "mgmt-eks-node"
  }  

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}  

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.aws_eks.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.4-eksbuild.10" 
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "vpc-cni" {
  cluster_name                = aws_eks_cluster.aws_eks.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.19.5-eksbuild.1" 
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "kube-proxy" {
  cluster_name                = aws_eks_cluster.aws_eks.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.32.3-eksbuild.7" 
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_launch_template" "eks_launch_template" {
  name = "prod_eks_launch_template"

  lifecycle {
    ignore_changes = [ user_data,latest_version ]
  }

  
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 30
      volume_type = "gp3"

    }
  }

  image_id = "i-0ae66b4aab6fe2362"
#  instance_type = var.instancetype
  user_data = base64encode(templatefile("eks_userdata.tftpl", {
    api_endpoint = aws_eks_cluster.aws_eks.endpoint
    certificate_authority = aws_eks_cluster.aws_eks.certificate_authority[0].data
    cluster = aws_eks_cluster.aws_eks.id
  }))


  tag_specifications {
    resource_type = "instance"

    tags = {
      CreatedBy       = "Terraform"     
    }
  }
}

resource "aws_security_group" "eks_cluster" {
  name        = "prod-num-mgmt-eks-cluster-sg"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.vpc.id

   tags = {
       Name = "mgmt-eks-cluster-sg"
       "kubernetes.io/cluster/num-mgmt-prod-eks-cluster" = "owned"
   }
}

resource "aws_security_group_rule" "cluster_inbound" {
  description              = "Allow worker nodes to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_node.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "cluster_inbound_subnet" {
  description              = "Mgmt Server subnet"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  cidr_blocks = ["10.20.1.0/24"]
  to_port                  = 443
  type                     = "ingress"
}

# Needed for admission controller webhooks for example
resource "aws_security_group_rule" "cluster_outbound" {
  description              = "Allow cluster API Server to communicate with the worker nodes"
  from_port                = 1024
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_node.id
  to_port                  = 65535
  type                     = "egress"
}

resource "aws_security_group_rule" "cluster_outbound_node" {
  description              = "Allow cluster API Server to communicate with the worker nodes on API server extension"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_node.id
  to_port                  = 443
  type                     = "egress"
}

resource "aws_security_group" "eks_node" {
  name        = "prod-num-mgmt-eks-node-sg"
  description = "Worker nodes SG"
  vpc_id      = aws_vpc.vpc.id

   tags = {
       Name = "mgmt-eks-node-sg"
   }
}

resource "aws_security_group_rule" "node_inbound_master" {
  description              = "Allow API Server to communicate with kubelet"
  from_port                = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_cluster.id
  to_port                  = 10250
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_inbound_node_extension" {
  description              = "Master to node on api server extension"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_cluster.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_inbound_webhooks" {
  description              = "Master to node for webhooks"
  from_port                = 1024
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_cluster.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_outbound_master" {
  description              = "Allow egress from nodes to master"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_cluster.id
  to_port                  = 443
  type                     = "egress"
}




resource "aws_security_group_rule" "node_outbound_internet" {
  description       = "Allow unrestricted egress for nodes"
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_node.id
  type              = "egress"
  from_port         = -1
  to_port           = -1
}

resource "aws_security_group_rule" "node_inbound_node" {
  description              = "Allow unrestricted inbound node 2 node"
  protocol                 = "all"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_node.id
  type                     = "ingress"
  from_port                = -1
  to_port                  = -1
}

resource "aws_security_group_rule" "node_outbound_node" {
  description              = "Allow unrestricted outbound node 2 node"
  protocol                 = "all"
  security_group_id        = aws_security_group.eks_node.id
  source_security_group_id = aws_security_group.eks_node.id
  type                     = "egress"
  from_port                = -1
  to_port                  = -1
}
