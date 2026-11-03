/* Shared by every portal page: the Supabase client and the logo. */
(function () {
  "use strict";
  var cfg = window.BC_PORTAL || {};
  var client = null;

  function configured() {
    return !!(cfg.supabaseUrl && cfg.supabaseKey && window.supabase && window.supabase.createClient);
  }

  window.BCPortal = {
    configured: configured,
    client: function () {
      if (client) return client;
      if (!configured()) return null;
      client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: "implicit", storageKey: "bc-portal-auth" }
      });
      return client;
    },
    /* The name to show for a user: their saved display name, else one made from the email
       (mo.tamer@... -> "Mo Tamer"). */
    displayName: function (user) {
      var m = (user && user.user_metadata) || {};
      var n = (m.display_name || m.full_name || m.name || "").trim();
      if (n) return n;
      var local = ((user && user.email) || "").split("@")[0];
      return local.split(/[._-]+/).filter(Boolean).map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join(" ");
    },
    /* Called by each app with the result of my_access(). For people whose access is
       temporary or tied to a project, shows a slim bar saying what they can see and until
       when, and remembers the access so saveError() can explain refused changes. */
    access: null,
    accessBanner: function (access) {
      this.access = access || null;
      if (!access || (!access.ends_at && !access.project_only)) return;
      var last = access.ends_at ? new Date(Date.parse(access.ends_at) - 1000) : null;
      var day = last ? new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Riyadh", weekday: "short", day: "numeric", month: "short" }).format(last) : "";
      var what = access.project_only && access.project ? access.project.name + " only"
        : access.kind === "project" && access.project ? "Access for " + access.project.name : "Temporary access";
      var bar = document.createElement("div");
      bar.setAttribute("role", "status");
      bar.style.cssText = "position:relative;z-index:50;display:flex;justify-content:center;gap:8px;padding:7px 16px;background:#F04E23;color:#0B0B0C;font:600 12.5px/1.3 'IBM Plex Mono',ui-monospace,Menlo,monospace;letter-spacing:.06em;text-transform:uppercase;text-align:center";
      bar.textContent = what + (day ? " · until " + day : "");
      document.body.insertBefore(bar, document.body.firstChild);
    },
    /* A plain explanation for a change the database refused because of the person's access. */
    saveError: function (e) {
      var m = (e && e.message) || "";
      if (!/row-level security|42501|permission denied/i.test(m)) return "";
      var a = this.access;
      if (a && a.project_only && a.project) return "You can only add or change things for " + a.project.name + ".";
      return "Your access doesn't allow this change. Ask a portal admin.";
    },
    /* kind: "line" (one-line logo) or "stack" (stacked primary logo) */
    logoSvg: function (kind, letters, dot) {
      var L = (window.BC_LOGO || {})[kind];
      if (!L) return "";
      return '<svg viewBox="0 0 ' + L.W + " " + L.H + '" role="img" aria-label="Black Canvas"><path fill="' + (letters || "currentColor") +
        '" fill-rule="evenodd" d="' + L.path + '"/><rect x="' + L.dot[0] + '" y="' + L.dot[1] + '" width="' + L.dot[2] + '" height="' + L.dot[3] +
        '" fill="' + (dot || "#F04E23") + '"/></svg>';
    }
  };
})();
