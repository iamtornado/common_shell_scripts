#!/bin/bash
# 一键安装最新版 Google Chrome 浏览器 (Ubuntu 24.04)
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
# 优先使用 curl/wget（部分网络环境会屏蔽 ICMP ping）
check_network() {
    # 1. 优先检查 Google 软件源（实际下载地址）
    if command -v curl &> /dev/null; then
        if curl -sf --connect-timeout 10 -o /dev/null https://dl.google.com 2>/dev/null; then
            echo -e "${GREEN}✓ 网络连接检查通过 (已连接至 Google 服务器)${NC}"
            return 0
        fi
    elif command -v wget &> /dev/null; then
        if wget -q --spider --timeout=10 https://dl.google.com 2>/dev/null; then
            echo -e "${GREEN}✓ 网络连接检查通过 (已连接至 Google 服务器)${NC}"
            return 0
        fi
    fi
    
    # 2. 尝试 ping（部分环境允许 ICMP）
    if ping -c 1 -W 5 dl.google.com &> /dev/null; then
        echo -e "${GREEN}✓ 网络连接检查通过${NC}"
        return 0
    fi
    
    # 3. 检测通用网络（如能访问国内站点，提示用户可能需代理/镜像）
    if command -v curl &> /dev/null; then
        if curl -sf --connect-timeout 5 -o /dev/null https://www.baidu.com 2>/dev/null; then
            echo -e "${YELLOW}⚠ 无法连接 Google 服务器，但检测到网络正常${NC}"
            echo -e "${YELLOW}  若在中国大陆，可能需要配置代理。是否继续尝试安装？(y/N): ${NC}"
            read -p "" -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error_exit "用户取消安装"
            fi
            echo -e "${GREEN}✓ 用户选择继续，跳过网络检查${NC}"
            return 0
        fi
    fi
    
    error_exit "无法连接到网络，请检查网络连接或代理设置"
}

# 检查是否为Ubuntu系统
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        error_exit "此脚本仅支持Ubuntu系统"
    fi
    echo -e "${GREEN}✓ Ubuntu系统检查通过${NC}"
}

# 检查是否已安装Chrome
check_existing_chrome() {
    if command -v google-chrome &> /dev/null; then
        echo -e "${YELLOW}检测到已安装的Google Chrome${NC}"
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
    echo -e "${BLUE}开始安装 Google Chrome 浏览器...${NC}"
    
    # 执行检查
    check_root
    check_ubuntu
    check_architecture
    check_network
    check_existing_chrome
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装依赖包...${NC}"
    sudo apt install -y wget ca-certificates gnupg || error_exit "安装依赖包失败"
    
    echo -e "${YELLOW}>>> 添加Google GPG密钥...${NC}"
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/google-chrome.gpg > /dev/null || error_exit "添加GPG密钥失败"
    
    echo -e "${YELLOW}>>> 添加Google Chrome软件源...${NC}"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null || error_exit "添加软件源失败"
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装 Google Chrome...${NC}"
    sudo apt install -y google-chrome-stable || error_exit "安装Google Chrome失败"
    
    echo -e "${YELLOW}>>> 验证安装结果...${NC}"
    if google-chrome --version; then
        echo -e "${GREEN}✓ Google Chrome 安装成功！${NC}"
        echo -e "${GREEN}>>> 安装完成！你可以在应用菜单中找到并启动 Google Chrome。${NC}"
        
        # 显示版本信息
        echo -e "${BLUE}版本信息:${NC}"
        google-chrome --version
        
        # 创建桌面快捷方式（可选）
        echo -e "${YELLOW}>>> 创建桌面快捷方式...${NC}"
        if [[ -d "$HOME/Desktop" ]]; then
            cat > "$HOME/Desktop/Google Chrome.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome
Comment=Google Chrome Web Browser
Exec=google-chrome %U
Terminal=false
Icon=google-chrome
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;
EOF
            chmod +x "$HOME/Desktop/Google Chrome.desktop"
            echo -e "${GREEN}✓ 桌面快捷方式已创建${NC}"
        fi
    else
        error_exit "Google Chrome 安装失败，请检查。"
    fi
}

# 捕获中断信号
trap 'echo -e "\n${RED}安装被用户中断${NC}"; exit 1' INT TERM

# 运行主函数
main "$@"
