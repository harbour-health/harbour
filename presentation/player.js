/* All lifted pixels come from genuine native captures. No UI component is redrawn. */
const data = JSON.parse(document.querySelector("#manifest").textContent),
  stage = document.querySelector("#stage"),
  scene = document.querySelector("#scene");
const q = (s) => document.querySelector(s),
  wait = (ms) => new Promise((r) => setTimeout(r, ms)),
  reduced = matchMedia("(prefers-reduced-motion:reduce)").matches;
let index = 0,
  currentShot = null,
  phone = null,
  video = null,
  lifted = false,
  live = false,
  busy = false,
  auto = false,
  stops = new Set(),
  mirrorURL = null;
const size = { w: 1920, h: 1080 },
  phoneBox = { x: 144, y: 304, w: 300, h: 652.24 };
if (new URLSearchParams(location.search).has("record"))
  document.body.classList.add("record");
function resize() {
  stage.style.transform = `scale(${Math.min(innerWidth / size.w, innerHeight / size.h)})`;
}
addEventListener("resize", resize);
resize();
function notice(text) {
  q("#notice").textContent = text;
  q("#notice").style.opacity = 1;
  setTimeout(() => (q("#notice").style.opacity = 0), 5000);
}
function chapterTime(prefix) {
  return (
    data.recording.chapters.find((c) => c.name.startsWith(prefix))
      ?.videoSeconds ?? 0
  );
}
function imgLoad(src) {
  return new Promise((resolve, reject) => {
    const i = new Image();
    i.onload = () => resolve(i);
    i.onerror = reject;
    i.src = src;
  });
}
function cropImage(source, rect, screen) {
  // CSS clipping keeps real pixels and also works from file:// without canvas tainting.
  const piece = document.createElement("div"),
    image = document.createElement("img");
  image.src = source;
  image.alt = "";
  Object.assign(image.style, {
    position: "absolute",
    maxWidth: "none",
    width: `${(screen.width / rect.w) * 100}%`,
    height: `${(screen.height / rect.h) * 100}%`,
    left: `${(-rect.x / rect.w) * 100}%`,
    top: `${(-rect.y / rect.h) * 100}%`,
  });
  piece.append(image);
  return piece;
}
function clearLayers() {
  scene
    .querySelectorAll(".layer,.leaders,.explanation,.scene-note")
    .forEach((e) => e.remove());
  phone?.classList.remove("exploded");
  lifted = false;
}
async function collapse() {
  if (!lifted) return;
  const layers = [...scene.querySelectorAll(".layer")];
  scene.querySelectorAll(".leaders,.explanation").forEach((e) => e.remove());
  await Promise.all(
    layers.map(
      (e) =>
        e.animate(
          [
            {
              left: e.style.left,
              top: e.style.top,
              width: e.style.width,
              height: e.style.height,
              transform: e.style.transform,
            },
            JSON.parse(e.dataset.origin),
          ],
          {
            duration: reduced ? 0 : 550,
            easing: "cubic-bezier(.3,0,.2,1)",
            fill: "forwards",
          },
        ).finished,
    ),
  );
  clearLayers();
}
async function setShot(key) {
  const shot = typeof key === "string" ? data.scenes[key] : key;
  if (!shot) throw Error("No capture for this scene");
  currentShot = shot;
  const image = await imgLoad(shot.image);
  let still = phone.querySelector(".still");
  if (!still) {
    still = document.createElement("img");
    still.className = "still";
    still.alt = "Actual native app capture";
    phone.append(still);
  }
  still.src = shot.image;
  still.hidden = false;
  phone.querySelector("iframe")?.setAttribute("hidden", "");
  if (video) video.hidden = true;
  return image;
}
function leader(layer, i) {
  const svg =
    scene.querySelector(".leaders") ??
    (() => {
      const s = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      s.classList.add("leaders");
      s.setAttribute("viewBox", "0 0 1920 1080");
      scene.append(s);
      return s;
    })();
  const y = layer.to.y + layer.to.h / 2,
    x = layer.to.x + layer.to.w,
    labelY = layer.labelY ?? y - 36;
  const path = document.createElementNS(svg.namespaceURI, "path");
  path.setAttribute(
    "d",
    `M ${x + 12} ${y} H ${Math.max(x + 35, 1335)} V ${labelY + 18} H 1375`,
  );
  svg.append(path);
  const circle = document.createElementNS(svg.namespaceURI, "circle");
  circle.setAttribute("cx", x + 12);
  circle.setAttribute("cy", y);
  circle.setAttribute("r", "4");
  svg.append(circle);
  const length = path.getTotalLength();
  path.style.strokeDasharray = length;
  path.style.strokeDashoffset = length;
  path.animate([{ strokeDashoffset: length }, { strokeDashoffset: 0 }], {
    duration: reduced ? 0 : 450,
    delay: i * 90,
    fill: "forwards",
  });
  const label = document.createElement("div");
  label.className = "explanation";
  label.style.left = "1400px";
  label.style.top = `${labelY}px`;
  const h = document.createElement("h3");
  h.textContent = layer.title;
  const p = document.createElement("p");
  p.textContent = layer.detail;
  label.append(h, p);
  scene.append(label);
  label.animate(
    [
      { opacity: 0, transform: "translateX(-12px)" },
      { opacity: 1, transform: "translateX(0)" },
    ],
    { duration: reduced ? 0 : 400, delay: 200 + i * 90, fill: "both" },
  );
}
async function explode(key = null) {
  if (busy) return;
  busy = true;
  try {
    if (lifted) {
      await collapse();
      return;
    }
    if (key) await setShot(key);
    if (!currentShot) return;
    const image = await imgLoad(currentShot.image);
    clearLayers();
    phone.classList.add("exploded");
    const scale = phoneBox.w / currentShot.screen.width;
    for (const [i, part] of currentShot.layers.entries()) {
      const src = part.rect,
        origin = {
          left: `${phoneBox.x + src.x * scale}px`,
          top: `${phoneBox.y + src.y * scale}px`,
          width: `${src.w * scale}px`,
          height: `${src.h * scale}px`,
          transform: "rotateX(0deg) rotateY(0deg) translateZ(0)",
        };
      const layer = cropImage(currentShot.image, src, currentShot.screen);
      layer.className = "layer";
      layer.style.borderRadius = `${((part.radius ?? 0) * part.to.w) / part.rect.w}px`;
      layer.setAttribute("role", "img");
      layer.setAttribute("aria-label", part.title);
      Object.assign(layer.style, origin);
      layer.dataset.origin = JSON.stringify(origin);
      scene.append(layer);
      const final = {
        left: `${part.to.x}px`,
        top: `${part.to.y}px`,
        width: `${part.to.w}px`,
        height: `${part.to.h}px`,
        transform: "rotateX(2deg) rotateY(-5deg) translateZ(35px)",
      };
      await layer.animate([origin, final], {
        duration: reduced ? 0 : 850,
        delay: i * 70,
        easing: "cubic-bezier(.17,.8,.2,1)",
        fill: "forwards",
      }).finished;
      Object.assign(layer.style, final);
      leader(part, i);
    }
    lifted = true;
  } finally {
    busy = false;
  }
}
function defaultScene(s) {
  return s === "interfaces"
    ? "home"
    : s === "medication"
      ? "medication"
      : s === "visit"
        ? "visit"
        : "readings";
}
async function show(i) {
  if (busy) return;
  auto = false;
  video?.pause();
  index = Math.max(0, Math.min(data.slides.length - 1, i));
  live = false;
  scene.replaceChildren();
  phone = null;
  video = null;
  lifted = false;
  currentShot = null;
  const s = data.slides[index];
  q("#slide").src = `slides/slide-${String(index + 1).padStart(2, "0")}.svg`;
  q("#slide").alt = s.title;
  await q("#slide").decode();
  q("#count").textContent = `${index + 1} / ${data.slides.length}`;
  q("#notes").textContent = `${s.title} · ${s.seconds}s\n\n${s.notes}`;
  const dynamic = Boolean(s.scene);
  for (const id of ["play", "explain", "live", "capture", "simulator"])
    q("#" + id).hidden = !dynamic;
  if (!dynamic) return;
  phone = document.createElement("div");
  phone.className = "phone";
  scene.append(phone);
  if (s.scene === "walkthrough") {
    video = document.createElement("video");
    video.src = "media/harbour-walkthrough.mp4";
    video.playsInline = true;
    video.preload = "auto";
    video.muted = true;
    phone.append(video);
    await setShot("home");
    video.onended = async () => {
      if (!auto) return;
      if (!stops.has("visit")) {
        stops.add("visit");
        await explode("visit");
        await wait(6500);
      }
      window.presentation.done = true;
    };
    video.ontimeupdate = () => autoStop();
  } else await setShot(defaultScene(s.scene));
  const hint = document.createElement("div");
  hint.className = "scene-note";
  hint.innerHTML =
    s.scene === "interfaces"
      ? "Talk, message, record.<small>Settings opens the caregiver interface.</small>"
      : s.scene === "medication"
        ? "A suggestion needs a decision.<small>Name lookup never silently rewrites a transcript or medication.</small>"
        : s.scene === "visit"
          ? "Review before saving.<small>Directions and proposed changes remain visible together.</small>"
          : "Ask freely.<small>The local model chooses a tool. The app reads the saved values.</small>";
  scene.append(hint);
  q("#play").hidden = s.scene !== "walkthrough";
}
async function play() {
  if (!video) return;
  clearLayers();
  phone.querySelector(".still").hidden = true;
  video.hidden = false;
  await video.play();
}
async function autoStop() {
  if (!auto || busy || !video) return;
  const points = [
    { key: "home", at: 0.5 },
    { key: "readings", at: chapterTime("237-") + 0.2 },
    { key: "medication", at: chapterTime("244-") + 0.2 },
    {
      key: "visit",
      at: Math.min(chapterTime("247-") + 0.2, video.duration - 2),
    },
  ];
  const item = points.find(
    (x) => video.currentTime >= x.at && !stops.has(x.key),
  );
  if (!item) return;
  stops.add(item.key);
  window.onPresentationStep?.(item.key);
  video.pause();
  await explode(item.key);
  await wait(6500);
  if (item.key === "visit") {
    auto = false;
    window.presentation.done = true;
    return;
  }
  await collapse();
  if (video) {
    phone.querySelector(".still").hidden = true;
    video.hidden = false;
    await video.play();
  }
}
async function capture() {
  live = true;
  try {
    const response = await fetch("/api/capture", {
      headers: { "X-Harbour-Presentation": "1" },
    });
    if (!response.ok) throw Error(await response.text());
    const shot = await response.json();
    await collapse();
    const image = await imgLoad(shot.image);
    currentShot = {
      image: shot.image,
      screen: { width: image.naturalWidth, height: image.naturalHeight },
      layers: [],
    };
    await setShot(currentShot);
    phone.classList.add("selecting");
    notice("Drag over a part of the actual capture to lift it out.");
    let start = null,
      box = null;
    phone.onpointerdown = (e) => {
      e.preventDefault();
      start = { x: e.clientX, y: e.clientY };
      box = document.createElement("div");
      box.className = "selection";
      phone.append(box);
      phone.setPointerCapture(e.pointerId);
    };
    phone.onpointermove = (e) => {
      if (!start) return;
      const r = phone.querySelector(".still").getBoundingClientRect(),
        sx = phoneBox.w / r.width;
      Object.assign(box.style, {
        left: `${(Math.min(start.x, e.clientX) - r.left) * sx}px`,
        top: `${(Math.min(start.y, e.clientY) - r.top) * sx}px`,
        width: `${Math.abs(e.clientX - start.x) * sx}px`,
        height: `${Math.abs(e.clientY - start.y) * sx}px`,
      });
    };
    phone.onpointerup = async (e) => {
      if (!start) return;
      const r = phone.querySelector(".still").getBoundingClientRect(),
        factor = image.naturalWidth / r.width;
      const rect = {
        x: Math.max(0, (Math.min(start.x, e.clientX) - r.left) * factor),
        y: Math.max(0, (Math.min(start.y, e.clientY) - r.top) * factor),
        w: Math.abs(e.clientX - start.x) * factor,
        h: Math.abs(e.clientY - start.y) * factor,
      };
      box.remove();
      start = null;
      if (rect.w < 20 || rect.h < 20) return;
      rect.w = Math.min(rect.w, image.naturalWidth - rect.x);
      rect.h = Math.min(rect.h, image.naturalHeight - rect.y);
      const width = Math.min(680, rect.w * 1.5),
        height = Math.min(560, (width * rect.h) / rect.w);
      currentShot.layers = [
        {
          rect,
          to: { x: 670, y: 340, w: width, h: height },
          title: "Actual interface",
          detail:
            "Captured from the running app. Explain this part while it is lifted out.",
        },
      ];
      phone.onpointerdown = phone.onpointermove = phone.onpointerup = null;
      phone.classList.remove("selecting");
      await explode();
    };
  } catch (error) {
    notice(
      `Live capture needs the local presentation server: ${error.message}`,
    );
  }
}
q("#next").onclick = () => show(index + 1);
q("#previous").onclick = () => show(index - 1);
q("#play").onclick = () => (video?.paused ? play() : video?.pause());
q("#explain").onclick = async () => {
  video?.pause();
  if (lifted) return collapse();
  if (video && !live) {
    const t = video.currentTime;
    return explode(
      t >= chapterTime("247-")
        ? "visit"
        : t >= chapterTime("244-")
          ? "medication"
          : t >= chapterTime("237-")
            ? "readings"
            : "home",
    );
  }
  if (!currentShot || currentShot.layers.length === 0)
    return notice("Capture and select a part first.");
  await explode();
};
q("#capture").onclick = capture;
q("#notesButton").onclick = () => (q("#notes").hidden = !q("#notes").hidden);
q("#fullscreen").onclick = () =>
  document.fullscreenElement
    ? document.exitFullscreen()
    : document.documentElement.requestFullscreen();
