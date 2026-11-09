#requires -Version 5.1
<#
.SYNOPSIS
  把「个人编码与 AI 协作规范」安装到本机：落地规范本体 → 合并入口指针 → 校验。

.DESCRIPTION
  对应 README「安装」的三步，但第 3 步（常驻铁律）无法由脚本完成：
  写入常驻记忆必须由 AI 会话调用记忆工具，脚本只打印可粘贴指令，结果交给 verify.ps1 检查。

  脚本可重复执行：已安装则只做差异合并，入口文件里标记块之外的内容一字不动。

.PARAMETER HostType
  宿主类型，决定入口文件默认落位：dsh / claude / cursor / codex。

.PARAMETER EntryPath
  自定义入口文件路径，覆盖 -HostType 的默认值。

.PARAMETER StandardsPath
  规范本体目录，默认 ~/.dsh/standards（也即本仓的克隆目录）。

.PARAMETER Update
  规范本体已存在时执行 git pull --ff-only。

.PARAMETER DryRun
  只计算将要写入的内容并展示，不落盘。

.EXAMPLE
  pwsh -File install/install.ps1

.EXAMPLE
  pwsh -File install/install.ps1 -HostType claude

.EXAMPLE
  pwsh -File install/install.ps1 -HostType cursor -Update
#>
[CmdletBinding()]
param(
    [ValidateSet('dsh', 'claude', 'cursor', 'codex')]
    [string]$HostType = 'dsh',

    [string]$EntryPath = '',
    [string]$StandardsPath = '',
    [string]$RepoUrl = 'https://gitee.com/ydcy_studio/ai-compilation-specifications.git',
    [switch]$Update,
    [switch]$DryRun,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

function Write-Section { param([string]$Text) Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "   [OK]   $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "   [WARN] $Text" -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host "   [FAIL] $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "   $Text" -ForegroundColor Gray }

# UTF-8 读取，返回正文与 BOM 标记（保留目标文件原有编码形态）
function Read-TextFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }
    return [pscustomobject]@{ Text = $text; Bom = $hasBom }
}

