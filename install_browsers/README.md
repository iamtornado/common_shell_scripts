# Ubuntu 浏览器安装脚本集合

## 概述
这是一个多浏览器安装脚本集合，用于在Ubuntu系统上自动安装最新版本的各种主流浏览器。目前支持Google Chrome和Microsoft Edge，未来将支持更多浏览器。

## 脚本列表

### 1. Google Chrome 安装脚本
- **文件名**: `install_googlechrome.sh`
- **功能**: 自动安装最新版Google Chrome浏览器
- **特点**: 使用官方软件源，完整的错误处理

### 2. Microsoft Edge 安装脚本
- **文件名**: `install_microsoft_edge.sh`
- **功能**: 自动安装最新版Microsoft Edge浏览器
- **特点**: 使用Microsoft官方软件源，智能检测，桌面快捷方式

### 3. 未来计划支持的浏览器
- Firefox (Mozilla)
- Opera
- Brave
- Vivaldi
- 其他主流浏览器

## 系统要求
- Ubuntu 24.04 或更高版本
- x86_64 架构
- 网络连接
- sudo权限

## 使用方法

### Google Chrome 安装
```bash
# 1. 给脚本执行权限
chmod +x install_googlechrome.sh

# 2. 运行安装
./install_googlechrome.sh
```

### Microsoft Edge 安装
```bash
# 1. 给脚本执行权限
chmod +x install_microsoft_edge.sh

# 2. 运行安装
./install_microsoft_edge.sh
```

## 脚本特性对比

| 特性 | Google Chrome | Microsoft Edge |
|------|---------------|----------------|
| 自动系统检查 | ✅ | ✅ |
| 官方软件源 | ✅ | ✅ |
| GPG密钥验证 | ✅ | ✅ |
| 错误处理 | ✅ | ✅ |
| 彩色输出 | ✅ | ✅ |
| 重新安装检测 | ❌ | ✅ |
| 桌面快捷方式 | ❌ | ✅ |
| 架构检查 | ✅ | ✅ |
| 网络检查 | ✅ | ✅ |

## 安装过程说明

### 预检查步骤
两个脚本都会执行以下检查：
- 检查是否为root用户（禁止root运行）
- 检查Ubuntu系统兼容性
- 检查系统架构（仅支持x86_64）
- 检查网络连接

### Google Chrome 安装步骤
1. 更新软件包索引
2. 安装依赖包（wget, ca-certificates, gnupg）
3. 添加Google GPG密钥
4. 配置Google Chrome软件源
5. 安装Google Chrome浏览器
6. 验证安装结果

### Microsoft Edge 安装步骤
1. 更新软件包索引
2. 安装依赖包（wget, ca-certificates, gnupg, software-properties-common）
3. 添加Microsoft GPG密钥
4. 配置Microsoft Edge软件源
5. 安装Microsoft Edge浏览器
6. 验证安装结果
7. 创建桌面快捷方式

## 依赖包

### 共同依赖
- `wget` - 下载工具
- `ca-certificates` - SSL证书
- `gnupg` - GPG密钥管理

### Microsoft Edge 额外依赖
- `software-properties-common` - 软件源管理

## 故障排除

### 常见问题

#### 1. 权限不足
```bash
sudo chmod +x install_*.sh
```

#### 2. 网络连接问题
确保能够访问相应的网站：
- Google Chrome: `google.com`
- Microsoft Edge: `microsoft.com`

#### 3. 软件源更新失败
```bash
sudo apt clean
sudo apt update
```

#### 4. GPG密钥问题
```bash
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys <key_id>
```

### 手动安装方法

#### Google Chrome
```bash
# 添加GPG密钥
wget -qO- https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -

# 添加软件源
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list

# 更新并安装
sudo apt update
sudo apt install google-chrome-stable
```

#### Microsoft Edge
```bash
# 添加GPG密钥
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-edge.gpg

# 添加软件源
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list

# 更新并安装
sudo apt update
sudo apt install microsoft-edge-stable
```

## 卸载方法

### Google Chrome
```bash
sudo apt remove google-chrome-stable
sudo rm /etc/apt/sources.list.d/google-chrome.list
sudo apt update
```

### Microsoft Edge
```bash
sudo apt remove microsoft-edge-stable
sudo rm /etc/apt/sources.list.d/microsoft-edge.list
sudo rm /usr/share/keyrings/microsoft-edge.gpg
sudo apt update
```

## 注意事项
- 两个脚本都需要网络连接
- 安装过程可能需要几分钟
- 建议在安装前备份重要数据
- Microsoft Edge脚本支持重新安装检测
- 两个脚本可以同时安装，互不影响

## 脚本优势
1. **自动化程度高** - 一键安装，无需手动配置
2. **安全性好** - 使用官方软件源和GPG密钥验证
3. **兼容性强** - 自动检测系统兼容性
4. **错误处理完善** - 详细的错误信息和处理机制
5. **用户体验佳** - 彩色输出，进度提示

## 作者
tornadoami

## 许可证
此脚本集合仅供学习和个人使用。

## 更新日志
- 2024: 初始版本发布
- 支持Ubuntu 24.04
- 包含Google Chrome和Microsoft Edge安装脚本

## 🔮 未来扩展计划

### 即将支持的浏览器
- **Firefox (Mozilla)** - 开源浏览器，注重隐私保护
- **Opera** - 功能丰富的浏览器，内置VPN和广告拦截
- **Brave** - 注重隐私的浏览器，内置广告拦截和追踪保护
- **Vivaldi** - 高度可定制的浏览器，适合高级用户

### 功能增强
- 批量安装多个浏览器
- 浏览器版本管理（安装/更新/降级）
- 配置文件导入导出
- 浏览器插件自动安装
- 多语言支持

### 系统支持扩展
- 支持更多Linux发行版（Debian、CentOS、Fedora等）
- 支持ARM架构（ARM64）
- 支持容器化环境（Docker、WSL）
- 支持云服务器环境
