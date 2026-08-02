
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

// PCスリープ・長時間離席から戻った時にログインを先回りで復帰させる（父親版 PR #45 の共通版展開）。
// startAutoRefresh の setTimeout はスリープ中・バックグラウンドタブでは動かないため、
// 戻ってきた瞬間にトークンが期限切れだと次の画面移動で checkAuth に弾かれて
// 「勝手にログアウトされた」状態になる。画面が再表示された時に、期限切れ or 5分以内に
// 切れるトークンを更新トークンで先に更新しておく。
// ※60分放置の自動ログアウト（startIdleWatch）は共通版では維持する。signOut 済みなら
//   user キーが消えているため下のガードで何もしない＝この復帰処理では延命しない。
let _reviving = false;
async function reviveSession() {
  if (_reviving) return;
  if (!sessionStorage.getItem('user')) return;
  if (!sessionStorage.getItem('_sb_refresh')) return;
  const expiry = _getTokenExpiry();
  // まだ5分以上余裕があるなら何もしない（通常の自動更新に任せる）
  if (expiry && expiry - Date.now() > 5 * 60 * 1000) return;
  _reviving = true;
  try {
    const data = await sbRefreshSession();
    // 更新の最中に自動ログアウトが走っていたら、書き戻したトークンを取り消す
    if (!sessionStorage.getItem('user')) {
      sessionStorage.removeItem('_sb_jwt');
      sessionStorage.removeItem('_sb_refresh');
    } else if (data?.access_token) {
      startAutoRefresh();
    }
  } catch (e) { /* 復帰失敗は握りつぶす（次の操作時の checkAuth に委ねる） */ }
  finally { _reviving = false; }
}
document.addEventListener('visibilitychange', () => { if (!document.hidden) reviveSession(); });
window.addEventListener('focus', reviveSession);
window.addEventListener('pageshow', reviveSession);

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
