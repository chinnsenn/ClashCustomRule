# scripts/
> L2 | 父级: ../CLAUDE.md

成员清单
publish-config.sh: 从 GitHub Actions Secrets 接收多订阅，驱动本地 subconverter、校验输出并更新私有 Gist。
validate-config.sh: 验证 subconverter 引用、provider payload、策略组和 Clash Meta 模板结构。

法则: 只输出计数和脱敏状态；订阅、节点、令牌及完整产物永不写入日志或 artifact。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
