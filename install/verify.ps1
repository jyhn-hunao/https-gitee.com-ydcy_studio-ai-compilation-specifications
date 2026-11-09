#requires -Version 5.1
<#
.SYNOPSIS
  校验「个人编码与 AI 协作规范」在本机是否真的生效（安装三步有没有漏）。

.DESCRIPTION
  检查项：规范本体是同一个 git 仓、正文与附录齐全、入口文件存在且标记块完整、
  入口文件没有超出宿主字节预算、常驻记忆里确实有铁律指纹。
  任何一项 FAIL 都以退出码 1 结束，便于接进开机脚本或 CI。

.PARAMETER StandardsPath
  规范本体目录，默认 ~/.dsh/standards。

.PARAMETER EntryPath
  宿主入口文件；默认按 -HostType 推断，与 install.ps1 的映射一致。

.EXAMPLE
  pwsh -File install/verify.ps1

.EXAMPLE
  pwsh -File install/verify.ps1 -HostType claude -EntryPath ~/.claude/CLAUDE.md
#>
[CmdletBinding()]
param(
    [ValidateSet('dsh', 'claude', 'cursor', 'codex')]
    [string]$HostType = 'dsh',

    [string]$EntryPath = '',
    [string]$StandardsPath = '',
    [string]$RepoUrl = 'https://gitee.com/ydcy_studio/ai-compilation-specifications.git',
    [int]$ByteBudget = 65536
)

$ErrorActionPreference = 'Stop'

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
    return [pscustomobject]@{ Text = $text; Bom = $hasBom }
}

if (-not $StandardsPath) { $StandardsPath = Join-Path $HOME '.dsh/standards' }
$StandardsPath = [System.IO.Path]::GetFullPath($StandardsPath)

$defaultEntries = @{
    dsh    = Join-Path $HOME '.dsh/AGENTS.md'
    claude = Join-Path $HOME '.claude/CLAUDE.md'
    codex  = Join-Path (Get-Location).Path 'AGENTS.md'
    cursor = Join-Path (Get-Location).Path '.cursor/rules/personal-standards.mdc'
}
if (-not $EntryPath) { $EntryPath = $defaultEntries[$HostType] }
$EntryPath = [System.IO.Path]::GetFullPath($EntryPath)

Write-Host "`n校验：个人编码与 AI 协作规范" -ForegroundColor Cyan
Write-Host "  规范本体 : $StandardsPath"
Write-Host "  入口文件 : $EntryPath"
Write-Host "  宿主     : $HostType`n"

# 1. 规范本体必须是同一个 git 仓，且能用 git 识别版本
if (-not (Test-Path (Join-Path $StandardsPath '.git'))) {
    Add-Result '规范本体' 'FAIL' "不是 git 仓：$StandardsPath" "运行 install.ps1 重新落地，或 git clone $RepoUrl `"$StandardsPath`""
} else {
    $origin = & git -C $StandardsPath remote get-url origin 2>$null
    $head = & git -C $StandardsPath rev-parse --short HEAD 2>$null
    if ($origin -and $origin.Trim() -ne $RepoUrl) {
        Add-Result '规范本体' 'WARN' "origin=$($origin.Trim())，与预期上游不同" "确认这是同一仓；不是就改 origin 或换目录"
    } else {
        Add-Result '规范本体' 'PASS' "git 仓，commit $($head.Trim())"
    }
}

# 2. 正文、附录、安装物料必须齐全（缺正文等于规范本体没落地）
$required = @(
    'specs/个人编码与AI协作规范.md',
    'specs/附录-后端-Java-SpringBoot.md',
    'specs/附录-前端-Vue3.md',
    'specs/附录-算法-Python-FastAPI.md',
    'specs/附录-数据-SQL与数据库.md',
    'specs/附录-文档记忆体系.md',
    'specs/附录-提交准则.md',
    'install/agents-pointer.md',
    'install/iron-rules.txt',
    'install/project-spec-checklist.md'
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path (Join-Path $StandardsPath $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    Add-Result '物料齐全' 'FAIL' ("缺 {0} 个文件：{1}" -f $missing.Count, ($missing -join '、')) "git -C `"$StandardsPath`" pull 后重试"
} else {
    Add-Result '物料齐全' 'PASS' "正文 + 6 份附录 + 3 份安装物料"
}

# 2.1 用户层是可选的：没有它照样能用，只是少了一层个人默认值
if (-not (Test-Path (Join-Path $StandardsPath 'specs/个人偏好.md'))) {
    Add-Result '个人偏好' 'WARN' '缺少 specs/个人偏好.md（用户层可选）' '不需要就忽略；需要就 git pull 取回'
} else {
    Add-Result '个人偏好' 'PASS' 'specs/个人偏好.md 存在'
}

