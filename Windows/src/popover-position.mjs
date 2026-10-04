export function placePopover(anchor, size, bounds, preferred = "bottom") {
  const gap = 8;
  const inset = 8;
  const width = Math.min(
    size.width,
    Math.max(1, bounds.right - bounds.left - inset * 2),
  );
  const height = Math.min(
    size.height,
    Math.max(1, bounds.bottom - bounds.top - inset * 2),
  );
  const clamp = (value, min, max) => Math.max(min, Math.min(value, max));
  let left = anchor.left - 12;
  let top = anchor.bottom + gap;
  let side = "bottom";
  if (
    preferred === "right" &&
    anchor.right + gap + width <= bounds.right - inset
  ) {
    left = anchor.right + gap;
    top = (anchor.top + anchor.bottom - height) / 2;
    side = "right";
  } else if (top + height > bounds.bottom - inset) {
    if (
      anchor.top - gap - height >= bounds.top + inset ||
      anchor.top - bounds.top > bounds.bottom - anchor.bottom
    ) {
      top = anchor.top - gap - height;
      side = "top";
    }
  }
  return {
    left: clamp(left, bounds.left + inset, bounds.right - width - inset),
    top: clamp(top, bounds.top + inset, bounds.bottom - height - inset),
    maxWidth: bounds.right - bounds.left - inset * 2,
    maxHeight: bounds.bottom - bounds.top - inset * 2,
    side,
  };
}