# 按指定行尾与 BOM 写回；内容统一先规范化成 LF 再转换，避免 CRLF 叠成 CRCRLF
function Write-TextFile {
    param([string]$Path, [string]$Text, [bool]$Bom, [string]$Eol = "`n")
    $normalized = $Text -replace "`r`n", "`n"
    if ($Eol -eq "`r`n") { $normalized = $normalized -replace "`n", "`r`n" }
    $encoding = New-Object System.Text.UTF8Encoding($Bom)
    [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
}

# 1. 解析路径：规范本体目录、宿主入口文件、模板文件
if (-not $StandardsPath) { $StandardsPath = Join-Path $HOME '.dsh/standards' }
$StandardsPath = [System.IO.Path]::GetFullPath($StandardsPath)

# 1.1 宿主 → 入口文件默认落位（换宿主时只换这一个映射，正文不动）
$defaultEntries = @{
    dsh    = Join-Path $HOME '.dsh/AGENTS.md'
    claude = Join-Path $HOME '.claude/CLAUDE.md'
    codex  = Join-Path (Get-Location).Path 'AGENTS.md'
    cursor = Join-Path (Get-Location).Path '.cursor/rules/personal-standards.mdc'
}
if (-not $EntryPath) { $EntryPath = $defaultEntries[$HostType] }
$EntryPath = [System.IO.Path]::GetFullPath($EntryPath)

$pointerTemplate = Join-Path $StandardsPath 'install/agents-pointer.md'
$ironRulesFile = Join-Path $StandardsPath 'install/iron-rules.txt'
$mainSpec = Join-Path $StandardsPath 'specs/个人编码与AI协作规范.md'

Write-Section "安装目标"
Write-Info "宿主        : $HostType"
Write-Info "规范本体    : $StandardsPath"
Write-Info "入口文件    : $EntryPath"
if ($DryRun) { Write-Warn "DryRun：只展示差异，不写盘" }

# 2. 落地规范本体：不存在则克隆；已存在则校验是否同一仓；-Update 时只做快进合并
Write-Section "2. 规范本体"
if (-not (Test-Path $pointerTemplate)) {
    if (Test-Path (Join-Path $StandardsPath '.git')) {
        Write-Fail "$StandardsPath 存在 git 目录但缺少 install/agents-pointer.md，拒绝继续（请人工确认该目录）"
        exit 1
    }
    Write-Info "未发现规范本体，执行：git clone $RepoUrl"
    New-Item -ItemType Directory -Force -Path (Split-Path $StandardsPath -Parent) | Out-Null
    & git clone $RepoUrl $StandardsPath
    if ($LASTEXITCODE -ne 0) { Write-Fail "克隆失败（退出码 $LASTEXITCODE）"; exit 1 }
    Write-Ok "已克隆"
} else {
    Write-Ok "规范本体已存在"
    $origin = & git -C $StandardsPath remote get-url origin 2>$null
    if ($origin -and $origin.Trim() -ne $RepoUrl) {
        Write-Warn "origin 与预期不一致：$($origin.Trim())（继续，但请确认这是同一个仓）"
    }
    if ($Update) {
        & git -C $StandardsPath pull --ff-only 2>&1 | ForEach-Object { Write-Info $_ }
        if ($LASTEXITCODE -ne 0) { Write-Warn "git pull 未成功（可能有本地改动），保持当前版本继续" }
    }
}

if (-not (Test-Path $mainSpec)) { Write-Fail "缺少正文 $mainSpec，规范本体不完整"; exit 1 }
$head = (& git -C $StandardsPath rev-parse --short HEAD 2>$null)
if ($head) { Write-Info "当前 commit: $($head.Trim())" }

# 3. 读取模板块：install/agents-pointer.md 的 BEGIN/END 区间；Cursor 额外补 frontmatter
Write-Section "3. 入口模板块"
$template = Read-TextFile -Path $pointerTemplate
# 模板与目标文件统一按 LF 切行：模板可能是 CRLF 检出，不统一会让「是否变化」的比较永远为真
$templateLines = @(($template.Text -replace "`r`n", "`n") -split "`n")

$beginIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $templateLines.Count; $i++) {
    if ($beginIdx -lt 0 -and $templateLines[$i] -match '^\s*<!--\s*BEGIN\s+personal-coding-standards\s*-->\s*$') { $beginIdx = $i; continue }
    if ($beginIdx -ge 0 -and $templateLines[$i] -match '^\s*<!--\s*END\s+personal-coding-standards\s*-->\s*$') { $endIdx = $i; break }
}
if ($beginIdx -lt 0 -or $endIdx -lt 0) {
    Write-Fail "$pointerTemplate 缺少 BEGIN/END 标记块（模板本身坏了，先修模板）"
    exit 1
}

$blockLines = @()
for ($i = $beginIdx; $i -le $endIdx; $i++) { $blockLines += $templateLines[$i] }
Write-Ok "模板块 $($blockLines.Count) 行"

$frontMatter = @()
if ($HostType -eq 'cursor') {
    # Cursor 的 .mdc 需要 frontmatter 才会自动挂载；标记块之外的内容不参与替换
    $frontMatter = @(
        '---',
        'description: 个人编码与 AI 协作规范（跨项目入口）',
        'alwaysApply: true',
        '---',
        ''
    )
}

# 4. 合并：有标记块则替换块内，无标记块则追加；块外内容一字不动
Write-Section "4. 合并入口文件"
$entryExists = Test-Path $EntryPath
$eol = "`n"
$bom = $false
$entryLines = @()
if ($entryExists) {
    $current = Read-TextFile -Path $EntryPath
    $eol = if ($current.Text -match "`r`n") { "`r`n" } else { "`n" }
    $bom = $current.Bom
    $entryLines = @($current.Text -replace "`r`n", "`n" -split "`n")
    # PowerShell 的 -split 会在末尾留一个空串，合并时保留它以免丢末尾换行
} else {
    Write-Info "入口文件不存在，将新建（含父目录）"
}

