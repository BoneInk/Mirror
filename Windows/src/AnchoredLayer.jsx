import React, { useLayoutEffect, useRef, useState } from "react";
import { placePopover } from "./popover-position.mjs";

export function AnchoredLayer({
  anchor,
  boundaryRef,
  hideOffscreen = false,
  className,
  children,
  maxHeight = Infinity,
  as: Element = "div",
  ...props
}) {
  const ref = useRef();
  const [position, setPosition] = useState(null);
  useLayoutEffect(() => {
    let frame;
    const update = () => {
      const boundary = boundaryRef.current?.getBoundingClientRect();
      if (!boundary) return;
      const bounds = {
        left: Math.max(0, boundary.left),
        top: Math.max(0, boundary.top),
        right: Math.min(innerWidth, boundary.right),
        bottom: Math.min(innerHeight, boundary.bottom),
      };
      let rect = anchor?.getRect();
      if (!rect && hideOffscreen) {
        setPosition(null);
        return;
      }
      if (!rect)
        rect = {
          left: (bounds.left + bounds.right) / 2,
          right: (bounds.left + bounds.right) / 2,
          top: (bounds.top + bounds.bottom) / 2,
          bottom: (bounds.top + bounds.bottom) / 2,
        };
      const clip = anchor?.element?.getBoundingClientRect() || bounds;
      const visible =
        rect.bottom >= Math.max(bounds.top, clip.top) &&
        rect.top <= Math.min(bounds.bottom, clip.bottom) &&
        rect.right >= Math.max(bounds.left, clip.left) &&
        rect.left <= Math.min(bounds.right, clip.right);
      if (!visible && hideOffscreen) {
        setPosition(null);
        return;
      }
      const size = ref.current.getBoundingClientRect();
      const next = placePopover(rect, size, bounds, anchor?.preferred);
      setPosition((previous) =>
        previous &&
        Object.keys(next).every((key) => next[key] === previous[key])
          ? previous
          : next,
      );
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(update);
    };
    update();
    const observer = new ResizeObserver(schedule);
    observer.observe(ref.current);
    if (boundaryRef.current) observer.observe(boundaryRef.current);
    if (anchor?.element?.isConnected) observer.observe(anchor.element);
    window.addEventListener("resize", schedule);
    window.addEventListener("scroll", schedule, true);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", schedule);
      window.removeEventListener("scroll", schedule, true);
    };
  }, [anchor, boundaryRef, hideOffscreen]);
  return (
    <Element
      {...props}
      ref={ref}
      className={`${className} anchored-layer`}
      data-placement={position?.side}
      style={{
        left: position?.left || 0,
        top: position?.top || 0,
        maxWidth: position?.maxWidth,
        maxHeight: position
          ? Math.min(position.maxHeight, maxHeight)
          : Number.isFinite(maxHeight)
            ? maxHeight
            : undefined,
        visibility: position ? "visible" : "hidden",
      }}
    >
      {children}
    </Element>
  );
}
