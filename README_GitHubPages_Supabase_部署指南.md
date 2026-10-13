# 肾功能与抗肿瘤剂量计算辅助平台｜GitHub Pages + Supabase

这是从原始本地网页 `/home/user/renal_dose_assistant.html` 制作的云端适配包：**保留原页面架构、计算界面、数据库维护界面、配色与现有剂量资料**，仅把原来由 Python `/api/*` 提供的数据、登录、保存、导入和二维码接口接到 Supabase。公开访客可查看/计算；数据库写入由 Supabase Auth、RLS 管理员白名单和 Storage policies 共同保护。

## 先看这几项

- 本包不等于已经发布。GitHub 仓库、Supabase 项目和权限需要你本人创建/授权；真实 `github.io` 网址只会在你完成 Pages 部署后生成。
- 当前本地 JSON 是 **59 条规则、0 个二维码关联**。初始化 SQL 从当前 `/home/user/renal_dose_database.json` 生成，保留原字段、文本剂量、ID 和顺序；没有做剂量换算或重新解释。
- 若你已经在 Supabase 建好 `drug_rules` / `drug_qr`，**不要重跑初始化 seed**，避免误覆盖云端当前资料；只执行下文的管理员 RLS migration。
- 页面保留原用户名 `admin`。它会映射到你在配置文件中填写的管理员 Supabase Auth 邮箱；密码只在 Supabase Auth 中验证，**不写在网页、配置文件或 GitHub 中**。
- 你最新指定的原密码是 `admin123`，但它非常弱。若仍要沿用，只能由你在 Supabase Auth 设置；公开站点上的弱密码风险较高，建议改成独有强密码。不要把密码发给我。
- `sb_publishable_...` 是浏览器公开 key，不是管理员密码；绝不能放 `sb_secret_...` 或旧 `service_role` key 到网站或仓库。实际写保护依赖 RLS，而不是隐藏网页按钮。

## 文件结构

- `site/index.html`：原始完整网页 UI，加云端接口适配脚本。
- `site/supabase-cloud-adapter.js`：把原页面 `/api/*` 请求接到 Supabase Auth / REST / Storage。
- `site/supabase-config.js`：部署前需要填 Supabase URL、Publishable Key 和管理员邮箱。
- `supabase-schema-seed.sql`：新 Supabase 项目专用，创建两张表并写入当前 59 条规则；不操作 Supabase 托管的 `storage.objects`。
- `supabase-admin-rls-migration.sql`：创建管理员白名单、RLS 权限、审计触发器和事务式保存 RPC；不会替你自动授权某个用户，也不改 `storage.objects`。
- `.github/workflows/pages.yml`：推送后自动部署 `site/` 到 GitHub Pages。

## 一、配置 Supabase 数据库和登录

### 1. 创建或选择项目

1. 登录 Supabase 并选择你的项目；如果尚无项目，先创建一个。
2. 若这是此前的只读项目且两张表、59 条数据已存在，**跳过第 2 步 seed**。
3. 只有在全新、空项目里，打开 **SQL Editor → New query**，运行包内 `supabase-schema-seed.sql`。完成后应有 `public.drug_rules`（59 行）和 `public.drug_qr`（当前 0 行）。不要拿旧只读包里的 seed 覆盖已有云端修改。

### 2. 启用管理员写入保护

1. 在 SQL Editor 运行 `supabase-admin-rls-migration.sql`。
2. 脚本会将 `anon` / `authenticated` 的数据库表读取开放给网页；普通访客没有写权限。登录用户只有在 `private.renal_admins` 白名单内，才可新增、更新、删除剂量规则和二维码索引。
3. 它还创建 `public.replace_renal_database(jsonb)` 事务式保存函数，并启用私有审计记录。脚本有意不对 `storage.objects` 执行 DDL。

### 3. 创建管理员 Auth 用户

