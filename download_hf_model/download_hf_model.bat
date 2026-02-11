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

REM 解析 --token / -t 参数
set "model_name="
set "download_path="
set "max_retries="

if "%1"=="--token" (
    if "%2"=="" (
        echo [ERROR] --token 需要指定令牌值
        exit /b 1
    )
    set "HF_TOKEN=%2"
    set "HUGGING_FACE_HUB_TOKEN=%2"
    echo [INFO] 已设置访问令牌 (从命令行)
    shift
    shift
)

if "%1"=="-t" (
    if "%2"=="" (
        echo [ERROR] -t 需要指定令牌值
        exit /b 1
    )
    set "HF_TOKEN=%2"
    set "HUGGING_FACE_HUB_TOKEN=%2"
    echo [INFO] 已设置访问令牌 (从命令行)
    shift
    shift
)

if "%1"=="--no-proxy" (
    set "HTTP_PROXY="
    set "http_proxy="
    set "HTTPS_PROXY="
    set "https_proxy="
    set "ALL_PROXY="
    set "all_proxy="
    set "no_proxy="
    set "NO_PROXY="
    echo [INFO] 已禁用代理，使用直连网络
    shift
)

if "%1"=="--mirror" (
    set "HF_ENDPOINT=https://hf-mirror.com"
    set "MIRROR_MODE=force"
    echo [INFO] 已强制使用镜像站点: https://hf-mirror.com
    shift
)

