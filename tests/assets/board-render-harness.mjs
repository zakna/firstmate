// Render a built bearings board's shipped inline script under a minimal DOM
// shim and print what the renderer actually produced, so board behavior is
// asserted through the real template rather than by reading its source.
//
// Usage: node board-render-harness.mjs <built-board.html>
// Optional environment, for the appearance toggle:
//   BOARD_RENDER_STORED_THEME  value already remembered in browser storage
//   BOARD_RENDER_NO_STORAGE=1  browser storage is unavailable
//   BOARD_RENDER_CLICK=<id>    click that element once the page has rendered
// Prints one JSON document:
//   { stats:[{n,label}], captains_call:[text], underway:[{title,sub,badges}],
//     charted:[{title,sub,badges,pickable}], empty, more, error,
//     calls:[{key,badges,title,ctx:[{k,v}],questions:[{n,text,options,
//       rec_option,rec_line}],detail:{open,summary,body}|null,pr,options,
//       freeform}],
//     theme:{attribute,light_pressed,dark_pressed,stored} }
import { readFileSync } from "node:fs";

const html = readFileSync(process.argv[2], "utf8");

class Node {
  constructor(tag) {
    this.tagName = tag;
    this.className = "";
    this.children = [];
    this.attributes = {};
    this._text = "";
    this.hidden = false;
    this.disabled = false;
    this.innerHTML = "";
    this.parentNode = null;
    this.type = "";
    this.value = "";
    this.checked = false;
    this.listeners = {};
    this.classList = {
      add: (c) => { this.className = (this.className + " " + c).trim(); },
      contains: (c) => this.className.split(/\s+/).includes(c),
      remove: (c) => { this.className = this.className.split(/\s+/).filter((x) => x && x !== c).join(" "); },
      toggle: (c, on) => {
        const want = on === undefined ? !this.classList.contains(c) : !!on;
        if (want && !this.classList.contains(c)) this.classList.add(c);
        if (!want) this.classList.remove(c);
        return want;
      },
    };
  }
  get textContent() {
    return this.children.length
      ? this.children.map((c) => c.textContent).join("")
      : this._text;
  }
  set textContent(v) { this._text = String(v); this.children = []; }
  appendChild(n) { n.parentNode = this; this.children.push(n); return n; }
  setAttribute(k, v) { this.attributes[k] = String(v); }
  removeAttribute(k) { delete this.attributes[k]; }
  getAttribute(k) { return k in this.attributes ? this.attributes[k] : null; }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  dispatch(type) { for (const fn of this.listeners[type] || []) fn({ type, preventDefault() {} }); }
  querySelectorAll(sel) {
    const want = sel.replace(/^\./, "").replace(/:checked$/, "");
    const checkedOnly = sel.endsWith(":checked");
    const out = [];
    const walk = (n) => {
      for (const c of n.children) {
        if (c.className.split(/\s+/).includes(want) && (!checkedOnly || c.checked)) out.push(c);
        walk(c);
      }
    };
    walk(this);
    return out;
  }
}

const byId = new Map();
const dataNode = new Node("script");
dataNode.textContent = html
  .split('<script id="bearings-data" type="application/json">')[1]
  .split("</script>")[0];
byId.set("bearings-data", dataNode);

const root = new Node("html");
globalThis.document = {
  documentElement: root,
  createElement: (tag) => new Node(tag),
  // Lazily mint any element the page asks for: the shim tracks whatever ids
  // the shipped template actually uses instead of pinning a fixed list.
  getElementById: (id) => {
    if (!byId.has(id)) {
      const n = new Node("div");
      new Node("div").appendChild(n);
      byId.set(id, n);
    }
    return byId.get(id);
  },
  querySelector: (sel) => {
    const id = "sel:" + sel;
    if (!byId.has(id)) byId.set(id, new Node("div"));
    return byId.get(id);
  },
};
const storage = new Map();
if (process.env.BOARD_RENDER_STORED_THEME) storage.set("fm-bearings-board.theme", process.env.BOARD_RENDER_STORED_THEME);
globalThis.window = {};
if (process.env.BOARD_RENDER_NO_STORAGE !== "1") {
  globalThis.window.localStorage = {
    getItem: (k) => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => { storage.set(k, String(v)); },
  };
}
globalThis.TextEncoder = TextEncoder;

const script = html.slice(html.indexOf("<script>") + "<script>".length, html.lastIndexOf("</script>"));
new Function(script)();
if (process.env.BOARD_RENDER_CLICK) document.getElementById(process.env.BOARD_RENDER_CLICK).dispatch("click");

