/**
 * นำเข้าข้อมูลเก่าจาก Jotform → ฟอร์ม (Supabase) + ไฟล์แนบ → Google Drive
 * วางไฟล์นี้ในโปรเจกต์ Apps Script เดียวกับ forms-apps-script.gs
 * Project Settings → Script Properties ต้องมี:
 *   JOTFORM_KEY   = API Key ของ Jotform
 *   IMPORT_SECRET = รหัสเดียวกับที่ใส่ในตาราง form_admin (Supabase)
 *   JOTFORM_HOST  = (ไม่บังคับ) eu-api.jotform.com ถ้าบัญชีอยู่ฝั่งยุโรป  ค่าเริ่มต้น api.jotform.com
 * วิธีใช้: เลือกฟังก์ชัน importJotform → Run ครั้งเดียว สคริปต์จะทำต่อเองทุก ~6 นาทีจนเสร็จ (ดูผลที่เมนู การดำเนินการ)
 * รันซ้ำได้ปลอดภัย: รายการที่นำเข้าแล้วจะไม่ซ้ำ
 */
const JF_FORMS = [
  ['232398989456479', 'book'], ['222842451151448', 'book'], ['232492147856464', 'book'], ['222832458107051', 'book'],
  ['222899217007460', 'book'], ['233328375164458', 'book'], ['240681385967470', 'book'], ['233342101447445', 'book'],
  ['230218323895457', 'book'], ['233201895233452', 'book'], ['223072144655452', 'book'],
  ['223452002664447', 'acc'], ['230292508920453', 'acc'],
  ['223287965885072', 'job'], ['223537905149461', 'claim'],
  ['223110518338448', 'tc'], ['223110756744453', 'tc'], ['223109073476455', 'tc']
];
const JF_KIND_FOLDER = { book: 'Booking', acc: 'Account Application', job: 'ใบสมัครงาน', claim: 'Claim', tc: 'Terms & Conditions' };
const JF_SKIP = ['control_head', 'control_button', 'control_text', 'control_collapse', 'control_pagebreak', 'control_divider', 'control_image', 'control_captcha'];
const JF_BUDGET_MS = 300000;

function importJotform() {
  const P = PropertiesService.getScriptProperties();
  const key = P.getProperty('JOTFORM_KEY'), secret = P.getProperty('IMPORT_SECRET');
  if (!key || !secret) throw new Error('ตั้งค่า JOTFORM_KEY และ IMPORT_SECRET ใน Script Properties ก่อน');
  const host = P.getProperty('JOTFORM_HOST') || 'api.jotform.com';
  const t0 = Date.now();
  let state = JSON.parse(P.getProperty('JF_STATE') || '{"i":0,"off":0,"n":0}');
  const root = folder_(folder_(DriveApp.getRootFolder(), ROOT_NAME), 'Jotform เดิม');
  while (state.i < JF_FORMS.length) {
    const fid = JF_FORMS[state.i][0], kind = JF_FORMS[state.i][1];
    const info = jf_(host, '/form/' + fid, key, '');
    const title = info.content.title || fid;
    const brand = brandOf_(title);
    const formFolder = folder_(root, brand + ' · ' + title.replace(/[\\/:*?"<>|]/g, ' ').slice(0, 60));
    for (;;) {
      if (Date.now() - t0 > JF_BUDGET_MS) { P.setProperty('JF_STATE', JSON.stringify(state)); schedule_(); Logger.log('พักรอบนี้ — จะทำต่อเองอัตโนมัติในอีก 1 นาที (นำเข้าแล้ว ' + state.n + ')'); return; }
      const res = jf_(host, '/form/' + fid + '/submissions', key, '&limit=20&offset=' + state.off + '&orderby=created_at&direction=ASC');
      const subs = (res.content || []).filter(function (s) { return s.status !== 'DELETED'; });
      if (!(res.content || []).length) break;
      const rows = subs.map(function (s) { return row_(s, kind, brand, formFolder, key); });
      if (rows.length) {
        const r = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/form_import', {
          method: 'post', contentType: 'application/json',
          headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY },
          payload: JSON.stringify({ p_secret: secret, p_rows: rows }), muteHttpExceptions: true
        });
        if (r.getResponseCode() !== 200) throw new Error('Supabase: ' + r.getContentText());
        state.n += Number(r.getContentText()) || 0;
      }
      state.off += (res.content || []).length;
      if ((res.content || []).length < 20) break;
    }
    state.i++; state.off = 0;
    P.setProperty('JF_STATE', JSON.stringify(state));
  }
  P.deleteProperty('JF_STATE');
  unschedule_();
  Logger.log('เสร็จทั้งหมด — นำเข้าใหม่ ' + state.n + ' รายการ');
}

