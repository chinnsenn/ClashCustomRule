# ClashCustomRule - Clash Meta 分流规则与无服务器订阅发布
Clash Meta/Mihomo + 公共 subconverter + GitHub Actions + GitHub Gist

<directory>
providers/ - Rule-provider payload 数据源，按服务和行为类型维护
config/ - subconverter 输入与 Clash Meta 原生模板
scripts/ - 发布与静态校验脚本
tests/ - 面向直接导入模板与校验命令的回归测试
.github/ - GitHub Actions 自动拉取、转换和发布
</directory>

<config>
README.md - 用户工作流、安全模型、Fork 维护与自建进阶说明
rule_provider_config.yaml - 历史 Raw URL 兼容入口，与 config/subconverter.ini 保持同构
</config>

## 法则

- 用户 Fork 后在自己的仓库维护规则、配置与 Secrets；上游只提供基线。
- `providers/*.yaml` 只包含 `payload`，Clash Meta 模板负责添加 rule-provider 元数据。
- 订阅 URL、公共转换器 URL、节点凭据、Gist Raw URL 和访问令牌均属于敏感数据，禁止写入仓库、日志或 artifact。
- `config/subconverter.ini` 是 subconverter INI，不能作为 Clash YAML 导入。
- 修改 providers、策略组或工作流后必须先安装 `requirements-dev.txt`，再运行 `scripts/validate-config.sh` 和 `python3 tests/test_native_template.py`。
- 修改目录、文件职责或导出接口时同步更新本文件和所在目录的 CLAUDE.md。

## 变更记录

- 2026-08：建立 GitHub Actions → subconverter → 私有 Gist 的无服务器发布架构。
