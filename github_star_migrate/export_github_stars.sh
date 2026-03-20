#!/usr/bin/env bash
#
# 导出当前 GitHub 账号（由 Token 代表）starred 的仓库列表。
# 依赖: curl, jq
#
# 用法:
#   export GITHUB_TOKEN=ghp_xxx
#   ./export_github_stars.sh [--output-dir DIR] [--prefix NAME]
#
# 或:
#   ./export_github_stars.sh --token ghp_xxx

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error()   { echo -e "${RED}[ERR]${NC}  $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

show_help() {
  cat <<'EOF'
导出当前 Token 对应账号 star 过的仓库列表（GitHub REST API）。

用法:
  ./export_github_stars.sh [选项]

选项:
  --token TOKEN       GitHub Token（也可用环境变量 GITHUB_TOKEN）
  --token-file FILE   从文件读取 Token（文件内容会去空白；避免命令行/引号问题）
  --output-dir DIR    输出目录（默认: 当前目录）
  --prefix NAME       输出文件名前缀（默认: stars）
  -h, --help          显示本帮助

环境变量:
  GITHUB_TOKEN                 最低优先级；会被 --token / --token-file / GITHUB_TOKEN_FILE 覆盖
  GITHUB_TOKEN_FILE            第三优先级（低于 --token、--token-file）
  GITHUB_API_BASE              API 根地址（默认 https://api.github.com；GitHub Enterprise 示例见 README）
  GITHUB_AUTH_HEADER_STYLE     可选 token 或 bearer（默认 bearer）。个别环境可试 token
  GITHUB_STAR_MIGRATE_DEBUG=1  打印 Token 来源、长度、掩码前缀（不含完整 Secret）

输出:
  <prefix>.txt   每行一个 owner/repo
  <prefix>.json  完整分页合并后的 JSON 数组（与 /user/starred 单页结构一致）

依赖:
  curl, jq

示例:
  export GITHUB_TOKEN=ghp_xxxx
  ./export_github_stars.sh --output-dir ./out --prefix my_stars
EOF
}

# Token 优先级（高→低）：--token > --token-file > GITHUB_TOKEN_FILE > GITHUB_TOKEN
# 避免环境里残留的旧 GITHUB_TOKEN 导致「写了文件却仍 401」
TOKEN_CLI=""
TOKEN_FILE_ARG=""
OUT_DIR="."
PREFIX="stars"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)       TOKEN_CLI="${2:-}"; shift 2 ;;
    --token-file)  TOKEN_FILE_ARG="${2:-}"; shift 2 ;;
    --output-dir)  OUT_DIR="${2:-}"; shift 2 ;;
    --prefix)      PREFIX="${2:-}"; shift 2 ;;
    -h|--help)     show_help; exit 0 ;;
    *)             log_error "未知参数: $1"; show_help; exit 2 ;;
  esac
done

TOKEN=""
TOKEN_SOURCE=""
if [[ -n "${TOKEN_CLI}" ]]; then
  TOKEN="${TOKEN_CLI}"
  TOKEN_SOURCE="--token"
elif [[ -n "${TOKEN_FILE_ARG}" ]]; then
  if [[ ! -f "${TOKEN_FILE_ARG}" ]]; then
    log_error "找不到 --token-file：${TOKEN_FILE_ARG}"
    exit 1
  fi
  TOKEN="$(cat "${TOKEN_FILE_ARG}")"
  TOKEN_SOURCE="--token-file(${TOKEN_FILE_ARG})"
elif [[ -n "${GITHUB_TOKEN_FILE:-}" ]]; then
  if [[ ! -f "${GITHUB_TOKEN_FILE}" ]]; then
    log_error "找不到 GITHUB_TOKEN_FILE：${GITHUB_TOKEN_FILE}"
    exit 1
  fi
  TOKEN="$(cat "${GITHUB_TOKEN_FILE}")"
  TOKEN_SOURCE="GITHUB_TOKEN_FILE(${GITHUB_TOKEN_FILE})"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  TOKEN="${GITHUB_TOKEN}"
  TOKEN_SOURCE="GITHUB_TOKEN(环境变量)"
fi

if [[ -z "${TOKEN}" ]]; then
  log_error "未提供 Token。请使用：--token、--token-file、GITHUB_TOKEN_FILE 或 GITHUB_TOKEN。"
  exit 1
fi

# 从网页/文档复制 Token 时容易带入首尾空格或换行，会导致 HTTP 401
trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
TOKEN="${TOKEN#Bearer }"
TOKEN="${TOKEN#token }"
TOKEN="$(trim_whitespace "${TOKEN}")"

if [[ -z "${TOKEN}" ]]; then
  log_error "Token 在去空白后为空，请检查 Token 来源文件或变量。"
  exit 1
fi

# 避免把教程里的占位符当真（用户有时会照抄 ghp_***）
if [[ "${TOKEN}" == *'*'* ]]; then
  log_error "Token 中包含字符 *，像是占位符而非真实 Token。请粘贴 GitHub 生成后的完整字符串。"
  exit 1
fi

# Classic PAT 如遇极少数环境不识别 Bearer，可设: GITHUB_AUTH_HEADER_STYLE=token
case "${GITHUB_AUTH_HEADER_STYLE:-bearer}" in
  token|TOKEN) AUTH_HDR="Authorization: token ${TOKEN}" ;;
  *)           AUTH_HDR="Authorization: Bearer ${TOKEN}" ;;
esac

if [[ -n "${GITHUB_STAR_MIGRATE_DEBUG:-}" ]]; then
  tl="${#TOKEN}"
  pre="${TOKEN:0:8}"
  suf=""
  if [[ "${tl}" -ge 4 ]]; then
    suf="${TOKEN: -4}"
  fi
  log_warn "DEBUG: Token 来源=${TOKEN_SOURCE}，长度=${tl}，前缀=${pre}…后缀=…${suf}（请勿截图外传）"
