/* Black Canvas team portal: connection to Supabase.
   Fill these two values from Supabase > Project Settings > API (or "API Keys"):
   - supabaseUrl: the Project URL, like https://abcdefghijklm.supabase.co
   - supabaseKey: the publishable key (sb_publishable_...) or the legacy "anon public" key.
   Both are designed to be public. The data stays private because of the access
   rules in supabase/setup.sql. Never put the secret or service_role key here. */
window.BC_PORTAL = {
  supabaseUrl: "",
  supabaseKey: ""
};