q("#simulator").onclick = async () => {
  try {
    const r = await fetch("/api/simulator", {
      method: "POST",
      headers: { "X-Harbour-Presentation": "1" },
    });
    if (!r.ok) throw Error();
    notice("Use the actual Simulator, then return here and Capture.");
  } catch {
    notice("Start scripts/serve-presentation.py to open the live Simulator.");
  }
};
q("#live").onclick = async () => {
  await collapse();
  video?.pause();
  try {
    const r = await fetch("/api/config");
    const c = await r.json();
    mirrorURL = c.mirrorURL;
  } catch {}
  if (!mirrorURL) {
    notice("Open Simulator to use the app, then Capture the current screen.");
    return;
  }
  phone.querySelector(".still").hidden = true;
  if (video) video.hidden = true;
  let iframe = phone.querySelector("iframe");
  if (!iframe) {
    iframe = document.createElement("iframe");
    iframe.title = "Actual interactive iOS Simulator";
    iframe.src = mirrorURL;
    phone.append(iframe);
  }
  iframe.hidden = false;
  live = true;
};
addEventListener("keydown", (e) => {
  if (e.target.matches("input,textarea")) return;
  if (["ArrowRight", "PageDown"].includes(e.key)) {
    e.preventDefault();
    show(index + 1);
  }
  if (["ArrowLeft", "PageUp"].includes(e.key)) {
    e.preventDefault();
    show(index - 1);
  }
  if (e.key === "e") q("#explain").click();
  if (e.key === "n") q("#notesButton").click();
  if (e.key === " ") {
    e.preventDefault();
    q("#play").click();
  }
});
window.presentation = {
  ready: false,
  done: false,
  show,
  explode,
  collapse,
  async playDemo() {
    this.done = false;
    await show(3);
    auto = true;
    stops.clear();
    await play();
  },
  get state() {
    return {
      index,
      lifted,
      currentShot,
      stops: [...stops],
      playing: video && !video.paused,
    };
  },
};
show(0).then(() => (window.presentation.ready = true));
