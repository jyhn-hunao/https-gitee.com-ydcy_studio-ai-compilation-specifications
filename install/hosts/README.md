# 多宿主入口（同一份铁律，不同宿主怎么接）

> **正文只有一份**：`install/agents-pointer.md` 里的标记块。本目录不复制正文，只写各宿主的**落位路径与包装差异**——复制正文必然分叉，这正是本仓反复要避免的事。
> 生成入口一律用 `install/install.ps1 -HostType <宿主>`，它负责：落地规范本体 → 取标记块 → 按宿主包装（如 Cursor 的 frontmatter）→ 幂等合并进目标文件。

## 宿主映射

| 宿主 | 入口文件 | 作用域 | 生成命令 | 备注 |
| --- | --- | --- | --- | --- |
| DSH（本机默认） | `~/.dsh/AGENTS.md` | 用户级，全项目生效 | `pwsh -File install/install.ps1` | 参考 README「安装」；有会话规则字节预算，实测约 64KB |
| Claude Code | `~/.claude/CLAUDE.md`（用户级）或项目根 `CLAUDE.md` | 用户级 / 项目级 | `pwsh -File install/install.ps1 -HostType claude` | 正文同为 Markdown，标记块原样可用；项目级会随仓库分发，注意别无脑入库个人路径 |
| Cursor | 项目根 `.cursor/rules/personal-standards.mdc` | 项目级 | `pwsh -File install/install.ps1 -HostType cursor` | `.mdc` 需要 YAML frontmatter（`description` / `alwaysApply: true`）才会自动挂载；脚本会自动补，**不要手改 frontmatter 之外的块外内容** |
| Codex / 其他读 `AGENTS.md` 的工具 | 目标仓根 `AGENTS.md` | 项目级 | `pwsh -File install/install.ps1 -HostType codex -EntryPath <仓根>/AGENTS.md` | 与项目自己的 `AGENTS.md` 合并：标记块外是项目规则，块内是通用入口，互不覆盖 |

## 换宿主时会发生什么

1. **入口换了，正文不换**：四个宿主指向的都是同一个 `~/.dsh/standards`（或另一处克隆），升级方式仍是 `git pull`。
2. **常驻记忆没有通用接口**：DSH 走自己的记忆存储（`verify.ps1` 会直接读存储文件找铁律指纹）；Claude Code / Cursor 没有等价的"每轮注入"机制，铁律只能放进该宿主的用户级指令文件——`verify.ps1` 在找不到记忆存储时给 WARN，而不是假装通过。
3. **多宿主并存时只维护一份**：同一台机器同时装 DSH 和 Claude Code，改 `install/agents-pointer.md` 后分别跑两次 `install.ps1`，两边都会同步到同一份正文；不要手工改任何一边的标记块。

## 加一个新宿主

1. 在 `install/install.ps1` 的 `$defaultEntries` 里加一行「宿主 → 入口文件默认路径」；
2. 若该宿主有格式要求（如 Cursor 的 frontmatter），在同一脚本的 `$frontMatter` 分支里加包装；
3. 在上表补一行；
4. 跑 `install.ps1 -HostType <新宿主> -DryRun` 看合并结果，再实跑一次确认幂等（重复执行不产生 diff）。

**不需要**新建一份正文副本；也不需要改 `specs/` 下任何文件。
