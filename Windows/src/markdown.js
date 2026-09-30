import { marked } from "marked";
import createDOMPurify from "dompurify";
import katex from "katex";
import hljs from "highlight.js/lib/common";
import mermaid from "mermaid";
import "katex/dist/katex.min.css";
import "highlight.js/styles/github.css";
let chartID = 0;
// Separate instances keep Mermaid's sanitizer hooks/configuration isolated.
const DOMPurify = createDOMPurify(window);
const renderer = new marked.Renderer();
renderer.code = ({ text, lang }) => {
  // Encoding preserves Mermaid's arrows through DOMPurify's XML safety check.
  if (lang === "mermaid")
    return `<div class="mermaid" data-source="${escape(encodeURIComponent(text))}"></div>`;
  const language = (lang || "").split(" ")[0];
  const code = hljs.getLanguage(language)
    ? hljs.highlight(text, { language }).value
    : escape(text);
  return `<pre><code class="hljs">${code}</code></pre>`;
};
function escape(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
marked.use({
  renderer,
  gfm: true,
  extensions: [
    {
      name: "blockMath",
      level: "block",
      start: (src) => src.indexOf("$$"),
      tokenizer(src) {
        const match = /^\$\$\s*\n?([\s\S]+?)\n?\$\$(?:\n|$)/.exec(src);
        if (match) return { type: "blockMath", raw: match[0], text: match[1] };
      },
      renderer: (token) =>
        katex.renderToString(token.text, {
          displayMode: true,
          throwOnError: false,
          trust: false,
        }),
    },
    {
      name: "inlineMath",
      level: "inline",
      start: (src) => src.indexOf("$"),
      tokenizer(src) {
        const match = /^\$([^$\n]+?)\$/.exec(src);
        if (match) return { type: "inlineMath", raw: match[0], text: match[1] };
      },
      renderer: (token) =>
        katex.renderToString(token.text, { throwOnError: false, trust: false }),
    },
  ],
});
export function renderMarkdown(text, documentPath) {
  const clean = DOMPurify.sanitize(marked.parse(text), {
    ADD_TAGS: ["math", "annotation"],
    ADD_ATTR: ["data-source"],
    FORBID_TAGS: ["style", "form", "iframe", "object", "embed"],
    FORBID_ATTR: ["srcset"],
  });
  const template = document.createElement("template");
  template.innerHTML = clean;
  template.content.querySelectorAll("img").forEach((img) => {
    let src = img.getAttribute("src");
    try { src = decodeURI(src || ""); } catch { /* A literal % is valid in a local filename. */ }
    if (src?.startsWith("data:image/")) return;
    if (src && documentPath && !/^(?:[a-z]+:|\/|\\)/i.test(src))
      img.setAttribute(
        "src",
        `mirror-asset://local/image?doc=${encodeURIComponent(documentPath)}&src=${encodeURIComponent(src)}`,
      );
    else {
      img.removeAttribute("src");
      img.setAttribute("alt", img.alt || "请保存文档并使用相对路径图片");
    }
  });
  return template.innerHTML;
}
export async function renderDiagrams(container, dark) {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: dark ? "dark" : "neutral",
    fontFamily: "Segoe UI, Microsoft YaHei UI, sans-serif",
    suppressErrorRendering: true,
  });
  for (const node of container.querySelectorAll(".mermaid[data-source]")) {
    let source = node.getAttribute("data-source");
    try {
      source = decodeURIComponent(source);
      const { svg } = await mermaid.render(`mirror-chart-${++chartID}`, source);
      if (node.isConnected) {
        node.innerHTML = DOMPurify.sanitize(svg, {
          USE_PROFILES: { html: true, svg: true, svgFilters: true },
          ADD_TAGS: ["foreignObject"],
          ADD_ATTR: ["xmlns", "style"],
        });
        node.removeAttribute("data-source");
      }
    } catch {
      if (node.isConnected) {
        node.textContent = `图表语法错误\n${source}`;
        node.classList.add("diagram-error");
      }
    }
  }
}
export function headings(text) {
  let fence = false;
  const result = [];
  text.split("\n").forEach((line, i) => {
    if (/^\s*(```|~~~)/.test(line)) fence = !fence;
    if (!fence) {
      const match = /^(#{1,6})\s+(.+)$/.exec(line);
      if (match)
        result.push({
          level: match[1].length,
          text: match[2].replace(/\s+#+$/, ""),
          line: i,
        });
    }
  });
  return result;
}
