# build.ps1 — 把外部资源内联进所有课件,生成自包含单文件 HTML
#
# 为什么需要这一步:
#   lesson-XX.html 必须能"双击直接打开"就正常工作,不能依赖相对路径加载
#   assets/deck.css、assets/deck.js、assets/logos/*.svg —— 在某些预览器 /
#   沙箱 iframe 里相对路径会失效,结果是样式全丢、所有内容堆在一起。
#
# 用法:
#   在 courseware 目录下运行:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# 对每个 lesson-*.html 会替换三段内容:
#   · <style id="deck-css"> … </style>           ← assets/deck.css
#   · <script id="deck-js"> … </script>          ← assets/deck.js
#   · <!--LOGO:slug--> … <!--/LOGO-->            ← assets/logos/slug.svg
# 课件正文其余部分一律不动。可反复运行(幂等)。
#
# ⚠️ 本文件必须存为 UTF-8 **带 BOM**。
#    Windows PowerShell 5.1 对无 BOM 的 .ps1 会按系统本地代码页(中文 Windows
#    上是 GBK)解码,中文会被拆坏 —— 轻则输出乱码,重则语法错误、脚本不执行。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$cssPath = Join-Path $root 'assets\deck.css'
$jsPath  = Join-Path $root 'assets\deck.js'
$logoDir = Join-Path $root 'assets\logos'

foreach ($p in @($cssPath, $jsPath, $logoDir)) {
    if (-not (Test-Path $p)) { throw "缺少文件或目录:$p" }
}

$css = [System.IO.File]::ReadAllText($cssPath, [System.Text.Encoding]::UTF8)
$js  = [System.IO.File]::ReadAllText($jsPath,  [System.Text.Encoding]::UTF8)
$utf8 = New-Object System.Text.UTF8Encoding($false)   # 产物不写 BOM

$styleTag  = '<style id="deck-css">' + "`n" + $css + "`n" + '</style>'
$scriptTag = '<script id="deck-js">'  + "`n" + $js  + "`n" + '</script>'

$pages = @(Get-ChildItem -Path $root -Filter 'lesson-*.html' | Sort-Object Name)
if ($pages.Count -eq 0) { throw "在 $root 下没找到 lesson-*.html" }

foreach ($page in $pages) {
    $html = [System.IO.File]::ReadAllText($page.FullName, [System.Text.Encoding]::UTF8)

    # --- 1. 内联 CSS -------------------------------------------------------
    if ($html -match '<style id="deck-css">') {
        $html = [regex]::Replace($html, '(?s)<style id="deck-css">.*?</style>',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $styleTag })
        $cssState = 'updated'
    }
    elseif ($html -match '<link[^>]*deck\.css[^>]*>') {
        $html = [regex]::Replace($html, '<link[^>]*deck\.css[^>]*>',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $styleTag })
        $cssState = 'inlined'
    }
    else {
        Write-Warning "$($page.Name): 找不到 <style id=`"deck-css`"> 或 deck.css 的 <link>,跳过 CSS"
        $cssState = 'skipped'
    }

    # --- 2. 内联 JS --------------------------------------------------------
    if ($html -match '<script id="deck-js">') {
        $html = [regex]::Replace($html, '(?s)<script id="deck-js">.*?</script>',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $scriptTag })
        $jsState = 'updated'
    }
    elseif ($html -match '<script[^>]*deck\.js[^>]*>\s*</script>') {
        $html = [regex]::Replace($html, '<script[^>]*deck\.js[^>]*>\s*</script>',
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $scriptTag })
        $jsState = 'inlined'
    }
    else {
        Write-Warning "$($page.Name): 找不到 <script id=`"deck-js`"> 或 deck.js 的 <script src>,跳过 JS"
        $jsState = 'skipped'
    }

    # --- 3. 内联品牌图标 ---------------------------------------------------
    $logoCount = 0
    $missing   = New-Object System.Collections.Generic.List[string]

    $html = [regex]::Replace(
        $html,
        '(?s)<!--LOGO:([a-z0-9]+)-->(.*?)<!--/LOGO-->',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $slug = $m.Groups[1].Value
            $f = Join-Path $logoDir "$slug.svg"
            if (-not (Test-Path $f)) { $missing.Add($slug); return $m.Value }
            $svg = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
            $svg = $svg -replace '(?s)<title>.*?</title>', ''
            $svg = $svg -replace '<svg\s', '<svg class="logo" aria-hidden="true" '
            $script:logoCount++
            '<!--LOGO:' + $slug + '-->' + $svg.Trim() + '<!--/LOGO-->'
        })

    if ($missing.Count -gt 0) {
        throw "$($page.Name): 缺少图标文件:$(($missing | Sort-Object -Unique) -join ', ')"
    }

    # 原子写(契约 §8.5 / §10):先写同目录临时文件,再 rename 覆盖。
    # 直接 WriteAllText 是「截断 + 写入」两步 —— 同一时刻有别的进程读到一半,
    # 就会拿到残缺文件(症状:`</html>` 出现 0 次或 2 次)。与 build.sh 的
    # 临时文件 + os.replace 保持同一套语义。
    $tmp = $page.FullName + '.buildtmp'
    [System.IO.File]::WriteAllText($tmp, $html, $utf8)
    Move-Item -LiteralPath $tmp -Destination $page.FullName -Force
    Write-Host ("{0,-18} CSS={1,-8} JS={2,-8} LOGO={3,2}  {4} 字节" -f `
        $page.Name, $cssState, $jsState, $logoCount, (Get-Item $page.FullName).Length)
}