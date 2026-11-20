// Serves the box inventory (the Google Sheet's CSV) only to signed-in Packaging engineers,
// Admins and site admins, and lets them add a box to the sheet (POST). With ?stocked=1 it serves only the
// boxes marked Yes in the sheet's "Stocked at HAT" column, and any signed-in user of an approved company
// may read that (the Replacement Part page, which has the same access as the Shipment builder). The sheet's link lives in the BOX_INVENTORY_CSV_URL secret,
// so it never reaches the browser or this repo.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const reply = (status: number, body: string, type = "text/plain; charset=utf-8") =>
  new Response(body, { status, headers: { ...cors, "Content-Type": type, "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply(401, "Sign in to see the box inventory.");

  // Query as the caller, so row level security applies: they can read only their own profile and admin row.
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: userErr } = await sb.auth.getUser(auth.slice(7));
  if (userErr || !user) return reply(401, "Sign in to see the box inventory.");

  const [{ data: prof }, { data: adm }] = await Promise.all([
    sb.from("profiles").select("*, companies(status)").eq("id", user.id).maybeSingle(),
    sb.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle(),
  ]);
  const approved = (prof?.companies as { status?: string } | null)?.status === "approved";
  const active = prof?.active !== false; // deactivated accounts (supabase/deactivate-users.sql) are refused
  const allowed = active && (!!adm || (approved && (prof?.role === "engineer" || prof?.role === "company_admin")));
  const stockedOnly = req.method === "GET" && new URL(req.url).searchParams.get("stocked") === "1";
  if (stockedOnly && !(active && (!!adm || approved))) return reply(403, "Your account can't see the stocked boxes.");
  if (!stockedOnly && !allowed) return reply(403, "Only Packaging engineers and Admins can see the box inventory.");

  // POST adds a box to the sheet through its Apps Script web app (google/add-box.gs).
  // The script's URL and password are Supabase secrets, so they never reach the browser.
  if (req.method === "POST") {
    const addUrl = Deno.env.get("BOX_INVENTORY_ADD_URL"), token = Deno.env.get("BOX_INVENTORY_ADD_TOKEN");
    if (!addUrl || !token) return reply(404, "Adding boxes to the sheet isn't set up yet.");
    let b: { name?: unknown; length?: unknown; width?: unknown; height?: unknown; notes?: unknown };
    try { b = await req.json(); } catch { return reply(400, "Send the box as JSON."); }
    const name = String(b.name ?? "").trim(), notes = String(b.notes ?? "").trim();
    const dims = [b.length, b.width, b.height].map(Number);
    if (!name || name.length > 80) return reply(400, "Give the box a name of up to 80 characters.");
    if (notes.length > 200) return reply(400, "Keep notes under 200 characters.");
    if (dims.some((v) => !(v > 0 && v <= 240))) return reply(400, "Length, width and height must be between 0 and 240 in.");
    const r = await fetch(addUrl, {
      method: "POST", redirect: "follow", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token, name, length: dims[0], width: dims[1], height: dims[2], notes, addedBy: user.email ?? "" }),
    });
    const text = await r.text();
    let res: { ok?: boolean; error?: string; row?: number; tab?: string };
    try { res = JSON.parse(text); } catch { return reply(502, "The sheet's script didn't answer. Check that the web app is deployed for Anyone."); }
    if (!res.ok) return reply(400, res.error || "The sheet didn't add the box.");
    return reply(200, JSON.stringify(res), "application/json");
  }

  const url = Deno.env.get("BOX_INVENTORY_CSV_URL");
  if (!url) return reply(404, "The box inventory isn't connected yet.");
  const r = await fetch(url, { redirect: "follow" });
  if (!r.ok) return reply(502, `The sheet answered ${r.status}.`);
  const csv = await r.text();
  return reply(200, stockedOnly ? stockedRows(csv) : csv, "text/csv; charset=utf-8");
});

// Keeps the rows above and including the header, plus the rows whose "Stocked at HAT" cell says yes.
// The header is the first row with a stocked column (same names the site looks for in index.html).
const STOCK_HEAD = /^(stocked|instock|stockitem|stockeditem|carried|carry|wecarry|ininventory|inventoryitem|keptinstock)/;
const key = (h: string) => h.toLowerCase().replace(/\(.*?\)/g, "").replace(/[^a-z0-9]/g, "")
  .replace(/^(inside|interior|internal|int|id|box)(?=[a-z])/, "").replace(/(inches|inch|in)$/, "");
function stockedRows(text: string): string {
  const rows = parseCsv(text);
  let hi = -1, col = -1;
  for (let i = 0; i < rows.length && hi < 0; i++) {
    const k = rows[i].map((h) => key(h.trim()));
    const c = k.findIndex((h) => STOCK_HEAD.test(h) || /^(stock|inventory)$/.test(h));
    // the header row also names the box size (Length, or one Dimensions column), so a title row can't match
    if (c >= 0 && k.some((h) => /^(l|len|length)$|length|dimension|^dims$|^size$/.test(h))) { hi = i; col = c; }
  }
  if (hi < 0) return rows.slice(0, 2).map(toCsv).join("\n"); // no stocked column: header only, no boxes
  const yes = /^(y|yes|true|x|1|stocked|in stock)$/i;
  return rows.filter((r, i) => i <= hi || yes.test((r[col] ?? "").trim())).map(toCsv).join("\n");
}
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], f = "", q = false;
  text = text.replace(/^\uFEFF/, "");
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"' && f === "") q = true;
    else if (c === ",") { row.push(f); f = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(f); rows.push(row); row = []; f = ""; }
    else f += c;
  }
  if (f !== "" || row.length) { row.push(f); rows.push(row); }
  return rows;
}
const toCsv = (r: string[]) => r.map((v) => /[",\n\r]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v).join(",");
