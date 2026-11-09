#requires -Version 5.1
<#
.SYNOPSIS
  检查一个具体仓库有没有真正落地《个人编码与 AI 协作规范》（迁移 0–8 步的可执行判据）。

.DESCRIPTION
  检查项：项目规则入口是否存在、有没有残留占位符、迁移报告与三态矩阵是否齐全、
  待确认项有没有被写成既成事实、规范基线 commit 是否落后于本机规范本体、
  .env 是否被误入库、文档记忆索引是否存在、（可选）规则测试是否通过。

.PARAMETER RepoPath
  被检查的仓库根目录，默认当前目录。

.PARAMETER StandardsPath
  本机规范本体目录，默认 ~/.dsh/standards；用于比对规范基线 commit。

.PARAMETER RuleTestCommand
  项目的规则测试命令（如 `npm run test:rules`）；给了才会执行。

.PARAMETER ReportPath
  指定迁移报告文件；默认自动查找包含「迁移矩阵」的 Markdown。

.EXAMPLE
  pwsh -File install/check-project.ps1 -RepoPath D:\codeData\my-project

.EXAMPLE
  pwsh -File install/check-project.ps1 -RepoPath . -RuleTestCommand "npm run test:rules"
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [string]$StandardsPath = '',
    [string]$ReportPath = '',
    [string]$RuleTestCommand = ''
)

# 检查脚本按「逐项报告」执行，不用 Stop：某条 git 命令失败应降级成 WARN，而不是中断整份报告
$ErrorActionPreference = 'Continue'

$script:results = @()

function Add-Result {
    param([string]$Name, [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Level, [string]$Detail, [string]$Hint = '')
    $script:results += [pscustomobject]@{ Name = $Name; Level = $Level; Detail = $Detail; Hint = $Hint }
}

function Read-TextFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }
    return $text
}

if (-not (Test-Path $RepoPath)) { Write-Host "目标仓库不存在：$RepoPath" -ForegroundColor Red; exit 1 }
$RepoPath = (Resolve-Path $RepoPath).Path
if (-not $StandardsPath) { $StandardsPath = Join-Path $HOME '.dsh/standards' }

Write-Host "`n项目落地检查" -ForegroundColor Cyan
Write-Host "  目标仓库 : $RepoPath"
Write-Host "  规范本体 : $StandardsPath`n"

# 1. 规则入口：AGENTS.md / CLAUDE.md / .cursor/rules/*.mdc 至少要有一个
$ruleFiles = @()
foreach ($name in @('AGENTS.md', 'CLAUDE.md', '.cursorrules')) {
    $p = Join-Path $RepoPath $name
    if (Test-Path $p) { $ruleFiles += $p }
}
$cursorRules = Join-Path $RepoPath '.cursor/rules'
if (Test-Path $cursorRules) {
    $ruleFiles += @(Get-ChildItem -Path $cursorRules -Filter '*.mdc' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
}
if ($ruleFiles.Count -eq 0) {
    Add-Result '规则入口' 'FAIL' '没有 AGENTS.md / CLAUDE.md / .cursor/rules' '按 README「迁移到具体项目」第 2 步建立项目规则入口'
} else {
    Add-Result '规则入口' 'PASS' (($ruleFiles | ForEach-Object { Split-Path $_ -Leaf }) -join '、')
}

# 2. 迁移报告：优先用 -ReportPath，否则在仓库里找包含「迁移矩阵」的 Markdown
if (-not $ReportPath) {
    $docDirs = @((Join-Path $RepoPath 'docs'), (Join-Path $RepoPath 'doc'))
    $candidates = @()
    foreach ($dir in $docDirs) {
        if (Test-Path $dir) {
            $candidates += @(Get-ChildItem -Path $dir -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue | Select-Object -First 200)
        }
    }
    $candidates += @(Get-ChildItem -Path $RepoPath -Filter '*.md' -File -ErrorAction SilentlyContinue)
    foreach ($c in $candidates) {
        if ((Read-TextFile -Path $c.FullName) -like '*迁移矩阵*') { $ReportPath = $c.FullName; break }
    }
}

if (-not $ReportPath -or -not (Test-Path $ReportPath)) {
    Add-Result '迁移报告' 'FAIL' '没找到包含「迁移矩阵」的迁移报告' '用 install/project-spec-checklist.md 填写后放进 docs/task-artifacts/'
    $reportText = ''
} else {
    $reportText = Read-TextFile -Path $ReportPath
    Add-Result '迁移报告' 'PASS' (Resolve-Path $ReportPath).Path
}

# 3. 占位符扫描：只扫规则文件与迁移报告，避免误伤业务文档里的正常方括号
$placeholderPattern = 'TODO|TBD|FIXME|\[待填\]|\[仓库名|\[命令\]|\[路径\]|\[\.\.\.\]|\{\{'
$scanTargets = @($ruleFiles)
if ($reportText) { $scanTargets += $ReportPath }
$hits = @()
foreach ($f in $scanTargets) {
    $lines = (Read-TextFile -Path $f) -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $placeholderPattern) {
            $hits += ("{0}:{1}  {2}" -f (Split-Path $f -Leaf), ($i + 1), $lines[$i].Trim())
        }
    }
}
if ($hits.Count -gt 0) {
    $hitPreview = (($hits | Select-Object -First 5) -join '；')
    Add-Result '占位符' 'FAIL' ("{0} 处占位符（TODO/待填/未替换模板）" -f $hits.Count) $hitPreview
} else {
    Add-Result '占位符' 'PASS' '规则文件与迁移报告无占位符'
}