if "%1"=="--no-mirror" (
    set "HF_ENDPOINT="
    set "MIRROR_MODE=disable"
    echo [INFO] 已禁用镜像站点，将直连 Hugging Face 官方
    shift
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
if "%MIRROR_MODE%"=="force" (
    echo [SUCCESS] 已强制使用镜像站点: %HF_ENDPOINT%
    exit /b 0
)
if "%MIRROR_MODE%"=="disable" (
    echo [INFO] 已禁用镜像站点，将直连 Hugging Face 官方
    exit /b 0
)
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

REM 使用 hf cache ls 命令验证下载（huggingface_hub 1.4+ 使用 ls 替代已移除的 scan）
echo [INFO] 使用 hf cache ls 验证下载状态...

REM 检查 hf 命令是否可用
where hf >nul 2>&1
if errorlevel 1 (
    echo [ERROR] hf 命令不可用，无法验证下载完整性
    exit /b 1
)

REM 执行 hf cache ls 命令（1.4+ 为 ls）
set "cache_ls_output="
for /f "delims=" %%i in ('hf cache ls 2^>^&1') do set "cache_ls_output=!cache_ls_output! %%i"

REM 检查模型是否在缓存中（hf cache ls 输出 ID 格式为 model/org/repo）
echo %cache_ls_output% | findstr /i "model/%model_name%" >nul
if errorlevel 1 (
    echo %cache_ls_output% | findstr /i "%model_name%" >nul
    if errorlevel 1 (
        echo [WARNING] 在缓存中未找到模型 %model_name%
        echo [INFO] 这可能意味着：
        echo [INFO] 1. 模型下载失败
        echo [INFO] 2. 模型下载到了不同的位置
        echo [INFO] 3. 缓存列表结果不完整
        exit /b 1
    )
)
echo [SUCCESS] ✓ 模型 %model_name% 已成功下载到缓存

REM 显示缓存列表
echo.
echo [INFO] 📊 Hugging Face 缓存列表:
echo ==================================
hf cache ls
echo ==================================
echo.

exit /b 0

:show_completion
echo [SUCCESS] === 下载完成！ ===

REM 显示下载统计
call :show_download_stats

REM 获取模型的真实下载位置
call :get_model_cache_path

exit /b 0

:show_download_stats
echo [INFO] 下载统计信息:
echo ==================================

REM 获取模型的真实缓存路径和统计信息（hf cache ls 为 1.4+ 用法）
set "model_cache_path="
set "model_size="
set "file_count="

REM 执行 hf cache ls 获取模型信息，格式为 ID SIZE LAST_ACCESSED LAST_MODIFIED REFS
set "model_info="
for /f "delims=" %%i in ('hf cache ls 2^>^&1') do (
    set "line=%%i"
    echo !line! | findstr /i "model/%model_name%" >nul
    if not errorlevel 1 set "model_info=%%i"
)

if not "!model_info!"=="" (
    REM 第 2 列为大小
    for /f "tokens=2" %%a in ("!model_info!") do set "model_size=%%a"
    REM 构造缓存路径：%USERPROFILE%\.cache\huggingface\hub\models--org--repo\snapshots\<commit>
    set "repo_dir=models--%model_name:/=--%"
    set "cache_base=%USERPROFILE%\.cache\huggingface\hub\!repo_dir!\snapshots"
    if exist "!cache_base!" (
        for /f "delims=" %%s in ('dir /b "!cache_base!" 2^>nul') do (
            if "!model_cache_path!"=="" set "model_cache_path=!cache_base!\%%s"
        )
    )
    if not "!model_cache_path!"=="" (
        echo 模型缓存路径: !model_cache_path!
        echo 模型大小: !model_size!
    ) else (
        echo 模型大小: !model_size!
    )
) else (
    echo [WARNING] 无法获取模型缓存信息，可能模型下载失败或需 huggingface_hub 1.4+
)

echo ==================================
exit /b 0

:get_model_cache_path
REM 获取模型的真实下载位置（hf cache ls 为 1.4+ 用法，路径由缓存目录构造）
set "model_cache_path="

set "repo_dir=models--%model_name:/=--%"
set "cache_base=%USERPROFILE%\.cache\huggingface\hub\!repo_dir!\snapshots"
if exist "!cache_base!" (
    for /f "delims=" %%s in ('dir /b "!cache_base!" 2^>nul') do (
        if "!model_cache_path!"=="" set "model_cache_path=!cache_base!\%%s"
    )
)

if not "!model_cache_path!"=="" (
    echo [SUCCESS] 模型已成功下载到: !model_cache_path!
) else (
    echo [SUCCESS] 模型已成功下载到 Hugging Face 默认缓存目录
)
exit /b 0

:show_help
echo Hugging Face 模型下载脚本
echo.
echo 用法: %0 [选项] ^<model_name^> [download_path] [max_retries]
echo.
echo 选项:
echo   -t, --token TOKEN   Hugging Face 访问令牌 (用于 gated 模型，也可通过 HF_TOKEN 环境变量设置)
echo   --no-proxy         禁用代理，直连网络
echo   --mirror           强制使用镜像站点 (https://hf-mirror.com)
echo   --no-mirror        不使用镜像站点
echo.
echo 参数:
echo   model_name     要下载的模型名称 (例如: meta-llama/Llama-2-7b-chat-hf)
echo   download_path  下载路径 (可选，默认: 使用 hf 默认目录)
echo   max_retries    最大重试次数 (可选，默认: 5)
echo.
echo 示例:
echo   %0 meta-llama/Llama-2-7b-chat-hf
echo   %0 --token hf_xxxx black-forest-labs/FLUX.2-dev
echo   %0 --no-proxy meta-llama/Llama-2-7b-chat-hf
echo   %0 --mirror meta-llama/Llama-2-7b-chat-hf
echo   %0 --no-mirror meta-llama/Llama-2-7b-chat-hf
echo   %0 -t %%HF_TOKEN%% meta-llama/Llama-2-7b-chat-hf .\my_models 10
echo   %0 "microsoft/DialoGPT-medium" C:\data\models 3
echo.
echo 注意事项:
echo   - 确保已安装 huggingface_hub CLI 工具
echo   - 对于 gated/私有模型，需使用 --token 或 HF_TOKEN，或运行 'hf auth login'
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
