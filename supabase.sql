-- =====================================================================
--  petalnote — Supabase setup (run ONCE)
-- =====================================================================
--  1. Create a free project at https://supabase.com
--  2. Open  SQL Editor → New query → paste this WHOLE file → Run
--  3. Open  Project Settings → API  and copy:
--        • Project URL                      → CONFIG.SUPABASE_URL
--        • anon / public key (or publishable key) → CONFIG.SUPABASE_ANON_KEY
--     (both live at the very top of index.html)
--  4. Upload index.html to a static host (Vercel, Netlify, GitHub Pages…).
--     CONFIG.SHARE_BASE must be the address where it is hosted, e.g.
--     https://petalnote.vercel.app/   → share links look like
--     petalnote.vercel.app/?k7m2xq9a
--
--  What this creates
--    • table  public.cards         one row per shared card (letter, wishes,
--                                  background choice, photo + song URLs)
--    • rpc    public.get_card(id)  reads ONE card by its 8-letter id
--                                  (nobody can list or browse other cards)
--    • bucket card-media (public)  the photos, songs and background you upload
--
--  Visitors need no login: they can create cards and open them by link, but
--  cannot list, edit or delete anyone else's cards or files.
--  Safe to run again — it only updates what already exists.
-- =====================================================================

-- ---------- 1. Cards table ----------
create table if not exists public.cards (
  id          text primary key check (id ~ '^[a-z0-9]{6,16}$'),
  data        jsonb       not null,
  created_at  timestamptz not null default now()
);

alter table public.cards enable row level security;

-- Anyone may CREATE a card (size-limited). Nobody may select/update/delete directly.
drop policy if exists "anyone can create cards" on public.cards;
create policy "anyone can create cards"
  on public.cards
  for insert
  to anon, authenticated
  with check (pg_column_size(data) < 40000);

grant insert on public.cards to anon, authenticated;

-- ---------- 2. Read ONE card by id (the id is the secret link) ----------
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
    'image/jpeg','image/png','image/webp',
    'audio/mpeg','audio/mp4','audio/aac','audio/wav','audio/ogg','audio/webm','audio/flac'
  ]
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Anyone may UPLOAD NEW files, and only with the exact names the app uses:
--   <id>/bg.jpg   <id>/photo-0..7.jpg   <id>/song-0..2.<mp3|m4a|aac|wav|ogg|webm|flac>
-- (No overwrite, no delete, no listing.)
drop policy if exists "anyone can upload card media" on storage.objects;
create policy "anyone can upload card media"
  on storage.objects
  for insert
  to anon, authenticated
  with check (
    bucket_id = 'card-media'
    and name ~ '^[a-z0-9]{6,16}/(bg\.jpg|photo-[0-7]\.jpg|song-[0-2]\.(mp3|m4a|aac|wav|ogg|webm|flac))$'
  );

-- =====================================================================
--  Optional housekeeping (run manually whenever you like):
--    delete from public.cards where created_at < now() - interval '1 year';
--  (Files of deleted cards can be removed from Storage → card-media.)
-- =====================================================================
