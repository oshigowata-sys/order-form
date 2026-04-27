const _SB_URL = 'https://vrnayxmwcbxblfokveok.supabase.co';
const _SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZybmF5eG13Y2J4Ymxmb2t2ZW9rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNjc4NzIsImV4cCI6MjA5MTc0Mzg3Mn0.Rv_hZCtjOQZOecZPo7g9z62-r2RzearKb2DIKI322_M';

function getAccessToken() {
  return sessionStorage.getItem('_sb_jwt') || _SB_KEY;
}

async function sbSignIn(email, password) {
  const res = await fetch(`${_SB_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { 'apikey': _SB_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  if (!res.ok) return null;
  return res.json();
}

async function sbSignUp(email, password, metadata) {
  const res = await fetch(`${_SB_URL}/auth/v1/signup`, {
    method: 'POST',
    headers: { 'apikey': _SB_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, data: metadata })
  });
  return res.json();
}

async function sbUpdatePassword(newPassword) {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) return false;
  const res = await fetch(`${_SB_URL}/auth/v1/user`, {
    method: 'PUT',
    headers: { 'apikey': _SB_KEY, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ password: newPassword })
  });
  return res.ok;
}

async function sbUpdateUserMeta(metadata) {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) return false;
  const res = await fetch(`${_SB_URL}/auth/v1/user`, {
    method: 'PUT',
    headers: { 'apikey': _SB_KEY, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: metadata })
  });
  return res.ok;
}

async function sbRefreshSession() {
  const refresh = sessionStorage.getItem('_sb_refresh');
  if (!refresh) return null;
  const res = await fetch(`${_SB_URL}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: { 'apikey': _SB_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: refresh })
  });
  if (!res.ok) return null;
  const data = await res.json();
  if (data.access_token) {
    sessionStorage.setItem('_sb_jwt', data.access_token);
    if (data.refresh_token) sessionStorage.setItem('_sb_refresh', data.refresh_token);
  }
  return data;
}

let _refreshTimer = null;

function _getTokenExpiry() {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) return 0;
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.exp * 1000;
  } catch { return 0; }
}

function startAutoRefresh() {
  if (_refreshTimer) clearTimeout(_refreshTimer);
  const expiry = _getTokenExpiry();
  if (!expiry) return;
  const delay = Math.max(expiry - Date.now() - 5 * 60 * 1000, 30_000);
  _refreshTimer = setTimeout(async () => {
    const data = await sbRefreshSession();
    if (data?.access_token) {
      startAutoRefresh();
    } else {
      signOut();
    }
  }, delay);
}

if (sessionStorage.getItem('_sb_jwt')) startAutoRefresh();

async function signOut(redirectUrl) {
  const token = sessionStorage.getItem('_sb_jwt');
  if (token) {
    try {
      await fetch(`${_SB_URL}/auth/v1/logout`, {
        method: 'POST',
        headers: { 'apikey': _SB_KEY, 'Authorization': 'Bearer ' + token }
      });
    } catch {}
  }
  sessionStorage.removeItem('user');
  sessionStorage.removeItem('superAdmin');
  sessionStorage.removeItem('_sb_jwt');
  sessionStorage.removeItem('_sb_refresh');
  location.replace(redirectUrl || 'login.html');
}