1. 打开 **Authentication → Users → Add user → Send invitation**，填入你能收信的管理员邮箱并发送邀请。Supabase 文档说明受邀用户可通过邮件链接确认并完成账户设置（包括设置密码）：[Supabase Auth 用户与邀请](https://supabase.com/docs/guides/auth/users)。
2. 从邀请邮件打开链接，完成密码设置。若你要保留原密码，就在这里自行设置为 `admin123`；更推荐改为唯一强密码。
3. 回到 **Authentication → Users**，复制该用户的 **User UID**。
4. 在 SQL Editor 单独运行下面语句，把 `替换成Auth用户的UUID` 换成刚复制的 UUID：

```sql
insert into private.renal_admins (user_id)
values ('替换成Auth用户的UUID')
on conflict (user_id) do nothing;
```

**不要**把 UUID 填成邮箱，也不要把密码写进 SQL、网页或 GitHub。忘记加白名单时，即使 Auth 登录成功，页面也不会开放维护写入。

### 4. 创建二维码图片存储空间

当前源数据库没有已关联二维码，因此此步骤主要是为以后上传准备。

1. 打开 **Storage**，创建 bucket：`instructions`。
2. 将 bucket 设为 **Public**，因为计算页面需要公开读取药品说明书二维码图片。不要把患者资料上传到此 bucket。
3. 打开 Storage 的 **Policies**，为 `storage.objects` 建立三条独立策略，角色均选 `authenticated`，条件均限制为 `bucket_id = 'instructions' AND public.is_renal_admin()`：
   - **INSERT**：将条件放在 `WITH CHECK`。
   - **SELECT**：将条件放在 `USING`。只让白名单管理员通过 Storage API 看见对象；这也是安全删除对象所需的可见性策略。
   - **DELETE**：将条件放在 `USING`。
4. 不要用“所有登录用户可写”的宽松规则。以上函数检查当前 Auth 用户是否在私有白名单中。图片读取通过 Public bucket 的公开对象 URL，不需要给 `anon` 开数据库 SELECT 或上传/删除策略。Supabase 的 Storage `remove` 操作需要 DELETE 和 SELECT policy，因此 SELECT 也必须仅对白名单管理员开放：[Storage remove 权限说明](https://supabase.com/docs/reference/javascript/storage-from-remove)。

如果你已创建同名 bucket，先确认它的 Public 设置与 policies，不要重复新建。

### 5. 取公开前端配置

1. 在 Supabase 项目设置/API Keys（不同 Dashboard 版本菜单可能显示为 **Settings → API Keys** 或 **Project Settings → API**）复制 **Project URL** 和 **Publishable Key**。
2. 编辑 `site/supabase-config.js`：

```js
window.RENAL_SUPABASE_CONFIG = {
  url: "https://你的项目引用.supabase.co",
  publishableKey: "sb_publishable_你的公开key",
  maintenanceEmail: "你的管理员邮箱"
};
```

3. `maintenanceEmail` 必须和刚创建/选定的 Auth 用户邮箱完全一致。网页仍显示用户名 `admin`，登录时把它映射到这里的邮箱。
4. Publishable Key 可出现在静态前端，但 `Secret/service_role` key 不行。Supabase 对前端 key、数据库安全与 RLS 的说明见：[API Keys](https://supabase.com/docs/guides/getting-started/api-keys)、[Secure Data](https://supabase.com/docs/guides/database/secure-data)、[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)。

## 二、部署 GitHub Pages

### 1. 上传仓库

1. 解压 `supabase_github_integrated.zip`（或使用本目录中的文件）。
2. 在 GitHub 创建一个仓库，将解压后的**全部内容**放在仓库根目录；至少应看到 `.github/`、`site/`、两个 SQL 文件和本说明。
3. 先按上一节填写 `site/supabase-config.js`，再提交。该文件会随静态网页公开；里面只能有 Project URL、Publishable Key 和邮箱，不能放密码或 Secret key。

### 2. 开启 Pages

1. 在仓库进入 **Settings → Pages**。
2. 在 **Build and deployment → Source** 选择 **GitHub Actions**。
3. 打开 **Actions**，确认 `Deploy renal dose platform to GitHub Pages` workflow 成功。仓库内 workflow 从 `site/` 上传静态网页并部署；GitHub 官方步骤说明见[Configure a publishing source](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)。
4. 成功后回到 **Settings → Pages** 复制 GitHub 显示的网址。通常类似 `https://你的GitHub用户名.github.io/仓库名/`，但真实地址由 GitHub 项目生成；现在还没有可提供的已发布链接。

### 3. 首次验收

依次检查：

- 打开公开网址：原有首页/计算器显示，规则来自 Supabase；无需登录可查看，患者输入只在浏览器端参与计算。
- 打开数据库维护：未登录时只能看到原有登录表单；普通访客不可改库。
- 用页面用户名 `admin`、Supabase Auth 密码登录；登录成功后才出现原有维护操作。
- 修改一条测试规则并保存，刷新后仍在；随后把测试值改回原值。
- 可选：上传一个非敏感测试二维码，确认计算页显示；再移除并确认消失。
- 用未加入 `private.renal_admins` 的测试账号登录：应不能写入。即使有人直接调用浏览器 API，数据库 RLS 也会拒绝。

如出现“权限不足”，优先检查 Auth 邮箱是否一致、`private.renal_admins.user_id` 是否为正确 UUID、migration 是否成功、Storage policies 是否限制在 `public.is_renal_admin()`。

## 保留与边界

- 原计算方式、手动点击计算、检验值输入、剂量匹配、原始数据核对提示、数据库编辑/删除、CSV/XLSX 导入、CSV/JSON 导出、二维码按药品关联均保留；XLSX 导入时按需从 jsDelivr 加载 SheetJS，CSV 可直接导入。
- 公共数据库读取是公开的；不要把患者、身份信息或保密内容放进剂量规则备注、二维码文件名或 Storage。
- Supabase 的 Publishable Key 不负责保密数据库；所有写入都由 PostgreSQL grants/RLS、管理员白名单和 Storage policies 拦截。RLS 是实际安全边界。
- 这是临床辅助工具。剂量资料请按现行说明书和临床团队复核；CysC/联合 eGFR 对 CSV CrCl 范围的代理匹配仍非等价于 CrCl。
- GitHub Pages 只托管静态前端，原 Python 本地 `/api/*` 不能在 GitHub Pages 上运行；本包已以 Supabase 适配层替代这些调用。

## 官方说明

- Supabase Auth 用户：[supabase.com/docs/guides/auth/users](https://supabase.com/docs/guides/auth/users)
- Supabase RLS：[supabase.com/docs/guides/database/postgres/row-level-security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- GitHub Pages Actions：[docs.github.com/pages](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
