// Source-line anchors preserve semantic position across wrapping, tables and diagrams.
export function editorLines(area) {
  const css = getComputedStyle(area);
  const signature = [
    area.clientWidth,
    css.font,
    css.lineHeight,
    css.whiteSpace,
    css.padding,
  ].join("|");
  if (
    area._lineCache?.text === area.value &&
    area._lineCache.signature === signature
  )
    return area._lineCache.positions;
  const measure = document.createElement("div");
  Object.assign(measure.style, {
    position: "absolute",
    left: "-100000px",
    width: `${area.clientWidth}px`,
    font: css.font,
    lineHeight: css.lineHeight,
    letterSpacing: css.letterSpacing,
    padding: css.padding,
    boxSizing: css.boxSizing,
    whiteSpace: css.whiteSpace,
    overflowWrap: "break-word",
    tabSize: css.tabSize,
  });
  const positions = [];
  document.body.appendChild(measure);
  let top = parseFloat(css.paddingTop);
  // One layout pass rather than measuring each line separately.
  for (const line of area.value.split("\n")) {
    const node = document.createElement("div");
    node.textContent = line || "\u200b";
    measure.appendChild(node);
  }
  for (const node of measure.children) {
    positions.push(top);
    top += node.getBoundingClientRect().height;
  }
  positions.push(top);
  measure.remove();
  area._lineCache = { text: area.value, signature, positions };
  return positions;
}
const interpolate = (points, value, key, target) => {
  const next = points.findIndex((point) => point[key] > value);
  const before = points[Math.max(0, next < 0 ? points.length - 1 : next - 1)];
  const after = points[next < 0 ? points.length - 1 : next];
  if (!before) return 0;
  return (
    before[target] +
    ((value - before[key]) /
      Math.max(1, (after?.[key] ?? before[key]) - before[key])) *
      ((after?.[target] ?? before[target]) - before[target])
  );
};
export function syncSemanticScroll(source, target, name, mode = "smart") {
  if (mode === "off") return;
  const area = name === "editor" ? source : target;
  const preview = name === "editor" ? target : source;
  const positions = editorLines(area);
  const fraction = mode === "top" ? 0.08 : mode === "center" ? 0.5 : 0.35;
  const article = preview.querySelector(".prose");
  const anchors = [...(article?.children || [])]
    .filter((node) => node.dataset.sourceLine !== undefined)
    .map((node) => ({
      line: +node.dataset.sourceLine,
      top:
        node.getBoundingClientRect().top -
        preview.getBoundingClientRect().top +
        preview.scrollTop,
    }));
  anchors.push({ line: positions.length - 1, top: preview.scrollHeight });
  const editorPoints = positions.map((top, line) => ({ line, top }));
  if (source.scrollTop < 2) {
    target.scrollTop = 0;
    return;
  }
  if (source.scrollTop >= source.scrollHeight - source.clientHeight - 2) {
    target.scrollTop = target.scrollHeight;
    return;
  }
  const guide = source.scrollTop + source.clientHeight * fraction;
  const line = interpolate(
    name === "editor" ? editorPoints : anchors,
    guide,
    "top",
    "line",
  );
  target.scrollTop =
    interpolate(
      name === "editor" ? anchors : editorPoints,
      line,
      "line",
      "top",
    ) -
    target.clientHeight * fraction;
}
