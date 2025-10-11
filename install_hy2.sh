#!/usr/bin/env bash
# =====================================================
# Hysteria 2 一键安装脚本 - 推荐版
# Version: 1.0.0
# Last Updated: 2025-10-11
# Author: ChatGPT (GPT-5)
# =====================================================

set -e

echo -e "\033[1;36m=== Hysteria 2 一键安装开始 ===\033[0m"

# ===== 检查 root 权限 =====
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[1;31m请使用 root 用户运行此脚本！\033[0m"
  exit 1
fi

# ===== 输入必要信息 =====
read -p "请输入你的域名（例如: hy.example.com）: " domain
read -p "请输入你的 Cloudflare API Token（必须有编辑DNS权限）: " cf_token
read -p "请输入你的 Cloudflare 邮箱地址: " cf_email
read -p "请输入 Hysteria 2 服务端口 [默认443]: " port
port=${port:-443}

# ===== 安装依赖 =====
echo -e "\033[1;33m正在安装依赖...\033[0m"
apt update -y
apt install -y curl wget socat unzip ufw iptables

# ===== 放行端口 =====
ufw disable || true
iptables -I INPUT -p tcp --dport $port -j ACCEPT
iptables -I INPUT -p udp --dport $port -j ACCEPT

# ===== 安装 acme.sh 并申请证书 =====
echo -e "\033[1;33m正在申请 SSL 证书...\033[0m"
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m "$cf_email" --server letsencrypt

export CF_Token="$cf_token"
export CF_Email="$cf_email"

~/.acme.sh/acme.sh --issue --dns dns_cf -d "$domain" --keylength ec-256
mkdir -p /etc/hysteria
~/.acme.sh/acme.sh --install-cert -d "$domain" \
  --ecc \
  --key-file /etc/hysteria/private.key \
  --fullchain-file /etc/hysteria/cert.crt

# ===== 下载并安装 Hysteria 2 =====
echo -e "\033[1;33m正在安装 Hysteria 2...\033[0m"
latest_version=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O /tmp/hysteria.tar.gz https://github.com/apernet/hysteria/releases/download/${latest_version}/hysteria-linux-amd64.tar.gz
tar -xzf /tmp/hysteria.tar.gz -C /tmp
mv /tmp/hysteria /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# ===== 创建配置文件 =====
password=$(openssl rand -base64 12)
cat > /etc/hysteria/config.yaml <<EOF
listen: :$port
tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key
auth:
  type: password
  password: "$password"
masq:
  type: proxy
  proxy:
    url: https://www.bing.com
bandwidth:
  up: 100 mbps
  down: 100 mbps
EOF

# ===== 创建 systemd 服务 =====
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria 2 Service
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ===== 启动服务 =====
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# ===== 输出信息 =====
clear
echo -e "\033[1;32m=== Hysteria 2 安装完成 ===\033[0m"
echo "----------------------------------"
echo "域名: $domain"
echo "端口: $port"
echo "密码: $password"
echo "协议: hysteria2"
echo "----------------------------------"
echo
echo "✅ 客户端连接（Shadowrocket等）链接："
echo "hysteria2://${password}@${domain}:${port}/?insecure=0#Hysteria2"
echo
echo "📂 配置文件路径: /etc/hysteria/config.yaml"
echo "🔍 查看运行状态: systemctl status hysteria"
echo "📜 查看实时日志: journalctl -u hysteria -f"
echo
echo -e "\033[1;36m=== 安装成功！祝你使用愉快！ ===\033[0m"