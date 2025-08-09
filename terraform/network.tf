

resource "aws_vpc" "vpc" {
  cidr_block = "10.20.0.0/16"
  enable_dns_support = "true" 
  enable_dns_hostnames = "true"

  tags = {
      Name = "EKS-Demo"
  }
}


resource "aws_subnet" "private_subnet_a" {
  
  vpc_id                    = aws_vpc.vpc.id
  cidr_block                = "10.20.1.0/24"
  availability_zone         = "us-east-1a"
  map_public_ip_on_launch   = false

  tags = {
    Name = "eks-private-a"
    "kubernetes.io/cluster/num-mgmt-prod-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_subnet_b" {
  
  vpc_id                    = aws_vpc.vpc.id
  cidr_block                = "10.20.2.0/24"
  availability_zone         = "us-east-1b"
  map_public_ip_on_launch   = false

  tags = {
    Name = "eks-private-b"
    "kubernetes.io/cluster/num-mgmt-prod-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public_subnet_a" {
  
  vpc_id                    = aws_vpc.vpc.id
  cidr_block                = "10.20.3.0/24"
  availability_zone         = "us-east-1a"
  map_public_ip_on_launch   = true

  tags = {
    Name = "eks-public-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
  
  vpc_id                    = aws_vpc.vpc.id
  cidr_block                = "10.20.4.0/24"
  availability_zone         = "us-east-1b"
  map_public_ip_on_launch   = true

  tags = {
    Name = "eks-public-b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "eks-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "eks-public-route-table"
  }
}


resource "aws_route_table" "private" {
  
    vpc_id = aws_vpc.vpc.id
    
    route {
        cidr_block = "0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat.id
    }
    
    tags = {
        Name = "eks-private-route-table"
    }
    }

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet_a.id     
    depends_on = [aws_internet_gateway.igw]
    tags = {
        Name = "eks-nat-gateway"
    }
}

resource "aws_route_table_association" "public_rt_a" {  
    subnet_id      = aws_subnet.public_subnet_a.id
    route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_rt_b" {  
    subnet_id      = aws_subnet.public_subnet_b.id
    route_table_id = aws_route_table.public_route_table.id
  
}
resource "aws_route_table_association" "private_rt_a" {  
    subnet_id      = aws_subnet.private_subnet_a.id
    route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_rt_b" {  
    subnet_id      = aws_subnet.private_subnet_b.id
    route_table_id = aws_route_table.private.id
  
}
resource "aws_eip" "nat" {

  tags = {
    Name = "eks-nat-eip"
  }
}
