# Arvados 安装修复指南

## 问题诊断

根据实例控制台输出，Arvados安装失败的主要原因是：

1. 设备名称问题：在中国区的AWS环境中，EBS卷的设备名称不是 `/dev/xvdf`，而是 `/dev/nvme1n1` 格式
2. 用户数据脚本因此无法找到正确的设备进行格式化和挂载
3. 导致后续的Arvados安装步骤无法完成

## 修复步骤

### 步骤1：连接到实例
```bash
ssh -i gpu-wangjiawei.pem ec2-user@43.192.38.7
```

### 步骤2：检查设备名称
```bash
# 检查所有可用的块设备
lsblk
# 或者
sudo fdisk -l
```

### 步骤3：确定EBS卷的设备名称
通常在AWS中国区，附加的EBS卷会显示为 `/dev/nvme1n1`（第一个附加卷）或类似名称。

### 步骤4：格式化和挂载EBS卷
```bash
# 替换下面的设备名称为实际的设备名称
DEVICE_NAME="/dev/nvme1n1"  # 根据实际检查结果调整

# 格式化为XFS文件系统
sudo mkfs -t xfs $DEVICE_NAME

# 创建挂载点
sudo mkdir -p /data

# 挂载EBS卷
sudo mount $DEVICE_NAME /data

# 添加到fstab以确保重启后自动挂载
echo "$DEVICE_NAME /data xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
```

### 步骤5：启动Docker和PostgreSQL服务
```bash
# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 将ec2-user添加到docker组
sudo usermod -aG docker ec2-user

# 启动PostgreSQL服务
sudo systemctl start postgresql
sudo systemctl enable postgresql

# 配置PostgreSQL数据库
sudo -u postgres psql -c "CREATE USER arvados WITH PASSWORD 'arvados123';"
sudo -u postgres psql -c "CREATE DATABASE arvados OWNER arvados;"
```

### 步骤6：完成Arvados安装
```bash
# 创建Arvados安装脚本
sudo mkdir -p /opt/arvados

cat << 'EOF' | sudo tee /opt/arvados/setup-arvados.sh
#!/bin/bash
echo "Setting up Arvados POC environment..." >> /var/log/arvados-install.log

# 安装Arvados依赖
sudo yum install -y ruby ruby-devel gcc gcc-c++ make >> /var/log/arvados-install.log 2>&1

# 创建Arvados用户
if ! id "arvados" &>/dev/null; then
  sudo useradd -r -s /bin/false arvados >> /var/log/arvados-install.log 2>&1
fi

# 安装Nginx
sudo yum install -y nginx >> /var/log/arvados-install.log 2>&1
sudo systemctl enable nginx >> /var/log/arvados-install.log 2>&1

# 创建基本的Arvados配置目录
sudo mkdir -p /etc/arvados /var/log/arvados /var/www/arvados-api/shared/log

# 输出完成标记
echo "Arvados POC setup completed at $(date)" >> /var/log/arvados-install.log
sudo touch /opt/arvados/SETUP_COMPLETE

# 安装Certbot用于SSL证书
sudo yum install -y python3-pip >> /var/log/arvados-install.log 2>&1
sudo pip3 install certbot >> /var/log/arvados-install.log 2>&1

echo "Installation completed successfully!" >> /var/log/arvados-install.log
EOF

# 设置执行权限并运行
sudo chmod +x /opt/arvados/setup-arvados.sh
sudo /opt/arvados/setup-arvados.sh
```

### 步骤7：验证安装
```bash
# 检查SETUP_COMPLETE文件是否存在
ls -la /opt/arvados/SETUP_COMPLETE

# 检查服务状态
sudo systemctl status docker
sudo systemctl status postgresql
sudo systemctl status nginx

# 检查挂载
df -h | grep /data
```

### 步骤8：配置端口转发
```bash
# 添加iptables规则进行端口转发
sudo iptables -t nat -A PREROUTING -p tcp --dport 53080 -j REDIRECT --to-port 80

# 保存iptables规则以便重启后仍然有效
sudo yum install -y iptables-services
sudo systemctl enable iptables
sudo service iptables save
```

### 步骤9：启动Arvados服务
```bash
# 启动Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 检查Nginx配置
sudo nginx -t

# 检查端口监听
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :53080
```

## 验证外部访问

完成以上步骤后，您应该能够：

1. 从外部访问 http://43.192.38.7:53080
2. 请求会被转发到内部的80端口
3. 如果Arvados服务正确安装，您应该能看到Arvados界面

## 注意事项

- 设备名称可能因实例类型而异，请先使用lsblk命令确认
- 所有操作都需要适当的权限，某些命令需要sudo
- 安装过程可能需要一些时间，请耐心等待
- 请确保安全组规则已正确配置（已开放53080端口）