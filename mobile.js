document.addEventListener('DOMContentLoaded', function () {
  const sidebar = document.querySelector('.sidebar');
  if (!sidebar) return;

  // Inject overlay
  const overlay = document.createElement('div');
  overlay.className = 'sidebar-overlay';
  overlay.id = 'sidebarOverlay';
  overlay.addEventListener('click', closeSidebar);
  document.body.prepend(overlay);

  // Inject hamburger into topbar
  const topbar = document.querySelector('.topbar');
  if (topbar) {
    const ham = document.createElement('button');
    ham.className = 'hamburger';
    ham.setAttribute('aria-label', 'メニューを開く');
    ham.innerHTML = '<span></span><span></span><span></span>';
    ham.addEventListener('click', toggleSidebar);
    topbar.prepend(ham);
  }

  // Close sidebar on nav-item click (mobile transition)
  sidebar.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', closeSidebar);
  });
});

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
