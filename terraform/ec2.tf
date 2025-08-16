resource "aws_instance" "my-eks-mgmt" {
  ami                         = "ami-0de716d6197524dd9"
  associate_public_ip_address = "true"
  availability_zone           = "us-east-1b"
  instance_type               = "t3.medium"
  vpc_security_group_ids = [aws_security_group.eks_mgmt_sg.id]

  root_block_device {
    delete_on_termination = "true"
    encrypted             = "false"
    iops                  = "3000"
    throughput            = "125"
    volume_size           = "8"
    volume_type           = "gp3"
  }
    user_data = templatefile("bastion_userdata.sh", {
        cluster = "my-eks-demo"
    })
  subnet_id         = "${aws_subnet.eks_pb_b.id}"
  depends_on = [ aws_eks_cluster.my-eks-demo ]

  tags = {
    Name = "my-eks-mgmt"
  }

}

resource "aws_security_group" "eks_mgmt_sg" {
    name        = "eks_mgmt_sg"
    description = "Security group for EKS management instance"
    vpc_id      = aws_vpc.eks_vpc.id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "eks_mgmt_sg"
    }
}