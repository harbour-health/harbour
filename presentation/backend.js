/* Explanatory architecture animation. This never runs or impersonates the app backend. */
(() => {
  let generation = 0,
    active = null;
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const reduced = matchMedia("(prefers-reduced-motion:reduce)").matches;
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  function close() {
    generation++;
    active?.remove();
    active = null;
  }
  function frame(host, flow) {
    const root = element("section", "backend");
    root.setAttribute("aria-label", "Backend architecture: " + flow.title);
    const label = element("div", "backend-label", "Architecture animation");
    const exit = element("button", "backend-close", "Close");
    exit.setAttribute("aria-label", "Close backend explanation");
    exit.onclick = close;
    root.append(
      label,
      exit,
      element("h2", "backend-title", flow.title),
      element("p", "backend-subtitle", flow.subtitle),
    );
    const rail = element("div", "backend-rail");
    const line = element("div", "backend-line"),
      progress = element("div", "backend-progress");
    line.append(progress);
    rail.append(line);
    const stations = flow.stages.map((title, i) => {
      const node = element("div", "backend-station");
      node.append(
        element("span", "backend-number", String(i + 1)),
        element("span", "backend-station-title", title),
      );
      rail.append(node);
      return node;
    });
    const packet = element("div", "backend-packet");
    packet.setAttribute("aria-hidden", "true");
    rail.append(packet);
    const detail = element("div", "backend-detail");
    const heading = element("h3", ""),
      prose = element("p", ""),
      code = element("pre", "backend-code");
    const payload = element("div", "backend-payload");
    payload.append(code);
    detail.append(heading, prose, payload);
    const source = element("div", "backend-source");
    flow.sources.forEach((text) => source.append(element("div", "", text)));
    const meter = element("div", "backend-beats");
    flow.beats.forEach(() => meter.append(element("span", "")));
    root.append(rail, detail, meter, source);
    host.append(root);
    active = root;
    root.animate(
      [
        { opacity: 0, transform: "translateY(16px)" },
        { opacity: 1, transform: "translateY(0)" },
      ],
      { duration: reduced ? 0 : 320 },
    );
    return {
      root,
      rail,
      stations,
      progress,
      packet,
      detail,
      heading,
      prose,
      code,
      payload,
      meter,
    };
  }
  function diagram(spec) {
    const root = element("div", "backend-diagram " + spec.kind);
    root.setAttribute(
      "aria-label",
      spec.input + ": " + spec.options.join(", "),
    );
    root.append(element("div", "backend-diagram-input", spec.input));
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 410 180");
    svg.setAttribute("aria-hidden", "true");
    root.append(svg);
    spec.options.forEach((title, i) => {
      const selected = spec.selected.includes(i);
      const label = element(
        "div",
        "backend-option" + (selected ? " selected" : ""),
        title,
      );
      label.style.top = `${i * 53 + 10}px`;
      root.append(label);
      const path = document.createElementNS(svg.namespaceURI, "path");
      const y = i * 53 + 30;
      path.setAttribute(
        "d",
        spec.kind === "passes"
          ? i === 0
            ? "M 205 3 V 29 H 238"
            : "M 275 " + (y - 32) + " V " + y + " H 238"
          : `M 80 90 H 160 V ${y} H 238`,
      );
      path.setAttribute("class", selected ? "selected" : "");
      svg.append(path);
      if (selected && !reduced) {
        const dot = document.createElementNS(svg.namespaceURI, "circle");
        dot.setAttribute("r", "4");
        svg.append(dot);
        const motion = document.createElementNS(
          svg.namespaceURI,
          "animateMotion",
        );
        motion.setAttribute("dur", "1.25s");
        motion.setAttribute("repeatCount", "indefinite");
        motion.setAttribute("path", path.getAttribute("d"));
        dot.append(motion);
      }
    });
    return root;
  }
  function beat(view, flow, index) {
    const item = flow.beats[index];
    view.root.dataset.beat = String(index);
    view.root.dataset.stage = String(item.stage);
    view.stations.forEach((station, i) => {
      station.classList.toggle("active", i === item.stage);
      station.classList.toggle("complete", i < item.stage);
    });
    view.progress.style.width = `${(item.stage / (flow.stages.length - 1)) * 100}%`;
    const target = ((item.stage + 0.5) / flow.stages.length) * 100;
    const origin =
      (((item.stage === 1 && index > 1 ? 0 : Math.max(0, item.stage - 1)) +
        0.5) /
        flow.stages.length) *
      100;
    view.packet.style.left = `${target}%`;
    view.packet.animate(
      [
        { left: `${origin}%`, opacity: 1 },
        { left: `${target}%`, opacity: 1, offset: 0.8 },
        { left: `${target}%`, opacity: 0 },
      ],
      { duration: reduced ? 0 : 850 },
    );
    view.stations[item.stage].firstElementChild.animate(
      [
        { transform: "scale(1)" },
        { transform: "scale(1.12)", offset: 0.45 },
        { transform: "scale(1)" },
      ],
      { duration: reduced ? 0 : 650 },
    );
    view.heading.textContent = item.title;
    view.prose.textContent = item.detail;
    view.code.textContent = item.code;
    view.payload.querySelector(".backend-diagram")?.remove();
    view.payload.classList.toggle("has-diagram", Boolean(item.visual));
    if (item.visual) view.payload.append(diagram(item.visual));
    [...view.meter.children].forEach((dot, i) =>
      dot.classList.toggle("complete", i <= index),
    );
    view.detail.animate(
      [
        { opacity: 0, transform: "translateY(10px)" },
        { opacity: 1, transform: "translateY(0)" },
      ],
      { duration: reduced ? 0 : 320 },
    );
  }
  window.HarbourBackend = {
    close,
    get active() {
      return Boolean(active);
    },
    async play(host, flow, { previewBeat = null, onBeat = () => {} } = {}) {
      close();
      const token = generation,
        view = frame(host, flow);
      if (previewBeat !== null) {
        beat(view, flow, previewBeat);
        return;
      }
      for (let i = 0; i < flow.beats.length; i++) {
        if (token !== generation) return;
        beat(view, flow, i);
        onBeat(i);
        // Short waits keep Close and navigation responsive without losing the beat's full dwell.
        const until = performance.now() + flow.beats[i].seconds * 1000;
        while (performance.now() < until && token === generation)
          await wait(Math.min(100, until - performance.now()));
      }
      if (token === generation) close();
    },
  };
})();
