# ClashCustomRule

面向 Clash Meta / Mihomo 的分流规则库，以及无需自建服务器的多订阅发布方案。

它会把多个订阅链接转换为一份可直接导入客户端的 Clash Meta 配置，并按服务、地区和广告拦截规则生成策略组。规则、订阅凭据与发布地址均由你的个人 Fork 管理。

> 建议先 [Fork 本仓库](https://github.com/chinnsenn/ClashCustomRule/fork)。上游仓库提供规则基线；个人 Fork 才是你配置订阅、修改规则和保存发布地址的地方。

## 从这里开始

| 你的订阅情况 | 该用什么 | 最终得到什么 |
| --- | --- | --- |
| 订阅地址已经返回 Clash YAML | [原生模板](#使用原生模板) | 客户端直接拉取代理和规则 |
| Base64、混合协议、机场私有格式，或多个订阅链接 | [自动发布（推荐）](#自动发布推荐) | 每 6 小时更新的一份完整 Clash Meta 配置 |
| 需要网页管理、即时更新或自定义域名 | [自建部署](#自建部署) | 自己托管的订阅转换与发布服务 |

`config/subconverter.ini` 是转换器的输入文件，**不能**直接导入 Clash Meta / Mihomo 客户端。

## 自动发布（推荐）

GitHub Actions 会每 6 小时通过你指定的公共 subconverter 服务拉取全部订阅、过滤和重命名节点、应用规则、校验结果，再把有变化的配置写入一个私有 Gist。你只需把这个 Gist 的 Raw 文件地址添加到客户端一次。

```text
订阅链接
  → GitHub Actions
  → 公共 subconverter
  → 分流规则与策略组
  → YAML 校验
  → 私有 Gist
  → Clash Meta / Mihomo 客户端
```

### 第一次配置

1. [Fork 本仓库](https://github.com/chinnsenn/ClashCustomRule/fork)。如果 Actions 尚未启用，进入**你自己的 Fork 仓库**的 **Actions** 页面，并按提示启用工作流。
2. [创建一个私有 Gist](https://gist.github.com/)，新建文件并命名为 `clash-meta.yaml`。该文件会保存完整节点配置，请不要在公共位置分享。
3. 创建一个可编辑此 Gist 的 GitHub 访问令牌。使用经典个人访问令牌时，只需授予 `gist` 权限；可在 [个人访问令牌页面](https://github.com/settings/tokens) 创建。
4. 在你的 Fork 中打开 **Settings → Secrets and variables → Actions**，创建以下四个 Actions secrets：

   | 名称 | 填写内容 |
   | --- | --- |
   | `SUBSCRIPTION_URLS` | 每行一个订阅链接；空行和以 `#` 开头的行会忽略 |
   | `SUBCONVERTER_URL` | 你信任的公共 subconverter **基础地址**，例如 `https://converter.example`；不要填写末尾的 `/sub` |
   | `GIST_ID` | 第 2 步创建的 Gist ID |
   | `GIST_TOKEN` | 第 3 步创建的访问令牌 |

5. 可选：在同一页面的 **Variables** 新建 `GIST_FILENAME`，以修改 Gist 内文件名；默认是 `clash-meta.yaml`。
6. 打开 **Actions → Publish Clash Meta config → Run workflow**，手动运行一次。
7. 运行成功后，在 Gist 中复制 `clash-meta.yaml` 的 **Raw** 地址，并将其作为订阅地址添加到 Clash Meta / Mihomo 客户端。

### 更新与失败处理

- 工作流按 `17 */6 * * *` 触发，也可以随时手动运行；新任务会取消尚未完成的旧任务。
- 每次都会逐个请求公共转换器预检订阅，跳过不可转换的来源，再将成功来源交给同一服务聚合。最终 YAML 必须包含 `proxies`、`proxy-groups` 和 `rules`；日志只显示来源序号、计数和脱敏诊断。
- 只要至少一个订阅转换成功，工作流就会用可用来源发布；内容没有变化时不会写入 Gist。全部来源、聚合转换、校验或发布失败时，Gist 会保留上一份可用配置。

公共转换服务会收到订阅链接及其查询参数。请只使用你信任、明确承诺不记录请求且支持外部 `config` URL 的实例；不要将 Gist 令牌传给转换服务。

## 使用原生模板

如果你的订阅本身就是 Clash YAML，可使用 [原生模板](config/clash-meta.yaml)。它内置规则提供者、策略组和规则顺序，但不会转换通用或 Base64 订阅。

1. 下载或复制 [模板文件](config/clash-meta.yaml)。
2. 将 `proxy-providers.subscription.url` 改为你的 Clash YAML 订阅地址。
3. 将模板内的 `chinnsenn/ClashCustomRule/master` 替换为你的 GitHub 用户名、Fork 仓库名和分支名。
4. 导入客户端；规则 payload 会从你的 Fork 更新，因此后续添加的个人规则会生效。

通用/Base64 订阅、多机场聚合和节点重命名请使用上面的自动发布方案。

## 规则与策略组

默认配置涵盖以下方向：

- 常用服务：Telegram、YouTube、Google、Gemini、OpenAI、Anthropic、DeepSeek、GitHub、Cloudflare、TikTok、X、Spotify 等。
- 流媒体与游戏：Netflix、Disney+、Prime Video、Apple TV+、Bilibili、巴哈姆特、Steam、Epic、Nintendo 等。
- 网络与隐私：国内/国外媒体、直连、广告拦截、应用净化、AdBlock 与隐私防护。
- 节点选择：全局手动选择、自动测速、故障转移，以及港、台、日、新、美、韩等地区自动组。

规则会按配置中的顺序匹配；更具体的服务规则位于通用规则之前。生成后的配置可在客户端中按策略组选择节点或 `DIRECT`。

## 自定义

| 想调整什么 | 修改位置 | 说明 |
| --- | --- | --- |
| 新增少量个人域名、IP 或经典规则 | [providers/](providers/) | 每个文件只保留 YAML 的 `payload:` 列表 |
| 服务分流、策略组、节点过滤和名称重命名 | [config/subconverter.ini](config/subconverter.ini) | 自动发布方案的唯一规范配置 |
| 原生模板的 rule-provider、策略组与规则顺序 | [config/clash-meta.yaml](config/clash-meta.yaml) | 仅影响原生模板方案 |

### 重命名节点

在 [subconverter 配置](config/subconverter.ini) 末尾找到注释掉的 `rename=` 示例，取消注释后：

1. 把 `机场A` 改为订阅名称中可识别的关键字。
2. 把 `机场 A` 改为想在客户端显示的名称。
3. 再次运行工作流，新的节点名会随 Gist 配置发布。

`rule_provider_config.yaml` 是旧 Raw 地址的兼容副本；如仍在使用该旧入口，修改后请同步更新它。

### 提交前校验

修改 `providers/`、策略组或原生模板后，在仓库根目录运行：

```bash
python3 -m pip install -r requirements-dev.txt
./scripts/validate-config.sh
python3 tests/test_native_template.py
```

它会检查 provider YAML、rule-provider 行为、subconverter 规则与策略组引用、兼容副本同构性，以及原生模板与自动发布方案的服务覆盖一致性。

## 外部规则来源

本仓库负责组合、排序、策略组与自动发布；服务级分流主要来自长期维护的公开规则库，个人 Fork 适合保存自己的补充规则。

| 规则库 | 用途 | 本项目中的用法 |
| --- | --- | --- |
| [MetaCubeX meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | Mihomo 基础分类、GeoSite、GeoIP | 原生模板可使用 `.mrs` 格式 |
| [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | Clash 基础分流补充 | 适合作为 subconverter 输入 |
| [blackmatrix7 ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 流媒体、AI、金融、社交等服务级分流 | 通过 subconverter 转换为 Clash 规则 |
| [Loyalsoldier clash-rules](https://github.com/Loyalsoldier/clash-rules) | 直连、代理、拒绝、私有网络等基础类别 | 用于基础分类补充 |

Clash Meta 原生 `rule-providers` 只能接收 Clash provider YAML 或 MetaCubeX `.mrs`。Surge 和 Quantumult X 规则应交给 subconverter 转换，不要直接填入原生模板。

## 安全说明

- 订阅链接仅保存在 GitHub Actions secrets 和临时运行环境中；工作流不会上传含节点配置的 artifact。
- Gist Raw 地址可读取完整节点凭据。请只将它保存在受控客户端中，不要公开发布或截图分享。
- 地址或令牌泄露后，应更换机场订阅、创建新的私有 Gist，并撤销旧令牌。
- 私有 Gist 依赖“持有链接即可访问”的模式，适合低暴露场景；需要更严格访问控制时请使用自建、带认证的 HTTPS 地址。

## 自建部署

当你需要可视化管理订阅、即时生效或受认证的发布地址时，可以部署以下单向流程：

```text
sub-store（订阅录入、过滤、重命名）
  → subconverter（规则应用与格式转换）
  → 私有 Gist 或受认证 HTTPS 地址
  → Clash Meta / Mihomo 客户端
```

subconverter 默认服务端口为 `25500`。建议将服务放在反向代理后的内网环境，入口启用 HTTPS 和身份认证；订阅与令牌使用环境变量保存，备份配置和数据，日志仅保留脱敏状态。

## 迁移旧方案

如果曾使用公共转换站，建议按以下顺序迁移：Fork 本仓库 → 配置 Actions secrets 与私有 Gist → 手动运行工作流 → 在客户端导入 Gist Raw 地址 → 确认节点和策略组正常更新 → 从旧服务撤销订阅记录。

## 项目结构

```text
providers/                   个人规则 payload 数据源
config/subconverter.ini      转换规则、策略组、过滤与重命名
config/clash-meta.yaml       可直接导入的原生 Clash Meta 模板
scripts/publish-config.sh    经公共转换服务聚合订阅、校验并发布到 Gist
scripts/validate-config.*    离线配置一致性校验
requirements-dev.txt         本地校验所需的 Python 依赖
tests/                       原生模板与校验命令的回归测试
.github/workflows/           定时与手动发布工作流
```

## 变更记录

- 2026-08：移除旧网页转换、旧规则文件和 Surge/Stash 附加模块，改为 Clash Meta + GitHub Actions + 私有 Gist 工作流。
