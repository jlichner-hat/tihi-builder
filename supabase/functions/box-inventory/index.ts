// Serves the box inventory (the Google Sheet's CSV) only to signed-in Packaging engineers,
// Admins and site admins, and lets them add a box to the sheet (POST). The sheet's link lives in the BOX_INVENTORY_CSV_URL secret,
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
  if (!allowed) return reply(403, "Only Packaging engineers and Admins can see the box inventory.");

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
  return reply(200, await r.text(), "text/csv; charset=utf-8");
});
