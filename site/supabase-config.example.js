// Public browser configuration. These values are not passwords.
// Publishable keys are intended to be visible in a public webpage.
// NEVER put a Supabase Secret/service_role key or admin password here.
window.RENAL_SUPABASE_CONFIG = {
  url: "https://YOUR_PROJECT_REF.supabase.co",
  publishableKey: "sb_publishable_REPLACE_ME",
  // Supabase Auth email for the account whose page username remains "admin".
  // Use a dedicated admin mailbox/alias if you do not want your personal email public.
  maintenanceEmail: "admin@example.com"
};
