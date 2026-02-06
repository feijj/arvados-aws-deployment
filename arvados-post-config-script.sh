# Arvados POC 部署后配置脚本

此脚本用于在基础环境部署完成后，继续完成Arvados的详细配置。

```bash
#!/bin/bash

# Arvados POC环境详细配置脚本
# 在基础环境部署完成后运行此脚本

set -e

echo "=== Arvados POC环境详细配置 ==="

# 检查必要工具
for cmd in ssh scp; do
  if ! command -v $cmd &> /dev/null; then
    echo "错误: 未找到 $cmd，请先安装"
    exit 1
  fi
done

# 获取用户输入
read -p "请输入EC2实例的公网IP: " INSTANCE_IP
read -p "请输入SSH密钥文件路径: " SSH_KEY_PATH
read -p "请输入Arvados集群ID (5位字母数字): " CLUSTER_ID
read -p "请输入基础域名 (如 example.com): " BASE_DOMAIN

# 验证输入
if [[ ! $CLUSTER_ID =~ ^[a-z0-9]{5}$ ]]; then
    echo "错误: 集群ID必须是5位小写字母数字"
    exit 1
fi

# 创建配置文件
CONFIG_DIR="arvados-config-$(date +%Y%m%d-%H%M%S)"
mkdir -p $CONFIG_DIR
cd $CONFIG_DIR

# 创建Arvados配置文件
cat > arvados-config.yml << EOF
# Arvados配置文件
Clusters:
  $CLUSTER_ID:
    # 系统根令牌 - 使用至少50个随机字符
    SystemRootToken: "$(openssl rand -hex 32)"
    
    # 管理令牌
    ManagementToken: "$(openssl rand -hex 20)"
    
    # 服务配置
    Services:
      RailsAPI:
        InternalURLs:
          "https://$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://$CLUSTER_ID.$BASE_DOMAIN"
        
      Controller:
        InternalURLs:
          "https://$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://$CLUSTER_ID.$BASE_DOMAIN"
        
      Websocket:
        InternalURLs:
          "wss://ws.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "wss://ws.$CLUSTER_ID.$BASE_DOMAIN"
        
      Keepbalance:
        InternalURLs:
          "https://$CLUSTER_ID.$BASE_DOMAIN/keep-balance": {}
        ExternalURL: "https://$CLUSTER_ID.$BASE_DOMAIN/keep-balance"
        
      Keepproxy:
        InternalURLs:
          "https://keep.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://keep.$CLUSTER_ID.$BASE_DOMAIN"
        
      WebDAV:
        InternalURLs:
          "https://collections.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://collections.$CLUSTER_ID.$BASE_DOMAIN"
        
      WebDAVDownload:
        InternalURLs:
          "https://download.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://download.$CLUSTER_ID.$BASE_DOMAIN"
        
      Keepstore:
        InternalURLs:
          "https://keep0.$CLUSTER_ID.$BASE_DOMAIN": {}
          "https://keep1.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://keep.$CLUSTER_ID.$BASE_DOMAIN"
        
      Workbench2:
        InternalURLs:
          "https://workbench2.$CLUSTER_ID.$BASE_DOMAIN": {}
        ExternalURL: "https://workbench2.$CLUSTER_ID.$BASE_DOMAIN"
          
    PostgreSQL:
      ConnectionPool: 32
      Connection:
        host: "localhost"
        port: "5432"
        user: "arvados"
        password: "arvados123"
        dbname: "arvados"
        
    API:
      MaxTokenLifetime: 0s
      MaxRequestSize: 134217728
      MaxIndexDatabaseRead: 134217728
      MaxItemsPerResponse: 1000
      MaxConcurrentRequests: 64
      MaxConcurrentRailsRequests: 8
      
    Collections:
      BlobSigning: true
      BlobSigningKey: "$(openssl rand -hex 32)"
      BlobTrash: true
      BlobTrashLifetime: 336h
      DefaultReplication: 2
      BlobSigningTTL: 336h
EOF

# 创建Nginx配置
cat > nginx-config.conf << EOF
# Nginx配置文件
server {
    listen 80;
    server_name $CLUSTER_ID.$BASE_DOMAIN;
    
    # 重定向到HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $CLUSTER_ID.$BASE_DOMAIN;
    
    ssl_certificate /etc/ssl/certs/arvados.crt;
    ssl_certificate_key /etc/ssl/private/arvados.key;
    
    location / {
        proxy_pass http://127.0.0.1:9001;  # API服务器
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl http2;
    server_name ws.$CLUSTER_ID.$BASE_DOMAIN;
    
    ssl_certificate /etc/ssl/certs/arvados.crt;
    ssl_certificate_key /etc/ssl/private/arvados.key;
    
    location / {
        proxy_pass http://127.0.0.1:9002;  # WebSocket服务器
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 443 ssl http2;
    server_name keep.$CLUSTER_ID.$BASE_DOMAIN;
    
    ssl_certificate /etc/ssl/certs/arvados.crt;
    ssl_certificate_key /etc/ssl/private/arvados.key;
    
    location / {
        proxy_pass http://127.0.0.1:9003;  # Keepproxy服务器
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl http2;
    server_name download.$CLUSTER_ID.$BASE_DOMAIN;
    
    ssl_certificate /etc/ssl/certs/arvados.crt;
    ssl_certificate_key /etc/ssl/private/arvados.key;
    
    location / {
        proxy_pass http://127.0.0.1:9004;  # Keep-web服务器
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl http2;
    server_name workbench2.$CLUSTER_ID.$BASE_DOMAIN;
    
    ssl_certificate /etc/ssl/certs/arvados.crt;
    ssl_certificate_key /etc/ssl/private/arvados.key;
    
    location / {
        proxy_pass http://127.0.0.1:9005;  # Workbench2
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 创建安装检查脚本
cat > check-installation.sh << 'EOF'
#!/bin/bash

echo "检查Arvados安装状态..."

# 检查安装是否完成
if [ -f /opt/arvados/SETUP_COMPLETE ]; then
    echo "✓ Arvados基础安装完成"
else
    echo "✗ Arvados基础安装未完成，请等待安装完成后再运行此脚本"
    exit 1
fi

# 检查PostgreSQL
if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
    echo "✓ PostgreSQL服务正常"
else
    echo "✗ PostgreSQL服务异常"
    exit 1
fi

# 检查Docker
if systemctl is-active --quiet docker; then
    echo "✓ Docker服务正常"
else
    echo "✗ Docker服务异常"
    exit 1
fi

echo "所有服务检查通过，可以继续配置Arvados"
EOF

# 创建配置应用脚本
cat > apply-config.sh << EOF
#!/bin/bash

echo "应用Arvados配置..."

# 复制配置文件到正确位置
sudo mkdir -p /etc/arvados
sudo cp arvados-config.yml /etc/arvados/config.yml
sudo chown root:root /etc/arvados/config.yml
sudo chmod 644 /etc/arvados/config.yml

# 复制Nginx配置
sudo cp nginx-config.conf /etc/nginx/conf.d/arvados.conf

# 重启相关服务
sudo systemctl reload nginx

echo "配置已应用"
EOF

# 上传配置文件到远程服务器
echo "上传配置文件到远程服务器..."
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no arvados-config.yml ec2-user@$INSTANCE_IP:/tmp/
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no nginx-config.conf ec2-user@$INSTANCE_IP:/tmp/
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no check-installation.sh ec2-user@$INSTANCE_IP:/tmp/
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no apply-config.sh ec2-user@$INSTANCE_IP:/tmp/

# 在远程服务器上执行配置
echo "在远程服务器上执行配置步骤..."
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP << 'REMOTE_SCRIPT'
#!/bin/bash

echo "检查安装状态..."
if [ -f /opt/arvados/SETUP_COMPLETE ]; then
    echo "Arvados基础安装已完成"
else
    echo "等待Arvados基础安装完成..."
    while [ ! -f /opt/arvados/SETUP_COMPLETE ]; do
        echo -n "."
        sleep 10
    done
    echo
    echo "Arvados基础安装已完成"
fi

echo "等待PostgreSQL服务完全启动..."
sleep 30

# 检查安装状态
chmod +x /tmp/check-installation.sh
/tmp/check-installation.sh

# 应用配置
chmod +x /tmp/apply-config.sh
/tmp/apply-config.sh

# 生成自签名SSL证书（仅用于POC）
if [ ! -f /etc/ssl/certs/arvados.crt ]; then
    echo "生成自签名SSL证书..."
    sudo mkdir -p /etc/ssl/certs /etc/ssl/private
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/arvados.key \
        -out /etc/ssl/certs/arvados.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$HOSTNAME" \
        -addext "subjectAltName = DNS:$HOSTNAME,DNS:keep.$HOSTNAME,DNS:download.$HOSTNAME,DNS:ws.$HOSTNAME"
fi

# 重启Nginx
sudo systemctl restart nginx

echo "Arvados POC配置完成！"
echo ""
echo "服务状态检查："
echo "PostgreSQL: $(systemctl is-active postgresql)"
echo "Docker: $(systemctl is-active docker)"
echo "Nginx: $(systemctl is-active nginx)"
echo ""
echo "接下来的步骤："
echo "1. 配置DNS指向实例IP，或使用IP访问"
echo "2. 访问 https://workbench2.yourdomain.com (如果配置了域名)"
echo "3. 或使用IP访问: https://your.ip.address"
echo ""
echo "初始管理员账户将在首次访问时创建"
echo "查看安装日志: sudo tail -f /var/log/arvados-install.log"
REMOTE_SCRIPT

echo "=== Arvados POC配置完成 ==="
echo "请按照以下步骤完成最终设置："
echo ""
echo "1. 确保域名解析已指向实例IP，或使用IP地址访问"
echo "2. 访问 https://workbench2.$CLUSTER_ID.$BASE_DOMAIN"
echo "3. 或使用IP访问: https://$INSTANCE_IP"
echo ""
echo "注意：首次访问可能需要几分钟时间让所有服务完全启动"
echo ""
echo "查看详细日志："
echo "ssh -i $SSH_KEY_PATH ec2-user@$INSTANCE_IP"
echo "sudo tail -f /var/log/arvados-install.log"