-- Petalnote public gift storage setup (run in Supabase SQL Editor)
-- Each gift is available to anyone who has its unguessable share link.

create table if not exists public.gifts (
  id text primary key,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.gifts enable row level security;

drop policy if exists "Petalnote public can read gifts" on public.gifts;
drop policy if exists "Petalnote public can create gifts" on public.gifts;
create policy "Petalnote public can create gifts"
  on public.gifts for insert to anon
  with check (true);

-- Readers can retrieve one gift by its random ID via this function, rather than list the whole table.
create or replace function public.get_petalnote_gift(gift_id text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select payload from public.gifts where id = gift_id limit 1;
$$;
revoke all on function public.get_petalnote_gift(text) from public;
grant execute on function public.get_petalnote_gift(text) to anon;

insert into storage.buckets (id, name, public, file_size_limit)
values ('petalnote-media', 'petalnote-media', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

drop policy if exists "Petalnote public can upload media" on storage.objects;
create policy "Petalnote public can upload media"
  on storage.objects for insert to anon
  with check (bucket_id = 'petalnote-media');

-- Public bucket URLs let the recipient display uploaded images/audio.
-- This is a lightweight demo setup, not a private-file system; shared gifts/media are public to anyone with their URLs.
