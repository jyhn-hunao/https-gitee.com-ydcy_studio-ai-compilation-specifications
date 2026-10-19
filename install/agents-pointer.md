<!-- BEGIN personal-coding-standards -->
# 个人编码与 AI 协作规范（跨项目通用入口）

- 规范本体：`~/.dsh/standards/`（git 仓 `https://gitee.com/ydcy_studio/ai-compilation-specifications` 的克隆目录；正文在 `specs/个人编码与AI协作规范.md`，同目录另有 4 份技术栈附录：Java/Spring Boot、Vue3、Python/FastAPI、SQL 与数据库）。
- 适用于**任何项目、任何技术栈、任何仓库**。若写代码任务开始时上述规范未进上下文，请先读取正文再动手。
- 优先级：**铁律层任何项目不得豁免**——任务分级与 dsh-graph 路由、中文伪代码（以 `// 1. xxx` 编号注释直接写进实现代码，标关键步骤的业务语义，不逐行注释、不单独出文档）、先思路后代码、数据来源必须可证明、不静默兜底、交付必附缺陷/边界/验证用例；技术栈、目录、命名、构建约定服从所在仓库。
- dsh-graph：当前会话实际提供 `graph_*` 时，S 级开发任务不强制建目标，M/L 级必须创建或复用 graph 目标并按流程执行；用户指定既有目标时禁止旁路，执行前由当前任务会话接管 supervisor。规则、规范、协作机制等文字治理任务可由主管主会话直接实施，不强制派执行子代理；该例外不适用于常规功能开发。
<!-- END personal-coding-standards -->
