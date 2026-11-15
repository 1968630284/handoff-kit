# handoff-kit · 特征测试（Pester 3.4+）
# 运行：Invoke-Pester .\tests\Handoff.Tests.ps1

$Script = Join-Path (Split-Path -Parent $PSScriptRoot) 'handoff.ps1'
$Root = Join-Path $env:TEMP ('handoff_test_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Handoff = Join-Path $Root '.handoff'
$Utf8 = New-Object Text.UTF8Encoding($false)

New-Item -ItemType Directory -Path $Root -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $Root 'app.ps1'), 'Write-Host hi' + "`n", $Utf8)
[IO.File]::WriteAllText((Join-Path $Root 'README.md'), '# demo' + "`n", $Utf8)

& $Script init -Root $Root | Out-Null
[IO.File]::WriteAllText((Join-Path $Handoff 'notes.md'), @'
# 交接笔记

## 停点
改到 40_app.ps1 的状态机，下一步跑回归。

## 已完成
- 核心层状态化

## 待办
- [ ] 第二层拆分

## 约束 / 不要动
- 不要改总线协议
'@, $Utf8)
& $Script pack -Root $Root -Note '第一次交接' | Out-Null

$Packs = @(Get-ChildItem -LiteralPath (Join-Path $Handoff 'packs') -Directory | Sort-Object Name -Descending)
$LatestPack = $Packs[0].FullName

Describe 'handoff-kit' {

    It 'init 生成 .handoff 与笔记模板' {
        (Test-Path -LiteralPath $Handoff) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $Handoff 'packs')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $Handoff 'notes.md')) | Should Be $true
    }

    It 'pack 产出五件套' {
        foreach ($f in @('BOOT.md', 'HANDOFF.md', 'facts.json', 'manifest.json', 'notes.md')) {
            (Test-Path -LiteralPath (Join-Path $LatestPack $f)) | Should Be $true
        }
    }

    It 'manifest 的 id 与目录名一致，且记录备注' {
        $m = [IO.File]::ReadAllText((Join-Path $LatestPack 'manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        $m.id | Should Be (Split-Path -Leaf $LatestPack)
        $m.note | Should Be '第一次交接'
        # manifest 不把自己算进 files（写它的时候还没生成）
        @($m.files).Count | Should Be 4
    }

    It 'HANDOFF.md 含项目名、停点与约束' {
        $t = [IO.File]::ReadAllText((Join-Path $LatestPack 'HANDOFF.md'), [Text.Encoding]::UTF8)
        $t.Contains('handoff_test_') | Should Be $true
        $t.Contains('改到 40_app.ps1 的状态机') | Should Be $true
        $t.Contains('不要改总线协议') | Should Be $true
    }

    It 'boot 打印恢复语与停点' {
        $out = (& $Script boot -Root $Root) -join "`n"
        $out.Contains('恢复语') | Should Be $true
        $out.Contains('上次停点') | Should Be $true
        $out.Contains('改到 40_app.ps1 的状态机') | Should Be $true
    }

    It 'list 列出交接包' {
        $out = (& $Script list -Root $Root) -join "`n"
        $out.Contains((Split-Path -Leaf $LatestPack)) | Should Be $true
        $out.Contains('第一次交接') | Should Be $true
    }

    It 'check 对完整包返回 OK' {
        $out = (& $Script check -Root $Root) -join "`n"
        $out.Contains('[OK]') | Should Be $true
    }

    It '再次 pack 后 latest 指向新包' {
        Start-Sleep -Milliseconds 1100
        & $Script pack -Root $Root -Note '第二次交接' | Out-Null
        $latest = ([IO.File]::ReadAllText((Join-Path $Handoff 'latest.txt'), [Text.Encoding]::UTF8)).Trim()
        $latest.Contains('第二次交接') | Should Be $false
        (Split-Path -Leaf $latest) | Should Be (Get-ChildItem -LiteralPath (Join-Path $Handoff 'packs') -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name)
    }

    It '笔记里出现疑似密钥时 check 失败（退出码 1）' {
        [IO.File]::AppendAllText((Join-Path $Handoff 'notes.md'), "`nsk-ABCDEFGHIJKLMNOPQRSTUVWXYZ012345`n", $Utf8)
        & $Script pack -Root $Root -Note '含密钥' | Out-Null
        # 直接在当前进程调 check 会用 exit 把测试宿主带走，只能在子进程里看退出码
        if ($env:OS -eq 'Windows_NT') {
            $exe = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' }
            & $exe -NoProfile -ExecutionPolicy Bypass -File $Script check -Root $Root 2>$null | Out-Null
            $LASTEXITCODE | Should Be 1
        }
    }
}

Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
# 子进程那条用例会把 LASTEXITCODE 留成 1，重置以免污染调用方的退出码
$global:LASTEXITCODE = 0
