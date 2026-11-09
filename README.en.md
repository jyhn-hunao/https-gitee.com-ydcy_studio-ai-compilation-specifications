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
| `specs/附录-文档记忆体系.md` | General collaboration appendix (tech-stack agnostic): `docs/` growth memory directories, classification, naming, index maintenance, plus hard constraints for handoff / SQL log / test-method registry |
| `specs/附录-提交准则.md` | General collaboration appendix (tech-stack agnostic): commit unit, size limits (files/lines/review time), splitting strategy, commit messages, review view and AI commit discipline |
| `specs/个人偏好.md` | **User layer**: cross-project personal habits weaker than the iron rules (language, doc style, script choice); project rules may override |
| `install/install.ps1` | **Installer**: clone/update the repo → merge the pointer block (nothing outside it is touched) → print the persistent-memory instruction; idempotent |
| `install/verify.ps1` | **Verification**: same git origin, pointer block intact, byte budget, iron-rule fingerprints present in persistent memory |
| `install/check-project.ps1` | **Project landing check**: rule entry, placeholders, three-state matrix, open questions, spec-baseline drift, `.env` tracked, rule test |
| `install/hosts/README.md` | **Multi-host mapping**: where the same body goes on DSH / Claude Code / Cursor / Codex |
| `install/agents-pointer.md` | Pointer block to merge into the host entry file (delimited by `BEGIN/END` markers) |
| `install/iron-rules.txt` | Plain-text iron rules for an AI session to store in persistent memory |
| `install/project-spec-checklist.md` | **Project migration checklist template**: filled in by the AI while creating project rules (evidence, file list, migration matrix, open questions, verification) |

## Layering and precedence

1. **Iron rules** (main body chapters 2, 3, 5, 6, 7) — never waived by any project.
2. **Project rules** (layout, naming, build commands, framework conventions) — follow the repository you are working in.
3. **User layer** (`specs/个人偏好.md`) — cross-project habits, defaults only; project rules may override.
4. **Stack appendices** — generic defaults.

Precedence: **current user instruction > iron rules > project rules > user layer > appendix defaults**. If it is unclear which wins, stop and ask the human.

## Installation (make it effective on a new machine)

```powershell
git clone https://gitee.com/ydcy_studio/ai-compilation-specifications.git ~/.dsh/standards
pwsh -File ~/.dsh/standards/install/install.ps1    # add -Update on an existing machine
pwsh -File ~/.dsh/standards/install/verify.ps1     # must be all green
```

`install.ps1` covers the three manual steps: clone/update the repo, merge the `BEGIN/END` pointer block into the host entry file (content outside the block is never touched, repeated runs produce no diff), and print the instruction for step 3. Step 3 — writing the iron rules into persistent memory — cannot be scripted, so `verify.ps1` reads the memory store directly and looks for iron-rule fingerprints; a missing fingerprint is a FAIL, not a silent pass.

Manual equivalent: clone → merge `install/agents-pointer.md` between its markers → hand `install/iron-rules.txt` to the AI session and ask it to store the rules in persistent memory. Other hosts (Claude Code, Cursor, Codex): see `install/hosts/README.md` and `-HostType`.

## Migrating into a concrete project (AI execution order)

> Goal: after this repository is cloned, an AI can apply the general rules to a target repository **completely** — no missing items, no invented values, no autonomous decisions on undecided questions.
> The general rules are defaults only; project rules must be generated from evidence found in the target repository.

### Three hard prerequisites

1. **Read before writing**: read the main body plus the matching tech-stack appendices first.
2. **Evidence first**: every project value (paths, commands, versions, directories, naming, ports, config keys) must point to a file in the target repository; if it cannot, put it in the open-questions list — never guess and never pass a default off as a project value.
3. **Rules only**: do not change business code; run `git status` first; merge existing rule files instead of overwriting them.

### Execution order (0–8)

| Step | Action | Output | Done when |
| --- | --- | --- | --- |
| 0 | Record spec version + stack | version/commit, appendix list | you can name the appendices used |
| 1 | Reconnaissance (read-only) | facts with `file:line` evidence | every fact is traceable |
| 2 | Create/merge the project rule file | `AGENTS.md` or host equivalent | skeleton complete, no placeholders |
| 3 | Apply the stack appendix | defaults → project values | inapplicable items justified |
| 4 | Project-specific coding style | layering/naming/comments/errors/logging/models/persistence/frontend/config/tests | each item cites existing code |
| 5 | Land the commit standard | type/scope list, limits, commands, remote policy | references the commit appendix and states deltas |
| 6 | Verification gates | real command results (or "not run" + why) | never report "not run" as "passed" |
| 7 | Open questions | question, impact, options, owner | no open item is written as fact |
| 8 | Self-check + delivery | migration report | checklist all green |

Execution rule: steps 0–1 are read-only; from step 2, show the output of each step before continuing; do not deliver step 8 while step 7 is unresolved.

### Files to create, in order

| Order | File | Required | Must answer |
| --- | --- | --- | --- |
| 1 | `AGENTS.md` (or `CLAUDE.md`) | yes | positioning; directory ownership; build/run/verify commands; backend/frontend/data conventions; prohibitions; delivery; known risks; precedence |
| 2 | Commit standard file (e.g. `doc/commit-guidelines.md`) | yes | `type`/`scope` vocabulary; limits (stricter only; justify relaxations); verification commands; local/remote policy; real split examples |
| 3 | `docs/MEMORY_INDEX.md` + per-directory `README.md` (if memory appendix enabled) | if enabled | what each directory holds / excludes; where new notes go; index maintenance |
| 4 | `docs/architecture/`, `docs/interfaces/` (as needed) | recommended | module boundaries, call chains, contract sources |
| 5 | `.env.example` (if configuration exists) | yes (verify) | variable name, purpose, fake default, sensitivity |
| 6 | Rule test (if the project has a test runner) | recommended | asserts key rule entries; not bypassable |
| 7 | Migration report (one-off) | yes | landed / not applicable / open, with evidence |

### Migration report and open questions

Use the fill-in template `install/project-spec-checklist.md`: evidence table, migration matrix (`landed / not applicable (reason) / open (question id)`), open-question list, verification results and conclusion. Any open item must be asked, not assumed.

Machine check afterwards: `pwsh -File ~/.dsh/standards/install/check-project.ps1 -RepoPath <target repo>` covers the mechanical parts (rule entry, placeholders, three-state matrix, open questions, spec-baseline drift, `.env` tracked, rule test). It can only disprove; human judgement still decides whether the evidence is real.

### Common omissions

- build command without test command;
- directory responsibilities without "where new code goes";
- copying general text instead of writing project deltas (two sources drift);
- turning an open question into a default value;
- overwriting existing rule files;
- forgetting the commit `scope`/limits.

### Maintenance

- After pulling an update: compare versions/diff, re-check the migration matrix, update only affected rows, re-run the rule test.
- Project files hold deltas only; conflicts resolve as: current user instruction > project rules > general defaults.

## Updating

On this machine `~/.dsh/standards/` **is** the git clone of this repository — edit the documents under `specs/`, then `git commit` and `git push`. On other machines run `git -C ~/.dsh/standards pull`.

Commit identity is **repo-local** (`A.L <2310468741@qq.com>`); global git configuration is never modified.
