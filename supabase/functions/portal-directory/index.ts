// Black Canvas portal: copies the company's Microsoft 365 directory into the portal, so
// Team access can suggest people (name, work email, job title) as an admin types.
// Deployed to Supabase as the Edge Function "portal-directory" (verify_jwt off: it checks the caller itself).
//
// Needs three secrets (Supabase > Edge Functions > Secrets), from an app registered in
// Microsoft Entra with the Microsoft Graph application permission User.Read.All:
//   MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET
// Without them it answers { status: "not_configured" } and the portal falls back to
// Staff and Crew only.
//
// Only enabled member accounts with a mailbox are copied (no guests, no disabled
// accounts), and only their name, email, job title and department.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const ORIGINS = ["https://blackcanvas.live", "https://www.blackcanvas.live"];
const FRESH_MINUTES = 30; // don't re-copy more often than this unless asked to

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(origin) ? origin : ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function reply(req: Request, status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });
}

type GraphUser = {
  displayName?: string | null; mail?: string | null; userPrincipalName?: string | null;
  jobTitle?: string | null; department?: string | null; accountEnabled?: boolean | null; userType?: string | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "Use POST." });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return reply(req, 500, { error: "The directory service isn't configured." });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // Only portal admins.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token || token.startsWith("sb_")) return reply(req, 401, { error: "Sign in to the portal first." });
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  const callerEmail = who?.user?.email?.toLowerCase();
  if (whoErr || !callerEmail) return reply(req, 401, { error: "Your sign-in has expired. Sign in again." });
  const { data: me } = await admin.from("portal_access").select("is_admin").eq("email", callerEmail).maybeSingle();
  if (!me?.is_admin) return reply(req, 403, { error: "Only portal admins can update the directory." });

  let force = false;
  try { force = !!(await req.json())?.force; } catch { /* no body is fine */ }

  const tenant = Deno.env.get("MS_TENANT_ID")?.trim();
  const clientId = Deno.env.get("MS_CLIENT_ID")?.trim();
  const secret = Deno.env.get("MS_CLIENT_SECRET")?.trim();
  if (!tenant || !clientId || !secret) return reply(req, 200, { status: "not_configured" });

  // Copied recently? Then there's nothing to do.
  const { data: last } = await admin.from("directory_people").select("synced_at").order("synced_at", { ascending: false }).limit(1).maybeSingle();
  if (!force && last?.synced_at && Date.now() - Date.parse(last.synced_at) < FRESH_MINUTES * 60_000) {
    return reply(req, 200, { status: "fresh", synced_at: last.synced_at });
  }

  // Sign in to Microsoft Graph as the app.
  const tokRes = await fetch(`https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: clientId, client_secret: secret, scope: "https://graph.microsoft.com/.default" }),
  });
  const tok = await tokRes.json().catch(() => ({}));
  if (!tokRes.ok || !tok.access_token) return reply(req, 502, { error: msSignInError(String(tok.error ?? ""), String(tok.error_description ?? "")) });

  // Read every user, page by page.
  const users: GraphUser[] = [];
  let next: string | null = "https://graph.microsoft.com/v1.0/users?$select=displayName,mail,userPrincipalName,jobTitle,department,accountEnabled,userType&$top=999";
  for (let page = 0; next && page < 50; page++) {
    const r = await fetch(next, { headers: { Authorization: `Bearer ${tok.access_token}` } });
    const body = await r.json().catch(() => ({}));
    if (!r.ok) return reply(req, 502, { error: msGraphError(r.status, String(body?.error?.code ?? ""), String(body?.error?.message ?? "")) });
    users.push(...(body.value ?? []));
    next = body["@odata.nextLink"] ?? null;
  }

  const runStart = new Date().toISOString();
  const rows = new Map<string, Record<string, unknown>>();
  for (const u of users) {
    if (u.accountEnabled === false) continue;
    if (u.userType && u.userType !== "Member") continue;
    const upn = (u.userPrincipalName ?? "").toLowerCase();
    const email = (u.mail ?? (upn.includes("#ext#") ? "" : upn)).trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || /\.onmicrosoft\.com$/.test(email)) continue;
    rows.set(email, {
      email,
      name: (u.displayName ?? "").trim() || email.split("@")[0],
      title: u.jobTitle?.trim() || null,
      dept: u.department?.trim() || null,
      active: true,
      synced_at: runStart,
    });
  }

  const list = [...rows.values()];
  for (let i = 0; i < list.length; i += 500) {
    const { error } = await admin.from("directory_people").upsert(list.slice(i, i + 500), { onConflict: "email" });
    if (error) return reply(req, 500, { error: "Couldn't save the directory. Try again." });
  }
  // People who have left or been disabled stop being suggested.
  await admin.from("directory_people").update({ active: false }).lt("synced_at", runStart).eq("active", true);

  return reply(req, 200, { status: "synced", count: list.length, synced_at: runStart });
});

function msSignInError(code: string, desc: string): string {
  if (/AADSTS7000215|AADSTS7000222|invalid_client/i.test(code + " " + desc)) return "Microsoft 365 didn't accept the app's client secret. It may have expired: make a new one in Entra and update MS_CLIENT_SECRET.";
  if (/AADSTS90002|AADSTS900023|tenant/i.test(desc)) return "Microsoft 365 didn't recognise the tenant ID. Check MS_TENANT_ID.";
  if (/AADSTS700016|unauthorized_client/i.test(code + " " + desc)) return "Microsoft 365 didn't recognise the app. Check MS_CLIENT_ID.";
  return "Couldn't sign in to Microsoft 365. Check the three MS_ secrets.";
}

function msGraphError(status: number, code: string, message: string): string {
  if (status === 403 || /Authorization_RequestDenied/i.test(code)) return "The Microsoft 365 app isn't allowed to read users yet. In Entra, give it the User.Read.All application permission and grant admin consent.";
  if (status === 429) return "Microsoft 365 is busy. Try again in a minute.";
  return message || "Couldn't read the Microsoft 365 directory. Try again.";
}
