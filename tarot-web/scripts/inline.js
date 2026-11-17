// 构建后处理：把 Vite 产出的 JS/CSS 内联进 dist/index.html，转为经典脚本并剥掉 crossorigin。
// 原因：WKWebView 经 loadFileURL 加载 file:// 页面时，<script type="module" crossorigin>
// 与 <link crossorigin> 会以 CORS 模式拉取子资源，而 file:// 没有 origin，请求被 WebKit
// 拦截 → 页面全黑。单文件内联 + 经典脚本（bundle 无 import/export，可安全降级）后
// 不再发起任何会被拦截的请求，file:// 下稳定可用。
import fs from 'node:fs'
import path from 'node:path'

const dist = path.resolve('dist')
const htmlPath = path.join(dist, 'index.html')
let html = fs.readFileSync(htmlPath, 'utf8')

const before = html.length

// 1) 内联脚本并降级为经典脚本（bundle 为单 chunk、无 import/export/import.meta，
//    经典脚本在所有 WebKit 版本的 file:// 下都必然执行），转义 </script> 防止提前闭合
html = html.replace(
  /<script type="module"[^>]*src="\.\/(assets\/[^"]+\.js)"[^>]*><\/script>/g,
  (match, src) => {
    const code = fs.readFileSync(path.join(dist, src), 'utf8')
    const safe = code.replace(/<\/script>/gi, '<\\/script>')
    return `<script>\n${safe}\n</script>`
  }
)

// 2) 内联样式表
html = html.replace(
  /<link rel="stylesheet"[^>]*href="\.\/(assets\/[^"]+\.css)"[^>]*>/g,
  (match, href) => {
    const css = fs.readFileSync(path.join(dist, href), 'utf8')
    return `<style>\n${css}\n</style>`
  }
)

// 3) 兜底：移除一切 crossorigin 属性（file:// 下的 CORS 触发器）
html = html.replace(/ crossorigin(="[^"]*")?/g, '')

// 4) 删除已内联的 assets 残留（仅图片目录 cards/ tarot/ 保留）
const assetsDir = path.join(dist, 'assets')
if (fs.existsSync(assetsDir)) fs.rmSync(assetsDir, { recursive: true, force: true })

fs.writeFileSync(htmlPath, html)

const hasExternal = /<(script|link)[^>]*src="\.\/assets|<(script|link)[^>]*href="\.\/assets/.test(html)
const hasCrossorigin = /crossorigin/.test(html)
console.log(`inlined: ${htmlPath}`)
console.log(`size: ${before} -> ${html.length} bytes`)
console.log(`remaining external asset refs: ${hasExternal ? 'YES (bad)' : 'none'}`)
console.log(`remaining crossorigin attrs: ${hasCrossorigin ? 'YES (bad)' : 'none'}`)
if (hasExternal || hasCrossorigin) process.exit(1)
