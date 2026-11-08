// Black Canvas portal: lets portal admins invite people by email.
// Deployed to Supabase as the Edge Function "portal-invite" (verify_jwt off: it checks the caller itself).
// The caller must be signed in (their session token in Authorization) and be an
// admin in public.portal_access. The person must already have an access row.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const ORIGINS = ["https://blackcanvas.live", "https://www.blackcanvas.live", "https://blackcanvasglobal.com", "https://www.blackcanvasglobal.com"];
const PORTAL_URL = "https://blackcanvas.live/portal/";

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "Use POST." });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return reply(req, 500, { error: "The invite service isn't configured." });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // Who is calling?
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token || token.startsWith("sb_")) return reply(req, 401, { error: "Sign in to the portal first." });
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  const callerEmail = who?.user?.email?.toLowerCase();
  if (whoErr || !callerEmail) return reply(req, 401, { error: "Your sign-in has expired. Sign in again." });

  const { data: me } = await admin.from("portal_access").select("is_admin").eq("email", callerEmail).maybeSingle();
  if (!me?.is_admin) return reply(req, 403, { error: "Only portal admins can send invites." });

  // Who to invite?
  let email = "";
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
  } catch {
    return reply(req, 400, { error: "Send the email to invite." });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply(req, 400, { error: "Enter a valid email address." });

  const { data: row } = await admin.from("portal_access").select("email").eq("email", email).maybeSingle();
  if (!row) return reply(req, 400, { error: "Add this person to Team access before inviting them." });

  const { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: PORTAL_URL });
  if (!error) return reply(req, 200, { status: "invited" });

  const msg = error.message ?? "";
  if (/already.*registered|already exists|email_exists/i.test(msg) || (error as { code?: string }).code === "email_exists") {
    // They already have an account (invited before, or signed in already): send a
    // link to set a password instead, which also finishes an unaccepted invite.
    const { error: rErr } = await admin.auth.resetPasswordForEmail(email, { redirectTo: PORTAL_URL });
    if (!rErr) return reply(req, 200, { status: "link_sent" });
    return reply(req, 502, { error: friendly(rErr.message ?? "") });
  }
  return reply(req, 502, { error: friendly(msg) });
});

function friendly(m: string): string {
  if (/rate limit|too many/i.test(m)) return "Supabase's email limit for this hour is used up. Try again later, or set up your own email sender in Supabase.";
  if (/not authorized|not_authorized/i.test(m)) return "Supabase's built-in email can only reach members of your Supabase organization. Set up your own email sender in Supabase to invite anyone.";
  return m || "Couldn't send the invite. Try again.";
}
