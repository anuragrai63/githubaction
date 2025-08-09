resource "aws_instance" "ec2" {
  disable_api_termination = "true"

  ami = var.ami_id
  instance_type = var.instance_type

  subnet_id = var.subnet_id
  vpc_security_group_ids = var.security_group_id
  user_data = templatefile("userdata.tftpl", {
    cluster = var.cluster
  })  

  iam_instance_profile = var.iam_instance_profile

  root_block_device {
    volume_size = "${var.volume_size}"
    delete_on_termination = true
  }

  tags = {
      Name = "${var.projectparam}-${var.envparam}-mgmt",
      BackUpSchedule = "Daily"
  }
}

