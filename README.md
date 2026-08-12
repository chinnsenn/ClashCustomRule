# ClashCustomRule

Clash Meta/Mihomo 的分流规则库与无服务器多机场订阅发布方案。

> **建议 Fork 本仓库。** 个人 Fork 是规则、策略组、订阅 Secrets 与发布 Gist 的维护边界；上游仓库提供可更新的规则基线。

## 选择方案

| 订阅类型 | 推荐路径 | 结果 |
| --- | --- | --- |
| 已输出 Clash YAML 的订阅 | [Clash Meta 原生模板](#clash-meta-原生模板) | 客户端直接拉取代理与规则提供者 |
| Base64、混合协议、机场私有格式、多机场链接 | [GitHub Actions + 私有 Gist](#免自建方案github-actions--私有-gist) | 定时聚合、过滤、重命名、分流并发布最终 Clash 配置 |
| 需要可视化编排、即时更新和自定义服务域名 | [自建进阶](#自建进阶) | sub-store + subconverter + 受控发布地址 |

本仓库输出 Clash Meta 兼容 YAML。`config/subconverter.ini` 是 subconverter 的 INI 输入文件，不能直接导入客户端。

## 免自建方案：GitHub Actions + 私有 Gist

GitHub 托管定时任务。每 6 小时自动拉取所有订阅链接、更新节点、应用本仓库分流规则、验证输出，并在内容变化时更新私有 Gist。

```text
SUBSCRIPTION_URLS Secret
  → GitHub Actions 临时 Runner
  → metacubex/subconverter
  → config/subconverter.ini
  → YAML 校验与变更检测
  → 私有 Gist Raw URL
  → Clash Meta 客户端
```

### 配置步骤

1. Fork 本仓库。
2. 在 GitHub 创建一个专用 Gist，并新建文件 `clash-meta.yaml`。Gist 文件包含节点凭据，按敏感数据管理。
3. 打开 Fork 仓库的 **Settings → Secrets and variables → Actions**，添加以下 Secrets：

   | Secret | 内容 |
   | --- | --- |
   | `SUBSCRIPTION_URLS` | 每行一个机场订阅链接；`#` 开头的行作为注释 |
   | `GIST_ID` | 专用 Gist 的 ID |
   | `GIST_TOKEN` | 可编辑该 Gist 的最小权限 GitHub token |

4. 可选：在 **Variables** 添加 `GIST_FILENAME`，默认值为 `clash-meta.yaml`。
5. 打开 **Actions → Publish Clash Meta config → Run workflow**，首次手动运行。
6. 成功后复制 Gist 文件的 Raw URL，添加到 Clash Meta/Mihomo 客户端作为订阅地址。

工作流使用 `workflow_dispatch` 和 `17 */6 * * *` 定时触发。它采用并发取消策略，较新的运行取代尚未完成的旧运行。

### 节点更新行为

每次运行都会重新拉取 `SUBSCRIPTION_URLS` 中的全部链接。转换后脚本验证 YAML 必备的 `proxies`、`proxy-groups` 和 `rules`；Gist 内容一致时跳过写入，内容变化时更新节点和配置。拉取、转换、验证或 Gist API 请求失败时，已有 Gist 保持最后可用版本。

### 安全边界

- 订阅链接只存在于 GitHub Actions Secrets 和临时 Runner 环境。
- 工作流关闭 shell trace，掩盖每条订阅链接与 Gist token，且不上传包含节点配置的 artifact。
- Gist Raw URL 可访问完整节点凭据。将它保存在受控客户端中；泄露后轮换机场订阅、创建新 Gist、撤销旧 token。
- Gist 采用持有链接的访问模型。私有 Gist 适用于低暴露托管，敏感环境应使用自建受认证发布地址。

## Clash Meta 原生模板

`config/clash-meta.yaml` 复用 `providers/` 中的规则 payload，声明 rule-provider、策略组和规则顺序。将 `chinnsenn/ClashCustomRule/master` 替换为个人 Fork 的 GitHub 用户名、仓库名与分支名；再把 `proxy-providers.subscription.url` 填为**已经返回 Clash YAML** 的代理提供者地址。

通用/Base64 订阅需要转换，使用 GitHub Actions 方案。规则 payload 通过当前 Fork 的 Raw GitHub 地址加载，因此个人新增规则会随 Fork 生效。

## 外部规则源

本仓库的核心职责是组合、排序、策略组与自动发布。分流数据优先引用长期维护的公开规则库，个人 Fork 只保留自己的补充规则。

| 规则库 | 适用范围 | 主要格式 | 集成位置 |
| --- | --- | --- | --- |
| [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | Mihomo 基础大类、GeoSite、GeoIP | `.mrs`、`geo` | Clash Meta 原生模板使用 `format: mrs` |
| [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | 成熟的 Clash 基础分流补充 | Clash `.list`、YAML | `subconverter.ini` 使用对应输入类型 |
| [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 流媒体、AI、金融、社交等服务级分流 | Clash YAML、Surge、Quantumult X | `subconverter.ini` 使用 `clash-domain:`、`clash-ipcidr:`、`clash-classic:` |
| [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) | 直连、代理、拒绝、私有网络等基础类别 | Clash 文本规则 | 用于基础 `direct`、`proxy`、`reject`、`private` 分类 |

格式边界：Clash Meta 原生 `rule-providers` 接收 Clash provider YAML 或 MetaCubeX `.mrs`；Surge 与 Quantumult X 规则通过 subconverter 作为输入转换。不要把 Surge、Quantumult X 文本直接填入 Clash Meta 的 `rule-providers`。

推荐组合：MetaCubeX 提供原生基础规则，blackmatrix7 提供服务级分流，ACL4SSR 与 Loyalsoldier 提供转换器兼容和基础补充。

## 维护自己的规则

- 在 `providers/` 新增或编辑少量个人补充规则。每个文件只保留 YAML `payload:` 列表。
- 在 `config/subconverter.ini` 调整 `ruleset=`、`custom_proxy_group=`、节点过滤和重命名；底部的 `rename=` 示例支持按订阅名称关键字统一节点前缀。取消注释后，将 `机场A` 改为订阅名称中的识别关键字，将 `机场 A` 改为希望展示的名称。`rule_provider_config.yaml` 是兼容旧 Raw 链接的镜像副本，变更后同步更新。
- 在 `config/clash-meta.yaml` 调整原生模板中的 rule-provider、策略组与规则顺序。
- 提交前运行：

```bash
./scripts/validate-config.sh
```

它检查 provider YAML、subconverter 规则引用、策略组引用和原生模板结构。

## 文件结构

```text
providers/                   规则 payload 数据源
config/subconverter.ini      subconverter 规则、策略组、过滤和重命名
config/clash-meta.yaml       Clash Meta 原生模板
scripts/publish-config.sh    聚合、转换、校验和 Gist 发布
scripts/validate-config.sh   离线配置一致性校验
.github/workflows/           定时订阅刷新工作流
```

## 自建进阶

需要可视化订阅管理或受认证发布地址时，部署以下单向数据流：

```text
sub-store 前端/后端（订阅录入、过滤、重命名）
  → subconverter（规则应用与目标格式转换）
  → 私有 Gist 或受认证 HTTPS 地址
  → Clash Meta 客户端
```

subconverter 使用 `metacubex/subconverter`，服务端口为 `25500`。将它置于反向代理后的内网服务，入口提供 HTTPS 与身份认证；保存订阅和令牌的环境变量；备份配置与数据；日志只保留脱敏的运行状态。当前本机 Docker 环境未部署 sub-store 或 subconverter，`sub2api` 属于独立服务。

## 从旧方案迁移

旧公共转换站会接收订阅链接。迁移流程：Fork → 配置 Secrets 和私有 Gist → 手动运行 Actions → 在客户端导入 Gist Raw URL → 确认策略组与节点更新正常 → 从旧公共服务撤销订阅记录。

`rule_provider_config.yaml` 延续旧路径兼容性；新的自动化与维护入口使用 `config/subconverter.ini`。

## 变更记录

- 2026-08：移除旧网页转换、旧规则文件和 Surge/Stash 附加模块；建立 Clash Meta + GitHub Actions + 私有 Gist 工作流。
