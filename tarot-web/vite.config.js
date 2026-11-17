import { defineConfig } from 'vite'

// base: './' —— 全部资源使用相对路径，保证 dist/index.html 可通过 file:// 协议直接加载
export default defineConfig({
  base: './',
  build: {
    assetsInlineLimit: 0,
    chunkSizeWarningLimit: 1500
  }
})
