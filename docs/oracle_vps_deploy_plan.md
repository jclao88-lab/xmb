# Oracle VPS 发布操作清单

适用当前系统形态：`app-demo.html` 是单页前端，当前通过 Supabase JS 直接访问 Supabase Auth、PostgREST 和数据库表。

## 目标选择

### 方案 A：最快上线，VPS 只托管前端，数据库继续用 Supabase

这个方案改动最少，适合先上线试用。

1. 准备 Oracle VPS
   - 创建 Ubuntu 实例。
   - 开放端口：`80`、`443`、`22`。
   - 设置 SSH key 登录。
   - 设置固定公网 IP。

2. 准备域名
   - 域名 A 记录指向 Oracle VPS 公网 IP。
   - 例如：`erp.example.com -> VPS_IP`。

3. 安装 Web 服务
   - 安装 Nginx 或 Caddy。
   - 推荐 Caddy，自动 HTTPS 更简单。
   - 如果用 Nginx，需要另外配置 Certbot/Let's Encrypt 证书。

4. 上传前端文件
   - 上传 `app-demo.html`。
   - 上传 `assets/` 目录。
   - 如继续保留演示页面，可同时上传 `login-demo.html`、`inventory-check-demo.html`。
   - Web 根目录可用：`/var/www/xmb`。

5. 配置 Supabase 连接
   - 不要在公网页面里使用 service role key。
   - 只使用 anon/publishable key。
   - 确认 `app-demo.html` 里读取的 `window.XMB_SUPABASE_CONFIG` 能拿到：
     - `url`
     - `anonKey`
   - 当前 `.env.local` 不能直接被静态 HTML 读取；发布时需要生成一个浏览器可读的配置脚本，或把配置注入到 HTML。

6. 处理 Supabase JS CDN 依赖
   - 当前页面引用：
     - `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2`
   - 如果 VPS 版本允许联网，可以保留。
   - 如果希望减少外部依赖，应下载固定版本的 `supabase-js` 浏览器包到本地，比如放到 `assets/vendor/`，再改 HTML script 引用。

7. 配置 Supabase 允许来源
   - 在 Supabase 项目设置里加入站点 URL。
   - 加入 redirect URL：
     - `https://erp.example.com`
     - 如保留测试域名，也加入测试域名。

8. 执行数据库脚本
   - 新库：执行 `docs/supabase_schema.sql`。
   - 旧库升级：执行 `docs/supabase_update_existing_tables.sql`。
   - 执行或检查 RLS：`docs/supabase_rls_permissions.sql`。
   - 导入基础资料和测试数据。

9. 创建用户
   - 在 Supabase Auth 创建登录用户。
   - 在 `public.users` 里创建同 ID 的业务用户资料。
   - 角色只允许：
     - `owner`
     - `manager`
     - `cashier`

10. 验证业务功能
   - 登录。
   - 商品查询。
   - 采购订单列表。
   - 收货功能。
   - 收银销售。
   - 当前库存。
   - 库存流水。
   - 用 cashier 登录验证采购价格不可见。

11. 基础运维
   - 配置 HTTPS 自动续期。
   - 配置 VPS 防火墙。
   - 配置 Nginx/Caddy 访问日志。
   - 配置 Supabase 数据库备份。
   - 定期备份 `app-demo.html` 和配置文件。

## 方案 B：VPS 同时托管前端和后端数据库

这个方案是完整服务器部署，改动比方案 A 大。

1. 选择后端路线
   - 路线 B1：VPS 自托管 Supabase。
   - 路线 B2：VPS 上自建后端 API + PostgreSQL。

2. 如果选择自托管 Supabase
   - 安装 Docker 和 Docker Compose。
   - 部署 Supabase self-hosted stack。
   - 配置 Supabase Auth、PostgREST、Realtime、Storage 等服务。
   - 设置 JWT secret、anon key、service role key。
   - 配置反向代理和 HTTPS。
   - 执行 `docs/supabase_schema.sql` 和 RLS 脚本。
   - 修改前端配置指向 VPS 上的 Supabase API 地址。

3. 如果选择自建后端 API + PostgreSQL
   - 安装 PostgreSQL。
   - 建库、建用户。
   - 把 `docs/supabase_schema.sql` 改造成普通 PostgreSQL schema。
   - 去掉依赖 Supabase Auth 的部分，或改成自己的登录表/session/JWT。
   - 新建后端 API，覆盖当前前端使用的查询、插入、更新操作。
   - 前端不能再直接用 Supabase JS，需要改成调用后端 API。

4. 数据库初始化
   - 创建表结构。
   - 创建索引、约束。
   - 导入商品、供应商、客户、用户。
   - 创建默认客户：
     - `cccccccc-cccc-cccc-cccc-cccccc000003`
   - 创建默认供应商：
     - `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaa000000`

5. 安全配置
   - 数据库端口不要直接暴露公网。
   - 后端 API 才能访问数据库。
   - 前端只访问 HTTPS API。
   - 管理员密钥只保存在服务器环境变量。

6. 发布前端
   - 静态文件放到 Web 根目录。
   - 配置缓存策略。
   - 配置 HTTPS。
   - 检查中文编码为 UTF-8。

7. 发布后端
   - 使用 systemd 或 Docker Compose 管理服务。
   - 配置环境变量。
   - 配置日志轮转。
   - 配置开机自启。

8. 备份和恢复
   - 每日备份 PostgreSQL。
   - 保存最近 7 天备份。
   - 每周做一次恢复测试。
   - 同步备份到 VPS 外部位置。

## 建议执行顺序

1. 先做方案 A，上线成本最低。
2. 同时整理所有业务流程和权限问题。
3. 稳定后再决定是否做方案 B。
4. 如果目标是完全不联网，本地数据库版本应单独开发，不建议直接用当前 Supabase 前端硬改。

