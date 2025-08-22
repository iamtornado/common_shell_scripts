#!/bin/bash
# 一键安装最新版 Microsoft Edge 浏览器 (Ubuntu 24.04)
# Author: tornadoami

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误处理函数
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error_exit "请不要以root用户运行此脚本"
    fi
}

# 检查系统架构
check_architecture() {
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        error_exit "此脚本仅支持x86_64架构，当前架构: $arch"
    fi
    echo -e "${GREEN}✓ 系统架构检查通过: $arch${NC}"
}

# 检查网络连接
check_network() {
    if ! ping -c 1 microsoft.com &> /dev/null; then
        error_exit "无法连接到网络，请检查网络连接"
    fi
    echo -e "${GREEN}✓ 网络连接检查通过${NC}"
}

# 检查是否为Ubuntu系统
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        error_exit "此脚本仅支持Ubuntu系统"
    fi
    echo -e "${GREEN}✓ Ubuntu系统检查通过${NC}"
}

# 检查是否已安装Edge
check_existing_edge() {
    if command -v microsoft-edge &> /dev/null; then
        echo -e "${YELLOW}检测到已安装的Microsoft Edge${NC}"
        read -p "是否要重新安装？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}安装已取消${NC}"
            exit 0
        fi
        echo -e "${YELLOW}开始重新安装...${NC}"
    fi
}

# 主函数
main() {
    echo -e "${BLUE}开始安装 Microsoft Edge 浏览器...${NC}"
    
    # 执行检查
    check_root
    check_ubuntu
    check_architecture
    check_network
    check_existing_edge
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装依赖包...${NC}"
    sudo apt install -y wget ca-certificates gnupg software-properties-common || error_exit "安装依赖包失败"
    
    echo -e "${YELLOW}>>> 添加Microsoft GPG密钥...${NC}"
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-edge.gpg > /dev/null || error_exit "添加GPG密钥失败"
    
    echo -e "${YELLOW}>>> 添加Microsoft Edge软件源...${NC}"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null || error_exit "添加软件源失败"
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装 Microsoft Edge...${NC}"
    sudo apt install -y microsoft-edge-stable || error_exit "安装Microsoft Edge失败"
    
    echo -e "${YELLOW}>>> 验证安装结果...${NC}"
    if microsoft-edge --version; then
        echo -e "${GREEN}✓ Microsoft Edge 安装成功！${NC}"
        echo -e "${GREEN}>>> 安装完成！你可以在应用菜单中找到并启动 Microsoft Edge。${NC}"
        
        # 显示版本信息
        echo -e "${BLUE}版本信息:${NC}"
        microsoft-edge --version
        
        # 创建桌面快捷方式（可选）
        echo -e "${YELLOW}>>> 创建桌面快捷方式...${NC}"
        if [[ -d "$HOME/Desktop" ]]; then
            cat > "$HOME/Desktop/Microsoft Edge.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft Edge
Comment=Microsoft Edge Web Browser
Exec=microsoft-edge %U
Terminal=false
Icon=microsoft-edge
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;x-scheme-handler/edge;
EOF
            chmod +x "$HOME/Desktop/Microsoft Edge.desktop"
            echo -e "${GREEN}✓ 桌面快捷方式已创建${NC}"
        fi
    else
        error_exit "Microsoft Edge 安装失败，请检查。"
    fi
}

# 捕获中断信号
trap 'echo -e "\n${RED}安装被用户中断${NC}"; exit 1' INT TERM

# 运行主函数
main "$@"
