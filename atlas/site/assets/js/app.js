(() => {
  "use strict";
  const $ = (s) => document.querySelector(s),
    $$ = (s) => [...document.querySelectorAll(s)];
  const menu = $("[data-menu-toggle]"),
    nav = $("#main-navigation"),
    search = $("[data-search-toggle]"),
    panel = $("#site-search");
  function closePanels() {
    nav?.classList.remove("open");
    menu?.setAttribute("aria-expanded", "false");
    if (panel) panel.hidden = true;
    search?.setAttribute("aria-expanded", "false");
  }
  menu?.addEventListener("click", () => {
    const open = !nav.classList.contains("open");
    closePanels();
    nav.classList.toggle("open", open);
    menu.setAttribute("aria-expanded", String(open));
  });
  search?.addEventListener("click", () => {
    const open = panel.hidden;
    closePanels();
    panel.hidden = !open;
    search.setAttribute("aria-expanded", String(open));
    if (open) panel.querySelector("input").focus();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const hadSearch = panel && !panel.hidden;
      const hadMenu = nav?.classList.contains("open");
      closePanels();
      if (hadSearch) search.focus();
      else if (hadMenu) menu.focus();
    }
    if (
      event.key === "/" &&
      !["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName) &&
      !document.activeElement?.isContentEditable
    ) {
      event.preventDefault();
      closePanels();
      panel.hidden = false;
      search.setAttribute("aria-expanded", "true");
      panel.querySelector("input").focus();
    }
  });
  document.addEventListener("click", (event) => {
    if (!event.target.closest(".header")) closePanels();
  });
  const store = "atlas-earth-place:reading-list:v2";
  function saved() {
    try {
      const data = JSON.parse(localStorage.getItem(store) || "[]");
      return Array.isArray(data)
        ? data.filter((s) => typeof s === "string")
        : [];
    } catch {
      return [];
    }
  }
  const buttons = $$("[data-save]");
  function refreshSaved() {
    const items = saved();
    buttons.forEach((button) => {
      const active = items.includes(button.dataset.save);
      button.setAttribute("aria-pressed", String(active));
      button.textContent = active
        ? "Saved to reading list"
        : "Save to reading list";
    });
  }
  buttons.forEach((button) =>
    button.addEventListener("click", () => {
      const items = saved(),
        slug = button.dataset.save;
      const next = items.includes(slug)
        ? items.filter((s) => s !== slug)
        : [...items, slug];
      try {
        localStorage.setItem(store, JSON.stringify(next));
        refreshSaved();
      } catch {
        const toast = $("[data-toast]");
        if (toast)
          toast.textContent =
            "Browser storage is unavailable. Saving is disabled.";
      }
    }),
  );
  refreshSaved();
  const catalog = $("[data-catalog]");
  if (catalog) {
    const stories = $$("[data-story]"),
      field = $("[data-story-search]"),
      filters = $$("[data-filter]"),
      count = $("[data-count]"),
      empty = $("[data-empty]");
    const params = new URLSearchParams(location.search);
    let active =
      params.get("saved") === "1" ? "Saved" : params.get("category") || "All";
    if (
      !["All", "Saved", "Geography", "Cartography", "Earth Science"].includes(
        active,
      )
    )
      active = "All";
    field.value = params.get("q") || "";
    function render() {
      const term = field.value.trim().toLowerCase(),
        savedItems = saved();
      let total = 0;
      stories.forEach((story) => {
        const slug = story
          .getAttribute("href")
          .split("/")
          .pop()
          .replace(".html", "");
        const match =
          active === "All" ||
          (active === "Saved"
            ? savedItems.includes(slug)
            : story.dataset.category === active);
        story.hidden = !(
          match && story.dataset.search.toLowerCase().includes(term)
        );
        if (!story.hidden) total++;
      });
      filters.forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.filter === active),
        ),
      );
      count.textContent = total + (total === 1 ? " story" : " stories");
      empty.hidden = total !== 0;
    }
    filters.forEach((button) =>
      button.addEventListener("click", () => {
        active = button.dataset.filter;
        render();
      }),
    );
    field.addEventListener("input", render);
    window.addEventListener("storage", render);
    render();
  }
  $("[data-copy-link]")?.addEventListener("click", async () => {
    const toast = $("[data-toast]");
    try {
      await navigator.clipboard.writeText(location.href);
      toast.textContent = "Article link copied.";
    } catch {
      toast.textContent =
        "Copy the address from your browser to share this story.";
    }
  });
  const progress = $("[data-reading-progress]"),
    article = $(".article-body");
  if (progress && article) {
    let queued = false;
    const toc = $$(".toc a");
    const headings = [...article.querySelectorAll("h2[id]")];
    function update() {
      const start = article.getBoundingClientRect().top + scrollY;
      const end = start + article.offsetHeight - innerHeight * 0.5;
      progress.style.width =
        Math.min(
          100,
          Math.max(
            0,
            ((scrollY - start + innerHeight * 0.3) / Math.max(1, end - start)) *
              100,
          ),
        ) + "%";
      let id = "";
      headings.forEach((h) => {
        if (h.getBoundingClientRect().top < innerHeight * 0.4) id = h.id;
      });
      toc.forEach((a) => a.classList.toggle("active", a.hash === "#" + id));
      queued = false;
    }
    addEventListener(
      "scroll",
      () => {
        if (!queued) {
          queued = true;
          requestAnimationFrame(update);
        }
      },
      { passive: true },
    );
    addEventListener("resize", update);
    update();
  }
})();
