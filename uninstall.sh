#!/bin/bash

# 1. Check for Root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

echo "Stopping V2Ray service..."
# 2. Stop and Disable Service
systemctl stop v2ray >/dev/null 2>&1
systemctl disable v2ray >/dev/null 2>&1

echo "Removing V2Ray..."
# 3. Remove V2Ray using the official removal command
# This removes the core binary and systemd service files
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove >/dev/null 2>&1

# 4. Remove Configuration and Logs
# Clean up config files created by either script
rm -rf /usr/local/etc/v2ray
rm -rf /var/log/v2ray
rm -f /etc/systemd/system/v2ray.service
rm -f /etc/systemd/system/v2ray@.service

echo "Removing generated files..."
# 5. Remove artifacts from current directory
rm -f v2ray_qr.jpg

echo "Removing dependencies..."
# 6. Remove packages installed by the scripts
# Note: curl is preserved as it is a common utility
apt-get remove -y qrencode jq uuid-runtime >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

echo "------------------------------------------------------"
echo "Uninstallation Complete."
echo "------------------------------------------------------"
