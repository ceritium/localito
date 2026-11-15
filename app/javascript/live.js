// Polls /changes (file stats only) and, when something changed on disk,
// refetches the page and swaps #live in place, flashing the cells that differ.
(() => {
  const live = document.getElementById("live");
  if (!live) return;
  let version = live.dataset.version;
  let busy = false;

  async function tick() {
    if (busy || document.hidden) return;
    busy = true;
    try {
      const res = await fetch("/changes", { cache: "no-store" });
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
    const res = await fetch(location.href, { cache: "no-store" });
    if (!res.ok) return;
    const next = new DOMParser().parseFromString(await res.text(), "text/html").getElementById("live");
    if (!next) return;
    if (live.dataset.mode === "edit") return showDiskChange(next);

    const before = new Map([...live.querySelectorAll("[data-cell]")].map((td) => [td.dataset.cell, td.textContent]));
    live.innerHTML = next.innerHTML;
    for (const td of live.querySelectorAll("[data-cell]")) {
      if (before.get(td.dataset.cell) !== td.textContent) td.classList.add("changed");
    }
  }

  function showDiskChange(next) {
    const value = next.querySelector("[data-disk-value]")?.dataset.diskValue;
    const original = document.querySelector("input[name=original]").value;
    const banner = document.getElementById("disk-change");
    banner.hidden = value === undefined || value === original;
    banner.querySelector("pre").textContent = value ?? "";
  }

  setInterval(tick, 1500);
  document.addEventListener("visibilitychange", tick);
})();
