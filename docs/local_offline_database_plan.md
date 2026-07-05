# 完全本地数据库离线版操作清单

目标：系统在没有互联网的电脑上运行，数据保存在本机，不依赖 Supabase、不依赖 CDN、不依赖云认证。

## 当前系统需要改造的原因

当前 `app-demo.html` 依赖：

1. Supabase JS CDN
   - 页面加载 `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2`。
   - 离线环境无法加载。

2. Supabase Auth
   - 登录调用 `supabase.auth.signInWithPassword`。
   - 离线版不能继续依赖云端 Auth。

3. Supabase REST 查询
   - 页面大量使用 `client.from("table").select/insert/update/delete`。
   - 离线版需要替换成自己的本地数据访问层。

4. Supabase RLS
   - 当前权限依赖 Supabase 策略。
   - 本地版需要在应用层重新实现角色权限。

## 推荐本地架构

### 推荐方案：本地桌面服务 + SQLite

1. 前端
   - 继续使用当前 HTML 界面。
   - 移除 Supabase JS。
   - 改成调用本机 API，例如：
     - `http://127.0.0.1:8787/api/...`

2. 本地后端
   - 用 Node.js、Python 或 Go 做一个本机服务。
   - 推荐 Node.js 或 Python，开发速度快。
   - 服务只监听：
     - `127.0.0.1`
   - 不开放局域网，除非明确需要多电脑共享。

3. 本地数据库
   - SQLite 文件，例如：
     - `data/xmb.sqlite`
   - 优点：
     - 单文件
     - 易备份
     - 不需要安装数据库服务
     - 适合单机收银/库存

4. 打包方式
   - 简单版：一个启动脚本启动本地服务，再打开浏览器。
   - 正式版：Electron/Tauri 打包成桌面应用。

## 具体开发操作

1. 建立本地数据库 schema
   - 把 Supabase/PostgreSQL 表结构转换成 SQLite。
   - 需要转换：
     - `uuid` 改为 `text`
     - `timestamptz` 改为 `text`
     - `numeric(12, 3)` 改为 `real` 或 `numeric`
     - `gen_random_uuid()` 改为应用生成 UUID
     - `now()` 改为应用写入当前时间
   - 保留核心表：
     - `users`
     - `suppliers`
     - `customers`
     - `products`
     - `inventory`
     - `purchase_orders`
     - `purchase_order_items`
     - `sales_orders`
     - `sales_order_items`
     - `stock_movements`

2. 建立本地登录
   - 新增本地登录表或复用 `users`。
   - 建议字段：
     - `id`
     - `username`
     - `password_hash`
     - `display_name`
     - `zh_display_name`
     - `role`
     - `is_active`
   - 密码必须保存 hash，不保存明文。
   - 登录后后端发本地 session token。

3. 建立后端 API
   - 商品：
     - 查询商品
     - 新增商品
     - 修改商品
     - 停用/启用商品
   - 采购：
     - 查询采购订单列表
     - 新建采购订单
     - 显示/修改采购订单
     - 按订单收货
   - 销售：
     - 查询销售订单
     - 新建销售订单
     - 收银销售
   - 库存：
     - 当前库存
     - 库存流水
   - 基础资料：
     - 用户
     - 供应商
     - 客户

4. 改造前端数据访问层
   - 当前代码直接写：
     - `getClient().from("products").select(...)`
   - 离线版应新增统一数据层，例如：
     - `apiGet("/products", params)`
     - `apiPost("/purchase-orders", body)`
     - `apiPatch("/inventory/:id", body)`
   - 再逐步替换所有 Supabase 调用。

5. 改造认证
   - 删除 Supabase Auth 登录调用。
   - 改成调用：
     - `POST /api/login`
     - `POST /api/logout`
     - `GET /api/me`
   - 前端保存本地 session。
   - 后端每个 API 检查角色权限。

6. 权限重做
   - owner：
     - 全部功能。
   - manager：
     - 商品、采购、销售、库存、收货。
   - cashier：
     - 收银销售、销售订单、当前库存。
     - 不可看采购价格。
   - 这些规则必须在后端执行，不能只靠前端隐藏按钮。

7. 库存事务处理
   - 收银销售：
     - 检查库存是否足够。
     - 扣库存。
     - 建销售单。
     - 写 `stock_movements`，`movement_type = 601`。
   - 按订单收货：
     - 更新采购明细已收货数量。
     - 增库存。
     - 写 `stock_movements`，`movement_type = 101`。
   - 其他收货：
     - 建采购单。
     - 建采购明细。
     - 增库存。
     - 写 `stock_movements`，`movement_type = 501`。
   - 以上必须放在数据库事务里执行。

8. 替换外部资源
   - 下载并本地保存所有 JS/CSS 依赖。
   - 当前必须处理：
     - Supabase JS 删除或替换。
   - 确认页面没有外部字体、图片、CDN。

9. 数据备份
   - 本地数据库是一个 SQLite 文件。
   - 建议做：
     - 每天自动复制一份到 `backups/YYYY-MM-DD-xmb.sqlite`
     - 保留最近 30 天
     - 提供手动导出按钮

10. 数据恢复
   - 增加恢复工具。
   - 恢复前自动备份当前数据库。
   - 恢复后检查表结构版本。

11. 数据库版本升级
   - 建立 `schema_migrations` 表。
   - 每次新增字段或约束，都写 migration。
   - 启动时自动执行未执行的 migration。

12. 打包和安装
   - 简单安装包包含：
     - 前端文件
     - 本地后端程序
     - SQLite 数据库
     - 启动脚本
   - 桌面版包含：
     - 应用主程序
     - 本地 API
     - SQLite 数据库
     - 备份目录

## 不推荐的做法

1. 不建议让静态 HTML 直接读写 SQLite。
   - 浏览器不能安全直接访问本机数据库文件。
   - 权限和事务很难保证。

2. 不建议在离线版继续保留 Supabase Auth。
   - 没有网络时无法登录。

3. 不建议只把 Supabase JS 下载到本地就称为离线版。
   - Supabase JS 本身只是客户端库，后端仍然在云端。

4. 不建议把数据库端口暴露给浏览器直接连接。
   - 应通过本地后端 API 访问数据库。

## 建议执行顺序

1. 先冻结当前线上版功能范围。
2. 把 PostgreSQL schema 转成 SQLite schema。
3. 写本地 API。
4. 替换登录。
5. 替换商品、库存、库存流水查询。
6. 替换采购订单和收货。
7. 替换销售订单和收银销售。
8. 加备份/恢复。
9. 做安装包或桌面应用。
10. 用断网环境完整测试。

## 离线测试清单

1. 电脑断网。
2. 打开系统。
3. 登录 owner。
4. 查询商品。
5. 新建采购订单。
6. 按订单收货。
7. 其他收货。
8. 收银销售。
9. 查询当前库存。
10. 查询库存流水。
11. 退出后重启系统，确认数据仍在。
12. 用 cashier 登录，确认不能看到采购价格。

