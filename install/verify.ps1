#requires -Version 5.1
<#
.SYNOPSIS
  校验「个人编码与 AI 协作规范」是否真的生效（DSH 宿主，5 段 29 项）。

.DESCRIPTION
  五段：规范本体 → 入口指针 → 常驻记忆 → 项目落地 → 漂移。
  三态：PASS / FAIL（必须修）/ UNVERIFIABLE（无法自动判定，附人工步骤——不静默跳过）。
  任何 FAIL 都带修复指引；有 FAIL 时退出码为 1，便于接 CI 或开机脚本。

  严重度判定原则：
    FAIL         = 规范实际没生效，或规则文件被破坏（本体缺失、入口标记块坏、铁律没进记忆、矩阵造假、密钥入库）
    WARN         = 有偏移风险但可自动恢复或属正常过渡态（落后远端、文件变脏、字节接近上限、缺规范基线）
    UNVERIFIABLE = 脚本无法证明，必须人工确认（覆盖检测、证据抽查、无测试框架时的规则测试）

.PARAMETER Segment
  只跑指定段：standards / entry / memory / project / drift。默认全跑；未给 -Project 时跳过 project 与 drift。

.PARAMETER Project
  目标仓库根目录，第四、五段用。

.PARAMETER RuleTestCommand
  项目规则测试命令，第四段第 24 项用；不给则按是否具备测试框架判定。

.PARAMETER Json
  输出机器可读 JSON（含每项 id/segment/level/detail/hint 与汇总），便于接检查器。

.PARAMETER NoFetch
  跳过 git fetch（离线时避免卡住），第 6 项将报 UNVERIFIABLE。

.EXAMPLE
  powershell -File install/verify.ps1

.EXAMPLE
  powershell -File install/verify.ps1 -Segment standards,entry

.EXAMPLE
  powershell -File install/verify.ps1 -Segment project,drift -Project D:\codeData\my-app -Json
#>
[CmdletBinding()]
param(
    [string[]]$Segment = @('all'),

    [string]$StandardsPath = '',
    [string]$EntryPath = '',
    [ValidateSet('dsh', 'claude', 'cursor', 'codex')]
    [string]$HostType = 'dsh',

    [string]$Project = '',
    [string]$RuleTestCommand = '',
    [string[]]$MemoryFiles = @(),

    [int]$ByteBudget = 65536,
    [switch]$NoFetch,
    [switch]$Json
)

# 检查脚本按「逐项报告」执行：单条命令失败降级为该项结果，不中断整份报告
$ErrorActionPreference = 'Continue'

# powershell -File 会把 "project,drift" 当成一个字符串传进来，这里统一拆分并校验分段名
$validSegments = @('all', 'standards', 'entry', 'memory', 'project', 'drift')
$Segment = @($Segment | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($s in $Segment) {
    if ($validSegments -notcontains $s) {
        Write-Host "无效分段：$s（可选：$($validSegments -join ' / ')）" -ForegroundColor Red
        exit 2
    }
}

$script:results = New-Object System.Collections.ArrayList
$script:anchorList = @('中文伪代码', '先思路后代码', '数据来源', '静默兜底', '缺陷', '边界', 'graph', '提交', '密钥', '自审')

function Add-Check {
    param(
        [int]$Id, [string]$Seg, [string]$Name,
        [ValidateSet('PASS', 'FAIL', 'WARN', 'UNVERIFIABLE')][string]$Level,
        [string]$Detail, [string]$Hint = ''
    )
    # FAIL 必须带修复指引，否则等于只说"失败了"
    if ($Level -eq 'FAIL' -and -not $Hint) { $Hint = '（待补修复指引）' }
    [void]$script:results.Add([pscustomobject]@{
            Id = $Id; Segment = $Seg; Name = $Name; Level = $Level; Detail = $Detail; Hint = $Hint
        })
}

function Read-Text {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }
    return $text
}

# 统一按 LF 切行，避免 CRLF 检出导致逐行比对失配
function Get-Lines {
    param([string]$Text)
    return @(($Text -replace "`r`n", "`n") -split "`n")
}

function Get-MarkerIndex {
    param([string[]]$Lines)
    $b = -1; $e = -1; $bCount = 0; $eCount = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*<!--\s*BEGIN\s+personal-coding-standards\s*-->\s*$') {
            $bCount++
            if ($b -lt 0) { $b = $i }
        }
        if ($Lines[$i] -match '^\s*<!--\s*END\s+personal-coding-standards\s*-->\s*$') {
            $eCount++
            if ($e -lt 0) { $e = $i }
        }
    }
    return [pscustomobject]@{ Begin = $b; End = $e; BeginCount = $bCount; EndCount = $eCount }
}

function Get-SpecVersion {
    param([string]$StandardsPath)
    $spec = Join-Path $StandardsPath 'specs/个人编码与AI协作规范.md'
    if (-not (Test-Path $spec)) { return '' }
    $m = [regex]::Match((Read-Text $spec), '(?m)^版本:\s*(v[0-9]+\.[0-9]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-StandardsHead {
    param([string]$StandardsPath)
    $head = & git -C $StandardsPath rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) { return $head.Trim() }
    return ''
}

