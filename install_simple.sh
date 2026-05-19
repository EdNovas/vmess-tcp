#!/bin/bash
# VMess + TCP + ProxyProtocol 一键安装脚本
# 适用于 Debian/Ubuntu 系统
# ProxyProtocol=true: 用于接收前端(HAProxy/Nginx等)传递的真实客户端IP

set -euo pipefail

# ====== 配置区 ======
XRAY_PORT=${XRAY_PORT:-10086}
XRAY_VERSION=${XRAY_VERSION:-"latest"}
# =====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Root 检查
[[ $EUID -ne 0 ]] && error "请以 root 权限运行此脚本"

# 系统检查
if ! command -v apt &>/dev/null; then
    error "此脚本仅支持 Debian/Ubuntu 系统"
fi

info "======================================"
info " VMess + TCP + ProxyProtocol 一键安装"
info "======================================"

# 安装依赖
info "安装依赖..."
apt update -qq
apt install -y -qq curl unzip jq > /dev/null 2>&1

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
info "生成 UUID: ${CYAN}${UUID}${NC}"

# 获取 Xray 最新版本号
if [[ "$XRAY_VERSION" == "latest" ]]; then
    info "获取 Xray 最新版本..."
    XRAY_VERSION=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.tag_name')
    [[ -z "$XRAY_VERSION" || "$XRAY_VERSION" == "null" ]] && error "无法获取 Xray 最新版本"
fi
info "Xray 版本: ${CYAN}${XRAY_VERSION}${NC}"

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_ARCH="Xray-linux-64" ;;
    aarch64) XRAY_ARCH="Xray-linux-arm64-v8a" ;;
    armv7l)  XRAY_ARCH="Xray-linux-arm32-v7a" ;;
    *)       error "不支持的架构: $ARCH" ;;
esac

# 下载并安装 Xray
XRAY_DIR="/usr/local/xray"
XRAY_BIN="${XRAY_DIR}/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_LOG_DIR="/var/log/xray"

mkdir -p "$XRAY_DIR" "$(dirname "$XRAY_CONFIG")" "$XRAY_LOG_DIR"

if [[ -f "$XRAY_BIN" ]]; then
    CURRENT_VER=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print "v"$2}' || echo "unknown")
    if [[ "$CURRENT_VER" == "$XRAY_VERSION" ]]; then
        info "Xray 已是最新版本 ($CURRENT_VER)，跳过下载"
    else
        warn "Xray 当前版本 $CURRENT_VER，升级到 $XRAY_VERSION"
        NEED_DOWNLOAD=1
    fi
else
    NEED_DOWNLOAD=1
fi

if [[ "${NEED_DOWNLOAD:-0}" == "1" || ! -f "$XRAY_BIN" ]]; then
    info "下载 Xray ${XRAY_VERSION}..."
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ARCH}.zip"
    TMP_ZIP=$(mktemp /tmp/xray-XXXXXX.zip)
    curl -sL -o "$TMP_ZIP" "$DOWNLOAD_URL" || error "下载 Xray 失败"
    
    info "解压安装..."
    unzip -o -q "$TMP_ZIP" -d "$XRAY_DIR"
    chmod +x "$XRAY_BIN"
    rm -f "$TMP_ZIP"
fi

# 写入配置文件
info "生成配置文件..."
cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "${XRAY_LOG_DIR}/access.log",
        "error": "${XRAY_LOG_DIR}/error.log"
    },
    "inbounds": [
        {
            "tag": "vmess-tcp-in",
            "port": ${XRAY_PORT},
            "listen": "0.0.0.0",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "tcpSettings": {
                    "acceptProxyProtocol": true
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {}
        },
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {}
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": ["bittorrent"]
            }
        ]
    }
}
EOF

# 验证配置
info "验证配置文件..."
if ! "$XRAY_BIN" run -test -config "$XRAY_CONFIG" &>/dev/null; then
    error "配置文件验证失败！请检查 $XRAY_CONFIG"
fi
info "配置验证通过 ✓"

# 创建 systemd 服务
info "创建 systemd 服务..."
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service (VMess+TCP+ProxyProtocol)
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray --quiet
systemctl restart xray

# 等待并检查状态
sleep 1
if systemctl is-active --quiet xray; then
    info "Xray 服务启动成功 ✓"
else
    error "Xray 服务启动失败，请检查: journalctl -u xray -n 20"
fi

# 设置日志轮转
cat > /etc/logrotate.d/xray <<EOF
${XRAY_LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        systemctl restart xray > /dev/null 2>&1 || true
    endscript
}
EOF

# 获取本机 IP
SERVER_IP=$(curl -s4 ip.sb 2>/dev/null || curl -s4 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# 输出信息
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} 安装完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e " Xray 版本:     ${CYAN}${XRAY_VERSION}${NC}"
echo -e " 监听端口:      ${CYAN}${XRAY_PORT}${NC}"
echo -e " 协议:          ${CYAN}VMess${NC}"
echo -e " 传输:          ${CYAN}TCP${NC}"
echo -e " ProxyProtocol: ${CYAN}true (acceptProxyProtocol)${NC}"
echo -e " UUID:          ${CYAN}${UUID}${NC}"
echo -e " AlterID:       ${CYAN}0${NC}"
echo -e " 服务器 IP:     ${CYAN}${SERVER_IP}${NC}"
echo ""
echo -e " 配置文件:      ${YELLOW}${XRAY_CONFIG}${NC}"
echo -e " 日志目录:      ${YELLOW}${XRAY_LOG_DIR}${NC}"
echo ""
echo -e "${YELLOW}⚠ 注意: acceptProxyProtocol=true 表示此节点${NC}"
echo -e "${YELLOW}  期望接收 PROXY Protocol 头部。客户端必须通过${NC}"
echo -e "${YELLOW}  支持发送 PP 的前端（如 HAProxy/Nginx）连接，${NC}"
echo -e "${YELLOW}  否则直连将被拒绝。${NC}"
echo ""
echo -e "${GREEN}管理命令:${NC}"
echo -e "  启动:  systemctl start xray"
echo -e "  停止:  systemctl stop xray"
echo -e "  重启:  systemctl restart xray"
echo -e "  状态:  systemctl status xray"
echo -e "  日志:  journalctl -u xray -f"
echo ""

# 生成 vmess:// 链接 (base64 标准格式)
VMESS_JSON=$(cat <<EOF2
{
    "v": "2",
    "ps": "vmess-tcp-pp-${SERVER_IP}",
    "add": "${SERVER_IP}",
    "port": "${XRAY_PORT}",
    "id": "${UUID}",
    "aid": "0",
    "net": "tcp",
    "type": "none",
    "host": "",
    "path": "",
    "tls": ""
}
EOF2
)
VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

echo -e "${GREEN}VMess 分享链接 (仅供参考，直连需关闭 PP):${NC}"
echo -e "${CYAN}${VMESS_LINK}${NC}"
echo ""
