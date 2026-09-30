const { defineConfig } = require("@playwright/test");
module.exports = defineConfig({
  testDir: "./test/ui",
  timeout: 45000,
  workers: 1,
  reporter: "list",
});
