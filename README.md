# Arvados AWS 部署项目

此项目包含在AWS上部署Arvados环境所需的所有脚本和文档。

## 项目结构

- `arvados-auto-deploy-script.sh`: 基础环境部署脚本
- `arvados-post-config-script.sh`: 系统配置脚本
- `arvados-deployment-assistant.md`: 部署指南文档

## 部署概述

Arvados是一个用于管理云计算和HPC集群的平台，支持计算和存储管理、方法跟踪、数据集共享以及分析重运行等功能。

## 部署架构

- 单节点部署（适合POC环境）
- AWS EC2实例 (m5.xlarge)
- EBS存储卷
- 安全组和网络配置
- 自动SSL证书配置

## 快速开始

1. 确保已安装必要的工具 (AWS CLI, Terraform, Git)
2. 配置AWS凭证
3. 运行部署脚本
4. 完成系统配置

详情请参阅 `arvados-deployment-assistant.md` 文档。