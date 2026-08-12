# config/
> L2 | 父级: ../CLAUDE.md

成员清单
subconverter.ini: subconverter `[custom]` 输入，聚合规则、策略组、过滤与重命名的唯一规范副本。
clash-meta.yaml: Clash Meta 原生模板，包装本地与上游 Clash provider payload，并提供与自动发布方案一致的服务规则、地区筛选和规则顺序。

依赖关系
`subconverter.ini` 被 `scripts/publish-config.sh` 传给 Runner 内的 subconverter。
`clash-meta.yaml` 从 GitHub Raw 拉取 `providers/*.yaml`，仅适用于已输出 Clash YAML 的代理提供者。

法则: INI 与 YAML 语义分离；原生模板必须覆盖 INI 的全部规则目标组；禁止向模板写入订阅地址、节点凭据或令牌。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