# 3. 入口文件存在，标记块完整，并与模板一致（模板更新后没重跑安装会在这里暴露）
$templatePath = Join-Path $StandardsPath 'install/agents-pointer.md'
$blockRange = $null
if (Test-Path $templatePath) {
    $tplLines = (Read-TextFile -Path $templatePath).Text -replace "`r`n", "`n" -split "`n"
    $b = -1; $e = -1
    for ($i = 0; $i -lt $tplLines.Count; $i++) {
        if ($b -lt 0 -and $tplLines[$i] -match '^\s*<!--\s*BEGIN\s+personal-coding-standards\s*-->\s*$') { $b = $i; continue }
        if ($b -ge 0 -and $tplLines[$i] -match '^\s*<!--\s*END\s+personal-coding-standards\s*-->\s*$') { $e = $i; break }
    }
    if ($b -ge 0 -and $e -gt $b) { $blockRange = @($b, $e) }
}

if (-not (Test-Path $EntryPath)) {
    Add-Result '入口指针' 'FAIL' "入口文件不存在：$EntryPath" '运行 install.ps1（-HostType 与宿主一致）'
} else {
    $entry = Read-TextFile -Path $EntryPath
    $entryLines = $entry.Text -replace "`r`n", "`n" -split "`n"

    $eb = -1; $ee = -1
    for ($i = 0; $i -lt $entryLines.Count; $i++) {
        if ($eb -lt 0 -and $entryLines[$i] -match '^\s*<!--\s*BEGIN\s+personal-coding-standards\s*-->\s*$') { $eb = $i; continue }
        if ($eb -ge 0 -and $entryLines[$i] -match '^\s*<!--\s*END\s+personal-coding-standards\s*-->\s*$') { $ee = $i; break }
    }

    if ($eb -lt 0 -or $ee -le $eb) {
        Add-Result '入口指针' 'FAIL' '标记块缺失或不完整（BEGIN/END 对不上）' '重跑 install.ps1 重新并入标记块'
    } elseif ($null -ne $blockRange) {
        $tplBlock = @($tplLines[$blockRange[0]..$blockRange[1]] | ForEach-Object { $_.TrimEnd() })
        $curBlock = @($entryLines[$eb..$ee] | ForEach-Object { $_.TrimEnd() })
        if (($tplBlock -join "`n") -eq ($curBlock -join "`n")) {
            Add-Result '入口指针' 'PASS' "标记块 $($ee - $eb + 1) 行，与模板一致"
        } else {
            Add-Result '入口指针' 'WARN' '标记块内容与模板不一致（模板已更新，或本地改过入口）' '重跑 install.ps1 覆盖标记块；若是有意本地修改，忽略本条'
        }
    }

    # 4. 宿主对会话规则有字节预算，超了会被静默挤掉
    $size = (Get-Item $EntryPath).Length
    if ($size -ge $ByteBudget) {
        Add-Result '字节预算' 'WARN' ("{0} 字节，已达到/超过宿主预算 {1}" -f $size, $ByteBudget) '入口文件只留指针，正文放规范本体；铁律必须在常驻记忆里'
    } else {
        Add-Result '字节预算' 'PASS' ("{0} / {1} 字节" -f $size, $ByteBudget)
    }
}

# 5. 常驻记忆：直接查记忆存储原文，找铁律指纹（不依赖某个具体字段结构）
$memoryFiles = @(
    (Join-Path $HOME '.dsh/.mnemon/runtime/memories.json'),
    (Join-Path $HOME '.dsh/.mnemon/runtime/MEMORY.md'),
    (Join-Path (Get-Location).Path '.mnemon/runtime/memories.json'),
    (Join-Path (Get-Location).Path '.mnemon/runtime/MEMORY.md'),
    (Join-Path $HOME '.claude/CLAUDE.md')
)
$fingerprints = @('开发与 AI 协作铁律', '先思路后代码', '不静默兜底', '编号注释')
$existingStores = @($memoryFiles | Where-Object { Test-Path $_ })
$hitFile = $null
$hitCount = 0
foreach ($file in $existingStores) {
    $raw = Read-TextFile -Path $file
    $count = 0
    foreach ($fp in $fingerprints) { if ($raw.Text -like "*$fp*") { $count++ } }
    if ($count -ge 2 -and $count -gt $hitCount) { $hitCount = $count; $hitFile = $file }
}
if ($existingStores.Count -eq 0) {
    Add-Result '常驻记忆' 'WARN' '未发现本机记忆存储（可能不是 DSH 宿主）' '按宿主机制确认铁律是否每轮注入'
} elseif ($hitFile) {
    Add-Result '常驻记忆' 'PASS' ("命中 {0} 条铁律指纹：{1}" -f $hitCount, $hitFile)
} else {
    Add-Result '常驻记忆' 'FAIL' ("{0} 个记忆存储里都没有铁律指纹" -f $existingStores.Count) "把 install/iron-rules.txt 交给 AI 会话写入常驻记忆，再重跑本脚本"
}

# 6. 汇总
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
    Write-Host ("结论：未生效（FAIL {0} 项，WARN {1} 项）" -f $fail, $warn) -ForegroundColor Red
    exit 1
}
if ($warn -gt 0) {
    Write-Host ("结论：基本生效（WARN {0} 项，请逐条确认）" -f $warn) -ForegroundColor Yellow
    exit 0
}
Write-Host '结论：三项全部生效' -ForegroundColor Green
exit 0
