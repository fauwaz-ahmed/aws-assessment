# Configure the AWS Provider
provider "aws" {
  region = "us-east-1" # Set your desired region
}

# Fetch the first two available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_a = data.aws_availability_zones.available.names[0]
  az_b = data.aws_availability_zones.available.names[1]
  prefix = "FirstName_Lastname" # !!! IMPORTANT: Replace with your actual name
}

# --- 1. Create 1 VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-VPC" }
}

# --- 4. Attach an Internet Gateway (IGW) ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.prefix}-IGW" }
}

# --- 2. Create 2 Public Subnets ---
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = count.index == 0 ? "10.0.1.0/24" : "10.0.2.0/24"
  availability_zone       = count.index == 0 ? local.az_a : local.az_b
  map_public_ip_on_launch = true # Public subnets should auto-assign public IPs

  tags = { Name = "${local.prefix}-Public-Subnet-${count.index + 1}" }
}

# --- 3. Create 2 Private Subnets ---
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = count.index == 0 ? "10.0.11.0/24" : "10.0.12.0/24"
  availability_zone = count.index == 0 ? local.az_a : local.az_b

  tags = { Name = "${local.prefix}-Private-Subnet-${count.index + 1}" }
}

# --- 5. Configure NAT Gateway for private subnet outbound access ---

# EIP is required for the Public NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "${local.prefix}-NAT-EIP" }
}

# Create the NAT Gateway in the first Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]

  tags = { Name = "${local.prefix}-NAT-GW" }
}

# --- Route Tables ---

# Public Route Table (Route to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.prefix}-Public-RT" }
}

# Private Route Table (Route to NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = { Name = "${local.prefix}-Private-RT" }
}

# --- Route Table Associations ---

# Associate Public Route Table with Public Subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate Private Route Table with Private Subnets
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
