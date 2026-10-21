# verify.ps1 —— 课件验收检查(契约 §10 + §11)
#
# 用法:  cd courseware;  powershell -ExecutionPolicy Bypass -File verify.ps1
#         powershell -ExecutionPolicy Bypass -File verify.ps1 -Lesson lesson-04.html
#
# 必须存为 UTF-8 带 BOM(与 build.ps1 同理,见契约 §8.3)。
#
# 一个反复踩到的坑:直接在全文件里数 <aside class="notes"> 会多出 1 ——
# deck.css 的注释里出现了这个选择器的字样。所以下面一律先剥掉 <style>。

[CmdletBinding()]
param(
    [string]$Lesson = ''
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$fail = 0
$total = 0

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:total++
    if (-not $Ok) { $script:fail++ }
    $tag = if ($Ok) { '[PASS]' } else { '[FAIL]' }
    Write-Host ('  {0} {1,-36} {2}' -f $tag, $Name, $Detail)
}

# CJK 记 1 字,ASCII 记 0.5 字 —— 契约 §11.1 的「每行 ≤ 11 个汉字」口径
function Get-EquivWidth {
    param([string]$Text)
    $t = [regex]::Replace($Text, '<[^>]+>', '')
    $w = 0.0
    foreach ($c in $t.ToCharArray()) {
        if ([int][char]$c -lt 128) { $w += 0.5 } else { $w += 1.0 }
    }
    return $w
}

$files = if ($Lesson) { @(Get-Item -LiteralPath $Lesson) }
         else { Get-ChildItem -Filter 'lesson-*.html' | Sort-Object Name }

