
function getAccessToken() {
  return sessionStorage.getItem('_sb_jwt') || _SB_KEY;
}

function getJwtPayload() {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) return null;
  try {
    const payload = token.split('.')[1];
    if (!payload) return null;
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(payload.length / 4) * 4, '=');
    return JSON.parse(atob(base64));
  } catch {
    return null;
  }
}

function getStrictAccessToken(redirectUrl) {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) {
    signOut(redirectUrl);
    throw new Error('missing_jwt');
  }
  const payload = getJwtPayload();
  if (!payload || payload.exp * 1000 < Date.now()) {
    signOut(redirectUrl);
    throw new Error('expired_jwt');
  }
  return token;
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
let _idleTimer = null;
const _IDLE_MS = 60 * 60 * 1000;

function _getTokenExpiry() {
  const token = sessionStorage.getItem('_sb_jwt');
  if (!token) return 0;
  try {
    const payload = getJwtPayload();
    if (!payload) return 0;
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

if (sessionStorage.getItem('_sb_jwt')) { startAutoRefresh(); startIdleWatch(); }

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

function checkAuth(redirectUrl) {
  if (!sessionStorage.getItem('user')) { location.replace(redirectUrl || 'login.html'); return false; }
  const jwt = sessionStorage.getItem('_sb_jwt');
  if (!jwt) { signOut(redirectUrl || 'login.html'); return false; }
  if (jwt) {
    try {
      const payload = getJwtPayload();
      if (!payload || payload.exp * 1000 < Date.now()) { signOut(redirectUrl || 'login.html'); return false; }
    } catch { /* malformed JWT — ignore, user key still valid */ }
  }
  // 小売店(retail)は管理画面を使わせない。注文画面へ送り返す（shop.html 自身は checkAuth を呼ばない）
  try {
    const u = JSON.parse(sessionStorage.getItem('user') || '{}');
    if (u.role === 'retail') { location.replace('shop.html'); return false; }
  } catch {}
  return true;
}

function _resetIdleTimer() {
  clearTimeout(_idleTimer);
  if (!sessionStorage.getItem('_sb_jwt')) return;
  _idleTimer = setTimeout(() => signOut(), _IDLE_MS);
}

function startIdleWatch() {
  ['mousedown', 'keydown', 'touchstart', 'scroll', 'click'].forEach(e =>
    document.addEventListener(e, _resetIdleTimer, { passive: true })
  );
  _resetIdleTimer();
}
