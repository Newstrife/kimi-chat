# Kimi Chat —— 企业知识库 AI 问答助手

一个自托管的企业级 AI Agent Web 应用。员工用自然语言提问，系统从**企业内部的文件和数据库**中检索相关内容，连同问题一起交给 Kimi（k3 大模型）回答，并标注每个回答的数据来源。

技术栈：Rails 8.1 + SQLite + 自研 [kimi-agent-sdk-ruby](../kimi-agent-sdk-ruby)（封装 Kimi Code CLI）+ 原生 JS 前端（无构建步骤、无外网 CDN）。

---

## 功能一览

| 功能 | 说明 |
|---|---|
| 企业知识问答 | 提问时自动检索企业文件和数据库，注入上下文后由 AI 回答，注明来源 |
| 文件检索 | 关键词分词评分（内容 + 文件名加权），阈值制入选，命中后注入完整文件 |
| 数据库接入 | 可配置多数据源（SQLite / PostgreSQL / MySQL / SQL Server），只读、仅 SELECT |
| Markdown 渲染 | 表格、列表、代码块、标题等完整渲染，XSS 过滤 |
| 数据图表 | AI 输出 chart JSON 块，前端用 Chart.js 渲染柱状/折线/饼图 |
| 会话管理 | 侧边栏历史会话列表，点击切换续聊，可删除；消息持久化到数据库 |
| 审计日志 | 每次提问、文件读取、SQL 执行均记录（动作、内容、IP、时间） |
| 数据源管理页 | `/databases` 查看各数据源连接状态、表清单 |
| 访问控制 | 全站 HTTP Basic 认证；局域网 IP + 端口访问 |
| 异步问答 | 后台线程执行 AI 调用，前端轮询获取结果，避免长请求超时 |
| 传输层加固 | SDK 内置读超时、进程清理、行缓冲保护 |

---

## 工作原理

### 整体架构

```
浏览器（侧边栏 + 聊天区，原生 JS）
   │  POST /chat/ask（立即返回）     GET /chat/history（轮询结果）
   ▼
Rails（Puma）
   ├── ChatController ──► ChatWorker（后台线程）
   │                         │
   │                         ├── EnterpriseRetriever（检索注入）
   │                         │      ├── EnterpriseFileService（文件：白名单目录）
   │                         │      └── EnterpriseQueryService（数据库：多数据源配置）
   │                         │
   │                         └── KimiAgentSDK.query()
   │                                └── kimi CLI（子进程，stream-JSON）
   │                                       └── Kimi k3 大模型（API）
   │
   ├── DatabasesController（/databases 管理页）
   └── SQLite（chat_sessions / messages / audit_logs）
```

### 一次问答的完整链路

1. 前端提交问题，`ChatController#ask` 落库用户消息，立即返回 `session_id`
2. `ChatWorker` 后台线程启动，先跑 `EnterpriseRetriever.build_context`：
   - **分词**：问题切成"中文段/字母数字段"，中文 3 字以上再切二元组
   - **评分**：每个文件得分 = 关键词内容命中（单词封顶 10 分）+ 文件名命中 ×3
   - **入选**：得分 ≥ 2 且 ≥ 最高分 25% 的文件全部入选（不限个数），累计注入不超过 60KB
   - **数据库**：遍历所有启用的数据源，注入表结构 + 每表前 10 行样例
3. 检索结果拼成"企业数据上下文"，附在用户问题前，通过 `KimiAgentSDK` 启动 `kimi` CLI 子进程发给 k3 模型
4. AI 的回复（含 Markdown、chart 块）落库为 assistant 消息，前端轮询 `/chat/history` 拿到后渲染

### 文件检索的技术细节

见 `app/services/enterprise_retriever.rb`。当前是**纯关键词检索**（无语义理解），规则全部可调：

| 常量 | 含义 | 默认值 |
|---|---|---|
| `MIN_SCORE` | 入选绝对阈值 | 2 分 |
| `RELATIVE_THRESHOLD` | 不低于最高分的比例 | 25% |
| `MAX_TOTAL_BYTES` | 注入内容总量上限 | 60 KB |
| `TOKEN_CONTENT_CAP` | 单关键词内容得分封顶 | 10 分 |

