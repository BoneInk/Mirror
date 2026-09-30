const fs = require("node:fs");
const path = require("node:path");
const output = path.resolve(__dirname, "../public/katex");
fs.mkdirSync(output, { recursive: true });
fs.copyFileSync(
  require.resolve("katex/dist/katex.min.css"),
  path.join(output, "katex.min.css"),
);
fs.cpSync(
  path.join(path.dirname(require.resolve("katex/dist/katex.min.css")), "fonts"),
  path.join(output, "fonts"),
  { recursive: true },
);
