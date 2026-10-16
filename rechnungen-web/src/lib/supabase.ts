import { createClient } from '@supabase/supabase-js'

// Publishable-Key ist bewusst öffentlich (RLS schützt die Daten).
// Per .env.local (VITE_SUPABASE_URL / VITE_SUPABASE_KEY) überstimmbar.
const url =
  import.meta.env.VITE_SUPABASE_URL ?? 'https://yqnbjspyucmzfdraqccg.supabase.co'
const key =
  import.meta.env.VITE_SUPABASE_KEY ?? 'sb_publishable_kenzKpyhcWYhRiKEYMkmGA_aAV8E_Ty'

export const supabase = createClient(url, key)