const badgesOf = (row) =>
  row.children
    .filter((c) => c.className.includes("fm-badge"))
    .map((c) => ({ tone: c.className.replace(/.*fm-badge--/, "").trim(), text: c.textContent }));

const strip = byId.get("bb-stats") || new Node("div");
const stats = strip.children.map((t) => ({
  n: Number(t.children.find((c) => c.className.includes("bb-stat__num"))?.textContent),
  label: t.children.find((c) => c.className.includes("bb-stat__label"))?.textContent,
}));

const rowsOf = (container) =>
  container.children
    .filter((r) => r.className.split(/\s+/).includes("bb-row"))
    .map((row) => {
      const main = row.children.find((c) => c.className.includes("bb-row__main"));
      return {
        title: main?.children.find((c) => c.className.includes("bb-row__title"))?.textContent ?? "",
        sub: main?.children.find((c) => c.className.includes("bb-row__sub"))?.textContent ?? "",
        badges: badgesOf(row),
        pickable: row.children.some((c) => c.className.includes("bb-pick") && !c.className.includes("spacer")),
      };
    });

const uw = byId.get("bb-underway") || new Node("div");
const underway = rowsOf(uw);
const captains_call = (byId.get("bb-call") || new Node("div")).children
  .filter((n) => n.className.split(/\s+/).includes("bb-decision"))
  .map((n) => n.textContent);

const ch = byId.get("bb-charted") || new Node("div");
const charted = rowsOf(ch);
// A fail-closed render replaces the page body instead of the board sections, so
// surface it rather than reporting an empty board as a successful render.
const errorText = [...byId.entries()]
  .filter(([k]) => k.startsWith("sel:"))
  .flatMap(([, n]) => n.children.map((c) => c.textContent))
  .join(" ");
const empty = ch.children.filter((c) => c.className.includes("bb-empty")).map((c) => c.textContent);
const more = ch.children.filter((c) => c.className.includes("bb-morechip")).map((c) => c.textContent);

// Captain's Call cards, read from the deck exactly as the renderer built them.
const findAll = (n, cls) => {
  const out = [];
  const walk = (x) => { for (const c of x.children) { if (c.className.split(/\s+/).includes(cls)) out.push(c); walk(c); } };
  walk(n);
  return out;
};
const findOne = (n, cls) => findAll(n, cls)[0];
const deck = byId.get("bb-call") || new Node("div");
const calls = deck.children
  .filter((c) => c.className.split(/\s+/).includes("bb-decision"))
  .map((card) => {
    const form = findAll(card, "bb-opts")[0]?.parentNode;
    const det = findOne(card, "bb-detail");
    return {
      key: form?.getAttribute("data-lavish-question") ?? null,
      badges: badgesOf(findOne(card, "bb-decision__top") || new Node("div")),
      title: findOne(card, "bb-decision__title")?.textContent ?? "",
      ctx: findAll(card, "bb-ctx__row").map((r) => ({
        k: findOne(r, "bb-ctx__k")?.textContent, v: findOne(r, "bb-ctx__v")?.textContent })),
      questions: findAll(card, "bb-q").map((q) => ({
        n: findOne(q, "bb-q__n")?.textContent,
        text: findOne(q, "bb-q__text")?.textContent,
        // a chip keeps its label as its own text; a rec chip appends a marker child
        options: findAll(q, "bb-chip").map((c) => c._text),
        rec_option: findAll(q, "bb-chip--rec").map((c) => c._text),
        rec_line: findOne(q, "bb-q__rec")?.textContent ?? null,
      })),
      detail: det ? {
        open: det.getAttribute("open") !== null,
        summary: findOne(det, "bb-detail__sum")?.textContent,
        body: findOne(det, "bb-detail__body")?.textContent,
      } : null,
      pr: findOne(card, "bb-decision__link")?.textContent ?? null,
      options: findAll(card, "bb-opt").map((o) => o.children.find((c) => c.tagName === "input")?.value),
      freeform: findAll(card, "bb-freeform").length > 0,
    };
  });

const theme = {
  attribute: root.getAttribute("data-theme"),
  light_pressed: byId.get("bb-theme-light")?.getAttribute("aria-pressed") ?? null,
  dark_pressed: byId.get("bb-theme-dark")?.getAttribute("aria-pressed") ?? null,
  stored: storage.has("fm-bearings-board.theme") ? storage.get("fm-bearings-board.theme") : null,
};

process.stdout.write(
  JSON.stringify({ stats, captains_call, underway, charted, empty, more, error: errorText, calls, theme }) + "\n");