/** ให้นำเข้าทำต่อเองทุกครั้งที่พักรอบ จนเสร็จ (ไม่ต้องกด Run ซ้ำ) */
function schedule_() {
  unschedule_();
  ScriptApp.newTrigger('importJotform').timeBased().after(60 * 1000).create();
}
function unschedule_() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'importJotform') ScriptApp.deleteTrigger(t);
  });
}

/** หยุดการนำเข้าอัตโนมัติ */
function importJotformStop() { unschedule_(); }

function importJotformReset() { PropertiesService.getScriptProperties().deleteProperty('JF_STATE'); }

function jf_(host, path, key, qs) {
  const r = UrlFetchApp.fetch('https://' + host + path + '?apiKey=' + encodeURIComponent(key) + qs, { muteHttpExceptions: true });
  if (r.getResponseCode() !== 200) throw new Error('Jotform ' + r.getResponseCode() + ' ' + path + ' ' + r.getContentText().slice(0, 200));
  return JSON.parse(r.getContentText());
}

function brandOf_(title) {
  const t = String(title).toUpperCase();
  return t.indexOf('CLMV') >= 0 ? 'CLMV' : t.indexOf('IMTH') >= 0 ? 'IMTH' : t.indexOf('CPLEX') >= 0 ? 'CPLEx' : 'CPL-Inter';
}

function row_(s, kind, brand, formFolder, key) {
  const answers = [], files = [];
  let company = '', contact = '', nameGuess = '';
  const subFolderName = s.id;
  let sub = null;
  const qs = Object.keys(s.answers || {}).map(Number).sort(function (a, b) { return a - b; });
  qs.forEach(function (q) {
    const a = s.answers[q];
    if (!a || JF_SKIP.indexOf(a.type) >= 0) return;
    const label = String(a.text || a.name || '').trim();
    if (a.type === 'control_fileupload') {
      const urls = [].concat(a.answer || []).filter(Boolean);
      urls.forEach(function (u) {
        try {
          const resp = UrlFetchApp.fetch(u + (u.indexOf('?') < 0 ? '?' : '&') + 'apiKey=' + encodeURIComponent(key), { muteHttpExceptions: true });
          if (resp.getResponseCode() !== 200) throw new Error(resp.getResponseCode());
          const blob = resp.getBlob();
          if (blob.getBytes().length > 25 * 1024 * 1024) throw new Error('large');
          if (!sub) sub = formFolder.createFolder(subFolderName + ' ' + String(company || nameGuess || '').replace(/[\\/:*?"<>|]/g, ' ').slice(0, 50));
          const name = decodeURIComponent(String(u).split('/').pop().split('?')[0]) || 'file';
          const f = sub.createFile(blob.setName(name));
          files.push({ label: label, le: label, name: name, url: f.getUrl() });
        } catch (err) {
          files.push({ label: label, le: label, name: String(u).split('/').pop(), url: u });
        }
      });
      return;
    }
    let v = a.prettyFormat != null && a.prettyFormat !== '' ? a.prettyFormat : a.answer;
    if (v && typeof v === 'object') v = Array.isArray(v) ? v.join(', ') : Object.keys(v).map(function (k) { return v[k]; }).filter(String).join(' ');
    v = String(v == null ? '' : v).replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();
    if (!v) return;
    answers.push({ k: 'q' + q, l: label, e: label, v: v });
    if (!company && /company|บริษัท|ชื่อนิติ|shipper|ผู้ส่ง/i.test(label) && a.type !== 'control_email') company = v;
    if (!contact && /contact|ผู้ติดต่อ|ชื่อผู้/i.test(label) && !/phone|tel|โทร|mail/i.test(label)) contact = v;
    if (!nameGuess && /(name|ชื่อ)/i.test(label) && !/mail|file|ไฟล์/i.test(label)) nameGuess = v;
  });
  if (sub) sub.setDescription('Jotform submission ' + s.id);
  const at = new Date(String(s.created_at).replace(' ', 'T') + '+07:00').toISOString();
  return {
    jf_id: s.id, kind: kind, brand: brand, company: company || nameGuess, contact: contact || (company ? nameGuess : ''),
    answers: answers, files: files, at: at, folder: sub ? sub.getUrl() : null
  };
}
