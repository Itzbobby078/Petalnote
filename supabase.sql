-- =====================================================================
--  Birthday / Anniversary Surprise Cards — Supabase setup (run ONCE)
-- =====================================================================
--  1. Create a free project at https://supabase.com
--  2. Open  SQL Editor → New query → paste this WHOLE file → Run
--  3. Open  Project Settings → API  and copy:
--        • Project URL            → CONFIG.SUPABASE_URL      in index.html
--        • anon / public key      → CONFIG.SUPABASE_ANON_KEY in index.html
--  4. Host index.html anywhere static (Netlify Drop, GitHub Pages,
--     Cloudflare Pages, Vercel…). Share links only work for other people
--     once index.html itself is online.
--
--  What this creates
--    • table  public.cards        → one row per card (text, background, media URLs)
--    • rpc    public.get_card(id) → read ONE card by its secret id (no listing)
--    • bucket card-media (public) → uploaded photos, songs and backgrounds
--  Visitors need no login: they can create cards and open them by link,
--  but cannot list, edit or delete anyone else's cards or files.
-- =====================================================================

-- ---------- 1. Cards table ----------
create table if not exists public.cards (
  id          text primary key check (id ~ '^[a-z0-9]{6,16}$'),
  data        jsonb       not null,
  created_at  timestamptz not null default now()
);

alter table public.cards enable row level security;

-- Anyone may CREATE a card (small payloads only). Nobody may select/update/delete directly.
drop policy if exists "anyone can create cards" on public.cards;
create policy "anyone can create cards"
  on public.cards
  for insert
  to anon, authenticated
  with check (pg_column_size(data) < 20000);

grant insert on public.cards to anon, authenticated;

-- ---------- 2. Read ONE card by id (id acts like a secret link) ----------
create or replace function public.get_card(card_id text)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select data from public.cards where id = card_id;
$$;

revoke all on function public.get_card(text) from public;
grant execute on function public.get_card(text) to anon, authenticated;

-- ---------- 3. Storage bucket for photos, songs & backgrounds ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'card-media',
  'card-media',
  true,                                   -- files are readable by direct public URL
  15728640,                               -- 15 MB per file
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'audio/mpeg','audio/mp3','audio/mp4','audio/x-m4a','audio/aac',
    'audio/wav','audio/x-wav','audio/ogg','audio/webm'
  ]
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Anyone may UPLOAD new files into this bucket (no overwrite, no delete, no listing).
drop policy if exists "anyone can upload card media" on storage.objects;
create policy "anyone can upload card media"
  on storage.objects
  for insert
  to anon, authenticated
  with check (bucket_id = 'card-media');

-- =====================================================================
--  Optional housekeeping (run manually whenever you like):
--    delete from public.cards where created_at < now() - interval '1 year';
--  (Files for deleted cards can be removed from Storage → card-media.)
-- =====================================================================
