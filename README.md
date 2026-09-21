# AI-CompilationSpecifications

用于记录 AI 编写代码的规范文件。**本仓是规范本体（单一事实源）**——换机器、换项目都从这里取，不在别处再存一份。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `specs/个人编码与AI协作规范.md` | 主正文（技术栈无关）：任务分级与 dsh-graph 路由、**中文伪代码**、编码铁律、交付八项、验收清单、提示词模板、反模式 |
| `specs/附录-后端-Java-SpringBoot.md` | 后端（Java/Spring Boot）技术栈附录 |
| `specs/附录-前端-Vue3.md` | 前端（Vue 3）技术栈附录 |
| `specs/附录-算法-Python-FastAPI.md` | 算法服务（Python/FastAPI）技术栈附录 |
| `specs/附录-数据-SQL与数据库.md` | 数据、SQL 与数据库附录 |
| `install/agents-pointer.md` | 并入 `~/.dsh/AGENTS.md` 的入口指针段（带 `BEGIN/END` 标记块） |
| `install/iron-rules.txt` | 常驻铁律纯文本，供 AI 会话写入常驻记忆 |

## 分层与优先级

1. **铁律层**（主正文第 2、3、5、6、7 章：任务分级与 dsh-graph 路由、中文伪代码、先思路后代码、数据来源可证明、编码铁律、交付八项）——**任何项目不得豁免**；
2. **项目层**（目录、命名、构建命令、框架约定、既有风格）——服从所在仓库；
3. 无法判断谁优先时，停下来问人。

## 安装（在新机器上生效）

1. 落地规范本体：
   ```bash
   git clone https://gitee.com/ydcy_studio/ai-compilation-specifications.git ~/.dsh/standards
   ```
2. 把 `install/agents-pointer.md` 的内容**按标记块**并入 `~/.dsh/AGENTS.md`（插入或替换标记块之间的内容，**不要覆盖该文件里原有的其他规则**）。
3. 把 `install/iron-rules.txt` 交给该机器上的 AI 会话，要求它**写进常驻/全局记忆**。

三步缺任一步都会漏生效：第 1 步给正文，第 2 步给入口，第 3 步给每轮都注入的底线。

## 更新

- 本机的装机目录 `~/.dsh/standards/` **就是这个仓的 git 克隆**，直接在里面改 `specs/` 下的文档 → `git commit` → `git push` 即可，不必另建副本（两份会分叉）。
- 其他机器：`git -C ~/.dsh/standards pull`。
- 提交身份使用 **repo-local** 配置（`A.L <2310468741@qq.com>`），不改动任何机器的全局 git 配置。

## 已知边界

- 入口指针按 **DSH 宿主**写（读 `~/.dsh/AGENTS.md`）。换其他宿主（读 `CLAUDE.md`、`.cursorrules` 等）需按对方的约定改造入口指针。
- **常驻记忆必须经记忆工具写入**：`USER.md` / `MEMORY.md` / `memories.json` 里，Markdown 是生成投影，直接拷文件会在下一次写入时被覆盖。
- `~/.dsh/AGENTS.md` 会被宿主的会话规则字节预算挤掉（实测：项目规则文件 82KB 时，用户级规则整个没进上下文），所以铁律层必须落在常驻记忆里。
- 附录中标「示例」的条目来自具体项目（如禁用某个 CSS 属性），进入新仓库前先确认该仓是否同样要求，不要默认套用。
