#!/usr/bin/env bash
#
# 根据 stars.txt（每行 owner/repo）批量 star 仓库（当前 Token 对应账号）。
# 依赖: curl
#
# 用法:
#   ./import_github_stars.sh --input stars.txt
#   ./import_github_stars.sh --input stars.txt --dry-run
#

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
根据文本列表批量 star 仓库（GitHub REST API）。

用法:
  ./import_github_stars.sh [选项]

选项:
  --input FILE     输入文件：每行一个 owner/repo（可含空行与 # 注释）
  --token TOKEN    GitHub Token（也可用环境变量 GITHUB_TOKEN）
  --token-file FILE 从文件读取 Token（会去空白）
  --dry-run        只打印将处理的条目，不调用 API
  --delay SEC      每次请求之间的休眠秒数（默认 0；大量操作时建议 0.05~0.2）
  --report FILE    报告输出路径（默认: import_report.txt）
  -h, --help       显示本帮助

环境变量:
  GITHUB_TOKEN              最低优先级（会被 --token / --token-file / GITHUB_TOKEN_FILE 覆盖）
  GITHUB_TOKEN_FILE         第三优先级
  GITHUB_API_BASE           默认 https://api.github.com（GitHub Enterprise 见 README）
  GITHUB_AUTH_HEADER_STYLE  可选 token 或 bearer（默认 bearer）
  GITHUB_STAR_MIGRATE_DEBUG=1  打印 Token 来源、长度、掩码前缀

依赖:
  curl

说明:
  - GitHub 对 PUT star 通常返回 204（已 star 再次 PUT 一般仍为 204）。
  - 若仓库不存在、无权限访问私有仓库等，会记录为失败行。
EOF
}

TOKEN_CLI=""
TOKEN_FILE_ARG=""
INPUT=""
DRY_RUN=0
DELAY="0"
REPORT="import_report.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)      TOKEN_CLI="${2:-}"; shift 2 ;;
    --token-file) TOKEN_FILE_ARG="${2:-}"; shift 2 ;;
    --input)    INPUT="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --delay)    DELAY="${2:-}"; shift 2 ;;
    --report)   REPORT="${2:-}"; shift 2 ;;
    -h|--help)  show_help; exit 0 ;;
    *)          log_error "未知参数: $1"; show_help; exit 2 ;;
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
  log_error "未提供 Token。请使用 --token、--token-file、GITHUB_TOKEN_FILE 或 GITHUB_TOKEN。"
  exit 1
fi

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
  log_error "Token 在去空白后为空，请检查 Token 来源。"
  exit 1
fi

if [[ "${TOKEN}" == *'*'* ]]; then
  log_error "Token 中包含字符 *，像是占位符而非真实 Token。"
  exit 1
fi

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
  log_warn "DEBUG: Token 来源=${TOKEN_SOURCE}，长度=${tl}，前缀=${pre}…后缀=…${suf}"
fi

if [[ -z "${INPUT}" ]]; then
  log_error "请使用 --input 指定 stars.txt"
  exit 1
fi

if [[ ! -f "${INPUT}" ]]; then
  log_error "找不到输入文件: ${INPUT}"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  log_error "未找到 curl，请先安装。"
  exit 1
fi

API_VERSION="2022-11-28"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"
GITHUB_API_BASE="${GITHUB_API_BASE%/}"
STAR_API_BASE="${GITHUB_API_BASE}/user/starred"

star_repo() {
  local full_name="$1"
  local owner repo
  IFS='/' read -r owner repo <<<"${full_name}"
  if [[ -z "${owner}" || -z "${repo}" || "${full_name}" != *"/"* ]]; then
    echo "BAD_FORMAT|${full_name}"
    return 2
  fi

  local url="${STAR_API_BASE}/${owner}/${repo}"
  local tmp body code

  tmp="$(mktemp)"
  code="$(curl -sS -o "${tmp}" -w "%{http_code}" -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "${AUTH_HDR}" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    -H "Content-Length: 0" \
    "${url}")"

  body="$(cat "${tmp}" 2>/dev/null || true)"
  rm -f "${tmp}"

  case "${code}" in
    204) echo "OK|${full_name}"; return 0 ;;
    304) echo "OK|${full_name}"; return 0 ;;
    404) echo "NOT_FOUND|${full_name}|${body}"; return 1 ;;
    403)
      # 限流时 GitHub 可能返回 403
      echo "FORBIDDEN|${full_name}|${body}"; return 3 ;;
    401) echo "UNAUTHORIZED|${full_name}|${body}"; return 4 ;;
    *)   echo "HTTP_${code}|${full_name}|${body}"; return 5 ;;
  esac
}

sleep_for_rate_limit() {
  local seconds="$1"
  if awk "BEGIN { exit !(${seconds} > 0) }"; then
    sleep "${seconds}"
  fi
}

: > "${REPORT}"
{
  echo "GitHub stars import report"
  echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Input: ${INPUT}"
  echo "Dry-run: ${DRY_RUN}"
  echo "----------------------------------------"
} >> "${REPORT}"

ok=0
fail=0
bad=0
total=0

while IFS= read -r line || [[ -n "${line}" ]]; do
  # trim
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  [[ -z "${line}" ]] && continue
  [[ "${line}" == \#* ]] && continue

  total=$((total + 1))

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "[dry-run] would star: ${line}"
    echo "DRY_RUN|${line}" >> "${REPORT}"
    ok=$((ok + 1))
    continue
  fi

  result="$(star_repo "${line}" || true)"
  status="${result%%|*}"

  case "${status}" in
    OK)
      log_success "star: ${line}"
      echo "${result}" >> "${REPORT}"
      ok=$((ok + 1))
      ;;
    BAD_FORMAT)
      log_error "格式错误（应为 owner/repo）: ${line}"
      echo "${result}" >> "${REPORT}"
      bad=$((bad + 1))
      ;;
    FORBIDDEN)
      log_warn "403: ${line} — 可能是私有仓库无权限或触发限流。详情见报告。"
      echo "${result}" >> "${REPORT}"
      fail=$((fail + 1))
      ;;
    *)
      log_error "失败 (${status}): ${line}"
      echo "${result}" >> "${REPORT}"
      fail=$((fail + 1))
      ;;
  esac

  sleep_for_rate_limit "${DELAY}"
done < "${INPUT}"

{
  echo "----------------------------------------"
  echo "Finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Total lines processed: ${total}"
  echo "OK (or dry-run): ${ok}"
  echo "Failed: ${fail}"
  echo "Bad format: ${bad}"
} >> "${REPORT}"

log_info "统计 — 处理行数: ${total}, 成功/dry-run: ${ok}, 失败: ${fail}, 格式错误: ${bad}"
log_info "报告已写入: ${REPORT}"

if [[ "${fail}" -gt 0 || "${bad}" -gt 0 ]]; then
  exit 1
fi
exit 0
