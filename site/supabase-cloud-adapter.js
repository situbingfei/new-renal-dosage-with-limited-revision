/*
 * Supabase adapter for the original renal_dose_assistant.html UI.
 * Keeps the existing page layout and routes its existing /api/* calls to Supabase.
 * Public reads use the Publishable Key + RLS; writes require both Supabase Auth
 * and the private.renal_admins allow-list. Never place a Secret/service_role key here.
 */
(() => {
  'use strict';

  const config = window.RENAL_SUPABASE_CONFIG || {};
  const projectUrl = String(config.url || '').trim().replace(/\/+$/, '');
  const publishableKey = String(config.publishableKey || '').trim();
  const maintenanceEmail = String(config.maintenanceEmail || '').trim();
  const configured = /^https?:\/\//i.test(projectUrl) && !!publishableKey && !/YOUR_PROJECT|REPLACE_ME/i.test(projectUrl + publishableKey);
  const bucket = 'instructions';
  const sessionKey = 'renal_supabase_admin_session_v1';
  const nativeFetch = window.fetch.bind(window);
  const fields = [
    'drug_id','drug_name','renal_function_level','ccr_min','ccr_max','dose_unit',
    'dose_value','dose_total_value','dose_description','adjustment_rule','special_notes','reference'
  ];

  class CloudError extends Error {
    constructor(message, status = 500) { super(message); this.name = 'CloudError'; this.status = status; }
  }

  const jsonResponse = (value, status = 200) => new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }
  });
  const newId = () => {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID().replace(/-/g, '');
    const bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
  };
  const safeFilename = name => String(name || '').split(/[\\/]/).pop().slice(0, 160) || '说明书二维码';
  const drugKey = row => `${String(row.drug_id || '')}||${String(row.drug_name || '')}`;
  const parseJsonText = async response => {
    const text = await response.text();
    if (!text) return null;
    try { return JSON.parse(text); } catch (_) { return text; }
  };
  const messageOf = data => {
    if (typeof data === 'string') return data;
    if (data && typeof data === 'object') return data.error_description || data.msg || data.message || data.error || data.hint || data.details || 'Supabase 请求失败';
    return 'Supabase 请求失败';
  };

  function requireConfig() {
    if (!configured) throw new CloudError('尚未配置 Supabase。请在 site/supabase-config.js 填写 Project URL、Publishable Key 和管理员邮箱。', 503);
  }

  function sessionRead() {
    try {
      const value = sessionStorage.getItem(sessionKey);
      return value ? JSON.parse(value) : null;
    } catch (_) { return null; }
  }
  function sessionWrite(raw) {
    const expiresIn = Number(raw.expires_in || 3600);
    const value = {
      access_token: raw.access_token,
      refresh_token: raw.refresh_token,
      token_type: raw.token_type || 'bearer',
      expires_at: raw.expires_at || (Math.floor(Date.now() / 1000) + expiresIn),
      user: raw.user || null
    };
    try { sessionStorage.setItem(sessionKey, JSON.stringify(value)); } catch (_) {}
    return value;
  }
  function sessionClear() {
    try { sessionStorage.removeItem(sessionKey); } catch (_) {}
  }

  async function sbRequest(path, options = {}) {
    requireConfig();
    const headers = new Headers(options.headers || {});
    headers.set('apikey', publishableKey);
    // Match Supabase's browser client behavior: use the publishable key as the
    // unauthenticated bearer; once signed in, replace it with the Auth user JWT.
    headers.set('Authorization', `Bearer ${options.token || publishableKey}`);
    const init = { ...options, headers };
    delete init.token;
    const response = await nativeFetch(`${projectUrl}/${String(path).replace(/^\/+/, '')}`, init);
    const data = await parseJsonText(response);
    if (!response.ok) throw new CloudError(messageOf(data), response.status);
    return data;
  }

  async function validSession() {
    requireConfig();
    const session = sessionRead();
    if (!session || !session.access_token) return null;
    const now = Math.floor(Date.now() / 1000);
    if (Number(session.expires_at || 0) > now + 45) return session;
    if (!session.refresh_token) { sessionClear(); return null; }
    try {
      const refreshed = await sbRequest('auth/v1/token?grant_type=refresh_token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: session.refresh_token })
      });
      return sessionWrite(refreshed);
    } catch (_) {
      sessionClear();
      return null;
    }
  }

  async function adminStatus(token) {
    const value = await sbRequest('rest/v1/rpc/is_renal_admin', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}', token
    });
    return value === true || value === 'true';
  }

  async function requireAdmin() {
    const session = await validSession();
    if (!session || !session.access_token) throw new CloudError('请先登录数据库维护。', 401);
    let allowed = false;
    try { allowed = await adminStatus(session.access_token); }
    catch (error) {
      if (error.status === 401) sessionClear();
      throw new CloudError(error.message || '无法核验管理员权限。', error.status || 403);
    }
    if (!allowed) {
      sessionClear();
      throw new CloudError('此 Supabase 账号尚未加入管理员白名单，或已被移除。', 403);
    }
    return session.access_token;
  }

  function encodeStoragePath(path) {
    return String(path).split('/').map(part => encodeURIComponent(part)).join('/');
  }
  function publicObjectUrl(path) {
    return `${projectUrl}/storage/v1/object/public/${bucket}/${encodeStoragePath(path)}`;
  }

  async function listQrRows(token = null) {
    const rows = await sbRequest('rest/v1/drug_qr?select=*&order=drug_id.asc,drug_name.asc', { token });
    return Array.isArray(rows) ? rows : [];
  }
  function qrRowsToMap(rows) {
    const result = {};
    for (const row of rows || []) {
      const storagePath = String(row.storage_path || '');
      if (!storagePath) continue;
      result[`${row.drug_id}||${row.drug_name}`] = {
        filename: row.original_name || '',
        originalName: row.original_name || '',
        url: publicObjectUrl(storagePath),
        updatedAt: row.updated_at || '',
        storagePath,
        storage_path: storagePath
      };
    }
    return result;
  }
  async function readDatabase(token = null) {
    const [rows, qrRows] = await Promise.all([
      sbRequest('rest/v1/drug_rules?select=*&order=sort_order.asc,_id.asc', { token }),
      listQrRows(token)
    ]);
    return { version: 1, records: Array.isArray(rows) ? rows : [], qr: qrRowsToMap(qrRows) };
  }

  function cleanRecords(input) {
    if (!Array.isArray(input)) throw new CloudError('records 必须是数组。', 400);
    const seen = new Set();
    const rows = [];
    for (const item of input) {
      if (!item || typeof item !== 'object') continue;
      const row = {};
      for (const field of fields) row[field] = String(item[field] == null ? '' : item[field]).trim();
      if (!row.drug_id || !row.drug_name) continue;
      let id = String(item._id || '').trim().slice(0, 80) || newId();
      if (seen.has(id)) id = newId();
      seen.add(id);
      row._id = id;
      rows.push(row);
    }
    return rows;
  }

  function cleanQrMap(qrInput, records) {
    const qr = {};
    if (!qrInput || typeof qrInput !== 'object' || Array.isArray(qrInput)) return qr;
    const validKeys = new Set(records.map(drugKey));
    for (const [key, item] of Object.entries(qrInput)) {
      if (!validKeys.has(key) || !item || typeof item !== 'object') continue;
      const storagePath = String(item.storagePath || item.storage_path || '').trim();
      if (!storagePath) continue;
      qr[key] = {
        storagePath,
        originalName: safeFilename(item.originalName || item.original_name || item.filename || '说明书二维码'),
        updatedAt: item.updatedAt || item.updated_at || new Date().toISOString()
      };
    }
    return qr;
  }

  async function removeStorageObjects(paths, token) {
    const unique = Array.from(new Set((paths || []).map(String).filter(Boolean)));
    if (!unique.length) return;
    try {
      await sbRequest(`storage/v1/object/${bucket}`, {
        method: 'DELETE', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: unique }), token
      });
    } catch (_) {
      // Database references are already safe/removed. A failed cleanup leaves only an orphaned
      // public image in Storage; the admin can remove it in Supabase Storage later.
    }
  }

  async function saveDatabase(payload, token) {
    if (!payload || !Array.isArray(payload.records)) throw new CloudError('records 必须是数组。', 400);
    const records = cleanRecords(payload.records);
    const qr = cleanQrMap(payload.qr || {}, records);
    const beforeQr = await listQrRows(token);
    await sbRequest('rest/v1/rpc/replace_renal_database', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_payload: { records, qr } }), token
    });
    const database = await readDatabase(token);
    const retainedPaths = new Set(Object.values(database.qr).map(item => item.storagePath).filter(Boolean));
    const orphaned = beforeQr.map(row => row.storage_path).filter(path => path && !retainedPaths.has(path));
    await removeStorageObjects(orphaned, token);
    return database;
  }

  async function validateImage(file) {
    const allowed = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];
    if (!allowed.includes(file.type)) throw new CloudError('仅支持 PNG/JPG/WebP/GIF 图片。', 415);
    if (!file.size) throw new CloudError('图片内容为空。', 400);
    if (file.size > 8 * 1024 * 1024) throw new CloudError('图片超过 8 MB，请压缩后再上传。', 413);
    const bytes = new Uint8Array(await file.slice(0, 12).arrayBuffer());
    const ascii = (start, count) => String.fromCharCode(...bytes.slice(start, start + count));
    const ok = file.type === 'image/png' ? bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v, i) => bytes[i] === v)
      : file.type === 'image/jpeg' ? bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
      : file.type === 'image/gif' ? ['GIF87a','GIF89a'].includes(ascii(0, 6))
      : bytes.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WEBP';
    if (!ok) throw new CloudError('图片格式与文件内容不匹配。', 400);
  }
  function imageExtension(mime) {
    return ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' })[mime];
  }
  async function uploadObject(path, file, token) {
    const headers = new Headers({ 'apikey': publishableKey, 'Authorization': `Bearer ${token}`, 'Content-Type': file.type, 'x-upsert': 'false' });
    const response = await nativeFetch(`${projectUrl}/storage/v1/object/${bucket}/${encodeStoragePath(path)}`, { method: 'POST', headers, body: file });
    const data = await parseJsonText(response);
    if (!response.ok) throw new CloudError(messageOf(data), response.status);
    return data;
  }

  // XLSX support is loaded only if the existing import button is used with an .xlsx file.
  let xlsxLoading = null;
  function loadXlsxLibrary() {
    if (window.XLSX) return Promise.resolve(window.XLSX);
    if (xlsxLoading) return xlsxLoading;
    xlsxLoading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';
      script.async = true;
      script.onload = () => window.XLSX ? resolve(window.XLSX) : reject(new CloudError('XLSX 解析库加载失败。', 503));
      script.onerror = () => reject(new CloudError('无法加载 XLSX 解析库；请检查网络，或将工作簿另存为 CSV 后导入。', 503));
      document.head.appendChild(script);
    });
    return xlsxLoading;
  }

  function parseCsv(text) {
    const rows = [];
    let row = [], cell = '', quoted = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (quoted) {
        if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
        else if (ch === '"') quoted = false;
        else cell += ch;
      } else if (ch === '"') quoted = true;
      else if (ch === ',') { row.push(cell); cell = ''; }
      else if (ch === '\n') { row.push(cell.replace(/\r$/, '')); rows.push(row); row = []; cell = ''; }
      else cell += ch;
    }
    if (cell.length || row.length) { row.push(cell.replace(/\r$/, '')); rows.push(row); }
    return rows;
  }

  const aliases = {
    drug_id:'drug_id', drug_name:'drug_name', renal_function_level:'renal_function_level',
    ccr_min:'ccr_min', ccr_max:'ccr_max', dose_unit:'dose_unit', dose_value:'dose_value',
    dose_total_value:'dose_total_value', dose_description:'dose_description', adjustment_rule:'adjustment_rule',
    special_notes:'special_notes', reference:'reference',
    '药物英文名':'drug_id', '药物中文名':'drug_name', '肾功能分级':'renal_function_level',
    'ccr范围最低值':'ccr_min', 'ccr范围最高值':'ccr_max', '血肌酐衡量单位':'dose_unit',
    '单次推荐剂量':'dose_value', '总剂量':'dose_total_value', '推荐剂量描述':'dose_description',
    '具体意见':'adjustment_rule', '特别提示':'special_notes', '特殊提示':'special_notes',
    '参考来源':'reference', '参考文献':'reference', '来源':'reference'
  };
  async function fileToTable(file) {
    if (file.size > 20 * 1024 * 1024) throw new CloudError('导入文件超过 20 MB。', 413);
    const lower = file.name.toLowerCase();
    if (lower.endsWith('.csv')) {
      const bytes = await file.arrayBuffer();
      let text;
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
      catch (_) { text = new TextDecoder('gb18030').decode(bytes); }
      return parseCsv(text.replace(/^\uFEFF/, ''));
    }
    if (lower.endsWith('.xlsx')) {
      const XLSX = await loadXlsxLibrary();
      const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: false });
      const sheet = workbook.Sheets[workbook.SheetNames[0]];
      if (!sheet) throw new CloudError('Excel 文件中没有找到工作表。', 400);
      return XLSX.utils.sheet_to_json(sheet, { header: 1, raw: false, defval: '' });
    }
    if (lower.endsWith('.xls')) throw new CloudError('不支持旧版 .xls 文件；请另存为 .xlsx 或 .csv 后导入。', 400);
    throw new CloudError('仅支持 .xlsx 或 .csv 文件。', 400);
  }
  function tableToRecords(table) {
    if (!Array.isArray(table) || !table.length) throw new CloudError('文件内容为空。', 400);
    let headerIndex = -1, mapped = [];
    for (let i = 0; i < Math.min(8, table.length); i++) {
      const names = (table[i] || []).map(value => aliases[String(value == null ? '' : value).replace(/\uFEFF/g, '').trim().toLowerCase()] || null);
      if (names.includes('drug_id') && names.includes('drug_name')) { headerIndex = i; mapped = names; break; }
    }
    if (headerIndex < 0) throw new CloudError('未识别到药品表头。请使用包含 drug_id、drug_name 的 CSV/XLSX 表格。', 400);
    const records = [];
    for (const sourceRow of table.slice(headerIndex + 1)) {
      if (!Array.isArray(sourceRow) || !sourceRow.some(value => String(value == null ? '' : value).trim())) continue;
      const row = Object.fromEntries(fields.map(field => [field, '']));
      sourceRow.forEach((value, index) => {
        const field = mapped[index];
        if (field) row[field] = String(value == null ? '' : value).trim();
      });
      if (['药物英文名','drug_id'].includes(row.drug_id) || ['药物中文名','drug_name'].includes(row.drug_name)) continue;
      if (!row.drug_id || !row.drug_name) continue;
      row._id = newId();
      records.push(row);
    }
    if (!records.length) throw new CloudError('没有找到有效药品记录（需要药物英文名和中文名）。', 400);
    return records;
  }
  const recordKey = row => JSON.stringify(['drug_id','drug_name','renal_function_level','ccr_min','ccr_max'].map(key => String(row[key] || '').trim()));

  async function importFile(file, mode, token) {
    if (!file) throw new CloudError('请先选择 .xlsx 或 .csv 文件。', 400);
    const imported = tableToRecords(await fileToTable(file));
    const current = await readDatabase(token);
    const existing = current.records || [];
    let merged;
    if (mode === 'replace') {
      const oldByKey = new Map(existing.map(row => [recordKey(row), row]));
      merged = imported.map(row => {
        const old = oldByKey.get(recordKey(row));
        return { ...row, _id: old && old._id ? old._id : row._id };
      });
    } else {
      merged = existing.map(row => ({ ...row }));
      const index = new Map(merged.map((row, i) => [recordKey(row), i]));
      for (const row of imported) {
        const key = recordKey(row);
        if (index.has(key)) {
          const i = index.get(key);
          row._id = merged[i]._id || row._id;
          merged[i] = row;
        } else {
          index.set(key, merged.length);
          merged.push(row);
        }
      }
    }
    const valid = new Set(merged.map(drugKey));
    const qr = Object.fromEntries(Object.entries(current.qr || {}).filter(([key]) => valid.has(key)));
    const db = await saveDatabase({ records: merged, qr }, token);
    return { db, imported: imported.length, total: db.records.length, mode: mode === 'replace' ? 'replace' : 'merge' };
  }

  async function uploadQr(file, key, filename, token) {
    const database = await readDatabase(token);
    if (!database.records.some(row => drugKey(row) === key)) throw new CloudError('该药品不在当前数据库中，无法关联二维码。', 404);
    await validateImage(file);
    const path = `qr/${newId()}.${imageExtension(file.type)}`;
    await uploadObject(path, file, token);
    const qr = { ...(database.qr || {}) };
    qr[key] = { storagePath: path, originalName: safeFilename(filename || file.name), updatedAt: new Date().toISOString() };
    try {
      const saved = await saveDatabase({ records: database.records, qr }, token);
      return { ok: true, qr: saved.qr[key], database: saved };
    } catch (error) {
      await removeStorageObjects([path], token);
      throw error;
    }
  }

  async function deleteQr(key, token) {
    const database = await readDatabase(token);
    const qr = { ...(database.qr || {}) };
    delete qr[key];
    return saveDatabase({ records: database.records, qr }, token);
  }

  async function routeApi(url, method, requestHeaders, init) {
    const path = url.pathname;
    if (path === '/api/config' && method === 'GET') {
      return jsonResponse({ readOnly: false, configured, authProvider: 'supabase' });
    }
    if (path === '/api/auth' && method === 'GET') {
      if (!configured) return jsonResponse({ authenticated: false, username: '' });
      const session = await validSession();
      if (!session) return jsonResponse({ authenticated: false, username: '' });
      try {
        const allowed = await adminStatus(session.access_token);
        if (!allowed) { sessionClear(); return jsonResponse({ authenticated: false, username: '' }); }
        return jsonResponse({ authenticated: true, username: 'admin' });
      } catch (_) {
        sessionClear();
        return jsonResponse({ authenticated: false, username: '' });
      }
    }
    if (path === '/api/login' && method === 'POST') {
      requireConfig();
      if (!maintenanceEmail || /YOUR_|REPLACE_ME/i.test(maintenanceEmail)) throw new CloudError('请先在 site/supabase-config.js 填写管理员 Supabase Auth 邮箱。', 503);
      let body = {};
      try { body = JSON.parse(typeof init.body === 'string' ? init.body : '{}'); } catch (_) {}
      const username = String(body.username || '').trim();
      const password = String(body.password || '');
      if (username !== 'admin') throw new CloudError('用户名或密码错误。', 401);
      if (!password) throw new CloudError('请输入密码。', 400);
      let session = null;
      try {
        const result = await sbRequest('auth/v1/token?grant_type=password', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: maintenanceEmail, password })
        });
        session = sessionWrite(result);
        if (!(await adminStatus(session.access_token))) {
          try { await sbRequest('auth/v1/logout', { method: 'POST', token: session.access_token }); } catch (_) {}
          sessionClear();
          throw new CloudError('该账号已通过登录验证，但尚未加入 Supabase 管理员白名单。请按部署说明登记 Auth User UUID。', 403);
        }
        return jsonResponse({ ok: true, username: 'admin', token: session.access_token });
      } catch (error) {
        if (session) sessionClear();
        throw error;
      }
    }
    if (path === '/api/logout' && method === 'POST') {
      if (configured) {
        const session = await validSession();
        if (session && session.access_token) {
          try { await sbRequest('auth/v1/logout', { method: 'POST', token: session.access_token }); } catch (_) {}
        }
      }
      sessionClear();
      return jsonResponse({ ok: true });
    }
    if (path === '/api/db' && method === 'GET') {
      const session = configured ? await validSession() : null;
      const database = await readDatabase(session && session.access_token ? session.access_token : null);
      return jsonResponse(database);
    }
    if (path === '/api/db' && method === 'POST') {
      const token = await requireAdmin();
      let payload;
      try { payload = JSON.parse(typeof init.body === 'string' ? init.body : '{}'); }
      catch (_) { throw new CloudError('保存内容不是有效 JSON。', 400); }
      return jsonResponse(await saveDatabase(payload, token));
    }
    if (path === '/api/import' && method === 'POST') {
      const token = await requireAdmin();
      const file = init.body;
      const mode = url.searchParams.get('mode') || 'merge';
      return jsonResponse(await importFile(file, mode, token));
    }
    if (path === '/api/qr' && method === 'POST') {
      const token = await requireAdmin();
      const key = url.searchParams.get('key') || '';
      if (!key || !key.includes('||')) throw new CloudError('缺少有效药品标识。', 400);
      const file = init.body;
      const filename = url.searchParams.get('filename') || (file && file.name) || '说明书二维码';
      return jsonResponse(await uploadQr(file, key, filename, token));
    }
    if (path === '/api/qr' && method === 'DELETE') {
      const token = await requireAdmin();
      const key = url.searchParams.get('key') || '';
      if (!key || !key.includes('||')) throw new CloudError('缺少有效药品标识。', 400);
      return jsonResponse(await deleteQr(key, token));
    }
    throw new CloudError('API endpoint not found', 404);
  }

  window.fetch = async function(input, init = {}) {
    let url;
    try {
      url = new URL(typeof input === 'string' || input instanceof URL ? String(input) : input.url, window.location.href);
    } catch (_) { return nativeFetch(input, init); }
    if (url.origin !== window.location.origin || !url.pathname.startsWith('/api/')) return nativeFetch(input, init);
    const method = String(init.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();
    const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
    try { return await routeApi(url, method, headers, init); }
    catch (error) {
      const status = Number(error && error.status) || 500;
      return jsonResponse({ error: error && error.message ? error.message : '云端请求失败' }, status);
    }
  };
})();
