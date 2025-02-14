# Define the AWS region variable
variable "region" {
  default     = "us-east-1"
  description = "AWS region"
}

# Configure the AWS provider with the specified region
provider "aws" {
  region = var.region
}

# Create the VPC
resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/16"
}

# Create the Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

# Define public subnets
resource "aws_subnet" "pub_sub1" {
  cidr_block          = "192.168.1.0/24"
  availability_zone   = "us-east-1a"
  vpc_id              = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/ed-eks-01" = "shared"
  }
}

resource "aws_subnet" "pub_sub2" {
  cidr_block          = "192.168.2.0/24"
  availability_zone   = "us-east-1b"
  vpc_id              = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/ed-eks-01" = "shared"
  }
}

# Create route tables for public subnets
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.vpc.id
}

# Associate route tables with subnets
resource "aws_route_table_association" "pub-sub1-rt-association" {
  subnet_id      = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "pub-sub2-rt-association" {
  subnet_id      = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub_rt.id
}

# Create a route for the public route table to the internet gateway
resource "aws_route" "pub-rt" {
  route_table_id            = aws_route_table.pub_rt.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.igw.id
}

# Define IAM roles for EKS
resource "aws_iam_role" "master" {
  name               = "ed-eks-master"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "eks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role" "worker" {
  name               = "ed-eks-worker"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

# Define IAM policies for worker role
resource "aws_iam_policy" "autoscaler" {
  name   = "ed-eks-autoscaler-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action"   : [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeTags",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ],
        "Effect"   : "Allow",
        "Resource" : "*"
      }
    ]
  })
}

# Attach IAM policies to worker role
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AWSXRayDaemonWriteAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonS3ReadOnlyAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.worker.name
}

# Create IAM instance profile for worker nodes
resource "aws_iam_instance_profile" "worker" {
  name = "ed-eks-worker-profile"
  role = aws_iam_role.worker.name
}

# Define security group for EKS nodes
resource "aws_security_group" "node" {
  name        = "ed-eks-node-sg"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH access from anywhere"
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
}

# Create EKS cluster
resource "aws_eks_cluster" "eks" {
  name     = "ed-eks-01"
  version  = "1.28"
  role_arn = aws_iam_role.master.arn

  vpc_config {
    subnet_ids = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]
  }
}

# Create Node Group for EKS
resource "aws_eks_node_group" "web-app" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "web1"
  node_role_arn   = aws_iam_role.worker.arn
  subnet_ids      = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]
  capacity_type   = "ON_DEMAND"
  disk_size       = 10
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  remote_access {
    ec2_ssh_key = "eks"  // Ensure this matches the exact name of the SSH key pair in your AWS account
    source_security_group_ids = [aws_security_group.node.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonSSMManagedInstanceCore,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_subnet.pub_sub1,
    aws_subnet.pub_sub2,
  ]
}

output "endpoint" {
  value = aws_eks_cluster.eks.endpoint
}