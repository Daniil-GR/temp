(() => {
  'use strict';

  const root = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  const media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  let savedTheme = null;
  try { savedTheme = localStorage.getItem('cloudenza-theme'); } catch (_) {}
  const initialTheme = savedTheme === 'dark' || savedTheme === 'light'
    ? savedTheme : media && media.matches ? 'dark' : 'light';

  function setTheme(theme, persist) {
    root.dataset.theme = theme;
    toggle.setAttribute('aria-label', theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
    const colorMeta = document.querySelector('meta[name="theme-color"]');
    if (colorMeta) colorMeta.content = theme === 'dark' ? '#151f1b' : '#f5f3ee';
    if (persist) {
      try { localStorage.setItem('cloudenza-theme', theme); } catch (_) {}
    }
  }
  setTheme(initialTheme, false);
  toggle.addEventListener('click', () => setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark', true));

  const search = document.getElementById('search');
  const cards = Array.from(document.querySelectorAll('.article-card'));
  const empty = document.getElementById('no-results');

  search.addEventListener('input', () => {
    const query = search.value.trim().toLocaleLowerCase();
    let visible = 0;
    cards.forEach(card => {
      const text = (card.innerText + ' ' + (card.dataset.search || '')).toLocaleLowerCase();
      const matches = !query || text.includes(query);
      card.hidden = !matches;
      if (matches) visible++;
    });
    empty.hidden = visible > 0;
  });

  document.addEventListener('keydown', event => {
    if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey ||
      /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName) ||
      document.activeElement.isContentEditable) return;
    event.preventDefault();
    search.focus();
    document.getElementById('library').scrollIntoView({behavior:'smooth'});
  });

  document.querySelectorAll('.copy-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const original = btn.textContent;
      try {
        await navigator.clipboard.writeText(btn.dataset.copy);
        btn.textContent = 'Copied';
      } catch (_) {
        btn.textContent = 'Select code';
      }
      window.setTimeout(() => { btn.textContent = original; }, 1800);
    });
  });

  const button = document.getElementById('run-check');
  const status = document.getElementById('check-status');
  const latency = document.getElementById('latency');
  const httpStatus = document.getElementById('http-status');
  const checkTime = document.getElementById('check-time');
  const explanation = document.getElementById('check-explanation');

  button.addEventListener('click', async () => {
    if (button.disabled) return;
    button.disabled = true;
    status.textContent = 'CHECKING';
    status.style.color = '#e0ad8d';
    latency.textContent = '…';
    httpStatus.textContent = 'Waiting';
    checkTime.textContent = '—';

    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 8000);
    const url = new URL('./', window.location.href);
    url.searchParams.set('_check', String(Date.now()));
    const start = performance.now();

    try {
      const response = await fetch(url, {
        method: 'HEAD',
        cache: 'no-store',
        credentials: 'same-origin',
        redirect: 'follow',
        signal: controller.signal
      });
      const elapsed = Math.max(0, performance.now() - start);
      latency.textContent = Math.round(elapsed).toLocaleString();
      httpStatus.textContent = response.status + (response.ok ? ' / OK' : ' / Response');
      checkTime.textContent = new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'});
      if (response.ok) {
        status.textContent = 'REACHABLE';
        status.style.color = '#b8e2b2';
        explanation.textContent = 'A HEAD request to this website returned successfully. The time includes browser and network overhead.';
      } else {
        status.textContent = 'HTTP ERROR';
        status.style.color = '#f2a8a8';
        explanation.textContent = 'The server responded, but the returned HTTP status was not successful.';
      }
    } catch (error) {
      latency.textContent = '—';
      httpStatus.textContent = 'No response';
      checkTime.textContent = new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'});
      status.textContent = 'FAILED';
      status.style.color = '#f2a8a8';
      explanation.textContent = error.name === 'AbortError'
        ? 'The request did not finish within eight seconds.'
        : 'The browser could not complete a request to this website. Check your connection and try again.';
    } finally {
      window.clearTimeout(timer);
      button.disabled = false;
    }
  });
})();
