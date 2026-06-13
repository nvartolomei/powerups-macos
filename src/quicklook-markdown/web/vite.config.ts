import { defineConfig } from "vite"
import { viteSingleFile } from "vite-plugin-singlefile"

// Inlines all JS and CSS into one self-contained preview.html. The Quick Look
// extension bundles exactly this one file and loads it offline; the document is
// injected at runtime via window.renderMarkdown, never concatenated into HTML.
export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    rollupOptions: {
      input: "preview.html",
    },
  },
})
