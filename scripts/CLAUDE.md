# scripts/
> L2 | 父级: ../CLAUDE.md

成员清单
publish-config.sh: 从 GitHub Actions Secrets 接收多订阅与公共 subconverter 地址；逐个请求公共服务预检、跳过失效来源、校验输出并更新私有 Gist；全部来源失效或聚合失败时保留旧 Gist。
validate-config.sh: 调用 validate-config.py，验证 subconverter 引用、provider payload/行为、策略组和 Clash Meta 模板结构及双方案一致性。
validate-config.py: 校验逻辑实现，依赖 requirements-dev.txt 中的 PyYAML。

法则: 只输出序号、计数和脱敏诊断；订阅、节点、令牌及完整产物永不写入日志或 artifact。公共转换器地址和订阅均按敏感数据处理；所有来源失败时不得覆盖 Gist。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
