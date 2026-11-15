# handoff-kit · 让下一个 agent 三秒接上你
#
# 解决的问题：多轮 agent 会话之间上下文会丢，接手的人只能重新问一遍「做到哪了」。
# 做法：在项目里放一个 .handoff\ 目录，pack 一次就产出一份可交接的快照 + 一段可直接粘贴的恢复语。
#
# 命令：
#   handoff.ps1 init                 初始化 .handoff\（笔记模板 + 配置）
#   handoff.ps1 pack [-Note 一句话]  采集事实 + 合入笔记，生成一包
#   handoff.ps1 boot [-Json]         打印最新包的恢复语（粘给下一个 agent）
#   handoff.ps1 list                 列出所有包
#   handoff.ps1 check                检查最新包是否完整、有无疑似密钥

param(
    [Parameter(Position = 0)][string]$Cmd = 'help',
    [Parameter(Position = 1)][string]$Arg1,
    [string]$Root = '',
    [string]$Note = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
# 项目根：默认当前目录；CI 与测试用 -Root 指过去
$Root = if ($Root) { [IO.Path]::GetFullPath($Root) } else { [IO.Path]::GetFullPath((Get-Location).Path) }
$HandoffDir = Join-Path $Root '.handoff'
$PacksDir = Join-Path $HandoffDir 'packs'
$LatestFile = Join-Path $HandoffDir 'latest.txt'
$NotesFile = Join-Path $HandoffDir 'notes.md'
$Utf8 = New-Object Text.UTF8Encoding($false)

$NotesTemplate = @'
# 交接笔记

> 这份是给人/agent 手写的部分。pack 时原样并入交接包，不会覆盖。

## 停点
（上次做到哪、下一步从哪开始。一句话也行）

## 已完成
-

## 待办
- [ ]

## 约束 / 不要动
-
'@

function Initialize-Handoff {
    foreach ($d in @($HandoffDir, $PacksDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $NotesFile)) {
        [IO.File]::WriteAllText($NotesFile, (($NotesTemplate -replace "`r`n", "`n") + "`n"), $Utf8)
    }
}

function Get-GitExe {
    # PATH 里没有 git 时，退回 Windows 默认安装位置（新装 git 的机器常见 PATH 未刷新）
    $c = Get-Command git -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}
$script:GitExe = Get-GitExe

function Invoke-Git([string[]]$GitArgs) {
    # 没有 git 或不是仓库时返回 $null，交接包照常生成（只是没有 git 事实）
    if (-not $script:GitExe) { return $null }
    try {
        $out = & $script:GitExe -C $Root @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($out)
    } catch { return $null }
}

function Get-GitFacts {
    $branch = Invoke-Git @('branch', '--show-current')
    if ($null -eq $branch) { return $null }
    $head = Invoke-Git @('log', '-1', '--pretty=format:%h %s')
    $count = Invoke-Git @('rev-list', '--count', 'HEAD')
    $dirty = Invoke-Git @('status', '--short')
    return [ordered]@{
        branch  = ([string]($branch -join '')).Trim()
        head    = ([string]($head -join '')).Trim()
        commits = ([string]($count -join '')).Trim()
        dirty   = @($dirty | Where-Object { $_ -and $_.Trim() })
    }
}

function Get-TopLevel {
    Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.handoff' } |
        Sort-Object { -not $_.PSIsContainer }, Name |
        Select-Object -First 40 |
        ForEach-Object { if ($_.PSIsContainer) { $_.Name + '/' } else { $_.Name } }
}

function Get-NotesSection([string]$text, [string]$title) {
    # 从笔记里取一段（## 标题 到下一个 ## 之前），去掉模板占位
    $m = [regex]::Match($text, '(?ms)^##\s*' + [regex]::Escape($title) + '\s*\r?\n(.*?)(?=^##\s|\z)')
    if (-not $m.Success) { return '' }
    $body = $m.Groups[1].Value.Trim()
    $body = ($body -split "\r?\n" | Where-Object { $_.Trim() -and $_.Trim() -ne '-' -and $_.Trim() -ne '- [ ]' }) -join "`n"
    return $body
}

function New-Pack {
    Initialize-Handoff
    $now = Get-Date
    $id = $now.ToString('yyyyMMdd_HHmmss')
    $packDir = Join-Path $PacksDir $id
    New-Item -ItemType Directory -Path $packDir -Force | Out-Null

    $git = Get-GitFacts
    $notes = [IO.File]::ReadAllText($NotesFile, [Text.Encoding]::UTF8)
    $top = @(Get-TopLevel)
    $projectName = Split-Path -Leaf $Root

    $facts = [ordered]@{
        project = $projectName
        root    = $Root
        created = $now.ToString('yyyy-MM-dd HH:mm:ss')
        os      = [Environment]::OSVersion.VersionString
        pwsh    = $PSVersionTable.PSVersion.ToString()
        note    = $Note
        git     = $git
        top     = $top
    }
    [IO.File]::WriteAllText((Join-Path $packDir 'facts.json'), (ConvertTo-Json -InputObject $facts -Depth 6), $Utf8)

    $stop    = Get-NotesSection $notes '停点'
    $done    = Get-NotesSection $notes '已完成'
    $todo    = Get-NotesSection $notes '待办'
    $limits  = Get-NotesSection $notes '约束 / 不要动'

    $gitLine = if ($git) { ('分支 `' + $git.branch + '`，HEAD `' + $git.head + '`，脏文件 ' + $git.dirty.Count + ' 个') } else { '（非 git 仓库或没有 git）' }

    $bootLines = @(
        '# 恢复语（直接粘给接手的 agent）'
        ''
        ('你在接手项目「' + $projectName + '」。先读同目录下的 HANDOFF.md，再按下面的停点继续。')
        ''
        ('- 路径：' + $Root)
        ('- 版本：' + $gitLine)
        ('- 生成时间：' + $now.ToString('yyyy-MM-dd HH:mm:ss'))
        ''
        '## 上次停点'
        $(if ($stop) { $stop } else { '（未填写）' })
        ''
        '## 硬约束'
        $(if ($limits) { $limits } else { '（未填写）' })
        ''
        '## 规矩'
        '1. 先复述你读到的「停点 / 待办 / 约束」，确认无误再动手。'
        '2. 不确定的事先问，不要猜着改。'
        '3. 每完成一步就更新 .handoff\notes.md，下次交接靠它。'
    )
    [IO.File]::WriteAllText((Join-Path $packDir 'BOOT.md'), (($bootLines -join "`n") + "`n"), $Utf8)

    $handoffLines = @(
        ('# ' + $projectName + ' · 交接包 ' + $id)
        ''
        '## 一句话'
        $(if ($Note) { $Note } else { '（未填写 pack 备注）' })
        ''
        '## 事实（自动采集）'
        ''
        '| 项 | 值 |'
        '| --- | --- |'
        ('| 路径 | `' + $Root + '` |')
        ('| 生成时间 | ' + $now.ToString('yyyy-MM-dd HH:mm:ss') + ' |')
        ('| 版本 | ' + $gitLine + ' |')
        ('| 顶层条目 | ' + $top.Count + ' 个 |')
        ''
        $(if ($git -and $git.dirty.Count -gt 0) { '### 未提交改动' + "`n" + (($git.dirty | Select-Object -First 30 | ForEach-Object { '- `' + $_ + '`' }) -join "`n") } else { '' })
        ''
        '## 停点'
        $(if ($stop) { $stop } else { '（未填写）' })
        ''
        '## 已完成'
        $(if ($done) { $done } else { '（未填写）' })
        ''
        '## 待办'
        $(if ($todo) { $todo } else { '（未填写）' })
        ''
        '## 约束 / 不要动'
        $(if ($limits) { $limits } else { '（未填写）' })
        ''
        '## 顶层条目'
        (($top | ForEach-Object { '- `' + $_ + '`' }) -join "`n")
    )
    [IO.File]::WriteAllText((Join-Path $packDir 'HANDOFF.md'), (($handoffLines -join "`n") + "`n"), $Utf8)

    Copy-Item -LiteralPath $NotesFile -Destination (Join-Path $packDir 'notes.md') -Force

    $files = @(Get-ChildItem -LiteralPath $packDir -File | ForEach-Object { [ordered]@{ name = $_.Name; bytes = $_.Length } })
    $manifest = [ordered]@{
        id      = $id
        project = $projectName
        created = $now.ToString('yyyy-MM-dd HH:mm:ss')
        note    = $Note
        git     = $git
        files   = $files
    }
    [IO.File]::WriteAllText((Join-Path $packDir 'manifest.json'), (ConvertTo-Json -InputObject $manifest -Depth 6), $Utf8)

    [IO.File]::WriteAllText($LatestFile, $packDir, $Utf8)
    return $packDir
}

function Get-LatestPack {
    if (-not (Test-Path -LiteralPath $LatestFile)) { return $null }
    $p = ([IO.File]::ReadAllText($LatestFile, [Text.Encoding]::UTF8)).Trim()
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    return $null
}

function Invoke-Check([string]$packDir) {
    $required = @('BOOT.md', 'HANDOFF.md', 'facts.json', 'manifest.json', 'notes.md')
    $problems = @()
    foreach ($f in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $packDir $f))) { $problems += ('缺文件：' + $f) }
    }
    if ($problems.Count -eq 0) {
        $patterns = @(
            'sk-[A-Za-z0-9]{20,}', 'ghp_[A-Za-z0-9]{36}', 'gho_[A-Za-z0-9]{36}',
            'AKIA[0-9A-Z]{16}', 'xox[baprs]-[A-Za-z0-9-]+', 'BEGIN [A-Z ]*PRIVATE KEY'
        )
        foreach ($f in @('BOOT.md', 'HANDOFF.md', 'facts.json', 'notes.md')) {
            $text = [IO.File]::ReadAllText((Join-Path $packDir $f), [Text.Encoding]::UTF8)
            foreach ($p in $patterns) {
                if ($text -match $p) { $problems += ('疑似密钥：' + $f + ' 命中 /' + $p + '/') }
            }
        }
    }
    if ($problems.Count -eq 0) { return @() }
    return $problems
}

