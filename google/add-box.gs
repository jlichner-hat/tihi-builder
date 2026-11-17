// Adds a box to the company box inventory sheet. Ti:Hi Builder's "Add to company boxes" buttons
// send the box here through the box-inventory Supabase function, which checks the person's role first.
//
// Setup (once):
// 1. Open the box inventory Google Sheet (the one the site reads), then Extensions > Apps Script.
// 2. Replace the code there with this file and click Save.
// 3. Project Settings (gear) > Script Properties > Add script property:
//      ADD_TOKEN = a long random password (keep it secret; it also goes into Supabase).
// 4. If the box list isn't the first tab, put its tab name in TAB below.
// 5. Deploy > New deployment > type "Web app". Execute as: Me. Who has access: Anyone. Deploy,
//    approve the access prompt, and copy the Web app URL.
// 6. In Supabase (Edge Functions > Secrets) add BOX_INVENTORY_ADD_URL = that URL and
//    BOX_INVENTORY_ADD_TOKEN = the same password as ADD_TOKEN.
const TAB = ""; // blank = the first tab

function doPost(e) {
  const out = o => ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
  try {
    const d = JSON.parse(e.postData.contents);
    const token = PropertiesService.getScriptProperties().getProperty("ADD_TOKEN");
    if (!token || d.token !== token) return out({ ok: false, error: "Not allowed." });
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sh = TAB ? ss.getSheetByName(TAB) : ss.getSheets()[0];
    if (!sh) return out({ ok: false, error: "The tab " + TAB + " wasn't found." });
    const lock = LockService.getScriptLock();
    lock.waitLock(15000);
    try {
      const cols = sh.getLastColumn(), top = sh.getRange(1, 1, Math.min(10, Math.max(1, sh.getLastRow())), cols).getDisplayValues();
      // Same header matching as the site: "Inside L (in)" -> "l", "Interior Length" -> "length".
      const key = h => String(h).toLowerCase().replace(/\(.*?\)/g, "").replace(/[^a-z0-9]/g, "")
        .replace(/^(inside|interior|internal|int|id|box)(?=[a-z])/, "").replace(/(inches|inch|in)$/, "");
      let hr = -1, c = null;
      for (let i = 0; i < top.length && hr < 0; i++) {
        const k = top[i].map(key), f = t => k.findIndex(t);
        const L = f(x => x === "l" || x === "len" || x.startsWith("length")),
              W = f(x => x === "w" || x === "wid" || x.startsWith("width")),
              H = f(x => x === "h" || x === "d" || x === "ht" || x.startsWith("height") || x.startsWith("depth"));
        if (L >= 0 && W >= 0 && H >= 0) {
          hr = i;
          c = { L, W, H,
            N: f(x => /^(box|boxname|name|item|itemno|itemnumber|itemnum|sku|part|partno|partnumber|model|boxid|id|code)$/.test(x)),
            D: f(x => x.includes("desc") || x.includes("note") || x.includes("comment")) };
        }
      }
      if (hr < 0) return out({ ok: false, error: "Couldn't find Length, Width and Height columns in the sheet." });
      const name = String(d.name || "").trim();
      if (c.N >= 0 && name && sh.getLastRow() > hr + 1) {
        const names = sh.getRange(hr + 2, c.N + 1, sh.getLastRow() - hr - 1, 1).getDisplayValues().map(r => r[0].trim().toLowerCase());
        if (names.indexOf(name.toLowerCase()) >= 0) return out({ ok: false, error: name + " is already in the sheet." });
      }
      const row = new Array(cols).fill("");
      row[c.L] = +d.length; row[c.W] = +d.width; row[c.H] = +d.height;
      if (c.N >= 0) row[c.N] = name;
      if (c.D >= 0 && d.notes) row[c.D] = String(d.notes);
      sh.appendRow(row);
      return out({ ok: true, row: sh.getLastRow(), tab: sh.getName() });
    } finally { lock.releaseLock(); }
  } catch (err) {
    return out({ ok: false, error: String((err && err.message) || err) });
  }
}