foreach ($page in $files) {

    Write-Host ''
    Write-Host ('===== ' + $page.Name + ' (' + $page.Length + ' 字节) =====') -ForegroundColor Cyan

    $raw = [System.IO.File]::ReadAllText($page.FullName, [System.Text.Encoding]::UTF8)

    # 三层剥离,得到「真正的画面正文」
    $noCss = [regex]::Replace($raw, '(?s)<style.*?</style>', '')
    $noCss = [regex]::Replace($noCss, '(?s)<script.*?</script>', '')
    $body  = [regex]::Replace($noCss, '(?s)<aside class="notes">.*?</aside>', '')

    $sections = ([regex]::Matches($noCss, '<section class="slide')).Count
    $notes    = ([regex]::Matches($noCss, '<aside class="notes">')).Count

    Write-Host '  --- §10 结构 ---'
    Check '自包含:无 <link> / <script src>' `
        (([regex]::Matches($raw, '<link')).Count -eq 0 -and ([regex]::Matches($raw, '<script[^>]*\ssrc=')).Count -eq 0)
    Check '内联恰好 1 个 deck-css + 1 个 deck-js' `
        (([regex]::Matches($raw, '<style id="deck-css">')).Count -eq 1 -and ([regex]::Matches($raw, '<script id="deck-js">')).Count -eq 1)
    Check '</html> 恰好出现 1 次' `
        (([regex]::Matches($raw, '</html>')).Count -eq 1) '防止写入交错(§8.5)'
    Check 'section 数 = aside.notes 数' `
        ($sections -eq $notes) ("$sections 页 / $notes 段备注")
    Check '正文无「第 N 讲」' `
        (([regex]::Matches($body, '第\s*[一二三四五六七八九十\d]+\s*讲')).Count -eq 0)
    Check '无底部说明句「记住它:」' `
        (([regex]::Matches($body, '记住它')).Count -eq 0)
    Check '无「黑窗口」黑话' `
        (([regex]::Matches($body, '黑窗口')).Count -eq 0)
    Check '无重复 style 属性' `
        (([regex]::Matches($raw, 'style="[^"]*"\s+style="')).Count -eq 0) '踩过 3 次的坑'
    Check '备注在画面上彻底消失(.notes)' `
        ([regex]::Match($raw, '(?s)<style id="deck-css">(.*?)</style>').Groups[1].Value `
            -match '(?s)\.notes\s*\{\s*display:\s*none') '§8.4'
    Check '品牌图标数(内联 SVG)' `
        (([regex]::Matches($raw, '<svg class="logo"')).Count -gt 0) `
        ("" + ([regex]::Matches($raw, '<svg class="logo"')).Count + ' 个')
    Check '备注内不使用 emoji' `
        (-not ([regex]::IsMatch($raw, '[\uD83C-\uDBFF][\uDC00-\uDFFF]')))

    Write-Host '  --- §11 开场与标题(抖音向)---'

    $h1m = [regex]::Match($body, '(?s)<h1[^>]*>(.*?)</h1>')
    if (-not $h1m.Success) {
        Check '封面存在 <h1>' $false
    }
    else {
        $h1 = $h1m.Groups[1].Value
        $parts = [regex]::Split($h1, '<br\s*/?>')
        $l1 = $parts[0]; $l2 = if ($parts.Count -gt 1) { $parts[1] } else { '' }

        Check '封面 h1 恰好 2 行' `
            ($l2.Trim() -ne '') ("`"$($l1.Trim())`" / `"$($l2.Trim())`"")
        Check '每行 ≤ 11 等效字' `
            ((Get-EquivWidth $l1) -le 11 -and (Get-EquivWidth $l2) -le 11) `
            ('{0:N1} / {1:N1} 等效字' -f (Get-EquivWidth $l1), (Get-EquivWidth $l2))

        $banned = @('如何', '帮你', '怎么才能', '到底是什么关系') | Where-Object { $h1 -match $_ }
        Check '无禁止的绕弯句式' ($banned.Count -eq 0) `
            $(if ($banned.Count) { '命中: ' + ($banned -join ',') } else { '' })

        Check '标题含可核实数字' ([regex]::IsMatch($h1, '\d'))

        # 标题在画面正文里只能出现 1 次(封面),内页不复述
        $bare = [regex]::Replace($l1.Trim(), '<[^>]+>', '')
        Check '标题在正文只出现 1 次' `
            (([regex]::Matches($body, [regex]::Escape($bare))).Count -eq 1) '内页不复述标题'

        $eyebrow = [regex]::Match($body, '(?s)class="eyebrow"[^>]*>(.*?)<').Groups[1].Value.Trim()
        Check '封面药丸写时间成本' ($eyebrow -match '\d+\s*分钟') $eyebrow

        $subm = [regex]::Match($body, '(?s)class="sub"[^>]*>(.*?)</p>')
        if ($subm.Success) {
            $sub = $subm.Groups[1].Value.Trim()
            Check '封面副标题一行 ≤ 24 字' ((Get-EquivWidth $sub) -le 24) `
                ("`"$sub`" (" + (Get-EquivWidth $sub) + ' 字)')
        }

        # 前 10 秒:封面备注第一行必须是痛点或结论
        $cover = [regex]::Match($noCss, '(?s)<section class="slide cover.*?<aside class="notes">(.*?)</aside>')
        if ($cover.Success) {
            $cLines = ($cover.Groups[1].Value.Trim() -split "`r?`n") | Where-Object { $_.Trim() -ne '' }
            $first = if ($cLines.Count -gt 1) { $cLines[1] } else { $cLines[0] }
            Check '封面备注第一句直接上干货' `
                ($cLines.Count -gt 1 -and ($first -notmatch '^(大家好|各位|欢迎|今天我们来聊)')) `
                $first.Trim()
        }

        # 前 30 秒:承接页必须有兑现物条带
        Check '承接页有兑现物条带 .for-who' `
            (([regex]::Matches($body, 'class="for-who"')).Count -ge 1)
        Check '条带标签为「今天你能拿走」' ($body -match '今天你能拿走')
        Check '条带含预告结构 + 兑现物' `
            (($body -match '截图就能用') -and ($body -match '页'))
        Check '兑现物页备注写「建议暂停截图」' ($noCss -match '建议暂停截图')
        Check '顶栏是主题标签,不复述标题' `
            (([regex]::Match($noCss, 'chrome-lesson">([^<]*)<').Groups[1].Value) -notmatch [regex]::Escape($bare)) `
            ([regex]::Match($noCss, 'chrome-lesson">([^<]*)<').Groups[1].Value)
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host ("全部通过:{0} 项" -f $total) -ForegroundColor Green
} else {
    Write-Host ("{0} / {1} 项未通过" -f $fail, $total) -ForegroundColor Red
}
exit $fail