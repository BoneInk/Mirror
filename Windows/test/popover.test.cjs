const { test } = require("node:test");
const assert = require("node:assert/strict");

test("selection popovers prefer below, flip above, and remain within workspace edges", async () => {
  const { placePopover } = await import("../src/popover-position.mjs");
  const bounds = { left: 240, top: 90, right: 1000, bottom: 700 };
  const size = { width: 300, height: 40 };
  assert.deepEqual(
    placePopover(
      { left: 400, right: 401, top: 300, bottom: 320 },
      size,
      bounds,
    ),
    { left: 388, top: 328, maxWidth: 744, maxHeight: 594, side: "bottom" },
  );
  const edge = placePopover(
    { left: 998, right: 999, top: 660, bottom: 680 },
    size,
    bounds,
  );
  assert.equal(edge.side, "top");
  assert.equal(edge.top, 612);
  assert.equal(edge.left, 692);
  const oversized = placePopover(
    { left: -10, right: -9, top: -20, bottom: -10 },
    { width: 1500, height: 900 },
    bounds,
  );
  assert.equal(oversized.left, 248);
  assert.equal(oversized.top, 98);
  assert.equal(oversized.maxWidth, 744);
  assert.equal(oversized.maxHeight, 594);
  const marker = placePopover(
    { left: 400, right: 420, top: 300, bottom: 320 },
    size,
    bounds,
    "right",
  );
  assert.equal(marker.side, "right");
  assert.equal(marker.left, 428);
  const blocked = placePopover(
    { left: 950, right: 970, top: 300, bottom: 320 },
    size,
    bounds,
    "right",
  );
  assert.equal(blocked.side, "bottom");
  assert.equal(blocked.left, 692);
});