# ---------------- 命令 ----------------
switch ($Cmd.ToLower()) {
    'init' {
        Initialize-Handoff
        'handoff 已初始化：' + $HandoffDir
        '下一步：编辑 .handoff\notes.md 的「停点 / 待办 / 约束」，然后 handoff.ps1 pack'
    }
    'pack' {
        $dir = New-Pack
        'packed ' + $dir
        '恢复语：handoff.ps1 boot'
    }
    'boot' {
        $pack = Get-LatestPack
        if (-not $pack) { throw '还没有交接包，先运行 handoff.ps1 pack' }
        if ($Json) {
            $boot = Join-Path $pack 'BOOT.md'
            ConvertTo-Json -InputObject ([ordered]@{
                    pack = $pack
                    boot = [IO.File]::ReadAllText($boot, [Text.Encoding]::UTF8)
                }) -Depth 4
        } else {
            [IO.File]::ReadAllText((Join-Path $pack 'BOOT.md'), [Text.Encoding]::UTF8)
        }
    }
    'list' {
        if (-not (Test-Path -LiteralPath $PacksDir)) { '还没有任何交接包'; break }
        $packs = @(Get-ChildItem -LiteralPath $PacksDir -Directory | Sort-Object Name -Descending)
        if ($packs.Count -eq 0) { '还没有任何交接包'; break }
        foreach ($p in $packs) {
            $m = Join-Path $p.FullName 'manifest.json'
            $note = ''
            if (Test-Path -LiteralPath $m) {
                try { $note = [string]([IO.File]::ReadAllText($m, [Text.Encoding]::UTF8) | ConvertFrom-Json).note } catch { }
            }
            $size = [math]::Round((Get-ChildItem -LiteralPath $p.FullName -File | Measure-Object Length -Sum).Sum / 1KB, 1)
            '{0}  {1,6} KB  {2}' -f $p.Name, $size, $note
        }
    }
    'check' {
        $pack = Get-LatestPack
        if (-not $pack) { throw '还没有交接包，先运行 handoff.ps1 pack' }
        $problems = @(Invoke-Check $pack)
        if ($problems.Count -eq 0) { '[OK] ' + $pack; break }
        '[FAIL] ' + $pack
        $problems | ForEach-Object { '  - ' + $_ }
        exit 1
    }
    default {
        @'
用法：handoff.ps1 <命令> [-Root 项目目录] [-Note 备注]

  init                 初始化 .handoff\（笔记模板）
  pack [-Note 一句话]  采集事实 + 合入笔记，生成交接包
  boot [-Json]         打印最新包的恢复语（粘给下一个 agent）
  list                 列出所有交接包
  check                检查最新包是否完整、有无疑似密钥
'@
    }
}
