/**
 * CPL Lead Tracker · ฟอร์มลูกค้า → Google Sheets + Google Drive
 * ติดตั้งในบัญชี apisit@cpl-inter.com (Apps Script) แล้ว Deploy เป็น Web app
 *   Execute as: Me · Who has access: Anyone
 * ไฟล์ทั้งหมดอยู่ในโฟลเดอร์ "CPL Forms" ใน Drive ของบัญชีนี้
 *   CPL Forms/<แบรนด์>/  ← ชีตของแบรนด์ (แท็บ Booking / Account Application) และโฟลเดอร์ไฟล์แนบ
 */
const SUPABASE_URL = 'https://mdhtrioxacscstaqmlvy.supabase.co';
const SUPABASE_KEY = 'sb_publishable_00Ly9BUyenzeyyn9cWiCxQ_0HzrxeSF';
const ROOT_NAME = 'CPL Forms';
const BRANDS = ['CPL-Inter', 'CPLEx', 'CLMV', 'IMTH'];
const KIND_NAME = { book: 'Booking', acc: 'Account Application' };
const MAX_FILE = 10 * 1024 * 1024;

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    const form = getForm_(body.token);
    if (!form) return out_({ ok: false, error: 'not_found' });
    if (form.status !== 'sent') return out_({ ok: false, error: 'already_sent' });
    const brand = BRANDS.indexOf(form.brand) >= 0 ? form.brand : 'CPL-Inter';
    const kind = KIND_NAME[form.kind] ? form.kind : 'book';
    const lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try {
      const brandFolder = folder_(folder_(DriveApp.getRootFolder(), ROOT_NAME), brand);
      const files = saveFiles_(brandFolder, kind, body);
      const sheetUrl = appendRow_(brandFolder, brand, kind, body, files);
      return out_({ ok: true, sheet: sheetUrl, files: files });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return out_({ ok: false, error: String(err) });
  }
}

function doGet() {
  return out_({ ok: true });
}

function getForm_(token) {
  if (!/^[0-9a-f-]{36}$/i.test(String(token || ''))) return null;
  const r = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/rpc/form_get', {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY },
    payload: JSON.stringify({ p_token: token }),
    muteHttpExceptions: true
  });
  if (r.getResponseCode() !== 200) return null;
  return JSON.parse(r.getContentText() || 'null');
}

function folder_(parent, name) {
  const it = parent.getFoldersByName(name);
  return it.hasNext() ? it.next() : parent.createFolder(name);
}

function saveFiles_(brandFolder, kind, body) {
  const list = Array.isArray(body.files) ? body.files : [];
  if (!list.length) return [];
  const company = String(body.company || 'ลูกค้า').replace(/[\\/:*?"<>|]/g, ' ').slice(0, 80);
  const stamp = Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM-dd HHmm');
  const dir = folder_(folder_(brandFolder, 'ไฟล์แนบ ' + KIND_NAME[kind]), stamp + ' ' + company);
  return list.map(function (f) {
    const bytes = Utilities.base64Decode(f.data);
    if (bytes.length > MAX_FILE) throw new Error('file_too_large');
    const blob = Utilities.newBlob(bytes, f.mime || 'application/octet-stream', String(f.name || 'file').slice(0, 120));
    const file = dir.createFile(blob);
    return { label: String(f.label || ''), le: String(f.le || ''), name: file.getName(), url: file.getUrl() };
  });
}

function appendRow_(brandFolder, brand, kind, body, files) {
  const ss = spreadsheet_(brandFolder, brand);
  const tabName = KIND_NAME[kind];
  const sh = ss.getSheetByName(tabName) || ss.insertSheet(tabName);
  const answers = Array.isArray(body.answers) ? body.answers : [];
  const fileCols = {};
  files.forEach(function (f) { fileCols[f.label] = (fileCols[f.label] ? fileCols[f.label] + '\n' : '') + f.url; });
  const fixed = ['วันที่ส่ง', 'เซลล์', 'รหัสฟอร์ม'];
  const labels = answers.map(function (a) { return String(a.l); }).concat(Object.keys(fileCols));
  let header = sh.getLastRow() ? sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String) : [];
  if (!header.length) {
    header = fixed.slice();
    sh.appendRow(header);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, header.length).setFontWeight('bold');
  }
  labels.forEach(function (l) {
    if (header.indexOf(l) < 0) {
      header.push(l);
      sh.getRange(1, header.length).setValue(l).setFontWeight('bold');
    }
  });
  const row = new Array(header.length).fill('');
  row[header.indexOf('วันที่ส่ง')] = Utilities.formatDate(new Date(), 'Asia/Bangkok', 'dd/MM/yyyy HH:mm');
  row[header.indexOf('เซลล์')] = String(body.sales || '');
  row[header.indexOf('รหัสฟอร์ม')] = String(body.token || '');
  answers.forEach(function (a) { row[header.indexOf(String(a.l))] = String(a.v == null ? '' : a.v); });
  Object.keys(fileCols).forEach(function (l) { row[header.indexOf(l)] = fileCols[l]; });
  sh.appendRow(row);
  const n = sh.getLastRow();
  return ss.getUrl() + '#gid=' + sh.getSheetId() + '&range=A' + n;
}

function spreadsheet_(brandFolder, brand) {
  const name = 'ฟอร์มลูกค้า · ' + brand;
  const it = brandFolder.getFilesByName(name);
  if (it.hasNext()) return SpreadsheetApp.open(it.next());
  const ss = SpreadsheetApp.create(name);
  const f = DriveApp.getFileById(ss.getId());
  brandFolder.addFile(f);
  DriveApp.getRootFolder().removeFile(f);
  ss.getSheets()[0].setName(KIND_NAME.book);
  ss.insertSheet(KIND_NAME.acc);
  return ss;
}

function out_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

/** กด Run ฟังก์ชันนี้ 1 ครั้งหลังวางสคริปต์ เพื่ออนุญาตสิทธิ์และสร้างโฟลเดอร์ + ชีตทั้ง 4 แบรนด์ */
function setup() {
  const root = folder_(DriveApp.getRootFolder(), ROOT_NAME);
  BRANDS.forEach(function (b) { spreadsheet_(folder_(root, b), b); });
  UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/', { muteHttpExceptions: true, headers: { apikey: SUPABASE_KEY } });
  Logger.log('พร้อมใช้งาน: ' + root.getUrl());
}
