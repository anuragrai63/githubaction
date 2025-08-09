terraform {
  required_version = "~> 1.2.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45"
    }
  }
  backend "s3" {}
}

resource "aws_ssm_parameter" "foo" {
  name  = "foo"
  type  = "String"
  value = "barr"
}

resource "aws_instance" "vs-test" {
    ami = "ami-00beae93a2d981137"
    instance_type = "t2.micro"
    subnet_id = "subnet-0d0e3828e26eb661c"
    availability_zone = "us-east-1d"
    tags = {
      "Name" = "VS-instance"
    }
  
}

