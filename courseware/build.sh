#!/usr/bin/env bash
# ==========================================================================
# build.sh — build.ps1 的 macOS / Linux 等价物
#
# 为什么有它:build.ps1 是给 Windows PowerShell 写的,而这套课件是在 Mac 上
# 维护的。两者做的是**同一件事、同一套替换规则**,产物应当完全一致。
# 改 CSS / JS / 图标之后,在 courseware 目录下跑:
#
#     bash build.sh
#
# 对每个 lesson-*.html 替换三段内容:
#   · <style id="deck-css"> … </style>        ← assets/deck.css
#   · <script id="deck-js"> … </script>       ← assets/deck.js
#   · <!--LOGO:slug--> … <!--/LOGO-->         ← assets/logos/slug.svg
# 课件正文其余部分一律不动。可反复运行(幂等)。
#
# ⚠️ 两个脚本必须保持一致。只改一个,另一平台上的产物就会不同步。
# ==========================================================================
set -euo pipefail
cd "$(dirname "$0")"

exec python3 - "$@" << 'PY'
import io, os, re, sys

root = os.getcwd()
css_path = os.path.join(root, 'assets', 'deck.css')
js_path  = os.path.join(root, 'assets', 'deck.js')
logo_dir = os.path.join(root, 'assets', 'logos')

for p in (css_path, js_path, logo_dir):
    if not os.path.exists(p):
        sys.exit('缺少文件或目录:%s' % p)

css = io.open(css_path, encoding='utf-8').read()
js  = io.open(js_path,  encoding='utf-8').read()

style_tag  = '<style id="deck-css">\n' + css + '\n</style>'
script_tag = '<script id="deck-js">\n'  + js  + '\n</script>'

pages = sorted(f for f in os.listdir(root)
               if f.startswith('lesson-') and f.endswith('.html'))
if not pages:
    sys.exit('在 %s 下没找到 lesson-*.html' % root)

RE_CSS  = re.compile(r'(?s)<style id="deck-css">.*?</style>')
RE_LINK = re.compile(r'<link[^>]*deck\.css[^>]*>')
RE_JS   = re.compile(r'(?s)<script id="deck-js">.*?</script>')
RE_JSSRC= re.compile(r'<script[^>]*deck\.js[^>]*>\s*</script>')
RE_LOGO = re.compile(r'(?s)<!--LOGO:([a-z0-9]+)-->(.*?)<!--/LOGO-->')

def logo_sub(m):
    slug = m.group(1)
    f = os.path.join(logo_dir, slug + '.svg')
    if not os.path.exists(f):
        raise SystemExit('缺少图标文件:%s.svg' % slug)
    svg = io.open(f, encoding='utf-8').read()
    svg = re.sub(r'(?s)<title>.*?</title>', '', svg)
    svg = re.sub(r'<svg\s', '<svg class="logo" aria-hidden="true" ', svg, count=1)
    logo_sub.count += 1
    return '<!--LOGO:%s-->%s<!--/LOGO-->' % (slug, svg.strip())
logo_sub.count = 0

for name in pages:
    path = os.path.join(root, name)
    html = io.open(path, encoding='utf-8').read()

    if RE_CSS.search(html):
        html, n = RE_CSS.subn(lambda m: style_tag, html); css_state = 'updated'
    elif RE_LINK.search(html):
        html, n = RE_LINK.subn(lambda m: style_tag, html); css_state = 'inlined'
    else:
        css_state = 'skipped'

    if RE_JS.search(html):
        html, n = RE_JS.subn(lambda m: script_tag, html); js_state = 'updated'
    elif RE_JSSRC.search(html):
        html, n = RE_JSSRC.subn(lambda m: script_tag, html); js_state = 'inlined'
    else:
        js_state = 'skipped'

    logo_sub.count = 0
    html = RE_LOGO.sub(logo_sub, html)

    # ⚠️ 必须原子写:先写同目录下的临时文件,再 rename 覆盖。
    #    直接 WriteAllText 是「截断 + 写入」两步,如果同一时刻有别的进程
    #    (编辑器、另一个 agent、同步工具)也在写这个文件,两边的写入会交错,
    #    结果是文件尾部出现重复的 </html> 碎片 —— 2026-10-20 真的发生过一次,
    #    lesson-03.html 被写坏。rename 在同一文件系统上是原子的,不会交错。
    tmp = path + '.buildtmp'
    io.open(tmp, 'w', encoding='utf-8', newline='').write(html)
    os.replace(tmp, path)
    print('%-18s CSS=%-8s JS=%-8s LOGO=%2d  %d 字节'
          % (name, css_state, js_state, logo_sub.count, os.path.getsize(path)))
PY
