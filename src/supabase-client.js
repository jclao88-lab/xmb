import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const config = window.XMB_SUPABASE_CONFIG || {};

export const supabase = createClient(config.url || "", config.anonKey || "", {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export function hasSupabaseConfig() {
  return Boolean(config.url && config.anonKey);
}
