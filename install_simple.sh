#!/bin/bash

# 1. Check for Root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

echo "Installing dependencies..."
# 2. Install dependencies (curl, qrencode for jpg, jq for json, uuid-runtime)
apt-get update -qq >/dev/null
apt-get install -y curl qrencode jq uuid-runtime >/dev/null 2>&1

echo "Installing V2Ray..."
# 3. Install V2Ray using the official script
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) >/dev/null 2>&1

# 4. Generate Random Variables
PORT=$(shuf -i 10000-60000 -n1)
UUID=$(uuidgen)
IP=$(curl -s ifconfig.me)

# 5. Write Configuration (VMess + TCP)
cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
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

# 6. Start V2Ray
systemctl enable v2ray >/dev/null 2>&1
systemctl restart v2ray

# 7. Generate VMess Link
# Create the JSON structure for the link
VMESS_JSON=$(jq -n \
    --arg v "2" \
    --arg ps "${IP}" \
    --arg add "$IP" \
    --arg port "$PORT" \
    --arg id "$UUID" \
    --arg aid "0" \
    --arg net "tcp" \
    --arg type "none" \
    --arg host "" \
    --arg path "" \
    --arg tls "" \
    '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, net:$net, type:$type, host:$host, path:$path, tls:$tls}')

# Base64 encode the JSON to create the vmess:// link
VMESS_LINK="vmess://$(echo -n $VMESS_JSON | base64 -w 0)"

# 8. Generate QR Code Image (JPG)
qrencode -o v2ray_qr.jpg -s 10 "$VMESS_LINK"

# 9. Output Results
echo "------------------------------------------------------"
echo "Installation Complete."
echo ""
echo "VMess Link:"
echo "$VMESS_LINK"
echo ""
echo "QR Code Image saved to: $(pwd)/v2ray_qr.jpg"
echo "------------------------------------------------------"
