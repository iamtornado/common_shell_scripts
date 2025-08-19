#!/bin/bash

# Hugging Face 模型下载脚本
# 具有自动重试机制，支持断点续传和错误恢复
# 使用方法: ./download_hf_model.sh <model_name> [download_path] [max_retries]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_DOWNLOAD_PATH=""  # 空字符串表示使用 hf 默认目录
DEFAULT_MAX_RETRIES=999
DEFAULT_RETRY_DELAY=10

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
Hugging Face 模型下载脚本

用法: $0 <model_name> [download_path] [max_retries]

参数:
  model_name     要下载的模型名称 (例如: meta-llama/Llama-2-7b-chat-hf)
  download_path  下载路径 (可选，默认: 使用 hf 默认目录)
  max_retries    最大重试次数 (可选，默认: 999)

示例:
  $0 meta-llama/Llama-2-7b-chat-hf
  $0 meta-llama/Llama-2-7b-chat-hf ./my_models 10
  $0 "microsoft/DialoGPT-medium" /data/models 3

注意事项:
  - 确保已安装 huggingface_hub CLI 工具
  - 对于私有模型，需要先运行 'hf auth login' 进行身份验证
  - 大模型下载可能需要较长时间，建议使用 screen 或 tmux 运行
  - 脚本会直接尝试下载，如果模型不存在会自动报错

EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    # 检查 hf 命令是否可用
    if ! command -v hf &> /dev/null; then
        log_error "未找到 'hf' 命令。请先安装 huggingface_hub CLI 工具："
        echo "pip install -U 'huggingface_hub[cli]'"
        exit 1
    fi
    
    # 检查是否已登录
    if ! hf auth whoami &> /dev/null; then
        log_warning "未检测到 Hugging Face 登录状态。某些模型可能需要身份验证。"
        echo "如需登录，请运行: hf auth login"
        read -p "是否继续下载？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Hugging Face 身份验证正常"
    fi
    
    # 检查镜像站点配置（针对中国大陆用户）
    check_mirror_config
    
    log_success "依赖检查完成"
}

# 检查镜像站点配置
check_mirror_config() {
    log_info "检查镜像站点配置..."
    
    if [[ -n "$HF_ENDPOINT" ]]; then
        if [[ "$HF_ENDPOINT" == "https://hf-mirror.com" ]]; then
            log_success "已配置中国大陆镜像站点: $HF_ENDPOINT"
        else
            log_warning "检测到自定义 HF_ENDPOINT: $HF_ENDPOINT"
            log_info "如需使用中国大陆镜像站点，建议设置: export HF_ENDPOINT=https://hf-mirror.com"
        fi
    else
        log_warning "未配置 HF_ENDPOINT 环境变量"
        log_info "针对中国大陆用户，建议配置镜像站点以加快下载速度："
        echo ""
        echo "  临时配置（当前会话有效）："
        echo "    export HF_ENDPOINT=https://hf-mirror.com"
        echo ""
        echo "  永久配置（添加到 ~/.bashrc 或 ~/.zshrc）："
        echo "    echo 'export HF_ENDPOINT=https://hf-mirror.com' >> ~/.bashrc"
        echo "    source ~/.bashrc"
        echo ""
        echo "  或者使用以下命令快速配置："
        echo "    echo 'export HF_ENDPOINT=https://hf-mirror.com' >> ~/.bashrc && source ~/.bashrc"
        echo ""
        read -p "是否现在配置镜像站点？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo 'export HF_ENDPOINT=https://hf-mirror.com' >> ~/.bashrc
            export HF_ENDPOINT=https://hf-mirror.com
            log_success "镜像站点配置完成！当前会话已生效。"
            log_info "请运行 'source ~/.bashrc' 使配置永久生效。"
        else
            log_info "跳过镜像站点配置，继续使用默认设置。"
        fi
    fi
}

# 验证模型名称
validate_model_name() {
    local model_name="$1"
    
    if [[ -z "$model_name" ]]; then
        log_error "模型名称不能为空"
        show_help
        exit 1
    fi
    
    # 检查模型名称格式
    if [[ ! "$model_name" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9._-]+$ ]]; then
        log_warning "模型名称格式可能不正确: $model_name"
        log_info "标准格式应为: organization/model-name"
    fi
    
    log_info "验证模型名称: $model_name"
}

# 创建下载目录
create_download_dir() {
    local download_path="$1"
    
    if [[ -n "$download_path" ]]; then
        # 用户指定了下载路径
        if [[ ! -d "$download_path" ]]; then
            log_info "创建下载目录: $download_path"
            mkdir -p "$download_path"
        fi
        
        cd "$download_path"
        log_success "下载目录: $(pwd)"
    else
        # 使用 hf 默认目录
        log_info "使用 hf 默认下载目录"
        log_success "当前目录: $(pwd)"
    fi
}

