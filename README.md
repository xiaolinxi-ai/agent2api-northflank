# Agent2API on Northflank Sandbox

部署 Agent2API v3.0.8 官方镜像，自带网页管理面板和 OpenAI 兼容接口。
上游源码提交及镜像摘要固定在 deployment.json，构建不修改上游代码。

## 访问

- 面板：https://http--agent2api--xjmpj72ycwc8.code.run/login
- OpenAI Base URL：https://http--agent2api--xjmpj72ycwc8.code.run/v1
- 管理员：admin。密码与 API Key 保存在本机 ~/.config/northflank/agent2api-access.txt（0600）。
- 部署后需在面板添加提供商账号；未导入原 WorkBuddy 账号。

## 资源与数据

- 团队 xiaolis-team / 项目 first / 服务 agent2api。
- 应用：nf-compute-20，0.2 shared vCPU、512 MB、1 实例。
- 私有 MinIO addon agent2api-store：相同计算档、6 GiB 存储、1 实例，无公网端口。
- 账号唯一免费持久卷已被原 WorkBuddy 服务使用，平台拒绝创建第二个卷。因此新服务通过 Litestream 每秒同步 SQLite 到私有 MinIO，启动前自动恢复。
- 账号、配置、请求与任务记录都在 agent2api.db 中；账号加密密钥通过平台 Secret 环境变量持久保存，更新令牌的独立密钥也在启动时恢复。
- 数据恢复失败时拒绝启动，不会悄悄创建空白数据库继续服务。
- 异常宕机可能丢失尚未同步的最后几秒变更；对象存储不可用时风险窗口会延长。它不提供同步数据库的零数据丢失承诺。

## 认证

首次部署通过环境变量预置管理员，避免公网抢注。管理员已存入数据库后移除预置环境变量，后续可在面板修改密码，不会被重启覆盖。登录保留 ALTCHA 校验。
网关必须使用 API Key，未认证的管理与转发请求会被拒绝。
本仓库不含密码、API Key、S3 凭据或账号加密密钥。凭据仅在 Northflank 运行时 Secret 与本机 ~/.config/northflank/ 下保存。

## 构建与升级

容器内自更新关闭，Northflank 自动 CI 关闭，镜像摘要固定。项目仓库为私有。
Northflank 的 GitHub 集成无法直接读取新私有仓库，当前使用 bundle 构建：

1. 审查上游发行版及数据迁移，修改 Dockerfile 与 deployment.json 的固定版本、摘要。提交并推送私有仓库。
2. 确认数据库已同步；通过 Northflank API 暂停 agent2api，并等待原容器退出。MinIO addon 保持运行。不能同时运行两份此应用。
3. 使用 GitHub 认证 API 请求该提交的 tarball，取得临时签名下载 URL。签名地址不能提交到仓库或写入公开日志。
4. POST /v1/projects/first/services/agent2api/build，请求体为 {"bundleUrl":"临时签名URL","sha":"完整提交SHA"}。Combined service 不传 branch 字段。每次构建使用新的临时 URL。
5. 等待构建成功，选择该 buildId 部署；恢复为 1 实例。确认新容器恢复数据库，面板可访问，旧密钥鉴权成功，匿名请求返回 401。
6. 更新运维记录中的实际构建 ID、镜像与提交。失败时暂停应用，回退上一个已验证镜像，保留 MinIO 数据。涉及数据库不兼容迁移时先恢复对应版本备份。

普通启动要求备份存在并恢复成功。只有全新安装时，才可临时设置 AGENT2API_ALLOW_EMPTY_DB=1，并同时预置管理员及网关密钥；首次备份确认成功后立即移除这些初始化变量。正常运行不可开启 ALLOW_EMPTY_DB。
账号加密密钥与更新加密密钥必须沿用，不能在重建时重新生成。

## 域名

平台自动提供 HTTPS code.run 地址，不要求自定义域名。
如果以后绑定 Cloudflare 域名：
1. 确定子域名，例如 agent.example.com。
2. 在 Northflank 团队 Domains 中添加域名，取得平台实际给出的 TXT/CNAME 验证记录。
3. Cloudflare 对应域名 → DNS → Records → Add record，按平台给出的名称和值添加验证记录；CNAME 初始设为 DNS only（灰云），TTL 自动。
4. 回 Northflank 验证，给已验证域名添加子域名，关联 first/agent2api 的 http:3065 端口。
5. 根据 Northflank 给出的目标添加路由 CNAME，等待证书签发，测试 HTTPS 和流式响应。
6. 如启用 Cloudflare 代理，SSL/TLS 使用 Full (strict)，该子域名不要缓存 /api/*、/v1/*，避免对 API 启用交互式挑战。具体记录值必须从此次域名绑定返回，不能照抄其他服务。