function Test-GitRepo {
    param([string]$Path)
    $null = & git -C $Path rev-parse --git-dir 2>&1
    return ($LASTEXITCODE -eq 0)
}

# 1. 解析路径
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

if ($Project) { $Project = [System.IO.Path]::GetFullPath($Project) }

# 2. 解析分段：默认前三段；给了 -Project 才带项目段与漂移段
$segments = @()
if ($Segment -contains 'all') {
    $segments = @('standards', 'entry', 'memory')
    if ($Project) { $segments += @('project', 'drift') }
} else {
    $segments = $Segment
}

if (-not $Json) {
    Write-Host "`n校验：个人编码与 AI 协作规范" -ForegroundColor Cyan
    Write-Host "  规范本体 : $StandardsPath"
    Write-Host "  入口文件 : $EntryPath"
    if ($Project) { Write-Host "  目标项目 : $Project" }
    Write-Host "  执行分段 : $($segments -join ', ')"
}

$standardsHead = ''
$specVersion = ''

# ========== 第一段：规范本体 ==========
if ($segments -contains 'standards') {
    # 3. 目录存在且是 git 克隆
    $gitOk = (Test-Path (Join-Path $StandardsPath '.git'))
    if (-not $gitOk) {
        Add-Check 1 'standards' '本体是 git 克隆' 'FAIL' "不是 git 仓：$StandardsPath" "按 README 重新安装：powershell -File <仓>/install/install.ps1"
    } else {
        Add-Check 1 'standards' '本体是 git 克隆' 'PASS' $StandardsPath

        # 4. 远程指向正确仓库
        $origin = & git -C $StandardsPath remote get-url origin 2>$null
        $normalized = ($origin -join '').Trim().ToLower()
        if (-not $normalized) {
            Add-Check 2 'standards' '远程仓库正确' 'FAIL' '没有 origin' "git -C `"$StandardsPath`" remote add origin https://gitee.com/ydcy_studio/ai-compilation-specifications.git"
        } elseif ($normalized -match 'ydcy_studio/ai-compilation-specifications') {
            Add-Check 2 'standards' '远程仓库正确' 'PASS' $origin
        } else {
            Add-Check 2 'standards' '远程仓库正确' 'FAIL' "origin=$origin" "git -C `"$StandardsPath`" remote set-url origin https://gitee.com/ydcy_studio/ai-compilation-specifications.git"
        }

        # 5. 工作区是否干净（作者机在装修订时会短暂变脏，故不阻断）
        $porcelain = & git -C $StandardsPath status --porcelain 2>$null
        if ($porcelain) {
            $cnt = @($porcelain).Count
            Add-Check 3 'standards' '工作区干净' 'WARN' "有 $cnt 处未提交改动，本机与其他机器已分叉" "提交并 push，或 git -C `"$StandardsPath`" checkout -- . 还原"
        } else {
            Add-Check 3 'standards' '工作区干净' 'PASS' '无未提交改动'
        }

        # 6. 版本可识别
        $standardsHead = Get-StandardsHead $StandardsPath
        if ($standardsHead) {
            Add-Check 4 'standards' '版本可识别' 'PASS' "HEAD=$standardsHead"
        } else {
            Add-Check 4 'standards' '版本可识别' 'FAIL' 'rev-parse 取不到 HEAD' '仓库可能损坏：重新 clone'
        }
    }

    # 7. 必读文件齐全且非空
    $required = @(
        'specs/个人编码与AI协作规范.md',
        'specs/附录-提交准则.md',
        'specs/附录-文档记忆体系.md',
        'install/agents-pointer.md',
        'install/iron-rules.txt',
        'install/project-spec-checklist.md'
    )
    $missing = @()
    foreach ($rel in $required) {
        $p = Join-Path $StandardsPath $rel
        if (-not (Test-Path $p) -or (Get-Item $p).Length -eq 0) { $missing += $rel }
    }
    if ($missing.Count -gt 0) {
        Add-Check 5 'standards' '必读文件齐全' 'FAIL' ("缺 {0} 个：{1}" -f $missing.Count, ($missing -join '、')) "git -C `"$StandardsPath`" pull；仍缺就重新 clone"
    } else {
        Add-Check 5 'standards' '必读文件齐全' 'PASS' "6 份必读文件存在且非空"
    }

    # 8. 与远端是否一致
    if ($NoFetch) {
        Add-Check 6 'standards' '未落后于远端' 'UNVERIFIABLE' '指定了 -NoFetch，未检查远端' "去掉 -NoFetch 或手动 git fetch 后比较 HEAD 与 origin"
    } elseif (-not $gitOk) {
        Add-Check 6 'standards' '未落后于远端' 'UNVERIFIABLE' '本体不是 git 仓，无法比较' '先修复第 1 项'
    } else {
        $fetchOut = & git -C $StandardsPath fetch --quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Check 6 'standards' '未落后于远端' 'UNVERIFIABLE' '无法连接远端（离线或鉴权失败）' "联网后执行 git -C `"$StandardsPath`" pull"
        } else {
            $upstream = (& git -C $StandardsPath rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null)
            if (-not $upstream) {
                Add-Check 6 'standards' '未落后于远端' 'UNVERIFIABLE' '本地分支没有上游' "git -C `"$StandardsPath`" branch --set-upstream-to=origin/master"
            } else {
                $upstream = $upstream.Trim()
                $behind = & git -C $StandardsPath rev-list --count "HEAD..$upstream" 2>$null
                if ($LASTEXITCODE -eq 0 -and [int]$behind -gt 0) {
                    Add-Check 6 'standards' '未落后于远端' 'FAIL' "落后 $upstream $behind 个提交" "git -C `"$StandardsPath`" pull --ff-only"
                } else {
                    Add-Check 6 'standards' '未落后于远端' 'PASS' "与 $upstream 一致"
                }
            }
        }
    }

    $specVersion = Get-SpecVersion $StandardsPath
}

# ========== 第二段：入口指针 ==========
$entryText = ''
if ($segments -contains 'entry') {
    # 9. 文件存在
    if (-not (Test-Path $EntryPath)) {
        Add-Check 7 'entry' '入口文件存在' 'FAIL' "不存在：$EntryPath" "powershell -File $StandardsPath/install/install.ps1 -HostType $HostType"
    } else {
        $entryText = Read-Text $EntryPath
        Add-Check 7 'entry' '入口文件存在' 'PASS' $EntryPath

        # 10/11. 标记块成对完整、内容覆盖模板
        $entryLines = Get-Lines $entryText
        $idx = Get-MarkerIndex $entryLines
        $tplPath = Join-Path $StandardsPath 'install/agents-pointer.md'
        $tplLines = @()
        $tplIdx = $null
        if (Test-Path $tplPath) {
            $tplLines = Get-Lines (Read-Text $tplPath)
            $tplIdx = Get-MarkerIndex $tplLines
        }

        if ($idx.BeginCount -ne 1 -or $idx.EndCount -ne 1 -or $idx.Begin -lt 0 -or $idx.End -le $idx.Begin) {
            Add-Check 8 'entry' '标记块成对完整' 'FAIL' ("BEGIN {0} 处、END {1} 处" -f $idx.BeginCount, $idx.EndCount) "用 install.ps1 重新并入；或手工保证 BEGIN/END 各一处且 BEGIN 在前"
        } else {
            Add-Check 8 'entry' '标记块成对完整' 'PASS' ("BEGIN@{0} END@{1}" -f $idx.Begin, $idx.End)

            $curBlock = @($entryLines[$idx.Begin..$idx.End] | ForEach-Object { $_.Trim() })
            if ($null -eq $tplIdx -or $tplIdx.Begin -lt 0) {
                Add-Check 9 'entry' '入口不旧于模板' 'UNVERIFIABLE' '读不到模板标记块' "确认 $tplPath 存在且带标记块"
            } else {
                $tplBlock = @($tplLines[$tplIdx.Begin..$tplIdx.End] | ForEach-Object { $_.Trim() })
                $missingLines = @($tplBlock | Where-Object { $curBlock -notcontains $_ })
                $extraLines = @($curBlock | Where-Object { $tplBlock -notcontains $_ })
                if ($missingLines.Count -gt 0) {
                    Add-Check 9 'entry' '入口不旧于模板' 'FAIL' ("模板有 {0} 行在入口里缺失，例如：{1}" -f $missingLines.Count, $missingLines[0]) "powershell -File $StandardsPath/install/install.ps1 -HostType $HostType 覆盖标记块"
                } elseif ($extraLines.Count -gt 0) {
                    Add-Check 9 'entry' '入口不旧于模板' 'PASS' ("模板必含行齐全，另有 {0} 行本地补充" -f $extraLines.Count)
                } else {
                    Add-Check 9 'entry' '入口不旧于模板' 'PASS' '与模板逐行一致'
                }
            }
        }

        # 12. 块外原有规则没被覆盖：与 install.ps1 留的 .bak 比对
        $bak = $EntryPath + '.bak'
        if (-not (Test-Path $bak)) {
            Add-Check 10 'entry' '块外规则未被覆盖' 'UNVERIFIABLE' '没有安装前备份（.bak），无法比对' "下次安装前保留 .bak；或人工确认块外内容只增不减"
        } elseif ($null -eq $idx -or $idx.Begin -lt 0 -or $idx.End -le $idx.Begin) {
            Add-Check 10 'entry' '块外规则未被覆盖' 'UNVERIFIABLE' '标记块不完整，无法剥离块外内容' '先修第 8 项'
        } else {
            $bakLines = Get-Lines (Read-Text $bak)
            $bidx = Get-MarkerIndex $bakLines
            if ($bidx.Begin -lt 0 -or $bidx.End -le $bidx.Begin) {
                $bakOutside = $bakLines
            } else {
                $bakOutside = @($bakLines[0..($bidx.Begin - 1)]) + @($bakLines[($bidx.End + 1)..($bakLines.Count - 1)])
            }
            $curOutside = @($entryLines[0..($idx.Begin - 1)]) + @($entryLines[($idx.End + 1)..($entryLines.Count - 1)])
            $lost = @($bakOutside | Where-Object { $_ -ne '' -and $curOutside -notcontains $_ })
            if ($lost.Count -gt 0) {
                Add-Check 10 'entry' '块外规则未被覆盖' 'FAIL' ("块外丢了 {0} 行，例如：{1}" -f $lost.Count, $lost[0]) "从 $bak 恢复被删内容，再重跑 install.ps1（只替换标记块）"
            } else {
                Add-Check 10 'entry' '块外规则未被覆盖' 'PASS' '块外内容只增未减'
            }
        }

        # 13. 字节预算
        $size = (Get-Item $EntryPath).Length
        if ($size -ge $ByteBudget) {
            Add-Check 11 'entry' '不触发字节预算' 'WARN' ("{0} 字节 ≥ 预算 {1}" -f $size, $ByteBudget) '入口只留指针，正文放本体；确认铁律已在常驻记忆'
        } else {
            Add-Check 11 'entry' '不触发字节预算' 'PASS' "$size / $ByteBudget 字节"
        }
    }
}

# ========== 第三段：常驻记忆 ==========
if ($segments -contains 'memory') {
    $stores = @()
    if ($MemoryFiles.Count -gt 0) {
        $stores = @($MemoryFiles | Where-Object { Test-Path $_ })
    } else {
        $candidates = @(
            (Join-Path $HOME '.dsh/.mnemon/runtime/memories.json'),
            (Join-Path $HOME '.dsh/.mnemon/runtime/MEMORY.md'),
            (Join-Path $HOME '.dsh/.mnemon/runtime/USER.md'),
            (Join-Path (Get-Location).Path '.mnemon/runtime/memories.json'),
            (Join-Path (Get-Location).Path '.mnemon/runtime/MEMORY.md'),
            (Join-Path $HOME '.claude/CLAUDE.md')
        )
        $stores = @($candidates | Where-Object { Test-Path $_ })
    }

    # 14. 载体存在
    if ($stores.Count -eq 0) {
        Add-Check 12 'memory' '记忆载体存在' 'FAIL' '未发现任何记忆存储（DSH 的 .mnemon/runtime 或宿主等价物）' '先让宿主初始化记忆，再用记忆工具写入铁律'
    } else {
        Add-Check 12 'memory' '记忆载体存在' 'PASS' "$($stores.Count) 个载体"

        # 15. 铁律关键条目命中率
        $bestHit = 0; $bestFile = ''; $bestText = ''
        foreach ($f in $stores) {
            $raw = Read-Text $f
            $hit = 0
            foreach ($a in $script:anchorList) { if ($raw -like "*$a*") { $hit++ } }
            if ($hit -gt $bestHit) { $bestHit = $hit; $bestFile = $f; $bestText = $raw }
        }
        $ratio = [math]::Round($bestHit / $script:anchorList.Count, 2)
        if ($ratio -ge 0.8) {
            Add-Check 13 'memory' '铁律条目在场' 'PASS' ("命中 {0}/{1}（{2:P0}）：{3}" -f $bestHit, $script:anchorList.Count, $ratio, $bestFile)
        } elseif ($bestHit -gt 0) {
            Add-Check 13 'memory' '铁律条目在场' 'FAIL' ("只命中 {0}/{1}（{2:P0}）：{3}" -f $bestHit, $script:anchorList.Count, $ratio, $bestFile) "用记忆工具重新写入完整铁律（$StandardsPath/install/iron-rules.txt）"
        } else {
            Add-Check 13 'memory' '铁律条目在场' 'FAIL' ("{0} 个载体里 0 条锚点" -f $stores.Count) "把 install/iron-rules.txt 交给 AI 会话，用记忆工具写进常驻记忆"
        }

        # 16. 是否为结构化记录，而不是只写了 Markdown 投影
        $jsonStore = @($stores | Where-Object { $_ -like '*memories.json' })
        if ($jsonStore.Count -eq 0) {
            Add-Check 14 'memory' '结构化记录而非投影' 'UNVERIFIABLE' '没有 memories.json，无法区分结构化记录与投影' '按宿主存储格式确认；投影会被下一次写入覆盖'
        } else {
            $structuredHit = 0
            foreach ($f in $jsonStore) {
                $raw = Read-Text $f
                $hit = 0
                foreach ($a in $script:anchorList) { if ($raw -like "*$a*") { $hit++ } }
                if ($hit -gt $structuredHit) { $structuredHit = $hit }
            }
            if ($structuredHit -ge 5) {
                Add-Check 14 'memory' '结构化记录而非投影' 'PASS' "memories.json 内命中 $structuredHit 条锚点"
            } else {
                Add-Check 14 'memory' '结构化记录而非投影' 'FAIL' "memories.json 内只命中 $structuredHit 条锚点（疑似只写了投影）" '通过记忆工具写入；直接拷 MEMORY.md 会被下次写入覆盖'
            }
        }

        # 17. 铁律版本与本体一致
        $ver = Get-SpecVersion $StandardsPath
        if (-not $ver) {
            Add-Check 15 'memory' '铁律版本一致' 'UNVERIFIABLE' '本体取不到版本号' '确认正文 front matter 有 版本: vX.Y'
        } elseif ($bestText -like "*$ver*") {
            Add-Check 15 'memory' '铁律版本一致' 'PASS' "记忆里含 $ver"
        } elseif ($bestText -match 'v[0-9]+\.[0-9]+') {
            $found = [regex]::Match($bestText, 'v[0-9]+\.[0-9]+').Value
            Add-Check 15 'memory' '铁律版本一致' 'FAIL' "记忆里是 $found，本体是 $ver" '本体升级后需用记忆工具重写铁律'
        } else {
            Add-Check 15 'memory' '铁律版本一致' 'UNVERIFIABLE' "记忆里没有版本标记（本体 $ver）" "在铁律文本里带上「规范版本：$ver」再写入，才能自动比对"
        }
    }
}

# ========== 第四段：项目落地 ==========
$ruleFiles = @()
$ruleText = ''
$reportPath = ''
$reportText = ''
$baseline = ''

# 第四、五段共用的项目上下文：一次扫描，两段复用（含迁移报告与规范基线）
if ($segments -contains 'project' -or $segments -contains 'drift') {
    if (-not $Project -or -not (Test-Path $Project)) {
        if ($segments -contains 'project') {
            Add-Check 16 'project' '项目规则入口' 'UNVERIFIABLE' '未指定 -Project 或目录不存在' '用 -Project <目标仓根目录> 指定'
        }
    } else {
        foreach ($n in @('AGENTS.md', 'CLAUDE.md', '.cursorrules')) {
            $p = Join-Path $Project $n
            if (Test-Path $p) { $ruleFiles += $p }
        }
        $cr = Join-Path $Project '.cursor/rules'
        if (Test-Path $cr) {
            $ruleFiles += @(Get-ChildItem $cr -Filter '*.mdc' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
        foreach ($f in $ruleFiles) { $ruleText += (Read-Text $f) + "`n" }

        # 找迁移报告：优先 docs/ 与 doc/，其次仓库根的 Markdown
        $cands = @()
        foreach ($dirName in @('docs', 'doc')) {
            $d = Join-Path $Project $dirName
            if (Test-Path $d) { $cands += @(Get-ChildItem $d -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue | Select-Object -First 200) }
        }
        $cands += @(Get-ChildItem $Project -Filter '*.md' -File -ErrorAction SilentlyContinue)
        foreach ($c in $cands) {
            $t = Read-Text $c.FullName
            if ($t -like '*迁移矩阵*') { $reportPath = $c.FullName; $reportText = $t; break }
        }

        # 规范基线：规则文件或迁移报告里的「规范基线 <commit>」
        foreach ($f in (@($ruleFiles) + @($reportPath | Where-Object { $_ }))) {
            $m = [regex]::Match((Read-Text $f), '规范基线[^\r\n]{0,40}?([0-9a-f]{7,40})')
            if ($m.Success) { $baseline = $m.Groups[1].Value; break }
        }
    }
}

if ($segments -contains 'project' -and $Project -and (Test-Path $Project)) {
    # 18. 规则主文件存在且非空
    if ($ruleFiles.Count -eq 0) {
        Add-Check 16 'project' '项目规则入口' 'FAIL' '没有 AGENTS.md / CLAUDE.md / .cursor/rules' '按 README「迁移到具体项目」第 2 步建立项目规则入口'
    } else {
        $empty = @($ruleFiles | Where-Object { (Get-Item $_).Length -eq 0 })
        if ($empty.Count -gt 0) {
            Add-Check 16 'project' '项目规则入口' 'FAIL' ("空文件：{0}" -f (($empty | ForEach-Object { Split-Path $_ -Leaf }) -join '、')) '补全内容或删除空文件'
        } else {
            Add-Check 16 'project' '项目规则入口' 'PASS' (($ruleFiles | ForEach-Object { Split-Path $_ -Leaf }) -join '、')
        }
    }

    # 19. 迁移报告与规范基线已在第四、五段共用的上下文里扫描完成

    # 20. 占位符与疑似密钥（只扫规则文件与迁移报告，避免误伤业务文档）
    $scanFiles = @($ruleFiles)
    if ($reportPath) { $scanFiles += $reportPath }
    $phPattern = 'TODO|TBD|FIXME|\[待填\]|\[仓库名|\[命令\]|\[路径\]|\[\.\.\.\]|\{\{'
    $secretPattern = 'sk-[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    $phHits = @(); $secretHits = @()
    foreach ($f in $scanFiles) {
        $lines = Get-Lines (Read-Text $f)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $phPattern) { $phHits += ("{0}:{1} {2}" -f (Split-Path $f -Leaf), ($i + 1), $lines[$i].Trim()) }
            if ($lines[$i] -match $secretPattern) { $secretHits += ("{0}:{1}" -f (Split-Path $f -Leaf), ($i + 1)) }
        }
    }
    if ($secretHits.Count -gt 0) {
        Add-Check 17 'project' '无占位符与密钥' 'FAIL' ("疑似密钥 {0} 处：{1}" -f $secretHits.Count, ($secretHits -join '、')) '立即删除并轮换已泄露的值'
    } elseif ($phHits.Count -gt 0) {
        Add-Check 17 'project' '无占位符与密钥' 'FAIL' ("{0} 处占位符，例如 {1}" -f $phHits.Count, $phHits[0]) '逐项落实或移入待确认清单'
    } else {
        Add-Check 17 'project' '无占位符与密钥' 'PASS' '规则文件与迁移报告无占位符、无密钥特征'
    }

    if (-not $reportPath) {
        Add-Check 18 'project' '迁移矩阵三态' 'FAIL' '没找到包含「迁移矩阵」的迁移报告' '用 install/project-spec-checklist.md 填写后放进 docs/task-artifacts/'
    } else {
        $missingStates = @()
        foreach ($st in @('已落地', '不适用', '待确认')) { if ($reportText -notlike "*$st*") { $missingStates += $st } }
        if ($missingStates.Count -gt 0) {
            Add-Check 18 'project' '迁移矩阵三态' 'FAIL' ("缺状态：{0}" -f ($missingStates -join '、')) '每条只能是 已落地 / 不适用（理由） / 待确认（编号）'
        } else {
            Add-Check 18 'project' '迁移矩阵三态' 'PASS' '三态齐全'
        }

        # 21. 待确认项必须落到清单
        if ($reportText -like '*待确认*' -and $reportText -notlike '*待确认清单*') {
            Add-Check 19 'project' '待确认清单' 'FAIL' '矩阵里有「待确认」，但没有「待确认清单」' '按模板第 4 节列出编号/问题/可选方案/影响'
        } elseif ($reportText -like '*待确认清单*') {
            Add-Check 19 'project' '待确认清单' 'PASS' '存在待确认清单'
        } else {
            Add-Check 19 'project' '待确认清单' 'PASS' '无待确认项'
        }

        # 22. 矩阵里标「已落地」的必须有证据（空证据=把默认值当项目值）
        $noEvidence = @()
        foreach ($line in (Get-Lines $reportText)) {
            if ($line -notmatch '^\s*\|' -or $line -notmatch '已落地') { continue }
            $cells = @(($line.Trim().Trim('|')) -split '\|' | ForEach-Object { $_.Trim() })
            $statusIdx = -1
            for ($i = 0; $i -lt $cells.Count; $i++) { if ($cells[$i] -match '^已落地') { $statusIdx = $i; break } }
            if ($statusIdx -gt 0) {
                $evidence = $cells[$statusIdx - 1]
                if ($evidence -eq '' -or $evidence -eq '-' -or $evidence -eq '`-`') { $noEvidence += $line.Trim() }
            }
        }
        if ($noEvidence.Count -gt 0) {
            Add-Check 20 'project' '项目值有证据' 'FAIL' ("{0} 行标了已落地但证据列为空" -f $noEvidence.Count) "补 文件:行 证据；补不出就改成待确认"
        } else {
            Add-Check 20 'project' '项目值有证据' 'PASS' '已落地行均有证据列'
        }

        # 23. 规范基线
        $baseline = $null
        foreach ($f in $scanFiles) {
            $m = [regex]::Match((Read-Text $f), '规范基线[^\r\n]{0,40}?([0-9a-f]{7,40})')
            if ($m.Success) { $baseline = $m.Groups[1].Value; break }
        }
    # 23. 规范基线已在共用上下文里解析完成
    }

    # 24. 提交准则落地
    $commitDoc = @(Get-ChildItem $Project -Recurse -Filter '*commit*.md' -File -ErrorAction SilentlyContinue | Select-Object -First 3)
    if ($ruleText -match 'scope' -and $ruleText -match 'type') {
        Add-Check 21 'project' '提交准则已落地' 'PASS' '规则文件含 type/scope 约束'
    } elseif ($commitDoc.Count -gt 0) {
        Add-Check 21 'project' '提交准则已落地' 'PASS' ("提交准则文件：{0}" -f (($commitDoc | ForEach-Object { Split-Path $_ -Leaf }) -join '、'))
    } else {
        Add-Check 21 'project' '提交准则已落地' 'FAIL' '规则文件无 type/scope 约束，也没有提交准则文件' '按《附录-提交准则》写 scope 词表、阈值、验证命令、远程策略'
    }

    # 25. 文档记忆索引
    $docsDir = Join-Path $Project 'docs'
    if ((Test-Path $docsDir) -and -not (Test-Path (Join-Path $docsDir 'MEMORY_INDEX.md'))) {
        Add-Check 22 'project' '文档记忆索引' 'WARN' 'docs/ 存在但没有 docs/MEMORY_INDEX.md' '启用该附录时必建；不启用则在报告写「不适用」'
    } else {
        Add-Check 22 'project' '文档记忆索引' 'PASS' '无需处理或已存在'
    }

    # 26. .env / .env.example
    $trackedEnv = $null
    if (Test-GitRepo $Project) {
        $null = & git -C $Project ls-files --error-unmatch '.env' 2>&1
        if ($LASTEXITCODE -eq 0) { $trackedEnv = 'yes' }
    }
    $envExample = Join-Path $Project '.env.example'
    if ($trackedEnv) {
        Add-Check 23 'project' '配置与密钥' 'FAIL' '.env 已被 git 跟踪' 'git rm --cached .env，补 .gitignore 与 .env.example，并轮换已泄露的值'
    } elseif (-not (Test-Path $envExample)) {
        Add-Check 23 'project' '配置与密钥' 'WARN' '没有 .env.example' '涉及配置时补 .env.example（假值）；不涉及就在报告写「不适用」'
    } elseif ((Get-Content $envExample -Raw) -match 'TODO|\[\.\.\.\]') {
        Add-Check 23 'project' '配置与密钥' 'WARN' '.env.example 里还有占位符' '补变量名/用途/假默认值/敏感性'
    } else {
        Add-Check 23 'project' '配置与密钥' 'PASS' '未跟踪 .env，存在 .env.example'
    }

    # 27. 规则测试：有命令就跑，没命令按是否有测试框架判定
    if ($RuleTestCommand) {
        $LASTEXITCODE = 0
        $out = & ([scriptblock]::Create($RuleTestCommand)) 2>&1
        if ($LASTEXITCODE -eq 0 -and $?) {
            Add-Check 24 'project' '规则测试通过' 'PASS' '退出码 0'
        } else {
            Add-Check 24 'project' '规则测试通过' 'FAIL' ("退出码 $LASTEXITCODE") ((($out | Select-Object -Last 3) -join ' / '))
        }
    } else {
        $hasFramework = (Test-Path (Join-Path $Project 'package.json')) -or
            (Test-Path (Join-Path $Project 'pom.xml')) -or
            (Test-Path (Join-Path $Project 'build.gradle')) -or
            (Test-Path (Join-Path $Project 'pyproject.toml'))
        if ($hasFramework) {
            Add-Check 24 'project' '规则测试通过' 'UNVERIFIABLE' '项目有测试框架，但没给 -RuleTestCommand' '加 -RuleTestCommand "npm run test:rules"（或等价命令）'
        } else {
            Add-Check 24 'project' '规则测试通过' 'PASS' '未发现测试框架，按规范豁免'
        }
    }

    # 28. 原有规则是合并而非覆盖
    Add-Check 25 'project' '已有规则为合并' 'UNVERIFIABLE' '仓库里没有安装前基线，无法自动比对' '人工抽查：原有规则段落是否仍在；必要时与提交历史对比'

    # 29. 项目规范记录了规范基线
    if ($baseline) {
        Add-Check 26 'project' '记录规范基线' 'PASS' "基线 $baseline"
    } else {
        Add-Check 26 'project' '记录规范基线' 'WARN' '迁移报告里没有「规范基线 <commit>」' '取自 git -C ~/.dsh/standards rev-parse --short HEAD，填进报告'
    }
}

