// Shared interaction behavior from macOS MarkdownDiagramInteraction. Preview only.

(() => {
  const style = document.createElement("style");
  style.textContent = `
        .diagram-tools{display:flex;align-items:center;gap:4px;margin-left:auto;text-transform:none;letter-spacing:normal}
        .diagram-tools button{width:25px;height:24px;border:1px solid var(--line);border-radius:5px;background:var(--bg);color:var(--fg);font:16px/1 system-ui;cursor:pointer;padding:0}
        .diagram-tools button:hover{background:var(--code)}
        .diagram-tools button:disabled{opacity:.35;cursor:default}
        .diagram-tools button:focus-visible,.diagram-interactive:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
        .diagram-zoom{min-width:42px;text-align:center;font:11px/1 system-ui;color:var(--muted);font-variant-numeric:tabular-nums}
        .diagram-canvas.diagram-interactive{position:relative;padding:0;overflow:hidden;cursor:grab;touch-action:none;user-select:none;-webkit-user-select:none}
        .diagram-interactive.dragging{cursor:grabbing}
        .diagram-frame{position:relative;max-width:100%}
        .diagram-frame.resizing{user-select:none;-webkit-user-select:none}
        .diagram-resize{position:absolute;z-index:3;padding:0;border:0;background:transparent;touch-action:none}
        .diagram-resize-right{right:0;top:32px;bottom:14px;width:8px;cursor:ew-resize}
        .diagram-resize-bottom{left:0;right:14px;bottom:0;height:8px;cursor:ns-resize}
        .diagram-resize-corner{right:0;bottom:0;width:14px;height:14px;cursor:nwse-resize;background:repeating-linear-gradient(135deg,transparent 0 3px,var(--muted) 3px 4px,transparent 4px 6px);clip-path:polygon(100% 0,100% 100%,0 100%);opacity:.5}
        .diagram-resize-right:hover,.diagram-resize-bottom:hover{background:color-mix(in srgb,var(--accent) 25%,transparent)}
        .diagram-resize:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
        .diagram-content{position:absolute;left:0;top:0;transform-origin:0 0}
        .diagram-canvas .diagram-content>svg{display:block;width:100%;height:100%;max-width:none!important;margin:0}
        @media print{
          .diagram-tools,.diagram-resize{display:none!important}
          .diagram-frame{width:auto!important;max-width:none!important}
          .diagram-canvas.diagram-interactive{height:auto!important;padding:1.25em;overflow:visible;cursor:auto}
          .diagram-content{position:static;width:auto!important;height:auto!important;transform:none!important}
          .diagram-canvas .diagram-content>svg{width:100%;height:auto;max-width:100%!important;margin:auto}
        }
      `;
  document.head.appendChild(style);
  const controllers = new Map();
  window.mirrorDisposeDiagrams = (root) => {
    for (const [node, controller] of controllers) {
      if (!node.isConnected || root?.contains(node)) {
        controller.dispose();
        controllers.delete(node);
      }
    }
  };
  window.mirrorClearDiagramInteractions = () => {
    for (const controller of controllers.values()) controller.dispose();
    controllers.clear();
  };
  window.addEventListener("blur", () => {
    for (const controller of controllers.values()) controller.cancel();
  });
  window.mirrorInstallDiagram = (canvas) => {
    if (!canvas.isConnected || controllers.has(canvas)) return;
    const svg = canvas.querySelector("svg"),
      block = canvas.closest(".diagram-block"),
      header = block?.querySelector(".code-header");
    if (!svg || !header) return;
    block.classList.add("diagram-frame");
    const box = svg.viewBox.baseVal;
    const width = box.width || svg.getBoundingClientRect().width;
    const height = box.height || svg.getBoundingClientRect().height;
    if (!(width > 0 && height > 0)) return;
    const chinese = true;
    canvas.classList.add("diagram-interactive");
    canvas.tabIndex = 0;
    canvas.setAttribute("role", "region");
    canvas.setAttribute(
      "aria-label",
      chinese
        ? "流程图：拖拽移动，加减键缩放，0 复位"
        : "Diagram: drag to pan, plus/minus to zoom, 0 to reset",
    );
    canvas.title = chinese
      ? "拖拽移动；⌘/Ctrl + 滚轮或触控板捏合缩放；双击复位"
      : "Drag to pan; ⌘/Ctrl + wheel or pinch to zoom; double-click to reset";
    const content = document.createElement("div");
    content.className = "diagram-content";
    content.style.width = `${width}px`;
    content.style.height = `${height}px`;
    svg.replaceWith(content);
    content.appendChild(svg);
    const tools = document.createElement("div");
    tools.className = "diagram-tools";
    const button = (text, label) => {
      const item = document.createElement("button");
      item.type = "button";
      item.textContent = text;
      item.title = label;
      item.setAttribute("aria-label", label);
      tools.appendChild(item);
      return item;
    };
    const smaller = button("−", chinese ? "缩小流程图" : "Zoom out diagram");
    const output = document.createElement("span");
    output.className = "diagram-zoom";
    tools.appendChild(output);
    const larger = button("+", chinese ? "放大流程图" : "Zoom in diagram");
    const reset = button(
      "↺",
      chinese ? "复位并适配流程图" : "Reset and fit diagram",
    );
    header.appendChild(tools);
    const handles = ["right", "bottom", "corner"].map((edge) => {
      const handle = document.createElement("button");
      handle.type = "button";
      handle.className = `diagram-resize diagram-resize-${edge}`;
      handle.dataset.edge = edge;
      handle.title = chinese
        ? `拖动${edge === "right" ? "右边框调整宽度" : edge === "bottom" ? "下边框调整高度" : "右下角调整外框宽高"}；方向键微调；Esc 取消`
        : `Drag ${edge === "right" ? "right border to resize width" : edge === "bottom" ? "bottom border to resize height" : "corner to resize frame"}; arrow keys adjust; Escape to cancel`;
      handle.setAttribute("aria-label", handle.title);
      block.appendChild(handle);
      return handle;
    });
    let scale = 1,
      fitScale = 1,
      x = 0,
      y = 0,
      drag = null,
      gesture = null,
      lastWidth = -1,
      lastHeight = -1,
      manualHeight = null,
      fitted = true;
    const minimum = () => fitScale * 0.25;
    const maximum = () => Math.max(1, fitScale) * 8;
    const paint = () => {
      content.style.transform = `translate(${x}px,${y}px) scale(${scale})`;
      output.textContent = `${Math.round((scale / fitScale) * 100)}%`;
      smaller.disabled = scale <= minimum() + 0.00001;
      larger.disabled = scale >= maximum() - 0.00001;
    };
    const fit = () => {
      scale = fitScale;
      x = (canvas.clientWidth - width * scale) / 2;
      y = (canvas.clientHeight - height * scale) / 2;
      fitted = true;
      paint();
    };
    const layout = (force = false) => {
      const available = canvas.clientWidth;
      if (available <= 0) return;
      const viewportHeight =
        manualHeight ??
        Math.max(
          160,
          Math.min(
            520,
            height * Math.min(1, Math.max(1, available - 40) / width) + 40,
          ),
        );
      if (
        force !== true &&
        available === lastWidth &&
        viewportHeight === lastHeight
      )
        return;
      const oldWidth = lastWidth > 0 ? lastWidth : available,
        oldHeight = lastHeight > 0 ? lastHeight : viewportHeight;
      const oldFit = fitScale;
      const pointX = (oldWidth / 2 - x) / scale,
        pointY = (oldHeight / 2 - y) / scale;
      lastWidth = available;
      lastHeight = viewportHeight;
      canvas.style.height = `${viewportHeight}px`;
      fitScale = Math.min(
        1,
        Math.max(1, available - 40) / width,
        (viewportHeight - 40) / height,
      );
      if (fitted) fit();
      else {
        scale = Math.max(
          minimum(),
          Math.min(maximum(), (scale * fitScale) / oldFit),
        );
        x = available / 2 - pointX * scale;
        y = viewportHeight / 2 - pointY * scale;
        paint();
      }
    };
    const resizeFrame = (nextWidth, nextHeight) => {
      const parent = block.parentElement,
        style = getComputedStyle(parent);
      const limit =
        parent.clientWidth -
        (parseFloat(style.paddingLeft) || 0) -
        (parseFloat(style.paddingRight) || 0);
      block.style.width = `${Math.max(Math.min(280, limit), Math.min(limit, nextWidth))}px`;
      manualHeight = Math.max(120, Math.min(1600, nextHeight));
      fitted = true;
      layout(true);
      window.mirrorInvalidateLayout?.();
    };
    const zoom = (
      next,
      px = canvas.clientWidth / 2,
      py = canvas.clientHeight / 2,
    ) => {
      next = Math.max(minimum(), Math.min(maximum(), next));
      finish(false);
      const ratio = next / scale;
      x = px - (px - x) * ratio;
      y = py - (py - y) * ratio;
      scale = next;
      fitted = false;
      paint();
    };
    const finish = (cancel) => {
      if (!drag) return;
      const current = drag;
      drag = null;
      canvas.classList.remove("dragging");
      block.classList.remove("resizing");
      if (cancel) {
        if (current.resizing) {
          block.style.width = current.frameStyleWidth;
          manualHeight = current.manualHeight;
          fitted = true;
          layout(true);
          fitScale = current.fitScale;
        }
        x = current.x;
        y = current.y;
        scale = current.scale;
        fitted = current.fitted;
        paint();
      }
      if (current.capture.hasPointerCapture(current.id))
        current.capture.releasePointerCapture(current.id);
    };
    const resetFrame = () => {
      finish(true);
      block.style.width = "";
      manualHeight = null;
      fitted = true;
      layout(true);
      fit();
    };
    smaller.addEventListener("click", () => zoom(scale / 1.2));
    larger.addEventListener("click", () => zoom(scale * 1.2));
    reset.addEventListener("click", resetFrame);
    canvas.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || event.target.closest("a") || drag || gesture)
        return;
      event.preventDefault();
      canvas.focus({ preventScroll: true });
      drag = {
        id: event.pointerId,
        px: event.clientX,
        py: event.clientY,
        x,
        y,
        scale,
        fitted,
        capture: canvas,
      };
      canvas.setPointerCapture(event.pointerId);
      canvas.classList.add("dragging");
    });
    canvas.addEventListener("pointermove", (event) => {
      if (!drag || drag.resizing || drag.id !== event.pointerId) return;
      x = drag.x + event.clientX - drag.px;
      y = drag.y + event.clientY - drag.py;
      fitted = false;
      paint();
    });
    block.addEventListener("pointerdown", (event) => {
      const handle = event.target.closest(".diagram-resize");
      if (!handles.includes(handle) || event.button !== 0 || drag || gesture)
        return;
      event.preventDefault();
      event.stopPropagation();
      handle.focus({ preventScroll: true });
      drag = {
        id: event.pointerId,
        px: event.clientX,
        py: event.clientY,
        x,
        y,
        scale,
        fitScale,
        fitted,
        resizing: handle.dataset.edge,
        frameWidth: block.getBoundingClientRect().width,
        frameHeight: canvas.clientHeight,
        frameStyleWidth: block.style.width,
        manualHeight,
        capture: block,
      };
      block.setPointerCapture(event.pointerId);
      block.classList.add("resizing");
    });
    block.addEventListener("pointermove", (event) => {
      if (!drag?.resizing || drag.id !== event.pointerId) return;
      event.preventDefault();
      resizeFrame(
        drag.frameWidth +
          (drag.resizing === "bottom" ? 0 : event.clientX - drag.px),
        drag.frameHeight +
          (drag.resizing === "right" ? 0 : event.clientY - drag.py),
      );
    });
    block.addEventListener("pointerup", (event) => {
      if (drag?.resizing && drag.id === event.pointerId) finish(false);
    });
    block.addEventListener("pointercancel", (event) => {
      if (drag?.resizing && drag.id === event.pointerId) finish(true);
    });
    block.addEventListener("lostpointercapture", () => {
      if (drag?.resizing) finish(true);
    });
    for (const handle of handles) {
      handle.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
      });
      handle.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          finish(true);
          return;
        }
        if (event.metaKey || event.ctrlKey || event.altKey) return;
        if (event.key === "0" || event.key === "Home") {
          event.preventDefault();
          resetFrame();
          return;
        }
        if (
          !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
            event.key,
          )
        )
          return;
        event.preventDefault();
        event.stopPropagation();
        finish(false);
        const step = event.shiftKey ? 10 : 1,
          edge = handle.dataset.edge;
        resizeFrame(
          block.getBoundingClientRect().width +
            (edge !== "bottom"
              ? event.key === "ArrowRight"
                ? step
                : event.key === "ArrowLeft"
                  ? -step
                  : 0
              : 0),
          canvas.clientHeight +
            (edge !== "right"
              ? event.key === "ArrowDown"
                ? step
                : event.key === "ArrowUp"
                  ? -step
                  : 0
              : 0),
        );
      });
    }
    canvas.addEventListener("pointerup", (event) => {
      if (drag?.id === event.pointerId) finish(false);
    });
    canvas.addEventListener("pointercancel", (event) => {
      if (drag?.id === event.pointerId) finish(true);
    });
    canvas.addEventListener("lostpointercapture", () => {
      if (drag && !drag.resizing) finish(true);
    });
    canvas.addEventListener("dblclick", (event) => {
      if (event.target.closest("a,.diagram-resize")) return;
      event.preventDefault();
      resetFrame();
    });
    canvas.addEventListener(
      "wheel",
      (event) => {
        if (!event.ctrlKey && !event.metaKey) return;
        event.preventDefault();
        const rect = canvas.getBoundingClientRect();
        const delta =
          event.deltaY *
          (event.deltaMode === 1
            ? 16
            : event.deltaMode === 2
              ? canvas.clientHeight
              : 1);
        zoom(
          scale * Math.exp(-Math.max(-100, Math.min(100, delta)) * 0.01),
          event.clientX - rect.left,
          event.clientY - rect.top,
        );
      },
      { passive: false },
    );
    // WebKit reports trackpad magnification as gesture events rather than Ctrl-wheel.
    canvas.addEventListener(
      "gesturestart",
      (event) => {
        event.preventDefault();
        finish(true);
        const rect = canvas.getBoundingClientRect();
        gesture = {
          scale,
          x: event.clientX - rect.left,
          y: event.clientY - rect.top,
        };
      },
      { passive: false },
    );
    canvas.addEventListener(
      "gesturechange",
      (event) => {
        if (!gesture) return;
        event.preventDefault();
        zoom(gesture.scale * event.scale, gesture.x, gesture.y);
      },
      { passive: false },
    );
    canvas.addEventListener(
      "gestureend",
      (event) => {
        event.preventDefault();
        gesture = null;
      },
      { passive: false },
    );
    canvas.addEventListener("keydown", (event) => {
      if (event.target !== canvas) return;
      if (event.key === "Escape") {
        finish(true);
        return;
      }
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      if (
        [
          "+",
          "=",
          "-",
          "0",
          "Home",
          "ArrowLeft",
          "ArrowRight",
          "ArrowUp",
          "ArrowDown",
        ].includes(event.key)
      ) {
        event.preventDefault();
        event.stopPropagation();
        finish(false);
        if (event.key === "+" || event.key === "=") zoom(scale * 1.2);
        else if (event.key === "-") zoom(scale / 1.2);
        else if (event.key === "0" || event.key === "Home") resetFrame();
        else {
          const step = event.shiftKey ? 80 : 20;
          x +=
            event.key === "ArrowLeft"
              ? step
              : event.key === "ArrowRight"
                ? -step
                : 0;
          y +=
            event.key === "ArrowUp"
              ? step
              : event.key === "ArrowDown"
                ? -step
                : 0;
          fitted = false;
          paint();
        }
      }
    });
    const observer = new ResizeObserver(layout);
    observer.observe(canvas);
    layout();
    controllers.set(canvas, {
      cancel: () => {
        finish(true);
        gesture = null;
      },
      dispose: () => {
        finish(true);
        observer.disconnect();
      },
    });
  };
  for (const canvas of document.querySelectorAll(".diagram-canvas.mermaid"))
    window.mirrorInstallDiagram(canvas);
})();

export const installDiagram = (canvas) => window.mirrorInstallDiagram(canvas);
export const disposeDiagrams = (root) => window.mirrorDisposeDiagrams(root);