文件读取（`enterprise_file_service.rb`）带安全边界：白名单目录（防目录穿越）、单文件 20KB 上限（超出标注截断）、UTF-8/GBK 编码自动归一、每次读取写审计。

已知局限：不懂同义词和语义相关（问"工资"匹配不到"薪酬"）。文件量大后应升级为向量检索（embedding）。

### 数据库接入

`config/enterprise_databases.yml` 定义多个命名数据源，`EnterpriseQueryService` 按 adapter 分发（sqlite3 / pg / mysql2 / tiny_tds，后三者按需启用 Gemfile 中注释的 gem）。统一安全约束：**只读连接、仅允许 SELECT、限 100 行、5 秒超时、每次查询写审计**。密码等敏感字段用 `<%= ENV["..."] %>` 注入。

### 异步模型

AI 调用可能耗时几十秒，`ask` 接口立即返回，`ChatWorker` 在后台线程完成检索 + 调用 + 落库，前端每 2.5 秒轮询一次历史接口。SDK 层（kimi-agent-sdk-ruby）另有 `read_timeout`/`idle_timeout` 保护、子进程注册表 + at_exit 清理、优雅关停阶梯（等 3 秒 → TERM → KILL）。

---

## 目录结构（关键文件）

```
kimi_chat/
├── app/
│   ├── controllers/
│   │   ├── chat_controller.rb        # 聊天页 + ask/history/sessions/delete 接口
│   │   ├── databases_controller.rb   # /databases 数据源管理页
│   │   └── application_controller.rb # HTTP Basic 认证
│   ├── models/                       # ChatSession / Message / AuditLog
│   ├── services/
│   │   ├── chat_worker.rb            # 后台问答执行器
│   │   ├── enterprise_retriever.rb   # 检索注入（分词/评分/阈值入选）
│   │   ├── enterprise_file_service.rb# 文件读取（白名单/编码/审计）
│   │   └── enterprise_query_service.rb # 多数据源只读查询
│   └── views/chat/index.html.erb     # 侧边栏 + 聊天区（原生 JS）
├── config/
│   ├── enterprise_databases.yml      # 数据源配置（重点）
│   └── environments/development.rb   # 含 config.hosts.clear（允许 IP 访问）
├── public/
│   ├── vendor/                       # marked / DOMPurify / Chart.js（本地化）
│   └── js/                           # markdown-render.js / chart-render.js
├── check_*.rb                        # 各功能自检脚本（见下）
└── db/                               # 迁移 + development.sqlite3
```

## 运行

```bash
# 依赖：Ruby 3.2+（开发用 4.0）、kimi CLI（已配置 ~/.kimi-code/config.toml）
cd kimi_chat
bundle install
bin/rails db:migrate
bin/rails server -p 3001 -b 0.0.0.0
```

访问 `http://localhost:3001/`（局域网为 `http://<本机IP>:3001/`），登录 `admin / admin123`（用环境变量 `KIMI_CHAT_USER` / `KIMI_CHAT_PASSWORD` 覆盖）。

## 配置

| 环境变量 | 作用 | 默认 |
|---|---|---|
| `ENTERPRISE_DATA_DIR` | 企业文件知识库目录 | `E:/brjaiagent/enterprise_data` |
| `ENTERPRISE_DB_PATH` | SQLite 数据源路径（company 源） | `<知识库目录>/company.db` |
| `KIMI_CHAT_USER` / `KIMI_CHAT_PASSWORD` | Basic 认证账号 | `admin` / `admin123` |

接入新数据：文件直接放进知识库目录（`.md/.csv/.txt/.json/.log`）；新数据库在 `config/enterprise_databases.yml` 中添加数据源。

## 自检脚本

根目录的 `check_*.rb` 用 `bin/rails runner <脚本>` 运行，覆盖：数据源（`check_datasources`）、会话 API（`check_sessions_api`）、检索阈值（`check_threshold`）、文件编码（`check_encoding`/`check_gbk`）、完整文件注入（`check_full_file`）等。

## 相关项目

- [kimi-agent-sdk-ruby](../kimi-agent-sdk-ruby) —— 本应用依赖的 Kimi Code Ruby SDK（path gem）
- [claude-agent-sdk-ruby](../claude-agent-sdk-ruby) —— 架构参考来源
- [SDK对比分析报告.md](../SDK对比分析报告.md) —— 两个 SDK 的详细对比

## 许可证

MIT
