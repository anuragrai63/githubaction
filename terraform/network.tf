resource "aws_vpc" "eks_vpc" {
  cidr_block                           = "172.16.0.0/16"
  enable_dns_hostnames                 = "true"
  enable_dns_support                   = "true"
  
  tags = {
    Name = "my-vpc-eks"
  }

}

resource "aws_subnet" "eks_pb_a" {
  cidr_block                                     = "172.16.10.0/24"
  vpc_id                                         = aws_vpc.eks_vpc.id
  map_public_ip_on_launch                        = "true"
  availability_zone                              = "us-east-1a"

  tags = {
    Name = "pub-eks-subnet-a"
  }

    tags_all = {
        Name = "pub-eks-subnet-a"
        "kubernetes.io/cluster/eks-cluster" = "shared"
        "kubernetes.io/role/elb"   = "1"
        Type                     = "Public"
    }
}

resource "aws_subnet" "eks_pb_b" {
  cidr_block                                     = "172.16.20.0/24"
  vpc_id                                         = aws_vpc.eks_vpc.id
  map_public_ip_on_launch                        = "true"
  availability_zone                              = "us-east-1b"

  tags = {
    Name = "pub-eks-subnet-b"
  }

    tags_all = {
        Name = "pub-eks-subnet-b"
        "kubernetes.io/cluster/eks-cluster" = "shared"
        "kubernetes.io/role/elb"   = "1"
        Type                     = "Public"
    }
}


resource "aws_subnet" "eks_pr_a" {
  cidr_block                                     = "172.16.30.0/24"
  vpc_id                                         = aws_vpc.eks_vpc.id
  availability_zone                              = "us-east-1a"

  tags = {
    Name = "pr-eks-subnet-a"
  }

}

resource "aws_subnet" "eks_pr_b" {
  cidr_block                                     = "172.16.40.0/24"
  vpc_id                                         = aws_vpc.eks_vpc.id
  availability_zone                              = "us-east-1b"

  tags = {
    Name = "pr-eks-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
    vpc_id = aws_vpc.eks_vpc.id

    tags = {
        Name = "eks-igw"
    }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_a" {
    domain = "vpc"
    tags = {
        Name = "nat-a"
    }
}

resource "aws_eip" "nat_b" {
    domain = "vpc"
    tags = {
        Name = "nat-b"
    }
}

# NAT Gateways
resource "aws_nat_gateway" "nat_gw_a" {
    allocation_id = aws_eip.nat_a.id
    subnet_id     = aws_subnet.eks_pb_a.id

    tags = {
        Name = "nat-gw-a"
    }
}

resource "aws_nat_gateway" "nat_gw_b" {
    allocation_id = aws_eip.nat_b.id
    subnet_id     = aws_subnet.eks_pb_b.id

    tags = {
        Name = "nat-gw-b"
    }
}

# Route Tables
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.eks_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.eks_igw.id
    }

    tags = {
        Name = "public-rt"
    }
}

resource "aws_route_table" "private_a" {
    vpc_id = aws_vpc.eks_vpc.id

    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat_gw_a.id
    }

    tags = {
        Name = "private-rt-a"
    }
}

resource "aws_route_table" "private_b" {
    vpc_id = aws_vpc.eks_vpc.id

    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat_gw_b.id
    }

    tags = {
        Name = "private-rt-b"
    }
}

# Route Table Associations
resource "aws_route_table_association" "public_a" {
    subnet_id      = aws_subnet.eks_pb_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
    subnet_id      = aws_subnet.eks_pb_b.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
    subnet_id      = aws_subnet.eks_pr_a.id
    route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
    subnet_id      = aws_subnet.eks_pr_b.id
    route_table_id = aws_route_table.private_b.id
}
