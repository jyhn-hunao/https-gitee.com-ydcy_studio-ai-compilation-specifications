# AI-CompilationSpecifications

Specifications and standards for AI-assisted coding. **This repository is the single source of truth** — clone it on any machine instead of keeping extra copies elsewhere.

> The documents themselves are written in Chinese.

## Layout

| Path | Content |
| --- | --- |
| `specs/个人编码与AI协作规范.md` | Main body (tech-stack agnostic): task sizing, **Chinese pseudo-code as numbered comments inside the implementation**, coding rules, 8 required deliverables, acceptance checklist, prompt templates, anti-patterns |
| `specs/附录-后端-Java-SpringBoot.md` | Backend (Java / Spring Boot) appendix |
| `specs/附录-前端-Vue3.md` | Frontend (Vue 3) appendix |
| `specs/附录-算法-Python-FastAPI.md` | Algorithm service (Python / FastAPI) appendix |
| `specs/附录-数据-SQL与数据库.md` | SQL / database appendix |
| `install/agents-pointer.md` | Pointer block to merge into `~/.dsh/AGENTS.md` (delimited by `BEGIN/END` markers) |
| `install/iron-rules.txt` | Plain-text iron rules for an AI session to store in persistent memory |

## Layering and precedence

1. **Iron rules** (main body chapters 3, 5, 6, 7) — never waived by any project.
2. **Project rules** (layout, naming, build commands, framework conventions) — follow the repository you are working in.
3. If it is unclear which wins, stop and ask the human.

## Installation (make it effective on a new machine)

1. Clone the specs:
   ```bash
   git clone https://gitee.com/ydcy_studio/ai-compilation-specifications.git ~/.dsh/standards
   ```
2. Merge `install/agents-pointer.md` into `~/.dsh/AGENTS.md` between its markers, without overwriting other rules in that file.
3. Hand `install/iron-rules.txt` to the AI session on that machine and ask it to write the rules into persistent memory.

## Updating

On this machine `~/.dsh/standards/` **is** the git clone of this repository — edit the documents under `specs/`, then `git commit` and `git push`. On other machines run `git -C ~/.dsh/standards pull`.

Commit identity is **repo-local** (`A.L <2310468741@qq.com>`); global git configuration is never modified.
