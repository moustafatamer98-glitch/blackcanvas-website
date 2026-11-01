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
