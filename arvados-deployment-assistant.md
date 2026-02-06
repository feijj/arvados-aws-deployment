# Arvados AWS POC 部署助手

这是一个交互式部署助手，将引导您完成Arvados在AWS上的部署。

## 步骤 1：环境检查

首先，请确保您的环境中已安装以下工具：
- AWS CLI (`aws --version`)
- Terraform (`terraform version`)
- Git (`git --version`)
- SSH客户端 (`ssh -V`)

## 步骤 2：AWS配置

请运行以下命令配置AWS CLI：
```bash
aws configure
```

输入您的：
- AWS Access Key ID
- AWS Secret Access Key
- 默认区域（如 us-west-2）
- 默认输出格式（json）

## 步骤 3：SSH密钥对

确保您有一个AWS密钥对，用于SSH访问EC2实例：
- 如果已有密钥对，请记下其名称
- 如果没有，请在AWS控制台创建一个新的密钥对

## 步骤 4：运行部署脚本

1. 创建一个工作目录：
```bash
mkdir arvados-poc-deployment && cd arvados-poc-deployment
```

2. 创建部署脚本（使用前面生成的脚本内容）

3. 运行部署：
```bash
chmod +x arvados-auto-deploy-script.sh
./arvados-auto-deploy-script.sh
```

## 步骤 5：监控部署

部署过程中，您可以：
- 查看Terraform输出了解进度
- SSH到实例检查安装状态
- 查看/var/log/arvados-install.log了解安装进度

## 步骤 6：完成配置

部署完成后，运行配置脚本：
```bash
chmod +x arvados-post-config-script.sh
./arvados-post-config-script.sh
```

## 部署后访问

部署成功后，您可以通过以下方式访问系统：
- Workbench2: https://workbench2.your-cluster-id.your-domain.com
- API服务: https://your-cluster-id.your-domain.com

## 故障排除

如果遇到问题：
1. 检查AWS配额是否充足
2. 确认安全组允许相应端口访问
3. 查看实例系统日志
4. 检查/var/log/arvados-install.log

## 清理资源

POC结束后，记得清理资源：
```bash
cd arvados-poc-deployment
terraform destroy
```

这个部署方案让您完全控制整个过程，同时确保安全。所有敏感信息都保留在您的环境中，不会被传输或存储在任何地方。