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

provider "aws" {
  region = "us-east-1"
}

