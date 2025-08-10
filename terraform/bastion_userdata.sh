#!/bin/bash

# Update the system
yum update -y

# Install required packages
yum install -y curl wget git unzip


# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Docker (for building images)
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Configure kubectl for the EKS cluster
mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig --region ${region} --name ${cluster_name} --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

# Create helpful scripts for ec2-user
cat << 'EOF' > /home/ec2-user/update-kubeconfig.sh
#!/bin/bash
aws eks update-kubeconfig --region ${region} --name ${cluster_name}
echo "Kubeconfig updated for cluster: ${cluster_name}"
EOF

cat << 'EOF' > /home/ec2-user/get-cluster-info.sh
#!/bin/bash
echo "=== EKS Cluster Info ==="
kubectl cluster-info
echo ""
echo "=== Nodes ==="
kubectl get nodes
echo ""
echo "=== Pods in all namespaces ==="
kubectl get pods --all-namespaces
EOF

chmod +x /home/ec2-user/*.sh
chown ec2-user:ec2-user /home/ec2-user/*.sh

# Create a welcome message
cat << 'EOF' > /home/ec2-user/README.txt
Welcome to the EKS Bastion Host!

This instance is configured with:
- AWS CLI v2
- kubectl
- eksctl
- helm
- docker

Available scripts:
- ./update-kubeconfig.sh - Updates kubectl configuration for the EKS cluster
- ./get-cluster-info.sh - Shows cluster information and running pods

The kubeconfig is already configured for cluster: ${cluster_name}

To get started:
1. Test cluster access: kubectl get nodes
2. View pods: kubectl get pods --all-namespaces
3. Access via SSM: aws ssm start-session --target $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
EOF

chown ec2-user:ec2-user /home/ec2-user/README.txt

# Install SSM agent (should already be installed on Amazon Linux 2)
yum install -y amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent

echo "Bastion host setup completed successfully!"