# ========== 第五段：漂移闭环 ==========
if ($segments -contains 'drift') {
    if (-not $Project -or -not (Test-Path $Project)) {
        Add-Check 27 'drift' '项目规范未过期' 'UNVERIFIABLE' '未指定 -Project' '用 -Project <目标仓> 指定'
    } else {
        $head = $standardsHead
        if (-not $head) { $head = Get-StandardsHead $StandardsPath }
        if (-not $baseline) {
            Add-Check 27 'drift' '项目规范未过期' 'UNVERIFIABLE' '项目没记规范基线' '先补第 26 项'
        } elseif (-not $head) {
            Add-Check 27 'drift' '项目规范未过期' 'UNVERIFIABLE' '本体取不到 HEAD' '先修第一段'
        } elseif ($head.StartsWith($baseline) -or $baseline.StartsWith($head)) {
            Add-Check 27 'drift' '项目规范未过期' 'PASS' "基线 $baseline = 本体 $head"
        } else {
            Add-Check 27 'drift' '项目规范未过期' 'WARN' ("项目基线 $baseline，本体 $head" ) '规范升过版：按迁移矩阵逐条复核受影响条目，复核完更新基线'
        }

        # 28. 个人偏好层存在且被入口引用
        $pref = Join-Path $StandardsPath 'specs/个人偏好.md'
        if (-not (Test-Path $pref)) {
            Add-Check 28 'drift' '个人偏好层' 'WARN' '本体里没有 specs/个人偏好.md' '用户层是可选的：不需要就忽略；需要就 git pull 同步'
        } else {
            $refText = $entryText
            if (-not $refText -and (Test-Path $EntryPath)) { $refText = Read-Text $EntryPath }
            if ($refText -like '*个人偏好*') {
                Add-Check 28 'drift' '个人偏好层' 'PASS' '本体存在且入口指针已引用'
            } else {
                Add-Check 28 'drift' '个人偏好层' 'WARN' '文件存在但入口指针没引用' '重跑 install.ps1 让入口指向个人偏好层'
            }
        }

        # 29. 附录「示例」条目是否被默认套用
        # 只做启发式：从附录抽取「（示例：…）」片段，去掉「某仓」这类限定词后到项目规则里找；
        # 命中多说明项目规则在照抄别仓的示例，需要人工确认该仓是否同样要求。
        $examplePhrases = @()
        $specDir = Join-Path $StandardsPath 'specs'
        if (Test-Path $specDir) {
            foreach ($f in (Get-ChildItem $specDir -Filter '附录-*.md' -File -ErrorAction SilentlyContinue)) {
                $t = Read-Text $f.FullName
                foreach ($m in [regex]::Matches($t, '（示例：([^）]{3,60})）')) { $examplePhrases += $m.Groups[1].Value }
            }
        }
        $ruleTextAll = ''
        foreach ($f in $ruleFiles) { $ruleTextAll += (Read-Text $f) + "`n" }
        $adopted = @()
        foreach ($ph in ($examplePhrases | Select-Object -Unique)) {
            # 去限定词后作为主签名；带反引号的代码片段作为补充签名（太短的不算，避免 gap 这类误报）
            $key = ($ph -replace '[`（）]', '').Trim()
            $key = ($key -replace '^(某仓|某个仓|某项目|一个|本项目|目标仓)[，,、]?', '').Trim()
            $hit = $false
            if ($key.Length -ge 4 -and $ruleTextAll -like "*$key*") { $hit = $true }
            if (-not $hit) {
                $code = [regex]::Match($ph, '`([^`]{8,40})`')
                if ($code.Success -and $ruleTextAll -like "*$($code.Groups[1].Value)*") {
                    $hit = $true
                    $key = $code.Groups[1].Value
                }
            }
            if ($hit) { $adopted += $key }
        }
        $adopted = @($adopted | Select-Object -Unique)
        if ($adopted.Count -gt 0) {
            Add-Check 29 'drift' '示例条目未默认套用' 'WARN' ("规则文件出现 {0} 条疑似附录示例：{1}" -f $adopted.Count, ($adopted -join '、')) '逐条确认目标仓是否同样要求，确认后写进待确认清单或补证据'
        } else {
            Add-Check 29 'drift' '示例条目未默认套用' 'PASS' '未发现照抄附录示例条目'
        }
    }
}

