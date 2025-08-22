#!/bin/bash
# 一键安装最新版 Google Chrome 浏览器 (Ubuntu 24.04)
# Author: tornadoami

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    if ! ping -c 1 dl.google.com &> /dev/null; then
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

# 主函数
main() {
    echo -e "${YELLOW}开始安装 Google Chrome 浏览器...${NC}"
    
    # 执行检查
    check_root
    check_ubuntu
    check_architecture
    check_network
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装依赖包...${NC}"
    sudo apt install -y wget ca-certificates gnupg || error_exit "安装依赖包失败"
    
    echo -e "${YELLOW}>>> 添加Google GPG密钥...${NC}"
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add - || error_exit "添加GPG密钥失败"
    
    echo -e "${YELLOW}>>> 添加Google Chrome软件源...${NC}"
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null || error_exit "添加软件源失败"
    
    echo -e "${YELLOW}>>> 更新软件包索引...${NC}"
    sudo apt update -y || error_exit "更新软件包索引失败"
    
    echo -e "${YELLOW}>>> 安装 Google Chrome...${NC}"
    sudo apt install -y google-chrome-stable || error_exit "安装Google Chrome失败"
    
    echo -e "${YELLOW}>>> 验证安装结果...${NC}"
    if google-chrome --version; then
        echo -e "${GREEN}✓ Google Chrome 安装成功！${NC}"
        echo -e "${GREEN}>>> 安装完成！你可以在应用菜单中找到并启动 Google Chrome。${NC}"
    else
        error_exit "Google Chrome 安装失败，请检查。"
    fi
}

# 捕获中断信号
trap 'echo -e "\n${RED}安装被用户中断${NC}"; exit 1' INT TERM

# 运行主函数
main "$@"
