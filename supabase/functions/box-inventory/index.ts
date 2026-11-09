// Serves the box inventory (the Google Sheet's CSV) only to signed-in Packaging engineers,
// Admins and site admins. The sheet's link lives in the BOX_INVENTORY_CSV_URL secret,
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
    sb.from("profiles").select("role, companies(status)").eq("id", user.id).maybeSingle(),
    sb.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle(),
  ]);
  const approved = (prof?.companies as { status?: string } | null)?.status === "approved";
  const allowed = !!adm || (approved && (prof?.role === "engineer" || prof?.role === "company_admin"));
  if (!allowed) return reply(403, "Only Packaging engineers and Admins can see the box inventory.");

  const url = Deno.env.get("BOX_INVENTORY_CSV_URL");
  if (!url) return reply(404, "The box inventory isn't connected yet.");
  const r = await fetch(url, { redirect: "follow" });
  if (!r.ok) return reply(502, `The sheet answered ${r.status}.`);
  return reply(200, await r.text(), "text/csv; charset=utf-8");
});
