# EKS Cluster Role
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
}

# Attach required policies to cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node Role
resource "aws_iam_role" "eks_node_role" {
    name = "eks-node-role"

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
}

# Attach required policies to node role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    role       = aws_iam_role.eks_node_role.name
}
# EKS Node Instance Profile
resource "aws_iam_instance_profile" "eks_node_instance_profile" {
    name = "eks-node-instance-profile"
    role = aws_iam_role.eks_node_role.name
}
