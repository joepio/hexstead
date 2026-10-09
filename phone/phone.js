// Hexstead on your phone: your cards, and every choice you make on your turn.
// The game sends a full "view" after each change; this page only draws it and
// sends back what you tapped. The game checks every move.
(function () {
  const S = 100; // board units to SVG units
  const RES = ["timber", "clay", "wool", "grain", "ore"];
  const icon = (res) => `<img class="ico" src="art/${res}.png" alt="">`;
  const LABEL = { timber: "Timber", clay: "Clay", wool: "Wool", grain: "Grain", ore: "Ore" };
  const FIELD = { timber: "#527f34", clay: "#c97b4c", wool: "#a2cf5c", grain: "#e2b04a", ore: "#8f8ba3" };
  const BUILDS = [
    { kind: "road", name: "Road", what: "Connects your hamlets" },
    { kind: "hamlet", name: "Hamlet", what: "1 point" },
    { kind: "town", name: "Town", what: "Upgrade a hamlet, 2 points" },
    { kind: "festival", name: "Festival", what: "1 point, twice per game" },
  ];
  const $ = (id) => document.getElementById(id);
  const svgNS = "http://www.w3.org/2000/svg";

  let view = null;
  let mode = null; // "road" | "hamlet" | "town" while picking a spot
  let give = null, get = null;
  let lastHand = null;

  const game = GameNight.connect(onMessage, (status) => {
    if (status === "reconnecting") $("turn-line").textContent = "Reconnecting to the table…";
  });

  function onMessage(data) {
    if (data.t === "error") return toast(data.text);
    if (data.t !== "view") return;
    view = data;
    if (!view.you.turn || view.phase !== "build") mode = null;
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

  function el(tag, attrs, parent) {
    const node = document.createElementNS(svgNS, tag);
    for (const [k, v] of Object.entries(attrs || {})) node.setAttribute(k, v);
    if (parent) parent.appendChild(node);
    return node;
  }

  function hexPoints(x, y, r) {
    const pts = [];
    for (let c = 0; c < 6; c++) {
      const a = ((60 * c - 30) * Math.PI) / 180;
      pts.push(`${x + Math.cos(a) * r},${y + Math.sin(a) * r}`);
    }
    return pts.join(" ");
  }

  function pips(n) {
    return n ? 6 - Math.abs(7 - n) : 0;
  }

  function houseShape(x, y, town) {
    const w = town ? 26 : 19, h = town ? 24 : 18;
    if (town) {
      return `${x - w},${y + h * 0.7} ${x - w},${y - h * 0.5} ${x - w * 0.2},${y - h * 0.5} ${x - w * 0.2},${y - h * 1.2} ${x + w * 0.4},${y - h * 1.6} ${x + w},${y - h * 1.2} ${x + w},${y + h * 0.7}`;
    }
    return `${x - w},${y + h * 0.7} ${x - w},${y - h * 0.2} ${x},${y - h} ${x + w},${y - h * 0.2} ${x + w},${y + h * 0.7}`;
  }

  /// What the board lets you tap right now, if anything.
  function targets() {
    if (!view || !view.you.turn) return null;
    const legal = view.legal;
    if (view.phase === "setup_hamlet") return { kind: "hamlet", ids: legal.hamlet || [], text: "Tap a glowing corner to found a hamlet." };
    if (view.phase === "setup_road") return { kind: "road", ids: legal.road || [], text: "Tap a glowing side to lay a road." };
    if (view.phase === "storm") return { kind: "storm", ids: legal.storm || [], text: "Tap a field to move the storm. You take a card from a neighbour." };
    if (view.phase === "build" && mode) {
      const text = { road: "Tap where your road goes.", hamlet: "Tap a corner for your hamlet.", town: "Tap a hamlet to make it a town." }[mode];
      return { kind: mode, ids: legal[mode] || [], text };
    }
    return null;
  }

  function drawBoard() {
    const svg = $("board");
    svg.replaceChildren();
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const v of view.verts) {
      minX = Math.min(minX, v.x); maxX = Math.max(maxX, v.x);
      minY = Math.min(minY, v.y); maxY = Math.max(maxY, v.y);
    }
    const m = 0.35;
    svg.setAttribute("viewBox", `${(minX - m) * S} ${(minY - m) * S} ${(maxX - minX + 2 * m) * S} ${(maxY - minY + 2 * m) * S}`);
    const pick = targets();
    const colors = view.players.map((p) => p.color);
    const roll = view.dice ? view.dice[0] + view.dice[1] : null;

    for (const t of view.tiles) {
      el("polygon", { points: hexPoints(t.x * S, t.y * S, 104), fill: "#e7d29b" }, svg);
    }
    for (const t of view.tiles) {
      const x = t.x * S, y = t.y * S;
      el("polygon", { points: hexPoints(x, y, 96), fill: t.res ? FIELD[t.res] : "#5fb3c9", stroke: "#3a2a1c", "stroke-opacity": 0.25, "stroke-width": 3 }, svg);
      if (t.res) {
        el("image", { href: `art/${t.res}.png`, x: x - 42, y: y - 86, width: 84, height: 84 }, svg);
        const hot = pips(t.num) === 5;
        el("circle", { cx: x, cy: y + 16, r: 28, fill: "#f8f1dc", stroke: roll === t.num && t.id !== view.storm ? "#fff" : "none", "stroke-width": 8 }, svg);
        const num = el("text", { x, y: y + 28, "text-anchor": "middle", class: "tile-num", fill: hot ? "#b8291e" : "#1f1a16" }, svg);
        num.textContent = t.num;
      }
      if (t.id === view.storm) {
        const cloud = el("text", { x, y: y + 32, "text-anchor": "middle", "font-size": 54 }, svg);
        cloud.textContent = "⛈️";
      }
    }
    for (const e of view.edges) {
      if (!e.owner) continue;
      const mx = (e.x1 + e.x2) / 2, my = (e.y1 + e.y2) / 2, k = 0.78;
      const line = { x1: (mx + (e.x1 - mx) * k) * S, y1: (my + (e.y1 - my) * k) * S, x2: (mx + (e.x2 - mx) * k) * S, y2: (my + (e.y2 - my) * k) * S, "stroke-linecap": "round" };
      el("line", { ...line, stroke: "#f8f1dc", "stroke-width": 17 }, svg);
      el("line", { ...line, stroke: colors[e.owner - 1], "stroke-width": 11 }, svg);
    }
    for (const v of view.verts) {
      if (!v.owner) continue;
      el("polygon", { points: houseShape(v.x * S, v.y * S, v.kind === "town"), fill: colors[v.owner - 1], stroke: "#f8f1dc", "stroke-width": 4, "stroke-linejoin": "round" }, svg);
    }

    $("pick").hidden = !pick;
    if (!pick) return;
    $("pick").textContent = pick.text;
    const ids = new Set(pick.ids);
    const action = pick.kind === "storm" ? "storm" : pick.kind;
    if (pick.kind === "storm") {
      for (const t of view.tiles) {
        if (!ids.has(t.id)) continue;
        const poly = el("polygon", { points: hexPoints(t.x * S, t.y * S, 90), class: "target target-tile" }, svg);
        poly.addEventListener("click", () => send({ a: "storm", id: t.id }));
      }
    } else if (pick.kind === "road") {
      for (const e of view.edges) {
        if (!ids.has(e.id)) continue;
        const g = el("g", { class: "target" }, svg);
        const pos = { x1: e.x1 * S, y1: e.y1 * S, x2: e.x2 * S, y2: e.y2 * S };
        el("line", { ...pos, class: "target-edge" }, g);
        el("line", { ...pos, class: "target-hit" }, g);
        g.addEventListener("click", () => {
          mode = null;
          send({ a: "road", id: e.id });
        });
      }
    } else {
      for (const v of view.verts) {
        if (!ids.has(v.id)) continue;
        const g = el("g", { class: "target" }, svg);
        el("circle", { cx: v.x * S, cy: v.y * S, r: 15, class: "target-vert" }, g);
        el("circle", { cx: v.x * S, cy: v.y * S, r: 34, class: "target-hit" }, g);
        g.addEventListener("click", () => {
          mode = null;
          send({ a: action, id: v.id });
        });
      }
    }
  }

  function drawHand() {
    const hand = $("hand");
    hand.replaceChildren();
    for (const res of RES) {
      const n = view.you.hand[res] || 0;
      const card = document.createElement("div");
      card.className = "card" + (n === 0 ? " zero" : "");
      if (lastHand && n > (lastHand[res] || 0)) card.classList.add("bump");
      card.style.setProperty("--res", FIELD[res]);
      card.innerHTML = `<div class="label">${LABEL[res]}</div><img class="pic" src="art/${res}.png" alt=""><div class="count">${n}</div>`;
      hand.appendChild(card);
    }
    const snapshot = { ...view.you.hand };
    setTimeout(() => {
      for (const c of hand.querySelectorAll(".bump")) c.classList.remove("bump");
    }, 500);
    lastHand = snapshot;
  }

  function button(cls, text, onClick, disabled) {
    const b = document.createElement("button");
    b.className = cls;
    b.innerHTML = text;
    b.disabled = !!disabled;
    b.addEventListener("click", onClick);
    return b;
  }

  function drawActions() {
    const box = $("actions");
    box.replaceChildren();
    const you = view.you;
    if (view.phase === "over") {
      const w = view.players[view.winner - 1];
      const div = document.createElement("div");
      div.className = "winner";
      div.innerHTML = `<b></b>A new island rises in a moment.`;
      div.querySelector("b").textContent = view.winner === you.index ? "You win! 🎉" : `${w.name} wins!`;
      box.appendChild(div);
      return;
    }
    if (!you.turn) {
      const p = view.players[view.turn - 1];
      const div = document.createElement("div");
      div.className = "waiting";
      div.textContent = `${p.name} is playing. Your cards are safe here.`;
      box.appendChild(div);
      return;
    }
    if (view.phase === "roll") {
      box.appendChild(button("main wide", "🎲 Roll the dice", () => send({ a: "roll" })));
      return;
    }
    if (view.phase !== "build") return;
    const builds = document.createElement("div");
    builds.className = "builds";
    for (const b of BUILDS) {
      const legal = view.legal[b.kind];
      const allowed = b.kind === "festival" ? legal === true : Array.isArray(legal) && legal.length > 0;
      const node = button("build" + (mode === b.kind ? " on" : ""), "", () => {
        if (b.kind === "festival") return send({ a: "festival" });
        mode = mode === b.kind ? null : b.kind;
        render();
      }, !allowed);
      const cost = Object.entries(view.cost[b.kind]).map(([res, n]) => `<span>${icon(res)}${n}</span>`).join("");
      node.innerHTML = `<img class="pic" src="art/${b.kind}.png" alt=""><span class="text"><b>${b.name}</b><small>${b.what}</small><span class="cost">${cost}</span></span>`;
      builds.appendChild(node);
    }
    box.appendChild(builds);
    const row = document.createElement("div");
    row.className = "row";
    row.appendChild(button("ghost", "⇄ Trade", () => openTrade()));
    row.appendChild(button("main", "End turn", () => {
      mode = null;
      $("trade").hidden = true;
      send({ a: "end" });
    }));
    box.appendChild(row);
  }

  function openTrade() {
    give = get = null;
    $("trade").hidden = false;
    drawTrade();
    $("trade").scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  function drawTrade() {
    if ($("trade").hidden || !view) return;
    if (!view.you.turn || view.phase !== "build") {
      $("trade").hidden = true;
      return;
    }
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

  $("trade-close").addEventListener("click", () => ($("trade").hidden = true));
  $("trade-go").addEventListener("click", () => {
    if (give && get) send({ a: "bank", give, get });
    give = get = null;
  });

  function drawTable() {
    const list = $("players");
    list.replaceChildren();
    view.players.forEach((p, i) => {
      const li = document.createElement("li");
      if (view.turn === i + 1 && view.phase !== "over") li.className = "turn";
      li.innerHTML = `<span class="dot"></span><span class="name"></span><span class="meta"></span><span class="vp"></span>`;
      li.querySelector(".dot").style.background = p.color;
      li.querySelector(".name").textContent = p.name + (i + 1 === view.you.index ? " (you)" : "");
      li.querySelector(".meta").textContent = `${p.cards} cards`;
      li.querySelector(".vp").textContent = p.vp;
      list.appendChild(li);
    });
    const log = $("log");
    log.replaceChildren();
    for (const line of view.log.slice(0, 4)) {
      const li = document.createElement("li");
      li.textContent = line;
      log.appendChild(li);
    }
  }

  function turnLine() {
    const you = view.you;
    const p = view.players[view.turn - 1];
    if (view.phase === "over") return "Game over";
    if (!you.turn) return `${p.name}'s turn`;
    return {
      setup_hamlet: "Your turn: found a hamlet",
      setup_road: "Your turn: lay a road",
      roll: "Your turn: roll the dice",
      storm: "Your turn: move the storm",
      build: view.dice ? `You rolled ${view.dice[0] + view.dice[1]}. Build, trade or end` : "Build, trade or end",
    }[view.phase];
  }

  function render() {
    const you = view.you;
    $("you-dot").style.background = you.color;
    $("you-name").textContent = you.name;
    const line = $("turn-line");
    line.textContent = turnLine();
    line.classList.toggle("go", you.turn && view.phase !== "over");
    $("you-vp").textContent = you.vp;
    $("goal").textContent = "/" + view.goal;
    drawBoard();
    drawHand();
    drawActions();
    drawTrade();
    drawTable();
  }
})();
