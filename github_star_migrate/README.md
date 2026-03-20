# GitHub Star 迁移工具

将 **账号 A** 的 Star 列表导出为文件，再用 **账号 B** 的 Token 批量 Star 相同仓库。

## 环境要求

- **Bash**：Linux / macOS 自带；Windows 请使用 **Git Bash** 或 **WSL**。
- **curl**：一般系统已预装。
- **jq**：仅 **导出** 脚本需要（合并分页 JSON）。  
  - Ubuntu: `sudo apt install jq`  
  - macOS: `brew install jq`  
  - Windows: 通过 Git for Windows 可选组件、Scoop、Chocolatey 等安装 `jq`。

## 创建 Token

使用 GitHub **Fine-grained PAT**（推荐）或 **Classic PAT**：

| 阶段 | 说明 |
|------|------|
| 导出（账号 A） | Token 需能读取 **当前用户** 的 Star 列表（`GET /user/starred`）。在创建 Token 页面勾选与「读取账户/仓库元数据」相关的**最小只读**权限即可。 |
| 导入（账号 B） | Token 需能对目标仓库执行 Star（`PUT /user/starred/{owner}/{repo}`）。勾选与 **交互/Star** 相关的**最小写权限**（以 GitHub 页面选项为准）。 |

**安全建议**：仅为本次任务创建短期 Token，完成后在 GitHub 设置里删除；不要将 Token 写入仓库或截图分享。

## 脚本说明

| 文件 | 作用 |
|------|------|
| `export_github_stars.sh` | 用 **账号 A** 的 Token 拉取所有 Star，生成 `*.txt` 与 `*.json` |
| `import_github_stars.sh` | 用 **账号 B** 的 Token 按 `*.txt` 批量 Star |

## 使用步骤

### 1. 赋予执行权限（Linux / macOS）

```bash
chmod +x export_github_stars.sh import_github_stars.sh
```

### 2. 导出（账号 A）

```bash
cd github_star_migrate

export GITHUB_TOKEN='账号A的Token'
./export_github_stars.sh --output-dir ./out --prefix stars
```

生成：

- `out/stars.txt`：每行一个 `owner/repo`，供导入使用。
- `out/stars.json`：API 返回的完整数组（便于备份或二次处理）。

也可临时指定 Token：

```bash
./export_github_stars.sh --token 'ghp_xxx' --output-dir ./out --prefix stars
```

### 3.（可选）从 JSON 生成 txt

若你手里只有 `stars.json`：

```bash
jq -r '.[].full_name' stars.json | sort -u > stars.txt
```

### 4. 导入预演（账号 B，不真正 Star）

```bash
export GITHUB_TOKEN='账号B的Token'
./import_github_stars.sh --input ./out/stars.txt --dry-run
```

### 5. 正式导入（账号 B）

Star 数量很大时，建议加一点间隔，降低触发限流概率：

```bash
export GITHUB_TOKEN='账号B的Token'
./import_github_stars.sh --input ./out/stars.txt --delay 0.1 --report import_report.txt
```

结束后查看 `import_report.txt`：成功、失败原因（如仓库已删除、私有仓库无权限等）。

## 输入文件格式

`stars.txt` 支持：

- 每行一个 `owner/repo`，例如 `torvalds/linux`
- 空行忽略
- 以 `#` 开头的行为注释

## 常见问题

1. **HTTP 401（Bad credentials）**  
   - **401 表示 Token 本身不被接受**（错字、已撤销、已过期、复制时带了**空格/换行**），**不是**「少勾了某个 scope」（那种更常见是 **403**）。  
   - 不要把 Token 贴在聊天、截图、命令历史里；泄露后请到 GitHub **立刻撤销**并重新生成。  
   - **不要把教程里的 `ghp_***` 当成真实 Token**：必须是在 GitHub 页面上生成后显示的**完整**字符串（脚本若检测到 Token 里含 `*` 会直接报错）。  
   - **Token 优先级（脚本已按此实现）**：`--token` ＞ `--token-file` ＞ `GITHUB_TOKEN_FILE` ＞ `GITHUB_TOKEN`。  
     若你曾在 `~/.bashrc` 里 `export` 过**旧的、已失效的** `GITHUB_TOKEN`，即使用文件里的新 Token，旧版脚本也会一直用环境变量里的值 → 请先 **`unset GITHUB_TOKEN`**，或更新到本仓库最新脚本。  
   - **推荐用文件放 Token**（避免 shell 引号、换行、历史记录）：  
     ```bash
     printf '%s' '这里粘贴完整Token' > ~/.github_pat && chmod 600 ~/.github_pat
     unset GITHUB_TOKEN
     ./export_github_stars.sh --token-file "$HOME/.github_pat" --output-dir ./out
     ```  
     或使用：`GITHUB_TOKEN_FILE="$HOME/.github_pat" ./export_github_stars.sh ...`（同样优先于环境变量里的 `GITHUB_TOKEN`）  
   - **调试（不打印完整 Token）**：`GITHUB_STAR_MIGRATE_DEBUG=1 ./export_github_stars.sh` 会输出 Token **来源**、**长度**、**前后若干字符**（便于确认是否读错文件）。  
   - 自检（把 `YOUR_TOKEN` 换成新 Token，勿泄露）：  
     `curl -sS -H "Accept: application/vnd.github+json" -H "Authorization: Bearer YOUR_TOKEN" https://api.github.com/user`  
     应返回 JSON 里的 `"login"`；若仍是 401，说明 Token 无效。  
   - 不要用 **`sudo ./export_github_stars.sh`**（默认会丢掉当前用户的 `GITHUB_TOKEN`）。  
   - 极少数环境可尝试 Classic PAT 使用传统头：  
     `GITHUB_AUTH_HEADER_STYLE=token ./export_github_stars.sh ...`  
   - **GitHub Enterprise**：需设置与官方 `api.github.com` 不同的 API 根地址，例如：  
     `export GITHUB_API_BASE='https://github.example.com/api/v3'`

2. **403 / rate limit**  
   增大 `--delay`，或等待一段时间后重试；失败项可单独摘到新文件再跑一遍。

3. **私有仓库**  
   若账号 A Star 了 B 无法访问的私有仓库，导入会失败，属正常现象。

4. **重复执行**  
   对已 Star 的仓库再次 `PUT` 一般仍返回 204，重复跑通常安全；报告里仍会统计每次调用结果。

5. **与网页上 Star 数量不一致**  
   核对是否包含已删除/重命名仓库、或 Token 权限不足导致分页中断。

## 相关 API

- [List repositories starred by the authenticated user](https://docs.github.com/en/rest/activity/starring#list-repositories-starred-by-the-authenticated-user)
- [Star a repository for the authenticated user](https://docs.github.com/en/rest/activity/starring#star-a-repository-for-the-authenticated-user)

## 许可证

与本仓库一致（MIT）。
