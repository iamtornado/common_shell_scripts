@echo off
setlocal enabledelayedexpansion

REM Hugging Face 模型下载脚本 (Windows版本)
REM 具有自动重试机制，支持断点续传和错误恢复
REM 使用方法: download_hf_model.bat <model_name> [download_path] [max_retries]

REM 设置编码为UTF-8
chcp 65001 >nul

REM 默认配置
set "DEFAULT_DOWNLOAD_PATH="
set "DEFAULT_MAX_RETRIES=5"
set "DEFAULT_RETRY_DELAY=10"

REM 检查参数
if "%1"=="" (
    call :show_help
    exit /b 1
)

if "%1"=="-h" (
    call :show_help
    exit /b 0
)

if "%1"=="--help" (
    call :show_help
    exit /b 0
)

set "model_name=%1"
set "download_path=%2"
set "max_retries=%3"

REM 设置默认值
if "%download_path%"=="" set "download_path=%DEFAULT_DOWNLOAD_PATH%"
if "%max_retries%"=="" set "max_retries=%DEFAULT_MAX_RETRIES%"

echo [INFO] === Hugging Face 模型下载脚本 ===
echo [INFO] 模型名称: %model_name%
if not "%download_path%"=="" (
    echo [INFO] 下载路径: %download_path%
) else (
    echo [INFO] 下载路径: 使用 hf 默认目录
)
echo [INFO] 最大重试次数: %max_retries%
echo.

REM 记录开始时间
set "start_time=%time%"

REM 执行下载流程
call :check_dependencies
if errorlevel 1 goto :error_exit

call :validate_model_name
if errorlevel 1 goto :error_exit

call :create_download_dir
if errorlevel 1 goto :error_exit

call :download_model
if errorlevel 1 goto :error_exit

call :verify_download
if errorlevel 1 goto :error_exit

REM 计算耗时并显示结果
call :show_completion
goto :end

:check_dependencies
echo [INFO] 检查依赖...
REM 检查 hf 命令是否可用
where hf >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 'hf' 命令。请先安装 huggingface_hub CLI 工具：
    echo pip install -U "huggingface_hub[cli]"
    exit /b 1
)

REM 检查是否已登录
hf auth whoami >nul 2>&1
if errorlevel 1 (
    echo [WARNING] 未检测到 Hugging Face 登录状态。某些模型可能需要身份验证。
    echo 如需登录，请运行: hf auth login
    set /p "continue=是否继续下载？(y/N): "
    if /i not "!continue!"=="y" exit /b 1
) else (
    echo [SUCCESS] Hugging Face 身份验证正常
)

REM 检查镜像站点配置（针对中国大陆用户）
call :check_mirror_config

echo [SUCCESS] 依赖检查完成
exit /b 0

:check_mirror_config
echo [INFO] 检查镜像站点配置...
if not "%HF_ENDPOINT%"=="" (
    if "%HF_ENDPOINT%"=="https://hf-mirror.com" (
        echo [SUCCESS] 已配置中国大陆镜像站点: %HF_ENDPOINT%
    ) else (
        echo [WARNING] 检测到自定义 HF_ENDPOINT: %HF_ENDPOINT%
        echo [INFO] 如需使用中国大陆镜像站点，建议设置: set HF_ENDPOINT=https://hf-mirror.com
    )
) else (
    echo [WARNING] 未配置 HF_ENDPOINT 环境变量
    echo [INFO] 针对中国大陆用户，建议配置镜像站点以加快下载速度：
    echo.
    echo   临时配置（当前会话有效）：
    echo     set HF_ENDPOINT=https://hf-mirror.com
    echo.
    echo   永久配置（添加到系统环境变量）：
    echo     1. 右键"此电脑" ^> 属性 ^> 高级系统设置 ^> 环境变量
    echo     2. 新建系统变量 HF_ENDPOINT，值设为 https://hf-mirror.com
    echo.
    echo   或者使用以下命令快速配置（需要管理员权限）：
    echo     setx HF_ENDPOINT "https://hf-mirror.com"
    echo.
    set /p "configure=是否现在配置镜像站点？(y/N): "
    if /i "!configure!"=="y" (
        set HF_ENDPOINT=https://hf-mirror.com
        echo [SUCCESS] 镜像站点配置完成！当前会话已生效。
        echo [INFO] 请重启命令提示符或使用 setx 命令使配置永久生效。
    ) else (
        echo [INFO] 跳过镜像站点配置，继续使用默认设置。
    )
)
exit /b 0

:validate_model_name
if "%model_name%"=="" (
    echo [ERROR] 模型名称不能为空
    call :show_help
    exit /b 1
)
echo [INFO] 验证模型名称: %model_name%
exit /b 0

