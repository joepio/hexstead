// Hexstead on your phone. The TV is where the game happens; the phone stays
// quiet and only asks for something when it is your move, plus your cards,
// which are the one secret on the table. The game sends a full "view" after
// each change; this page draws it and sends back what you chose. The game
// checks every move.
(function () {
  const S = 100; // board units to SVG units
  const RES = ["timber", "clay", "wool", "grain", "ore"];
  const icon = (res) => `<img class="ico" src="art/${res}.png" alt="">`;
  const LABEL = { timber: "Timber", clay: "Clay", wool: "Wool", grain: "Grain", ore: "Ore" };
  const FIELD = { timber: "#527f34", clay: "#c97b4c", wool: "#a2cf5c", grain: "#e2b04a", ore: "#8f8ba3" };
  const BUILDS = [
    { kind: "road", name: "Road", what: "Joins your hamlets" },
    { kind: "hamlet", name: "Hamlet", what: "1 point" },
    { kind: "town", name: "Town", what: "Upgrade a hamlet, 2 points" },
    { kind: "festival", name: "Festival", what: "1 point" },
  ];
  const $ = (id) => document.getElementById(id);
  const svgNS = "http://www.w3.org/2000/svg";

  let view = null;
  let mode = null; // "road" | "hamlet" | "town" while picking a spot to build
  let trading = false;
  let give = null, get = null;
  let lastHand = null;
  let chosen = null; // the spot the picker has selected
  let aimed = null; // what the TV last heard we are pointing at
  let wasMyMove = false;

  const game = GameNight.connect(onMessage, (status) => {
    if (status === "reconnecting") showCalm("Reconnecting to the table…");
  });

  function onMessage(data) {
    if (data.t === "error") return toast(data.text);
    if (data.t !== "view") return;
    view = data;
    if (!view.you.turn || view.phase !== "build") mode = null, trading = false;
    if (mode && !(view.legal[mode] || []).length) mode = null;
    render();
  }

  function send(action) {
    game.send(action);
  }

  let toastTimer;
  function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (el.hidden = true), 2600);
  }

  function svg(tag, attrs, parent) {
    const node = document.createElementNS(svgNS, tag);
    for (const [k, v] of Object.entries(attrs || {})) node.setAttribute(k, v);
    if (parent) parent.appendChild(node);
    return node;
  }

  function button(cls, html, onClick, disabled) {
    const b = document.createElement("button");
    b.className = cls;
    b.innerHTML = html;
    b.disabled = !!disabled;
    b.addEventListener("click", onClick);
    return b;
  }

  function hexPoints(x, y, r) {
    const pts = [];
    for (let c = 0; c < 6; c++) {
      const a = ((60 * c - 30) * Math.PI) / 180;
      pts.push(`${x + Math.cos(a) * r},${y + Math.sin(a) * r}`);
    }
    return pts.join(" ");
  }

  function houseShape(x, y, town) {
    const w = town ? 26 : 19, h = town ? 24 : 18;
    if (town) {
      return `${x - w},${y + h * 0.7} ${x - w},${y - h * 0.5} ${x - w * 0.2},${y - h * 0.5} ${x - w * 0.2},${y - h * 1.2} ${x + w * 0.4},${y - h * 1.6} ${x + w},${y - h * 1.2} ${x + w},${y + h * 0.7}`;
    }
    return `${x - w},${y + h * 0.7} ${x - w},${y - h * 0.2} ${x},${y - h} ${x + w},${y - h * 0.2} ${x + w},${y + h * 0.7}`;
  }

  // --- What the game needs from you right now ----------------------------

  /// A spot to pick on the island, or null.
  function picking() {
    if (!view || !view.you.turn) return null;
    const legal = view.legal;
    if (view.phase === "setup_hamlet") return { kind: "hamlet", ids: legal.hamlet || [], title: "Found a hamlet" };
    if (view.phase === "setup_road") return { kind: "road", ids: legal.road || [], title: "Lay a road" };
    if (view.phase === "storm") return { kind: "storm", ids: legal.storm || [], title: "Move the storm" };
    if (view.phase === "build" && mode) {
      const title = { road: "Build a road", hamlet: "Build a hamlet", town: "Upgrade to a town" }[mode];
      return { kind: mode, ids: legal[mode] || [], title, back: true };
    }
    return null;
  }

  /// Where each pickable thing sits, in board units.
  function spot(kind, id) {
    if (kind === "storm") {
      const t = view.tiles.find((t) => t.id === id);
      return { x: t.x, y: t.y };
    }
    if (kind === "road") {
      const e = view.edges.find((e) => e.id === id);
      return { x: (e.x1 + e.x2) / 2, y: (e.y1 + e.y2) / 2 };
    }
    const v = view.verts.find((v) => v.id === id);
    return { x: v.x, y: v.y };
  }

  function aim(kind, id) {
    const key = id === null ? null : `${kind}:${id}`;
    if (key === aimed) return;
    aimed = key;
    send({ a: "aim", kind, id: id === null ? 0 : id });
  }

  // --- Screens -------------------------------------------------------------

  function show(which) {
    for (const id of ["calm", "ask", "picker", "trade"]) $(id).hidden = id !== which;
    document.body.dataset.screen = which;
  }

  function showCalm(text) {
    $("calm-text").textContent = text;
    show("calm");
  }

  function render() {
    const you = view.you;
    $("you-dot").style.background = you.color;
    $("you-name").textContent = you.name;
    $("you-vp").textContent = you.vp;
    $("goal").textContent = "/" + view.goal;
    drawHand();

    const myMove = you.turn && view.phase !== "over";
    if (myMove && !wasMyMove && navigator.vibrate) navigator.vibrate([60, 40, 60]);
    wasMyMove = myMove;

    const pick = picking();
    if (!pick) {
      chosen = null;
      if (aimed !== null) aim("", null);
    }
    if (view.phase === "over") {
      const w = view.players[view.winner - 1];
      return showCalm(view.winner === you.index ? "You win! 🎉" : `${w.name} wins! Watch the TV for the next island.`);
    }
    if (!you.turn) return showCalm("Watch the TV");
    if (pick) return drawPicker(pick);
    if (trading) return drawTrade();
    drawAsk();
  }

  function drawAsk() {
    show("ask");
    const body = $("ask-body");
    body.replaceChildren();
    if (view.phase === "roll") {
      $("ask-title").textContent = "Your turn";
      $("ask-hint").textContent = "";
      body.appendChild(button("main wide huge roll", "🎲 Roll the dice", () => send({ a: "roll" })));
      return;
    }
    if (view.phase !== "build") return showCalm("Watch the TV");
    const sum = view.dice ? view.dice[0] + view.dice[1] : null;
    $("ask-title").textContent = sum ? `You rolled ${sum}` : "Your turn";
    const builds = BUILDS.filter((b) => {
      const legal = view.legal[b.kind];
      return b.kind === "festival" ? legal === true : Array.isArray(legal) && legal.length > 0;
    });
    $("ask-hint").textContent = builds.length ? "Build something, or end your turn." : "Nothing to build yet. Trade, or end your turn.";
    const list = document.createElement("div");
    list.className = "builds";
    for (const b of builds) {
      const node = button("build", "", () => {
        if (b.kind === "festival") return send({ a: "festival" });
        mode = b.kind;
        chosen = null;
        render();
      });
      const cost = Object.entries(view.cost[b.kind]).map(([res, n]) => `<span>${icon(res)}${n}</span>`).join("");
      node.innerHTML = `<img class="pic" src="art/${b.kind}.png" alt=""><span class="text"><b>${b.name}</b><small>${b.what}</small><span class="cost">${cost}</span></span>`;
      list.appendChild(node);
    }
    body.appendChild(list);
    const canTrade = RES.some((res) => (view.you.hand[res] || 0) >= view.rates[res]);
    if (canTrade) {
      body.appendChild(button("ghost wide", "⇄ Trade with the bank", () => {
        trading = true;
        give = get = null;
        render();
      }));
    }
    body.appendChild(button("main wide huge", "End turn", () => send({ a: "end" })));
  }

  // --- Picking a spot ------------------------------------------------------

  let current = null; // {kind, ids, order: [{id, x, y}]}

  function drawPicker(pick) {
    show("picker");
    $("pick-title").textContent = pick.title;
    $("cancel").hidden = !pick.back;
    const order = pick.ids.map((id) => ({ id, ...spot(pick.kind, id) }));
    // Reading order: top to bottom, then left to right.
    order.sort((a, b) => (Math.abs(a.y - b.y) > 0.3 ? a.y - b.y : a.x - b.x));
    current = { kind: pick.kind, ids: pick.ids, order };
    if (!order.some((o) => o.id === chosen)) chosen = order.length ? order[Math.floor(order.length / 2)].id : null;
    drawBoard();
    aim(pick.kind, chosen);
  }

  function select(id) {
    if (id === chosen) return;
    chosen = id;
    drawBoard();
    aim(current.kind, id);
    if (navigator.vibrate) navigator.vibrate(8);
  }

  function step(dir) {
    if (!current || !current.order.length) return;
    const i = current.order.findIndex((o) => o.id === chosen);
    const n = current.order.length;
    select(current.order[(i + dir + n) % n].id);
  }

  function drawBoard() {
    const el = $("board");
    el.replaceChildren();
    const { kind, ids, order } = current;
    // Frame the spots you can pick, so a few close spots fill the screen.
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    const frame = order.length ? order : view.verts;
    for (const p of frame) {
      minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
      minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
    }
    const pad = 0.6;
    let w = Math.max(maxX - minX + 2 * pad, 3.6), h = Math.max(maxY - minY + 2 * pad, 3.6);
    // Match the shape of the space the board has on this phone.
    const aspect = (el.clientHeight || 1) / (el.clientWidth || 1);
    if (h / w < aspect) h = w * aspect;
    else w = h / aspect;
    const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    el.setAttribute("viewBox", `${(cx - w / 2) * S} ${(cy - h / 2) * S} ${w * S} ${h * S}`);
    const colors = view.players.map((p) => p.color);

    for (const t of view.tiles) svg("polygon", { points: hexPoints(t.x * S, t.y * S, 104), fill: "#e7d29b" }, el);
    for (const t of view.tiles) {
      const x = t.x * S, y = t.y * S;
      svg("polygon", { points: hexPoints(x, y, 96), fill: t.res ? FIELD[t.res] : "#5fb3c9", stroke: "#3a2a1c", "stroke-opacity": 0.25, "stroke-width": 3 }, el);
      if (t.res) {
        svg("image", { href: `art/${t.res}.png`, x: x - 42, y: y - 86, width: 84, height: 84 }, el);
        svg("circle", { cx: x, cy: y + 16, r: 28, fill: "#f8f1dc" }, el);
        const num = svg("text", { x, y: y + 28, "text-anchor": "middle", class: "tile-num", fill: t.num === 6 || t.num === 8 ? "#b8291e" : "#1f1a16" }, el);
        num.textContent = t.num;
      }
      if (t.id === view.storm) {
        const cloud = svg("text", { x, y: y + 32, "text-anchor": "middle", "font-size": 54 }, el);
        cloud.textContent = "⛈️";
      }
    }
    for (const e of view.edges) {
      if (!e.owner) continue;
      const mx = (e.x1 + e.x2) / 2, my = (e.y1 + e.y2) / 2, k = 0.78;
      const line = { x1: (mx + (e.x1 - mx) * k) * S, y1: (my + (e.y1 - my) * k) * S, x2: (mx + (e.x2 - mx) * k) * S, y2: (my + (e.y2 - my) * k) * S, "stroke-linecap": "round" };
      svg("line", { ...line, stroke: "#f8f1dc", "stroke-width": 17 }, el);
      svg("line", { ...line, stroke: colors[e.owner - 1], "stroke-width": 11 }, el);
    }
    for (const v of view.verts) {
      if (!v.owner) continue;
      svg("polygon", { points: houseShape(v.x * S, v.y * S, v.kind === "town"), fill: colors[v.owner - 1], stroke: "#f8f1dc", "stroke-width": 4, "stroke-linejoin": "round" }, el);
    }

    const set = new Set(ids);
    for (const o of order) {
      const on = o.id === chosen;
      const cls = "target" + (on ? " chosen" : "");
      if (kind === "storm") {
        const t = view.tiles.find((t) => t.id === o.id);
        svg("polygon", { points: hexPoints(t.x * S, t.y * S, on ? 92 : 80), class: cls + " target-tile" }, el);
      } else if (kind === "road") {
        const e = view.edges.find((e) => e.id === o.id);
        svg("line", { x1: e.x1 * S, y1: e.y1 * S, x2: e.x2 * S, y2: e.y2 * S, class: cls + " target-edge" }, el);
      } else if (set.has(o.id)) {
        // Dots grow with the view, so a whole island still shows them clearly.
        const r = Math.max(14, w * S * 0.022);
        svg("circle", { cx: o.x * S, cy: o.y * S, r: on ? r * 2 : r, class: cls + " target-vert" }, el);
      }
    }
    $("place").disabled = chosen === null;
    $("place").textContent = { storm: "Move the storm here", road: "Lay the road here", hamlet: "Found it here", town: "Make this a town" }[kind];
    const single = order.length <= 1;
    $("prev").disabled = $("next").disabled = single;
  }

  // Touch anywhere: the nearest spot you can pick is chosen, and sliding your
  // finger moves the choice. No need to hit a small dot.
  function nearestAt(evt) {
    if (!current || !current.order.length) return null;
    const el = $("board");
    const pt = el.createSVGPoint();
    pt.x = evt.clientX;
    pt.y = evt.clientY;
    const p = pt.matrixTransform(el.getScreenCTM().inverse());
    let best = null, bestD = Infinity;
    for (const o of current.order) {
      const d = (o.x * S - p.x) ** 2 + (o.y * S - p.y) ** 2;
      if (d < bestD) (bestD = d), (best = o.id);
    }
    return best;
  }
  let dragging = false;
  $("board").addEventListener("pointerdown", (evt) => {
    dragging = true;
    $("board").setPointerCapture(evt.pointerId);
    const id = nearestAt(evt);
    if (id !== null) select(id);
  });
  $("board").addEventListener("pointermove", (evt) => {
    if (!dragging) return;
    const id = nearestAt(evt);
    if (id !== null) select(id);
  });
  for (const type of ["pointerup", "pointercancel"]) $("board").addEventListener(type, () => (dragging = false));

  $("prev").addEventListener("click", () => step(-1));
  $("next").addEventListener("click", () => step(1));
  $("place").addEventListener("click", () => {
    if (!current || chosen === null) return;
    const id = chosen;
    const kind = current.kind;
    mode = null;
    chosen = null;
    send({ a: kind, id });
  });
  $("cancel").addEventListener("click", () => {
    mode = null;
    chosen = null;
    render();
  });

  // --- Cards and trading ---------------------------------------------------

  function drawHand() {
    const hand = $("hand");
    hand.replaceChildren();
    for (const res of RES) {
      const n = view.you.hand[res] || 0;
      const card = document.createElement("div");
      card.className = "card" + (n === 0 ? " zero" : "");
      if (lastHand && n > (lastHand[res] || 0)) card.classList.add("bump");
      card.style.setProperty("--res", FIELD[res]);
      card.innerHTML = `<img class="pic" src="art/${res}.png" alt=""><div class="count">${n}</div><div class="label">${LABEL[res]}</div>`;
      hand.appendChild(card);
    }
    setTimeout(() => {
      for (const c of hand.querySelectorAll(".bump")) c.classList.remove("bump");
    }, 600);
    lastHand = { ...view.you.hand };
  }

  function drawTrade() {
    show("trade");
    const market = view.market;
    $("trade-hint").textContent = `The bank takes 4 of a kind for 1, and ${LABEL[market]} at 2 for 1 this round.`;
    const giveBox = $("give"), getBox = $("get");
    giveBox.replaceChildren();
    getBox.replaceChildren();
    for (const res of RES) {
      const rate = view.rates[res];
      const can = (view.you.hand[res] || 0) >= rate;
      giveBox.appendChild(button("chip" + (give === res ? " on" : ""), `${rate}${icon(res)}`, () => {
        give = res;
        if (get === res) get = null;
        drawTrade();
      }, !can));
      getBox.appendChild(button("chip" + (get === res ? " on" : ""), `1${icon(res)}`, () => {
        get = res;
        drawTrade();
      }, res === give));
    }
    $("trade-go").disabled = !(give && get);
  }

  $("trade-close").addEventListener("click", () => {
    trading = false;
    render();
  });
  $("trade-go").addEventListener("click", () => {
    if (give && get) send({ a: "bank", give, get });
    give = get = null;
  });
})();
