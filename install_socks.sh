#!/bin/bash

# 1. 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

# 2. 安装必要依赖 (静默安装)
apt-get update -qq >/dev/null
apt-get install -y curl jq uuid-runtime >/dev/null 2>&1

# 3. 安装 V2Ray (强制 IPv4 下载，静默安装)
bash <(curl -4 -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) >/dev/null 2>&1

# 4. 生成随机变量
# 随机端口 10000-60000
PORT=$(shuf -i 10000-60000 -n1)
# 随机生成10位字母数字组合的用户名
USER=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
# 随机生成10位字母数字组合的密码
PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
# 获取本机公网 IPv4 地址
IP=$(curl -4 -s ifconfig.me)

# 5. 写入 V2Ray 配置文件 (SOCKS5 + 密码认证)
cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USER",
            "pass": "$PASS"
          }
        ],
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 6. 启动 V2Ray 服务
systemctl enable v2ray >/dev/null 2>&1
systemctl restart v2ray

# 7. 输出指定格式信息
echo "协议: socks"
echo "地址: $IP"
echo "端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASS"
