# Arvados AWS部署命令序列

此文档提供使用AWS CLI和Terraform部署Arvados的完整命令序列。

## 第一部分：基础环境准备

### 1. 创建VPC
```bash
# 创建VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=arvados-poc-vpc}]')
echo "VPC ID: $VPC_ID"

# 启用DNS主机名
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
```

### 2. 创建互联网网关
```bash
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=arvados-poc-igw}]')
echo "Internet Gateway ID: $IGW_ID"

# 将互联网网关附加到VPC
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

### 3. 创建子网
```bash
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-west-2a --query 'Subnet.SubnetId' --output text --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=arvados-poc-public}]')
echo "Subnet ID: $SUBNET_ID"
```

### 4. 创建路由表
```bash
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=arvados-poc-rt}]')
echo "Route Table ID: $ROUTE_TABLE_ID"

# 添加默认路由到互联网网关
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# 将子网关联到路由表
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $SUBNET_ID
```

### 5. 创建安全组
```bash
SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name arvados-poc-sg --description "Security group for Arvados POC" --vpc-id $VPC_ID --query 'GroupId' --output text)
echo "Security Group ID: $SECURITY_GROUP_ID"

# 添加入站规则
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
```

### 6. 创建EBS卷
```bash
EBS_VOLUME_ID=$(aws ec2 create-volume --availability-zone us-west-2a --size 100 --volume-type gp3 --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=arvados-poc-data}]' --query 'VolumeId' --output text)
echo "EBS Volume ID: $EBS_VOLUME_ID"

# 等待卷变为可用
aws ec2 wait volume-available --volume-ids $EBS_VOLUME_ID
```

## 第二部分：启动EC2实例

### 7. 启动EC2实例
```bash
# 创建用户数据脚本
cat > user-data.txt << 'EOF'
#!/bin/bash
set -e

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

Installation logs: /var/log/arvados-install.log
Setup status: /opt/arvados/SETUP_COMPLETE

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

# 启动EC2实例
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --count 1 \
  --instance-type m5.xlarge \
  --key-name YOUR_KEY_PAIR_NAME \
  --security-group-ids $SECURITY_GROUP_ID \
  --subnet-id $SUBNET_ID \
  --user-data file://user-data.txt \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=arvados-poc-server}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance ID: $INSTANCE_ID"

# 等待实例运行
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
```

### 8. 挂载EBS卷到实例
```bash
# 挂载EBS卷到实例
aws ec2 attach-volume --volume-id $EBS_VOLUME_ID --instance-id $INSTANCE_ID --device /dev/sdf

# 等待卷附加
aws ec2 wait volume-in-use --volume-ids $EBS_VOLUME_ID
```

### 9. 获取实例信息
```bash
# 获取公共IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Arvados POC instance is running at: $PUBLIC_IP"

# 获取实例详细信息
aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,State:State.Name}' --output table
```

## 第三部分：部署后配置

### 10. 连接到实例并完成配置
```bash
# 等待实例完全启动并完成初步配置
echo "等待实例启动和软件安装完成（可能需要5-10分钟）..."
sleep 300

# 检查安装状态（通过SSH连接）
# ssh -i your-private-key.pem ec2-user@$PUBLIC_IP 'ls -la /opt/arvados/SETUP_COMPLETE'
```

## 第四部分：清理用户数据文件
```bash
rm user-data.txt
```

## 使用说明

1. 将此脚本保存为 `arvados-deploy.sh`
2. 替换 `YOUR_KEY_PAIR_NAME` 为您实际的密钥对名称
3. 确保您已通过 `aws configure` 配置了AWS凭证
4. 运行脚本: `chmod +x arvados-deploy.sh && ./arvados-deploy.sh`

注意：此脚本创建的是基础环境，实际的Arvados配置需要在实例启动后通过SSH连接完成。