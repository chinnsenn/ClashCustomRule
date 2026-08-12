# .github/
> L2 | 父级: ../CLAUDE.md

成员清单
workflows/publish-config.yml: 定时和手动运行的无服务器订阅刷新任务，从 requirements-dev.txt 安装校验依赖，并在发布前运行配置回归测试。

法则: 工作流只读仓库内容；订阅、Gist ID、令牌仅从 Secrets 注入；订阅先下载到临时文件，成功下载至少一个才启动转换器；单个订阅下载或转换失败时跳过该来源，全部来源或聚合转换失败时保留现有 Gist；禁止上传敏感 artifact。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
