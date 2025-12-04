#!/bin/bash

# 1. Check for Root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

echo "Installing dependencies..."
apt-get update -qq >/dev/null
apt-get install -y curl qrencode jq uuid-runtime >/dev/null 2>&1

echo "Installing V2Ray..."
bash <(curl -4 -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) >/dev/null 2>&1

# 2. Generate Random Variables
IP=$(curl -4 -s ifconfig.me)

# --- VMESS VARIABLES ---
PORT_VMESS=$(shuf -i 10000-30000 -n1)
UUID=$(uuidgen)

# --- SOCKS5 VARIABLES ---
# Ensure ports don't match
while :; do
    PORT_SOCKS=$(shuf -i 30001-60000 -n1)
    [[ "$PORT_SOCKS" != "$PORT_VMESS" ]] && break
done
USER=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)
PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)

# 3. Write Combined Configuration
# We define TWO objects in the "inbounds" array
cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-in",
      "port": $PORT_VMESS,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "tag": "socks-in",
      "port": $PORT_SOCKS,
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

# 4. Start V2Ray
systemctl enable v2ray >/dev/null 2>&1
systemctl restart v2ray

# 5. Generate VMess Link
VMESS_JSON=$(jq -n \
    --arg v "2" \
    --arg ps "${IP}" \
    --arg add "$IP" \
    --arg port "$PORT_VMESS" \
    --arg id "$UUID" \
    --arg aid "0" \
    --arg net "tcp" \
    --arg type "none" \
    --arg host "" \
    --arg path "" \
    --arg tls "" \
    '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, net:$net, type:$type, host:$host, path:$path, tls:$tls}')

VMESS_LINK="vmess://$(echo -n $VMESS_JSON | base64 -w 0)"
qrencode -o v2ray_qr.jpg -s 10 "$VMESS_LINK"

# 6. Output Results
echo "------------------------------------------------------"
echo "Installation Complete (Dual Protocol)"
echo "------------------------------------------------------"
echo ""
echo "=== VMess Configuration ==="
echo "VMess Link:"
echo "$VMESS_LINK"
echo "QR Code: $(pwd)/v2ray_qr.jpg"
echo ""
echo "=== SOCKS5 Configuration ==="
echo "协议: socks"
echo "地址: $IP"
echo "端口: $PORT_SOCKS"
echo "用户名: $USER"
echo "密码: $PASS"
echo "------------------------------------------------------"
