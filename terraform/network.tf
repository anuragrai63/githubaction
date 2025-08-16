resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${var.cluster_name}-igw" }
}

# Public subnets (2)
resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : idx => az }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.key)           # 10.0.0.0/24, 10.0.1.0/24
  map_public_ip_on_launch = true

  tags = {
    Name                                     = "${var.cluster_name}-public-${each.value}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                  = 1
  }
}

# Private subnets (2)
resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : idx => az }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.key + 10)            # 10.0.10.0/24, 10.0.11.0/24

  tags = {
    Name                                         = "${var.cluster_name}-private-${each.value}"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

# NAT per AZ
resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain   = "vpc"
  tags     = { Name = "${var.cluster_name}-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = "${var.cluster_name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.cluster_name}-public-rt" }
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.cluster_name}-private-rt-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each               = aws_nat_gateway.this
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# EKS cluster SG (control plane)
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-cluster-sg" }
}

# Node SG
resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Worker nodes"
  vpc_id      = aws_vpc.this.id

  ingress { # kubelet from control plane
    description              = "Kubelet from control plane"
    from_port                = 10250
    to_port                  = 10250
    protocol                 = "tcp"
    security_groups          = [aws_security_group.eks_cluster.id]
  }

  ingress { # allow node-to-node
    description = "Node to node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-node-sg" }
}

# Rules for control plane <-> nodes on 443
resource "aws_security_group_rule" "cp_ingress_from_nodes_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.node.id
  description              = "API server inbound from nodes"
}
