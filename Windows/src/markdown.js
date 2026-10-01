import { marked } from "marked";
import createDOMPurify from "dompurify";
import katex from "katex";
import hljs from "highlight.js/lib/common";
import mermaid from "mermaid";
import { installDiagram } from "./diagrams";
import "katex/dist/katex.min.css";
import "highlight.js/styles/github.css";
let chartID = 0;
let footnotes = new Map();
// Separate instances keep Mermaid's sanitizer hooks/configuration isolated.
const DOMPurify = createDOMPurify(window);
const renderer = new marked.Renderer();
renderer.code = ({ text, lang }) => {
  // Encoding preserves Mermaid's arrows through DOMPurify's XML safety check.
  if (lang === "mermaid")
    return `<div class="diagram-block"><div class="code-header">Mermaid</div><div class="diagram-canvas mermaid" data-source="${escape(encodeURIComponent(text))}"></div></div>`;
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
      name: "frontmatter",
      level: "block",
      tokenizer(src) {
        const match = /^---\r?\n((?:[\s\S]*?))\r?\n---(?:\r?\n|$)/.exec(src);
        if (match && /^\s*[\w-]+\s*:/m.test(match[1]))
          return { type: "frontmatter", raw: match[0], text: match[1] };
      },
      renderer: (token) =>
        `<details class="frontmatter"><summary>文档元数据</summary><pre>${escape(token.text)}</pre></details>`,
    },
    {
      name: "footnoteDefinition",
      level: "block",
      tokenizer(src) {
        const match = /^\[\^([^\]\n]+)\]:\s*(.+)(?:\r?\n|$)/.exec(src);
        if (match) return { type: "footnoteDefinition", raw: match[0] };
      },
      renderer: () => "",
    },
    {
      name: "footnoteReference",
      level: "inline",
      start: (src) => src.indexOf("[^"),
      tokenizer(src) {
        const match = /^\[\^([^\]\n]+)\]/.exec(src);
        if (match && footnotes.has(match[1]))
          return { type: "footnoteReference", raw: match[0], text: match[1] };
      },
      renderer: (token) =>
        `<sup><a href="#footnote-${escape(encodeURIComponent(token.text))}">[${escape(token.text)}]</a></sup>`,
    },
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
  footnotes = new Map(
    [...text.matchAll(/^\[\^([^\]\n]+)\]:\s*(.+)$/gm)].map((match) => [
      match[1],
      match[2],
    ]),
  );
  const tokens = marked.lexer(text);
  let line = 0;
  const output = tokens
    .map((token) => {
      const start = line;
      line += (token.raw.match(/\n/g) || []).length;
      const single = [token];
      single.links = tokens.links;
      const fragment = document.createElement("template");
      fragment.innerHTML = marked.parser(single);
      for (const node of fragment.content.children) {
        node.dataset.sourceLine = start;
        node.dataset.sourceEnd = Math.max(start + 1, line);
        if (/^H[1-6]$/.test(node.tagName))
          node.id = node.textContent
            .trim()
            .toLowerCase()
            .replace(/[^\p{L}\p{N}\s-]/gu, "")
            .replace(/\s+/g, "-");
      }
      return fragment.innerHTML;
    })
    .join("");
  const notes = footnotes.size
    ? `<section class="footnotes"><hr><ol>${[...footnotes].map(([id, value]) => `<li id="footnote-${escape(encodeURIComponent(id))}">${marked.parseInline(value)}</li>`).join("")}</ol></section>`
    : "";
  const clean = DOMPurify.sanitize(output + notes, {
    ADD_TAGS: ["math", "annotation"],
    ADD_ATTR: ["data-source", "data-source-line", "data-source-end"],
    FORBID_TAGS: ["style", "form", "iframe", "object", "embed"],
    FORBID_ATTR: ["srcset"],
  });
  const template = document.createElement("template");
  template.innerHTML = clean;
  template.content.querySelectorAll("blockquote").forEach((block) => {
    const paragraph = block.querySelector("p");
    const match = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/.exec(
      paragraph?.textContent || "",
    );
    if (!match) return;
    block.classList.add("markdown-alert");
    const first = paragraph.firstChild;
    if (first?.nodeType === Node.TEXT_NODE)
      first.textContent = first.textContent.replace(match[0], match[1] + " · ");
  });
  template.content.querySelectorAll("img").forEach((img) => {
    let src = img.getAttribute("src");
    try {
      src = decodeURI(src || "");
    } catch {
      /* A literal % is valid in a local filename. */
    }
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
let diagramQueue = Promise.resolve();
export function renderDiagrams(container, dark, interactive = false) {
  const result = diagramQueue
    .catch(() => {})
    .then(() => renderDiagramBatch(container, dark, interactive));
  diagramQueue = result;
  return result;
}
async function renderDiagramBatch(container, dark, interactive) {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    htmlLabels: false,
    flowchart: { htmlLabels: false },
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
        if (interactive) installDiagram(node);
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
