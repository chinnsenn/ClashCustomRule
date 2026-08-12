# .github/
> L2 | 父级: ../CLAUDE.md

成员清单
workflows/publish-config.yml: 定时和手动运行的无服务器订阅刷新任务，从 requirements-dev.txt 安装校验依赖，并在发布前运行配置回归测试。

法则: 工作流只读仓库内容；订阅、Gist ID、令牌仅从 Secrets 注入；转换和校验失败时保留现有 Gist；禁止上传敏感 artifact。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
