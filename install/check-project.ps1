#requires -Version 5.1
<#
.SYNOPSIS
  兼容入口：检查目标仓是否已落地规范（等价于 verify.ps1 -Segment project,drift）。

.DESCRIPTION
  检查逻辑已并入 install/verify.ps1 的第四段（项目落地）与第五段（漂移闭环），
  本脚本只做参数转换，保留给已有调用方与文档引用；新用法请直接用 verify.ps1。

.EXAMPLE
  powershell -File install/check-project.ps1 -RepoPath D:\codeData\my-app

.EXAMPLE
  powershell -File install/check-project.ps1 -RepoPath . -Json
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [string]$StandardsPath = '',
    [string]$RuleTestCommand = '',
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

$verify = Join-Path $PSScriptRoot 'verify.ps1'
if (-not (Test-Path $verify)) {
    Write-Host "找不到 $verify（脚本必须与 verify.ps1 放在同一目录）" -ForegroundColor Red
    exit 1
}

# 参数原样转给 verify.ps1；-StandardsPath 为空时由 verify 按默认 ~/.dsh/standards 解析
& $verify -Segment project, drift -Project $RepoPath -StandardsPath $StandardsPath -RuleTestCommand $RuleTestCommand -Json:$Json
exit $LASTEXITCODE