:create_download_dir
if not "%download_path%"=="" (
    if not exist "%download_path%" (
        echo [INFO] 创建下载目录: %download_path%
        mkdir "%download_path%"
    )
    cd /d "%download_path%"
    echo [SUCCESS] 下载目录: %cd%
) else (
    echo [INFO] 使用 hf 默认下载目录
    echo [SUCCESS] 当前目录: %cd%
)
exit /b 0

:download_model
echo [INFO] 开始下载模型: %model_name%
echo [INFO] 最大重试次数: %max_retries%

set "retry_count=0"
set "success=false"

:download_loop
set /a "retry_count+=1"

if !retry_count! gtr 1 (
    echo [WARNING] 第 !retry_count! 次重试下载 (共 %max_retries% 次)
    echo [INFO] 等待 %DEFAULT_RETRY_DELAY% 秒后重试...
    timeout /t %DEFAULT_RETRY_DELAY% /nobreak >nul
)

echo [INFO] 开始下载 (尝试 !retry_count!/%max_retries%)...

REM 使用 hf download 命令下载模型
REM 不再预先验证模型是否存在，直接通过下载验证
if not "%download_path%"=="" (
    hf download "%model_name%" --local-dir .
) else (
    hf download "%model_name%"
)
if errorlevel 1 (
    echo [ERROR] 下载失败 (尝试 !retry_count!/%max_retries%)
    
    if !retry_count! lss %max_retries% (
        echo [INFO] 准备重试...
        goto :download_loop
    ) else (
        echo [ERROR] 已达到最大重试次数，下载失败
        exit /b 1
    )
) else (
    echo [SUCCESS] 模型下载成功！
    set "success=true"
)

if "!success!"=="false" (
    echo [ERROR] 模型下载最终失败，请检查网络连接和模型名称
    exit /b 1
)

exit /b 0

:verify_download
echo [INFO] 验证下载完整性...

REM 检查是否有文件被下载
set "file_count=0"
for /f %%i in ('dir /b /a-d 2^>nul ^| find /c /v ""') do set "file_count=%%i"

if %file_count% equ 0 (
    echo [ERROR] 未找到下载的文件
    exit /b 1
)

echo [SUCCESS] 找到 %file_count% 个文件

REM 检查常见的重要文件
set "found_important=0"
if exist "config.json" (
    set /a "found_important+=1"
    echo [INFO] ✓ 找到重要文件: config.json
)
if exist "tokenizer.json" (
    set /a "found_important+=1"
    echo [INFO] ✓ 找到重要文件: tokenizer.json
)
if exist "tokenizer_config.json" (
    set /a "found_important+=1"
    echo [INFO] ✓ 找到重要文件: tokenizer_config.json
)
if exist "pytorch_model.bin" (
    set /a "found_important+=1"
    echo [INFO] ✓ 找到重要文件: pytorch_model.bin
)
if exist "model.safetensors" (
    set /a "found_important+=1"
    echo [INFO] ✓ 找到重要文件: model.safetensors
)

if %found_important% gtr 0 (
    echo [SUCCESS] 下载验证通过，找到 %found_important% 个重要文件
) else (
    echo [WARNING] 未找到常见的重要文件，但下载可能仍然有效
)

exit /b 0

:show_completion
echo [SUCCESS] === 下载完成！ ===

REM 显示下载统计
echo [INFO] 下载统计信息:
echo ==================================
for /f "tokens=1" %%i in ('dir /s /-c 2^>nul ^| find "个文件"') do (
    echo 总下载大小: %%i
    break
)
echo 文件总数: %file_count%

echo.
echo [INFO] 下载的文件列表:
dir /b /a-d 2>nul | findstr /v "^$" | head -20

if %file_count% gtr 20 (
    echo ... 还有 %file_count% 个文件
)

echo ==================================
echo [SUCCESS] 模型已成功下载到: %cd%
exit /b 0

:show_help
echo Hugging Face 模型下载脚本
echo.
echo 用法: %0 ^<model_name^> [download_path] [max_retries]
echo.
echo 参数:
echo   model_name     要下载的模型名称 (例如: meta-llama/Llama-2-7b-chat-hf)
echo   download_path  下载路径 (可选，默认: 使用 hf 默认目录)
echo   max_retries    最大重试次数 (可选，默认: 5)
echo.
echo 示例:
echo   %0 meta-llama/Llama-2-7b-chat-hf
echo   %0 meta-llama/Llama-2-7b-chat-hf .\my_models 10
echo   %0 "microsoft/DialoGPT-medium" C:\data\models 3
echo.
echo 注意事项:
echo   - 确保已安装 huggingface_hub CLI 工具
echo   - 对于私有模型，需要先运行 'hf auth login' 进行身份验证
echo   - 大模型下载可能需要较长时间，建议使用 screen 或 tmux 运行
echo   - 脚本会直接尝试下载，如果模型不存在会自动报错
echo.
exit /b 0

:error_exit
echo [ERROR] === 下载失败 ===
exit /b 1

:end
echo.
echo 脚本执行完成
pause
