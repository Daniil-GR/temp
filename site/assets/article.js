(() => {
  "use strict";
  const root = document.documentElement;
  const toggle = document.getElementById("theme-toggle");
  const meta = document.querySelector('meta[name="theme-color"]');
  const systemDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;

  function applyTheme(value, save) {
    const mode = value === "dark" ? "dark" : "light";
    root.dataset.theme = mode;
    if (meta) meta.content = mode === "dark" ? "#151f1b" : "#f5f3ee";
    if (toggle) toggle.setAttribute("aria-label", mode === "dark" ? "Switch to light theme" : "Switch to dark theme");
    if (save) {
      try { localStorage.setItem("cloudenza-theme", mode); } catch (_) {}
    }
  }

  let saved;
  try { saved = localStorage.getItem("cloudenza-theme"); } catch (_) {}
  applyTheme(saved === "dark" || saved === "light" ? saved : systemDark ? "dark" : "light", false);
  if (toggle) toggle.addEventListener("click", () => applyTheme(root.dataset.theme === "dark" ? "light" : "dark", true));

  const bar = document.querySelector(".read-progress");
  let scheduled = false;
  function updateProgress() {
    if (!bar) return;
    const max = document.documentElement.scrollHeight - innerHeight;
    const progress = max > 0 ? Math.max(0, Math.min(100, scrollY / max * 100)) : 100;
    bar.style.width = progress + "%";
    scheduled = false;
  }
  window.addEventListener("scroll", () => {
    if (!scheduled) { scheduled = true; requestAnimationFrame(updateProgress); }
  }, {passive: true});
  window.addEventListener("resize", updateProgress);
  updateProgress();

  const links = Array.from(document.querySelectorAll('.article-toc a[href^="#"]'));
  const sections = links.map(a => document.getElementById(a.hash.slice(1))).filter(Boolean);
  if ("IntersectionObserver" in window && sections.length) {
    const observer = new IntersectionObserver(entries => {
      const visible = entries.filter(x => x.isIntersecting).sort((a,b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (visible.length) {
        links.forEach(link => {
          const active = link.hash === "#" + visible[0].target.id;
          link.classList.toggle("active", active);
          if (active) link.setAttribute("aria-current", "location");
          else link.removeAttribute("aria-current");
        });
      }
    }, {rootMargin:"-8% 0px -65% 0px", threshold:0});
    sections.forEach(s => observer.observe(s));
  }

  document.querySelectorAll(".code-copy").forEach(button => button.addEventListener("click", async () => {
    const code = button.closest(".code-example")?.querySelector("pre code")?.textContent;
    if (!code) return;
    const before = button.textContent;
    try {
      await navigator.clipboard.writeText(code.trim());
      button.textContent = "Copied";
    } catch (_) { button.textContent = "Select code"; }
    setTimeout(() => button.textContent = before, 1600);
  }));
})();