fi

if ! command -v curl &>/dev/null; then
  log_error "未找到 curl，请先安装。"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log_error "未找到 jq，请先安装（导出 JSON 需要 jq）。"
  exit 1
fi

mkdir -p "${OUT_DIR}"
TXT_PATH="${OUT_DIR}/${PREFIX}.txt"
JSON_PATH="${OUT_DIR}/${PREFIX}.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

API_VERSION="2022-11-28"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"
GITHUB_API_BASE="${GITHUB_API_BASE%/}"
BASE_URL="${GITHUB_API_BASE}/user/starred"
USER_API="${GITHUB_API_BASE}/user"

gh_curl() {
  local url="$1"
  local out="$2"
  local http_code
  http_code="$(curl -sS -o "${out}" -w "%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "${AUTH_HDR}" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    "${url}")"
  echo "${http_code}"
}

print_auth_troubleshooting() {
  log_error "排查建议："
  log_error "  1) 在 GitHub 上确认 Token 未被 Revoke，且未过期。"
  log_error "  2) 用文件传 Token（避免引号/换行）：printf '%s' '真实Token' > ~/.github_pat && chmod 600 ~/.github_pat"
  log_error "     然后：GITHUB_TOKEN_FILE=\$HOME/.github_pat ./export_github_stars.sh"
  log_error "  3) 确认未使用 sudo 运行脚本（sudo 会丢环境变量）。"
  log_error "  4) 若 shell 里曾 export 过旧的 GITHUB_TOKEN，请先 unset GITHUB_TOKEN 再改用 --token-file。"
  log_error "  5) 尝试：GITHUB_AUTH_HEADER_STYLE=token ./export_github_stars.sh"
  log_error "  6) 排查：GITHUB_STAR_MIGRATE_DEBUG=1 ./export_github_stars.sh（只打印来源/长度/掩码前缀）"
  log_error "  7) 若是 GitHub Enterprise，请设置 GITHUB_API_BASE（例如 https://github.example.com/api/v3）。"
}

log_info "预检：GET ${USER_API} …"
user_body="${TMP_DIR}/_user_probe.json"
code="$(gh_curl "${USER_API}" "${user_body}")"
if [[ "${code}" != "200" ]]; then
  if [[ "${code}" == "401" ]]; then
    msg="$(jq -r '.message // empty' "${user_body}" 2>/dev/null || true)"
    log_error "预检失败 HTTP 401：${msg:-Bad credentials}（${USER_API}）"
    print_auth_troubleshooting
  else
    log_error "预检失败：HTTP ${code}（${USER_API}）"
    head -c 400 "${user_body}" 2>/dev/null | tr -d '\r' >&2 || true
    echo >&2
  fi
  exit 1
fi
gh_login="$(jq -r '.login // empty' "${user_body}" 2>/dev/null || true)"
log_success "Token 有效，当前 API 用户：${gh_login:-?}"

log_info "开始分页拉取 starred 仓库…"
page=1
while true; do
  url="${BASE_URL}?per_page=100&page=${page}"
  # 使用零填充序号，避免 page_10.json 排在 page_2.json 之前
  body="${TMP_DIR}/page_$(printf '%05d' "${page}").json"
  code="$(gh_curl "${url}" "${body}")"

  if [[ "${code}" == "401" ]]; then
    msg="$(jq -r '.message // empty' "${body}" 2>/dev/null || true)"
    log_error "HTTP 401：${msg:-Bad credentials}"
    print_auth_troubleshooting
    exit 1
  fi

  if [[ "${code}" == "403" ]]; then
    # 可能是限流或权限不足
    msg="$(jq -r '.message // empty' "${body}" 2>/dev/null || true)"
    log_warn "HTTP 403：${msg:-无详情}。若为限流，请稍后再试。"
    exit 1
  fi

  if [[ "${code}" != "200" ]]; then
    log_error "请求失败：HTTP ${code}"
    cat "${body}" >&2 || true
    exit 1
  fi

  len="$(jq 'length' "${body}")"
  if [[ "${len}" -eq 0 ]]; then
    break
  fi

  log_info "已获取第 ${page} 页，本页 ${len} 条"
  page=$((page + 1))
done

# 合并各页 JSON（最后一页通常为 []，会在下面剔除）
shopt -s nullglob
pages=( "${TMP_DIR}"/page_*.json )
if [[ ${#pages[@]} -eq 0 ]]; then
  log_error "内部错误：未找到分页文件。"
  exit 1
fi

# 去掉最后一页如果是空数组（当 break 时当前 body 是空页）
last_idx=$((${#pages[@]} - 1))
last_file="${pages[$last_idx]}"
if [[ "$(jq 'length' "${last_file}")" -eq 0 ]]; then
  pages=( "${pages[@]:0:${last_idx}}" )
fi

if [[ ${#pages[@]} -eq 0 ]]; then
  log_warn "star 列表为空。"
  : > "${TXT_PATH}"
  echo '[]' > "${JSON_PATH}"
  log_success "已写入空文件: ${TXT_PATH}, ${JSON_PATH}"
  exit 0
fi

jq -s 'add' "${pages[@]}" > "${JSON_PATH}"

jq -r '.[].full_name' "${JSON_PATH}" | sort -u > "${TXT_PATH}"

count="$(jq 'length' "${JSON_PATH}")"
log_success "导出完成：共 ${count} 个仓库"
log_info "文本列表: ${TXT_PATH}"
log_info "JSON 数据: ${JSON_PATH}"