$curBegin = -1
$curEnd = -1
for ($i = 0; $i -lt $entryLines.Count; $i++) {
    if ($curBegin -lt 0 -and $entryLines[$i] -match '^\s*<!--\s*BEGIN\s+personal-coding-standards\s*-->\s*$') { $curBegin = $i; continue }
    if ($curBegin -ge 0 -and $entryLines[$i] -match '^\s*<!--\s*END\s+personal-coding-standards\s*-->\s*$') { $curEnd = $i; break }
}

$newLines = @()
if (-not $entryExists) {
    $newLines = @($frontMatter) + $blockLines + @('')
    $mode = '新建'
} elseif ($curBegin -ge 0 -and $curEnd -gt $curBegin) {
    $before = @()
    if ($curBegin -gt 0) { $before = $entryLines[0..($curBegin - 1)] }
    $after = @()
    if ($curEnd -lt ($entryLines.Count - 1)) { $after = $entryLines[($curEnd + 1)..($entryLines.Count - 1)] }
    $newLines = @($before) + $blockLines + @($after)
    $mode = '替换标记块'
} else {
    # 没有标记块：整段追加到文件末尾，不碰原有规则
    $trimmed = @($entryLines)
    while ($trimmed.Count -gt 0 -and $trimmed[$trimmed.Count - 1] -eq '') {
        if ($trimmed.Count -eq 1) { $trimmed = @(); break }
        $trimmed = $trimmed[0..($trimmed.Count - 2)]
    }
    $newLines = @($trimmed) + @('', '') + $blockLines + @('')
    if ($trimmed.Count -eq 0) { $newLines = @($blockLines) + @('') }
    $mode = '追加（文件中没有标记块）'
}
Write-Info "合并方式：$mode"

$newText = ($newLines -join "`n")
$oldText = ''
if ($entryExists) { $oldText = ($entryLines -join "`n") }

if ($entryExists -and $newText -eq $oldText) {
    Write-Ok "内容已是最新，跳过写入"
} elseif ($DryRun) {
    Write-Warn "DryRun：将写入以下内容（前 20 行）"
    ($newText -split "`n") | Select-Object -First 20 | ForEach-Object { Write-Host "   | $_" -ForegroundColor DarkGray }
} else {
    $entryDir = Split-Path $EntryPath -Parent
    if ($entryDir -and -not (Test-Path $entryDir)) { New-Item -ItemType Directory -Force -Path $entryDir | Out-Null }
    if ($entryExists) {
        # 改动前留一份 .bak，便于人工回滚；只保留最近一次
        Copy-Item -Path $EntryPath -Destination ($EntryPath + '.bak') -Force
        Write-Info "已备份原文件到 $EntryPath.bak"
    }
    Write-TextFile -Path $EntryPath -Text $newText -Bom $bom -Eol $eol
    Write-Ok "已写入 $EntryPath（块外内容保留）"
}

# 5. 常驻记忆：脚本无法代替 AI 调用记忆工具，只输出可粘贴指令
Write-Section "5. 常驻铁律（需要 AI 会话执行）"
if (Test-Path $ironRulesFile) {
    Write-Warn "本步骤脚本不能自动完成：写入常驻记忆必须由 AI 会话调用记忆工具"
    Write-Info "把下面这句话连同文件内容交给本机 AI 会话："
    Write-Host '   「读取 ' -NoNewline -ForegroundColor DarkGray
    Write-Host $ironRulesFile -NoNewline -ForegroundColor White
    Write-Host ' 中的铁律，用记忆工具写进常驻记忆，每轮都要遵守。」' -ForegroundColor DarkGray
    Write-Info "写入后运行 verify.ps1，它会检查记忆里是否真的存在铁律指纹"
} else {
    Write-Fail "缺少 $ironRulesFile"
}

# 6. 调用校验脚本（默认执行，-SkipVerify 可跳过）
if (-not $SkipVerify -and -not $DryRun) {
    $verify = Join-Path $PSScriptRoot 'verify.ps1'
    if (Test-Path $verify) {
        & $verify -StandardsPath $StandardsPath -EntryPath $EntryPath
        exit $LASTEXITCODE
    }
    Write-Warn "未找到 $verify，跳过校验"
}

exit 0