# 模型验证说明
# 不再预先验证模型是否存在，直接通过 hf download 命令进行下载
# 如果模型不存在，hf download 命令会自动报错

# 下载模型文件
download_model() {
    local model_name="$1"
    local max_retries="$2"
    local download_path="$3"
    local retry_count=0
    local success=false
    
    log_info "开始下载模型: $model_name"
    log_info "最大重试次数: $max_retries"
    
    while [[ $retry_count -lt $max_retries && $success == false ]]; do
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -gt 1 ]]; then
            log_warning "第 $retry_count 次重试下载 (共 $max_retries 次)"
            log_info "等待 ${DEFAULT_RETRY_DELAY} 秒后重试..."
            sleep $DEFAULT_RETRY_DELAY
        fi
        
        log_info "开始下载 (尝试 $retry_count/$max_retries)..."
        
                # 使用 hf download 命令下载模型
        if [[ -n "$download_path" ]]; then
            # 用户指定了下载路径，使用 --local-dir 参数
            if hf download "$model_name" --local-dir .; then
                log_success "模型下载成功！"
                success=true
                break
            fi
        else
            # 使用 hf 默认目录，不指定 --local-dir 参数
            if hf download "$model_name"; then
                log_success "模型下载成功！"
                success=true
                break
            fi
        fi
        
        # 如果下载失败，处理重试逻辑
        log_error "下载失败 (尝试 $retry_count/$max_retries)"
        
        if [[ $retry_count -lt $max_retries ]]; then
            log_info "准备重试..."
        else
            log_error "已达到最大重试次数，下载失败"
        fi
    done
    
    if [[ $success == false ]]; then
        log_error "模型下载最终失败，请检查网络连接和模型名称"
        return 1
    fi
    
    return 0
}

# 验证下载完整性
verify_download() {
    local model_name="$1"
    
    log_info "验证下载完整性..."
    
    # 检查是否有文件被下载
    local file_count=$(find . -type f -not -path "./.*" | wc -l)
    
    if [[ $file_count -eq 0 ]]; then
        log_error "未找到下载的文件"
        return 1
    fi
    
    log_success "找到 $file_count 个文件"
    
    # 检查常见的重要文件
    local important_files=("config.json" "tokenizer.json" "tokenizer_config.json" "pytorch_model.bin" "model.safetensors")
    local found_important=0
    
    for file in "${important_files[@]}"; do
        if [[ -f "$file" ]]; then
            found_important=$((found_important + 1))
            log_info "✓ 找到重要文件: $file"
        fi
    done
    
    if [[ $found_important -gt 0 ]]; then
        log_success "下载验证通过，找到 $found_important 个重要文件"
    else
        log_warning "未找到常见的重要文件，但下载可能仍然有效"
    fi
    
    return 0
}

# 显示下载统计
show_download_stats() {
    local download_path="$1"
    
    log_info "下载统计信息:"
    echo "=================================="
    
    # 文件大小统计
    local total_size=$(du -sh . | cut -f1)
    echo "总下载大小: $total_size"
    
    # 文件数量统计
    local file_count=$(find . -type f -not -path "./.*" | wc -l)
    echo "文件总数: $file_count"
    
    # 目录数量统计
    local dir_count=$(find . -type d -not -path "./.*" | wc -l)
    echo "目录总数: $dir_count"
    
    # 显示下载的文件列表
    echo ""
    log_info "下载的文件列表:"
    find . -type f -not -path "./.*" | sort | head -20
    
    if [[ $file_count -gt 20 ]]; then
        echo "... 还有 $((file_count - 20)) 个文件"
    fi
    
    echo "=================================="
}

# 主函数
main() {
    # 检查参数
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    local model_name="$1"
    local download_path="${2:-$DEFAULT_DOWNLOAD_PATH}"
    local max_retries="${999:-$DEFAULT_MAX_RETRIES}"
    
    log_info "=== Hugging Face 模型下载脚本 ==="
    log_info "模型名称: $model_name"
    if [[ -n "$download_path" ]]; then
        log_info "下载路径: $download_path"
    else
        log_info "下载路径: 使用 hf 默认目录"
    fi
    log_info "最大重试次数: $max_retries"
    echo ""
    
    # 开始时间
    local start_time=$(date +%s)
    
    # 执行下载流程
    if check_dependencies && \
       validate_model_name "$model_name" && \
       create_download_dir "$download_path" && \
       download_model "$model_name" "$max_retries" "$download_path" && \
       verify_download "$model_name"; then
        
        # 计算耗时
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        
        log_success "=== 下载完成！ ==="
        log_info "总耗时: ${hours}小时 ${minutes}分钟 ${seconds}秒"
        
        show_download_stats "$download_path"
        
        log_success "模型已成功下载到: $(pwd)"
        
    else
        log_error "=== 下载失败 ==="
        exit 1
    fi
}

# 错误处理
trap 'log_error "脚本执行被中断"; exit 1' INT TERM

# 执行主函数
main "$@"