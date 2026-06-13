import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkGfm from "remark-gfm"
import remarkRehype from "remark-rehype"
import rehypeStringify from "rehype-stringify"
import "github-markdown-css/github-markdown.css"
import "./style.css"

// Raw HTML in the document is passed through (allowDangerousHtml) rather than
// sanitized: this runs in an isolated WebKit view with no network egress
// (CSP connect-src 'none') and no JS↔native bridge, so embedded markup cannot
// exfiltrate or escalate. See PreviewViewController.swift for the boundary.
const processor = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkRehype, { allowDangerousHtml: true })
  .use(rehypeStringify, { allowDangerousHtml: true })

function showPlainText(content: Element, markdown: string): void {
  const pre = document.createElement("pre")
  pre.className = "plain-fallback"
  pre.textContent = markdown
  content.replaceChildren(pre)
}

// Render GFM, but fall back to the raw text (like the system's plain-text
// preview) on any failure, so a pathological document never shows blank.
function render(markdown: string): void {
  const content = document.getElementById("content")
  if (!content) return
  try {
    content.innerHTML = String(processor.processSync(markdown))
  } catch {
    showPlainText(content, markdown)
  }
}

declare global {
  interface Window {
    __markdown__?: string
    renderMarkdown?: (markdown: string) => void
  }
}

window.renderMarkdown = render

// The extension injects the document as window.__markdown__ via a document-start
// user script, so it is already present when this module runs after parsing.
if (typeof window.__markdown__ === "string") {
  render(window.__markdown__)
}
