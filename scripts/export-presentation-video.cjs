#!/usr/bin/env node
/* Record the actual HTML composition: native footage, genuine crops and leader lines. */
const path = require("node:path"),
  fs = require("node:fs/promises"),
  { spawnSync } = require("node:child_process");
const ROOT = path.resolve(__dirname, "..");
let playwright;
try {
  playwright = require(path.join(ROOT, "presentation/node_modules/playwright"));
} catch (error) {
  if (!process.env.HARBOUR_NODE_MODULES)
    throw new Error(
      "Install presentation/package.json dependencies or set HARBOUR_NODE_MODULES to an existing Playwright package directory.",
    );
  playwright = require(
    path.join(process.env.HARBOUR_NODE_MODULES, "playwright"),
  );
}
const args = process.argv.slice(2),
  argument = (flag, fallback) =>
    args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = argument("--url", "http://127.0.0.1:8766/"),
  out = path.resolve(
    argument("--output", path.join(ROOT, "docs/presentation/harbour-demo.mp4")),
  ),
  channel = argument("--browser", "chrome");
(async () => {
  await fs.mkdir(path.dirname(out), { recursive: true });
  const tmp = await fs.mkdtemp(path.join(ROOT, "build/presentation-video-"));
  const browser = await playwright.chromium.launch({
    headless: true,
    ...(channel === "chromium" ? {} : { channel }),
  });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
    recordVideo: { dir: tmp, size: { width: 1920, height: 1080 } },
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.exposeFunction("onPresentationStep", (step) =>
    console.log(`Explaining ${step}`),
  );
  await page.goto(url + (url.includes("?") ? "&" : "?") + "record=1");
  await page.waitForFunction(() => window.presentation?.ready);
  await page.evaluate(() => presentation.playDemo());
  console.log(
    "Recording actual native footage with external UI deconstruction…",
  );
  await page.waitForFunction(() => window.presentation.done, null, {
    timeout: 300000,
  });
  const stages = await page.evaluate(() => presentation.state.stops);
  if (
    !["home", "readings", "caregiver", "records", "medication", "visit"].every(
      (s) => stages.includes(s),
    )
  )
    throw new Error("Incomplete deconstruction sequence: " + stages.join(", "));
  await page.waitForTimeout(800);
  const recording = await page.video().path();
  await context.close();
  await browser.close();
  if (errors.length) throw new Error(errors.join("\n"));
  const converted = spawnSync(
    "ffmpeg",
    [
      "-y",
      "-i",
      recording,
      "-an",
      "-c:v",
      "libx264",
      "-crf",
      "20",
      "-preset",
      "fast",
      "-pix_fmt",
      "yuv420p",
      "-movflags",
      "+faststart",
      out,
    ],
    { encoding: "utf8" },
  );
  await fs.writeFile(path.join(tmp, "export.log"), converted.stderr ?? "");
  if (converted.status) throw new Error(`ffmpeg failed: ${converted.stderr}`);
  console.log(`Exported ${out}. Browser source recording retained in ${tmp}.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