# 4. 三态矩阵：已落地 / 不适用 / 待确认 必须都出现（没有不适用项也要显式写「不适用」）
if ($reportText) {
    $missingStates = @()
    foreach ($state in @('已落地', '不适用', '待确认')) {
        if ($reportText -notlike "*$state*") { $missingStates += $state }
    }
    if ($missingStates.Count -gt 0) {
        Add-Result '三态矩阵' 'FAIL' ("缺少状态：{0}" -f ($missingStates -join '、')) '矩阵每行只能是 已落地 / 不适用（理由） / 待确认（问题编号）'
    } else {
        Add-Result '三态矩阵' 'PASS' '已落地 / 不适用 / 待确认 三态齐全'
    }

    # 5. 待确认项必须落到清单里，不能只在矩阵里写个「待确认」就当处理完
    if ($reportText -like '*待确认*' -and $reportText -notlike '*待确认清单*') {
        Add-Result '待确认清单' 'FAIL' '矩阵里有「待确认」，但没有「待确认清单」小节' '按模板第 4 节列出问题、原因、可选方案与影响'
    } elseif ($reportText -like '*待确认清单*') {
        Add-Result '待确认清单' 'PASS' '存在待确认清单'
    } else {
        Add-Result '待确认清单' 'WARN' '没有待确认项（确认这是真的，而不是把问题拍成了默认值）'
    }
}

# 6. 规范基线：项目记的 commit 与本机规范本体不一致，说明该复核迁移矩阵了
$baseline = $null
foreach ($f in $scanTargets) {
    $m = [regex]::Match((Read-TextFile -Path $f), '规范基线[^\r\n]{0,40}?([0-9a-f]{7,40})')
    if ($m.Success) { $baseline = $m.Groups[1].Value; break }
}
$standardsHead = $null
if (Test-Path (Join-Path $StandardsPath '.git')) {
    $standardsHead = (& git -C $StandardsPath rev-parse --short HEAD 2>$null)
    if ($standardsHead) { $standardsHead = $standardsHead.Trim() }
}
if (-not $baseline) {
    Add-Result '规范基线' 'WARN' '迁移报告里没有「规范基线 <commit>」' '填上生成时用的规范 commit，便于日后比对漂移'
} elseif ($standardsHead -and -not $standardsHead.StartsWith($baseline) -and -not $baseline.StartsWith($standardsHead)) {
    Add-Result '规范基线' 'WARN' ("项目基线 {0}，本机规范 {1}" -f $baseline, $standardsHead) '规范升过版：按迁移矩阵逐条复核受影响条目，再更新基线'
} else {
    Add-Result '规范基线' 'PASS' "与规范本体一致（$baseline）"
}

