const { spawn } = require("node:child_process");
require("./prepare.cjs");
(async () => {
  const { createServer } = await import("vite");
  const server = await createServer();
  await server.listen();
  const child = spawn(require("electron"), ["."], {
    env: { ...process.env, MIRROR_DEV_URL: "http://127.0.0.1:5173" },
    stdio: "inherit",
  });
  child.on("exit", async (code) => {
    await server.close();
    process.exit(code ?? 0);
  });
  for (const signal of ["SIGINT", "SIGTERM"])
    process.on(signal, () => child.kill());
})();
