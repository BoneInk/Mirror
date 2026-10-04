// Textareas do not expose DOM Ranges. Mirror their actual layout to locate the
// selection's focus end, including wrapped lines, tabs and horizontal scroll.
export function textareaSelectionAnchor(area) {
  const offset =
    area.selectionDirection === "backward"
      ? area.selectionStart
      : area.selectionEnd;
  return {
    element: area,
    getRect() {
      if (!area.isConnected) return null;
      const css = getComputedStyle(area);
      const mirror = document.createElement("div");
      const properties = [
        "fontFamily",
        "fontSize",
        "fontWeight",
        "fontStyle",
        "lineHeight",
        "letterSpacing",
        "wordSpacing",
        "textIndent",
        "textAlign",
        "textTransform",
        "tabSize",
        "whiteSpace",
        "wordBreak",
        "overflowWrap",
        "paddingTop",
        "paddingRight",
        "paddingBottom",
        "paddingLeft",
        "direction",
      ];
      for (const property of properties) mirror.style[property] = css[property];
      Object.assign(mirror.style, {
        position: "fixed",
        left: "0",
        top: "0",
        width: `${area.clientWidth}px`,
        boxSizing: "border-box",
        visibility: "hidden",
        pointerEvents: "none",
      });
      mirror.setAttribute("aria-hidden", "true");
      mirror.append(document.createTextNode(area.value.slice(0, offset)));
      const tail = document.createElement("span");
      tail.textContent = area.value.slice(offset) || "\u200b";
      mirror.append(tail);
      document.body.append(mirror);
      try {
        const caret = document.createRange();
        caret.setStart(tail.firstChild, 0);
        caret.collapse(true);
        const rect = caret.getBoundingClientRect();
        const areaRect = area.getBoundingClientRect();
        const left =
          areaRect.left + area.clientLeft + rect.left - area.scrollLeft;
        const top = areaRect.top + area.clientTop + rect.top - area.scrollTop;
        const height =
          rect.height || parseFloat(css.lineHeight) || parseFloat(css.fontSize);
        return {
          left,
          right: left + 1,
          top,
          bottom: top + height,
          width: 1,
          height,
        };
      } finally {
        mirror.remove();
      }
    },
  };
}

export function previewSelectionAnchor(selection, viewport) {
  if (
    !selection?.rangeCount ||
    !viewport?.contains(selection.anchorNode) ||
    !viewport.contains(selection.focusNode)
  )
    return null;
  const range = selection.getRangeAt(0).cloneRange();
  const backwards =
    selection.focusNode === range.startContainer &&
    selection.focusOffset === range.startOffset;
  const caret = document.createRange();
  caret.setStart(selection.focusNode, selection.focusOffset);
  caret.collapse(true);
  return {
    element: viewport,
    getRect() {
      if (!caret.startContainer.isConnected) return null;
      const rect = caret.getBoundingClientRect();
      if (rect.height > 0) return rect;
      const rects = [...range.getClientRects()].filter((r) => r.height > 0);
      const edge = backwards ? rects[0] : rects.at(-1);
      if (!edge) return null;
      const left = backwards ? edge.left : edge.right;
      return {
        left,
        right: left + 1,
        top: edge.top,
        bottom: edge.bottom,
        width: 1,
        height: edge.height,
      };
    },
  };
}
