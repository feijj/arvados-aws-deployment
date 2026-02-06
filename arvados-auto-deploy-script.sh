# Arvados AWS自动化部署脚本

此脚本可在您的环境中运行，使用您的AWS凭据部署Arvados POC环境。

## 1. 部署脚本

```bash
#!/bin/bash

# Arvados POC环境自动化部署脚本
# 请在具有AWS访问权限的环境中运行此脚本

set -e  # 遇到错误时停止执行

echo "=== Arvados POC环境自动化部署 ==="

# 检查必要工具
echo "检查必要工具..."
for cmd in aws terraform git curl; do
  if ! command -v $cmd &> /dev/null; then
    echo "错误: 未找到 $cmd，请先安装"
    exit 1
  fi
done

echo "所有必要工具已找到"

# 获取用户输入
read -p "请输入您的密钥对名称: " KEY_NAME
read -p "请输入您的域名 (如没有则输入实例IP): " DOMAIN_NAME
read -p "请输入AWS区域 (如 us-west-2): " AWS_REGION

# 设置AWS区域
export AWS_DEFAULT_REGION=$AWS_REGION

# 创建部署目录
DEPLOY_DIR="arvados-poc-$(date +%Y%m%d-%H%M%S)"
mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

echo "在 $DEPLOY_DIR 中创建部署文件"

# 创建variables.tf
cat > variables.tf << 'EOF'
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "availability_zone" {
  description = "Availability Zone"
  type        = string
  default     = "us-west-2a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m5.xlarge"
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Arvados"
  type        = string
}
EOF

# 创建main.tf
cat > main.tf << 'EOF'
provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "arvados_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "arvados-poc-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "arvados_igw" {
  vpc_id = aws_vpc.arvados_vpc.id

  tags = {
    Name = "arvados-poc-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.arvados_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "arvados-poc-public"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.arvados_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.arvados_igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "arvados_sg" {
  name        = "arvados-poc-sg"
  description = "Security group for Arvados POC"
  vpc_id      = aws_vpc.arvados_vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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
    Name = "arvados-poc-sg"
  }
}

# EBS Volume
resource "aws_ebs_volume" "arvados_data" {
  availability_zone = var.availability_zone
  size              = 100
  type              = "gp3"

  tags = {
    Name = "arvados-poc-data"
  }
}

# EC2 Instance
resource "aws_instance" "arvados_server" {
  ami                         = "ami-0c02fb55956c7d316"  # Amazon Linux 2
  instance_type               = var.instance_type
  key_name                   = var.key_name
  vpc_security_group_ids     = [aws_security_group.arvados_sg.id]
  subnet_id                  = aws_subnet.public.id
  user_data                  = base64encode(templatefile("user_data.sh", {
    domain_name = var.domain_name
  }))
  iam_instance_profile       = aws_iam_instance_profile.arvados_profile.name

  tags = {
    Name = "arvados-poc-server"
  }

  depends_on = [
    aws_internet_gateway.arvados_igw
  ]
}

# EBS Volume Attachment
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.arvados_data.id
  instance_id = aws_instance.arvados_server.id
}

# IAM Role for EC2 instance
resource "aws_iam_role" "arvados_role" {
  name = "arvados-poc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "arvados_profile" {
  name = "arvados-poc-profile"
  role = aws_iam_role.arvados_role.name
}
EOF

# 创建outputs.tf
cat > outputs.tf << 'EOF'
output "instance_public_ip" {
  description = "Public IP of the Arvados instance"
  value       = aws_instance.arvados_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the Arvados instance"
  value       = aws_instance.arvados_server.private_ip
}

output "instance_public_dns" {
  description = "Public DNS of the Arvados instance"
  value       = aws_instance.arvados_server.public_dns
}

output "connection_info_file" {
  description = "Path to connection information file on the instance"
  value       = "/home/ec2-user/connection_info.txt"
}
EOF

# 创建user_data.sh模板
cat > user_data.sh << 'EOF'
#!/bin/bash
set -e

# 参数
DOMAIN_NAME=${domain_name}

# 记录开始时间
echo "$(date): Arvados POC installation started" > /var/log/arvados-install.log

# 更新系统
yum update -y >> /var/log/arvados-install.log 2>&1

# 安装必要的包
yum install -y docker git curl wget postgresql postgresql-server postgresql-devel postgresql-contrib >> /var/log/arvados-install.log 2>&1

# 启动服务
systemctl start docker >> /var/log/arvados-install.log 2>&1
systemctl enable docker >> /var/log/arvados-install.log 2>&1

# 添加ec2-user到docker组
usermod -aG docker ec2-user >> /var/log/arvados-install.log 2>&1

# 创建挂载点并挂载EBS卷
mkfs -t xfs /dev/xvdf
mkdir -p /data
mount /dev/xvdf /data
echo '/dev/xvdf /data xfs defaults,nofail 0 2' >> /etc/fstab >> /var/log/arvados-install.log 2>&1

# 安装Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >> /var/log/arvados-install.log 2>&1
chmod +x /usr/local/bin/docker-compose >> /var/log/arvados-install.log 2>&1
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose >> /var/log/arvados-install.log 2>&1

# 初始化PostgreSQL
postgresql-setup initdb >> /var/log/arvados-install.log 2>&1
systemctl start postgresql >> /var/log/arvados-install.log 2>&1
systemctl enable postgresql >> /var/log/arvados-install.log 2>&1

# 配置PostgreSQL
sudo -u postgres psql -c "CREATE USER arvados WITH PASSWORD 'arvados123';" >> /var/log/arvados-install.log 2>&1
sudo -u postgres psql -c "CREATE DATABASE arvados OWNER arvados;" >> /var/log/arvados-install.log 2>&1

# 创建Arvados安装目录
mkdir -p /opt/arvados

# 下载Arvados安装脚本
cat << 'SCRIPT_EOF' > /opt/arvados/setup-arvados.sh
#!/bin/bash
echo "Setting up Arvados POC environment..." >> /var/log/arvados-install.log

# 安装Arvados依赖
yum install -y ruby ruby-devel gcc gcc-c++ make >> /var/log/arvados-install.log 2>&1

# 创建Arvados用户
if ! id "arvados" &>/dev/null; then
  useradd -r -s /bin/false arvados >> /var/log/arvados-install.log 2>&1
fi

# 安装Nginx
yum install -y nginx >> /var/log/arvados-install.log 2>&1
systemctl enable nginx >> /var/log/arvados-install.log 2>&1

# 创建基本的Arvados配置目录
mkdir -p /etc/arvados /var/log/arvados /var/www/arvados-api/shared/log

# 输出完成标记
echo "Arvados POC setup completed at $(date)" >> /var/log/arvados-install.log
touch /opt/arvados/SETUP_COMPLETE

# 安装Certbot用于SSL证书
yum install -y python3-pip >> /var/log/arvados-install.log 2>&1
pip3 install certbot >> /var/log/arvados-install.log 2>&1

echo "Installation completed successfully!" >> /var/log/arvados-install.log
SCRIPT_EOF

chmod +x /opt/arvados/setup-arvados.sh

# 后台运行安装脚本
nohup /opt/arvados/setup-arvados.sh >> /var/log/arvados-install.log 2>&1 &

# 设置防火墙规则
if command -v firewall-cmd &> /dev/null; then
  firewall-cmd --permanent --add-port=80/tcp >> /var/log/arvados-install.log 2>&1
  firewall-cmd --permanent --add-port=443/tcp >> /var/log/arvados-install.log 2>&1
  firewall-cmd --permanent --add-port=22/tcp >> /var/log/arvados-install.log 2>&1
  firewall-cmd --reload >> /var/log/arvados-install.log 2>&1
fi

# 输出连接信息
cat << EOF > /home/ec2-user/connection_info.txt
Arvados POC Environment Setup Information:

Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
Domain: $DOMAIN_NAME

Installation logs: /var/log/arvados-install.log
Setup status: /opt/arvados/SETUP_COMPLETE

Access Workbench at: https://workbench.$DOMAIN_NAME (when configured)
Access API at: https://$DOMAIN_NAME (when configured)

Installation is running in background. Check status with:
  tail -f /var/log/arvados-install.log
  ls -la /opt/arvados/SETUP_COMPLETE (when setup completes)

Default database credentials:
  Database: arvados
  User: arvados
  Password: arvados123

SSH access:
  ssh -i your-key.pem ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
EOF

chown ec2-user:ec2-user /home/ec2-user/connection_info.txt

# 完成
echo "$(date): Arvados POC initialization completed." >> /var/log/arvados-install.log
EOF

# 创建terraform.tfvars
cat > terraform.tfvars << EOF
key_name    = "$KEY_NAME"
domain_name = "$DOMAIN_NAME"
region      = "$AWS_REGION"
EOF

# 初始化Terraform
echo "初始化Terraform..."
terraform init

# 预览部署
echo "预览部署配置..."
terraform plan

# 确认部署
read -p "以上是部署预览，确认部署？(y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "部署已取消"
    exit 0
fi

# 执行部署
echo "开始部署Arvados POC环境..."
terraform apply -auto-approve

echo "=== 部署完成 ==="
echo "部署已在目录 $DEPLOY_DIR 中创建"
echo ""
echo "下一步操作："
echo "1. 访问EC2实例并检查安装状态:"
echo "   ssh -i your-key.pem ec2-user@<PUBLIC_IP>"
echo "   sudo tail -f /var/log/arvados-install.log"
echo ""
echo "2. 检查安装是否完成:"
echo "   ls -la /opt/arvados/SETUP_COMPLETE"
echo ""
echo "3. 查看连接信息:"
echo "   cat /home/ec2-user/connection_info.txt"
echo ""
echo "注意：首次启动可能需要几分钟时间来完成软件安装"