# 7. 配置与密钥：.env 不得入库；用配置的项目要有 .env.example
$trackedEnv = $null
$gitDirProbe = & git -C $RepoPath rev-parse --git-dir 2>&1
if ($LASTEXITCODE -eq 0) {
    $trackedEnv = & git -C $RepoPath ls-files --error-unmatch '.env' 2>&1
    if ($LASTEXITCODE -ne 0) { $trackedEnv = $null }
}
if ($trackedEnv) {
    Add-Result '密钥入库' 'FAIL' '`.env` 已被 git 跟踪' 'git rm --cached .env，补 .gitignore 与 .env.example，并轮换已泄露的值'
} elseif (-not (Test-Path (Join-Path $RepoPath '.env.example')) -and $reportText -notlike '*不适用*') {
    Add-Result '密钥入库' 'WARN' '没有 .env.example，报告也没写不适用' '涉及配置时补 .env.example（假值）；确实不涉及则在报告里写「不适用」'
} else {
    Add-Result '密钥入库' 'PASS' '未跟踪 .env'
}

# 8. 文档记忆索引：启用《文档记忆体系》的仓应有 docs/MEMORY_INDEX.md
$docsDir = Join-Path $RepoPath 'docs'
if ((Test-Path $docsDir) -and -not (Test-Path (Join-Path $docsDir 'MEMORY_INDEX.md'))) {
    Add-Result '文档记忆索引' 'WARN' 'docs/ 存在但没有 docs/MEMORY_INDEX.md' '启用该附录时必建；不启用则在报告里写「不适用」'
} else {
    Add-Result '文档记忆索引' 'PASS' '无需处理或已存在'
}

# 9. 规则测试：由调用方给命令，脚本只负责如实记录结果
if ($RuleTestCommand) {
    Write-Host "  执行规则测试：$RuleTestCommand" -ForegroundColor DarkGray
    $LASTEXITCODE = 0
    $output = & ([scriptblock]::Create($RuleTestCommand)) 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0 -and $?) {
        Add-Result '规则测试' 'PASS' "退出码 0"
    } else {
        Add-Result '规则测试' 'FAIL' ("退出码 {0}" -f $code) (($output | Select-Object -Last 5) -join ' / ')
    }
} else {
    Add-Result '规则测试' 'WARN' '未提供 -RuleTestCommand，跳过' '项目有测试框架时用它断言规则文件包含关键条目'
}

# 10. 汇总
Write-Host ''
$fail = 0
$warn = 0
foreach ($r in $script:results) {
    switch ($r.Level) {
        'PASS' { Write-Host ("  [{0}] {1}：{2}" -f $r.Level, $r.Name, $r.Detail) -ForegroundColor Green }
        'WARN' { $warn++; Write-Host ("  [{0}] {1}：{2}" -f $r.Level, $r.Name, $r.Detail) -ForegroundColor Yellow }
        'FAIL' { $fail++; Write-Host ("  [{0}] {1}：{2}" -f $r.Level, $r.Name, $r.Detail) -ForegroundColor Red }
    }
    if ($r.Hint) { Write-Host ("          → {0}" -f $r.Hint) -ForegroundColor DarkGray }
}

Write-Host ''
if ($fail -gt 0) {
    Write-Host ("结论：未落地（FAIL {0} 项，WARN {1} 项）" -f $fail, $warn) -ForegroundColor Red
    exit 1
}
if ($warn -gt 0) {
    Write-Host ("结论：基本落地（WARN {0} 项，逐条确认）" -f $warn) -ForegroundColor Yellow
    exit 0
}
Write-Host '结论：落地检查全部通过' -ForegroundColor Green
exit 0
