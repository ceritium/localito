// Inline editing of .cell elements, and live refresh: /version is polled
// (file stats only) and, when something changed, the page refetches itself
// and swaps #live in place, flashing the cells that differ.
(() => {
  const token = () => document.querySelector("meta[name=csrf-token]")?.content || "";
  let pending = false;

  // Toolbar: selects, checkboxes and radios apply at once.
  for (const form of document.querySelectorAll("form[data-autosubmit]")) {
    form.addEventListener("change", (e) => {
      if (e.target.matches("select, input[type=radio]")) form.requestSubmit();
    });
    const menu = form.querySelector("details.locales");
    menu?.addEventListener("toggle", () => {
      if (!menu.open && menu.dataset.dirty) form.requestSubmit();
    });
    menu?.addEventListener("change", () => (menu.dataset.dirty = "1"));
  }

  document.addEventListener("click", (e) => {
    const cell = e.target.closest("#live .cell[data-editable='1']");
    if (!cell || cell.classList.contains("editing") || e.target.closest("a")) return;
    openEditor(cell);
  });

  // Import: a chosen file is read into the textarea, so no upload is needed.
  for (const input of document.querySelectorAll("input[type=file][data-fill]")) {
    input.addEventListener("change", async () => {
      const file = input.files[0];
      if (file) document.getElementById(input.dataset.fill).value = await file.text();
    });
  }

  // n / p move between missing cells, Enter edits the current one, / searches.
  const missingCells = () => [...document.querySelectorAll("#live .cell.is-missing[data-editable='1']")];
  let focusedCell = null;

  function focusCell(cell) {
    document.querySelector(".cell.current")?.classList.remove("current");
    focusedCell = cell?.dataset.cell || null;
    if (!cell) return;
    cell.classList.add("current");
    cell.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function step(dir, from) {
    const cells = missingCells();
    if (!cells.length) return null;
    const at = cells.findIndex((c) => c.dataset.cell === from);
    if (at === -1) return dir > 0 ? cells[0] : cells[cells.length - 1];
    return cells[(at + dir + cells.length) % cells.length];
  }

  document.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.target.closest?.("input, textarea, select")) return;
    if (e.key === "n" || e.key === "p") {
      e.preventDefault();
      focusCell(step(e.key === "n" ? 1 : -1, focusedCell));
    } else if (e.key === "Enter" && focusedCell) {
      const cell = document.querySelector(`#live [data-cell="${CSS.escape(focusedCell)}"]`);
      if (cell && !cell.classList.contains("editing")) {
        e.preventDefault();
        openEditor(cell);
      }
    } else if (e.key === "/") {
      e.preventDefault();
      document.querySelector(".toolbar input[type=search]")?.focus();
    }
  });

  function openEditor(cell) {
    focusCell(cell);
    const saved = cell.innerHTML;
    const missing = cell.dataset.missing === "1";
    cell.classList.add("editing");

    const area = document.createElement("textarea");
    area.value = missing ? "" : cell.dataset.original;
    area.rows = Math.min(10, Math.max(2, area.value.split("\n").length + 1));
    const save = Object.assign(document.createElement("button"), { type: "button", className: "primary", textContent: missing ? "Add" : "Save" });
    const discard = Object.assign(document.createElement("button"), { type: "button", textContent: "Discard" });
    const hint = Object.assign(document.createElement("span"), { className: "hint", textContent: missing ? "⌘↵ add and go to the next missing · Esc discard" : "⌘↵ save · Esc discard" });
    const error = Object.assign(document.createElement("p"), { className: "error" });
    const bar = Object.assign(document.createElement("div"), { className: "editor-bar" });
    bar.append(save, discard, hint);
    cell.replaceChildren(area, bar, error);
    area.focus();

    const close = () => {
      cell.classList.remove("editing");
      cell.innerHTML = saved;
      if (pending) refresh();
    };
    discard.addEventListener("click", close);
    area.addEventListener("keydown", (ev) => {
      if (ev.key === "Escape") close();
      if (ev.key === "Enter" && (ev.metaKey || ev.ctrlKey)) save.click();
    });
    save.addEventListener("click", async () => {
      save.disabled = true;
      const body = new URLSearchParams({
        _method: "patch", inline: "1", authenticity_token: token(),
        name: cell.dataset.name, locale: cell.dataset.locale, value: area.value,
        original: cell.dataset.original, was_missing: cell.dataset.missing,
      });
      // Filling a missing value moves on to the next one, to fill them in a row.
      const next = missing ? step(1, cell.dataset.cell) : null;
      const nextKey = next && next !== cell ? next.dataset.cell : null;
      try {
        const res = await fetch("/translation", { method: "POST", body, headers: { "X-CSRF-Token": token() } });
        if (res.ok) {
          cell.classList.remove("editing");
          await refresh();
          const target = nextKey && document.querySelector(`#live [data-cell="${CSS.escape(nextKey)}"]`);
          if (target) openEditor(target);
          else focusCell(document.querySelector(`#live [data-cell="${CSS.escape(cell.dataset.cell)}"]`));
          return;
        }
        error.textContent = await res.text();
      } catch (_) {
        error.textContent = "Couldn't reach the server.";
      }
      save.disabled = false;
    });
  }

  const live = () => document.getElementById("live");
  let version = live()?.dataset.version;
  let busy = false;

  async function tick() {
    if (!live() || busy || document.hidden) return;
    busy = true;
    try {
      const res = await fetch("/version", { cache: "no-store" });
      const latest = (await res.text()).trim();
      if (res.ok && latest !== version) {
        version = latest;
        await refresh();
      }
    } catch (_) {
      // Server restarting; try again on the next tick.
    } finally {
      busy = false;
    }
  }

  async function refresh() {
    if (document.querySelector(".cell.editing")) {
      pending = true;
      return;
    }
    pending = false;
    const res = await fetch(location.href, { cache: "no-store" });
    if (!res.ok) return;
    const doc = new DOMParser().parseFromString(await res.text(), "text/html");
    const next = doc.getElementById("live");
    const focusedKey = focusedCell;
    const current = live();
    if (!next || !current) return;
    version = next.dataset.version;
    const before = new Map([...current.querySelectorAll("[data-cell]")].map((el) => [el.dataset.cell, el.textContent]));
    current.innerHTML = next.innerHTML;
    for (const el of current.querySelectorAll("[data-cell]")) {
      if (before.has(el.dataset.cell) && before.get(el.dataset.cell) !== el.textContent) el.classList.add("flash");
    }
    const focused = focusedKey && current.querySelector(`[data-cell="${CSS.escape(focusedKey)}"]`);
    focused?.classList.add("current");
    const nav = doc.querySelector("header.top nav");
    if (nav) document.querySelector("header.top nav")?.replaceWith(nav);
  }

  setInterval(tick, 1500);
  document.addEventListener("visibilitychange", tick);
})();
