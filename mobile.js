document.addEventListener('DOMContentLoaded', function () {
  initSidebar();
  initTableCards();
});

/* ========== Sidebar ========== */
function initSidebar() {
  const sidebar = document.querySelector('.sidebar');
  if (!sidebar) return;

  const overlay = document.createElement('div');
  overlay.className = 'sidebar-overlay';
  overlay.id = 'sidebarOverlay';
  overlay.addEventListener('click', closeSidebar);
  document.body.prepend(overlay);

  const topbar = document.querySelector('.topbar');
  if (topbar) {
    const ham = document.createElement('button');
    ham.className = 'hamburger';
    ham.setAttribute('aria-label', 'メニューを開く');
    ham.innerHTML = '<span></span><span></span><span></span>';
    ham.addEventListener('click', toggleSidebar);
    topbar.prepend(ham);
  }

  sidebar.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', closeSidebar);
  });
}

function toggleSidebar() {
  const sidebar = document.querySelector('.sidebar');
  const overlay = document.getElementById('sidebarOverlay');
  const isOpen = sidebar.classList.toggle('open');
  overlay.classList.toggle('open', isOpen);
  document.body.classList.toggle('sidebar-open', isOpen);
}

function closeSidebar() {
  document.querySelector('.sidebar')?.classList.remove('open');
  document.getElementById('sidebarOverlay')?.classList.remove('open');
  document.body.classList.remove('sidebar-open');
}

/* ========== Table → Card layout ========== */
// For each table, watch tbody for new rows (Supabase loads data async)
// and inject data-label from the corresponding <th>
function initTableCards() {
  document.querySelectorAll('table').forEach(table => {
    applyLabels(table);

    const tbody = table.querySelector('tbody');
    if (!tbody) return;

    const observer = new MutationObserver(() => applyLabels(table));
    observer.observe(tbody, { childList: true, subtree: false });
  });
}

function applyLabels(table) {
  const headers = Array.from(table.querySelectorAll('thead th'))
    .map(th => th.textContent.trim());
  if (!headers.length) return;

  table.querySelectorAll('tbody tr').forEach(row => {
    row.querySelectorAll('td').forEach((td, i) => {
      const label = headers[i] || '';
      td.setAttribute('data-label', label);
    });
  });
}
