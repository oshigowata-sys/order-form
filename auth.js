const _SB_URL = 'https://vrnayxmwcbxblfokveok.supabase.co';
const _SB_KEY = 'sb_publishable_NIKtwat_yat2LxbACHVMbA_PT_8F53O';

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
