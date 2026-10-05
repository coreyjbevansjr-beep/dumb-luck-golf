-- Dumb Luck Golfing: shared online leaderboard
-- Run this once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run.

create table if not exists public.scores (
  id         bigint generated always as identity primary key,
  name       text        not null check (char_length(name) between 1 and 10),
  strokes    int         not null check (strokes between 1 and 200),
  to_par     int         not null,
  created_at timestamptz not null default now()
);

-- Row Level Security: anyone with the public (anon) key can read and add scores,
-- but nobody can edit or delete them through the API.
alter table public.scores enable row level security;

drop policy if exists "scores_select_public" on public.scores;
create policy "scores_select_public"
  on public.scores for select
  to anon, authenticated
  using (true);

drop policy if exists "scores_insert_public" on public.scores;
create policy "scores_insert_public"
  on public.scores for insert
  to anon, authenticated
  with check (true);

grant select, insert on table public.scores to anon, authenticated;

-- Speeds up the leaderboard query (best to-par first, then fewest strokes).
create index if not exists scores_rank_idx on public.scores (to_par asc, strokes asc);
