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
    menu?.addEventListener("change", (e) => {
      if (e.target.type === "checkbox") menu.dataset.dirty = "1";
    });
  }

  // Files sidebar: collapsed or not, remembered across pages.
  document.addEventListener("click", (e) => {
    if (!e.target.closest("[data-files-toggle]")) return;
    const hidden = document.documentElement.classList.toggle("files-collapsed");
    try { localStorage.setItem("localito.files", hidden ? "hidden" : "shown"); } catch {}
  });

  // Files sidebar: collapsible folders and a filter (GitHub-PR-like). The
  // collapse state and the filter query survive page reloads and refresh().
  const FILES_COLLAPSED_KEY = "localito.collapsed";
  let filesFilterQuery = "";

  const collapsedPaths = () => {
    try { return new Set(JSON.parse(localStorage.getItem(FILES_COLLAPSED_KEY)) || []); } catch { return new Set(); }
  };
  const saveCollapsedPaths = (set) => {
    try { localStorage.setItem(FILES_COLLAPSED_KEY, JSON.stringify([...set])); } catch {}
  };

  function syncFilesSidebar(root) {
    const nav = root.querySelector(".files nav");
    const input = root.querySelector(".files-filter");
    if (!nav || !input) return;
    input.value = filesFilterQuery;
    const q = filesFilterQuery.trim().toLowerCase();
    nav.classList.toggle("filtering", q.length > 0);
    for (const li of nav.querySelectorAll("li.file-node")) {
      li.hidden = q.length > 0 && !li.dataset.path.toLowerCase().includes(q);
    }
    const collapsed = collapsedPaths();
    for (const details of nav.querySelectorAll("li.file-folder > details")) {
      const li = details.parentElement;
      const visible = details.querySelectorAll("li.file-node:not([hidden])").length > 0;
      li.hidden = q.length > 0 && !visible;
      details.open = q.length > 0 ? visible : !collapsed.has(li.dataset.path);
    }
    // The scoped (active) row stays visible: expand its ancestors.
    const active = nav.querySelector(".file-row.active");
    let el = active && active.closest("li");
    while (el) {
      el = el.parentElement ? el.parentElement.closest("details") : null;
      if (el) el.open = true;
    }
  }

  syncFilesSidebar(document);

  document.addEventListener("input", (e) => {
    if (!e.target.classList.contains("files-filter")) return;
    filesFilterQuery = e.target.value;
    syncFilesSidebar(document);
  });

  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || !e.target.classList.contains("files-filter")) return;
    e.target.value = "";
    filesFilterQuery = "";
    syncFilesSidebar(document);
    e.target.blur();
  });

  // Manual toggles persist; filter-driven ones don't. `toggle` doesn't
  // bubble, so listen on the capture phase to catch it at the document.
  document.addEventListener("toggle", (e) => {
    const li = e.target.closest("li.file-folder");
    if (!li || li.closest(".files nav")?.classList.contains("filtering")) return;
    const collapsed = collapsedPaths();
    if (e.target.open) collapsed.delete(li.dataset.path); else collapsed.add(li.dataset.path);
    saveCollapsedPaths(collapsed);
  }, true);

  // Locales menu: typing hides the locales that don't match.
  for (const input of document.querySelectorAll("[data-filter-labels]")) {
    const labels = [...input.parentElement.querySelectorAll("label")];
    input.addEventListener("input", () => {
      const q = input.value.trim().toLowerCase();
      for (const label of labels) label.hidden = !label.textContent.toLowerCase().includes(q);
    });
    input.addEventListener("keydown", (e) => {
      if (e.key !== "Enter") return;
      e.preventDefault();
      labels.find((label) => !label.hidden)?.querySelector("input")?.click();
    });
  }

  // <select data-combo>: a text box that filters the options as you type.
  // The select stays in the form, hidden; data-free also takes typed values.
  for (const select of document.querySelectorAll("select[data-combo]")) combo(select);

  function combo(select) {
    const free = select.hasAttribute("data-free");
    const options = [...select.options].map((o) => ({ value: o.value, label: o.text }));
    const wrap = Object.assign(document.createElement("div"), { className: "combo" });
    const input = Object.assign(document.createElement("input"), {
      type: "text", className: "combo-input", autocomplete: "off", spellcheck: false,
    });
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-label", select.getAttribute("aria-label") || "");
    input.setAttribute("aria-expanded", "false");
    const list = Object.assign(document.createElement("ul"), { className: "combo-list", hidden: true });
    list.setAttribute("role", "listbox");
    select.hidden = true;
    select.before(wrap);
    wrap.append(input, list, select);

    let shown = [];
    let active = 0;
    const label = () => select.options[select.selectedIndex]?.text || select.value;
    input.value = label();
    input.size = Math.max(8, Math.min(30, 2 + Math.max(...options.map((o) => o.label.length))));

    function render(query) {
      const words = query.toLowerCase().split(/\s+/).filter(Boolean);
      shown = options.filter((o) => words.every((w) => `${o.label} ${o.value}`.toLowerCase().includes(w)));
      if (free && query.trim() && !shown.some((o) => o.value === query.trim())) {
        shown.push({ value: query.trim(), label: `Use “${query.trim()}”`, typed: true });
      }
      active = Math.max(0, shown.findIndex((o) => o.value === select.value && !query));
      list.replaceChildren(...shown.map((o, i) => {
        const li = Object.assign(document.createElement("li"), { textContent: o.label });
        li.setAttribute("role", "option");
        if (i === active) li.classList.add("active");
        li.addEventListener("mousedown", (e) => {
          e.preventDefault();
          pick(o);
        });
        return li;
      }));
      if (!shown.length) list.append(Object.assign(document.createElement("li"), { className: "empty", textContent: "No match" }));
      list.hidden = false;
      input.setAttribute("aria-expanded", "true");
    }

    function move(by) {
      if (!shown.length) return;
      active = (active + by + shown.length) % shown.length;
      [...list.children].forEach((li, i) => li.classList.toggle("active", i === active));
      list.children[active]?.scrollIntoView({ block: "nearest" });
    }

    function close() {
      list.hidden = true;
      input.setAttribute("aria-expanded", "false");
      input.value = label();
    }

    function pick(o) {
      if (o.typed) {
        select.append(new Option(o.value, o.value));
        options.push({ value: o.value, label: o.value });
      }
      const changed = select.value !== o.value;
      select.value = o.value;
      close();
      input.blur();
      if (changed) select.dispatchEvent(new Event("change", { bubbles: true }));
    }

    // Empty while open, the current choice as placeholder, so typing filters.
    input.addEventListener("focus", () => {
      input.placeholder = label();
      input.value = "";
      render("");
    });
    input.addEventListener("input", () => render(input.value));
    input.addEventListener("blur", close);
    input.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        if (list.hidden) render("");
        else move(e.key === "ArrowDown" ? 1 : -1);
      } else if (e.key === "Enter") {
        e.preventDefault();
        if (shown[active]) pick(shown[active]);
      } else if (e.key === "Escape") {
        close();
        input.blur();
      }
    });
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
    const menu = current.querySelector(".export-menu[open]");
    const choices = menu && new FormData(menu.querySelector("form"));
    current.innerHTML = next.innerHTML;
    if (menu) {
      const fresh = current.querySelector(".export-menu");
      fresh.open = true;
      for (const name of ["format", "source", "target"]) {
        for (const el of fresh.querySelectorAll(`[name="${name}"]`)) {
          if (el.type === "radio") el.checked = el.value === choices.get(name);
          else el.value = choices.get(name);
        }
      }
    }
    syncFilesSidebar(current);
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
