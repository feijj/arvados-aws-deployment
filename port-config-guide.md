# Arvados 端口配置指南

## 端口配置步骤

由于外部无法访问43.192.38.7:53080，需要进行以下配置：

### 1. 首先连接到实例
```bash
ssh -i gpu-wangjiawei.pem ec2-user@43.192.38.7
```

### 2. 配置端口转发
在实例上执行以下命令：

```bash
# 添加iptables规则进行端口转发
sudo iptables -t nat -A PREROUTING -p tcp --dport 53080 -j REDIRECT --to-port 80

# 保存iptables规则以便重启后仍然有效
sudo yum install -y iptables-services
sudo systemctl enable iptables
sudo service iptables save

# 验证规则是否已添加
sudo iptables -t nat -L -n -v
```

### 3. 检查Arvados服务状态
```bash
# 检查Nginx服务是否运行
sudo systemctl status nginx

# 检查是否有服务在监听80端口
sudo netstat -tlnp | grep :80

# 检查Arvados安装状态
ls -la /opt/arvados/SETUP_COMPLETE
```

### 4. 如果Nginx没有运行，启动它
```bash
# 启动Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 检查Nginx配置
sudo nginx -t
```

### 5. 验证端口转发
```bash
# 测试本地端口转发
curl -I http://localhost:80
curl -I http://localhost:53080
```

### 6. 防火墙配置（如果启用了firewalld）
```bash
# 检查firewalld状态
sudo systemctl status firewalld

# 如果firewalld正在运行，添加端口规则
sudo firewall-cmd --permanent --add-port=53080/tcp
sudo firewall-cmd --reload
```

### 7. 重启网络服务（如有必要）
```bash
sudo systemctl restart network
```

## 故障排查

如果仍然无法访问，请检查：

1. 实例上的服务是否正在运行
2. 防火墙规则是否正确
3. 安全组规则是否已生效
4. 是否有其他网络ACL阻止访问

## 验证步骤

配置完成后，您应该能够通过以下方式访问：

- 外部访问: http://43.192.38.7:53080
- 这将被转发到实例内部的80端口
- 如果Arvados服务正在80端口运行，您应该能看到Arvados界面

注意：目前Arvados可能还在安装过程中，需要先确保基础服务已正确安装和运行。