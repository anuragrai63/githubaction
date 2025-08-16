output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "kubeconfig_command" {
  description = "Run to configure kubectl on your machine/bastion"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