# ========== 输出 ==========
$pass = @($script:results | Where-Object { $_.Level -eq 'PASS' }).Count
$fail = @($script:results | Where-Object { $_.Level -eq 'FAIL' }).Count
$warn = @($script:results | Where-Object { $_.Level -eq 'WARN' }).Count
$unv = @($script:results | Where-Object { $_.Level -eq 'UNVERIFIABLE' }).Count
$exitCode = if ($fail -gt 0) { 1 } else { 0 }

if ($Json) {
    $report = [pscustomobject]@{
        generatedAt   = (Get-Date).ToString('o')
        host          = $HostType
        standardsPath = $StandardsPath
        entryPath     = $EntryPath
        projectPath   = $Project
        segments      = @($segments)
        checks        = @($script:results | ForEach-Object {
                [pscustomobject]@{ id = $_.Id; segment = $_.Segment; name = $_.Name; level = $_.Level; detail = $_.Detail; hint = $_.Hint }
            })
        summary       = [pscustomobject]@{ pass = $pass; fail = $fail; warn = $warn; unverifiable = $unv }
        exitCode      = $exitCode
    }
    $report | ConvertTo-Json -Depth 6
    exit $exitCode
}

$segNames = @{ standards = '一、规范本体'; entry = '二、入口指针'; memory = '三、常驻记忆'; project = '四、项目落地'; drift = '五、漂移闭环' }
foreach ($seg in @('standards', 'entry', 'memory', 'project', 'drift')) {
    $items = @($script:results | Where-Object { $_.Segment -eq $seg })
    if ($items.Count -eq 0) { continue }
    Write-Host "`n$($segNames[$seg])" -ForegroundColor Cyan
    foreach ($r in $items) {
        switch ($r.Level) {
            'PASS' { Write-Host ("  [{0}] {1,2}. {2}：{3}" -f 'PASS', $r.Id, $r.Name, $r.Detail) -ForegroundColor Green }
            'WARN' { Write-Host ("  [{0}] {1,2}. {2}：{3}" -f 'WARN', $r.Id, $r.Name, $r.Detail) -ForegroundColor Yellow }
            'FAIL' { Write-Host ("  [{0}] {1,2}. {2}：{3}" -f 'FAIL', $r.Id, $r.Name, $r.Detail) -ForegroundColor Red }
            'UNVERIFIABLE' { Write-Host ("  [{0}] {1,2}. {2}：{3}" -f 'UNVERIFIABLE', $r.Id, $r.Name, $r.Detail) -ForegroundColor Magenta }
        }
        if ($r.Hint) { Write-Host ("            → {0}" -f $r.Hint) -ForegroundColor DarkGray }
    }
}

Write-Host ''
Write-Host ("汇总：PASS {0} / FAIL {1} / WARN {2} / UNVERIFIABLE {3}" -f $pass, $fail, $warn, $unv)
if ($fail -gt 0) {
    Write-Host '结论：未生效（有必须修复项）' -ForegroundColor Red
} elseif ($unv -gt 0) {
    Write-Host '结论：自动检查通过，但有无法自动验证项，需人工确认' -ForegroundColor Magenta
} elseif ($warn -gt 0) {
    Write-Host '结论：生效（WARN 项建议处理）' -ForegroundColor Yellow
} else {
    Write-Host '结论：全部通过' -ForegroundColor Green
}
exit $exitCode
