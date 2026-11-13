-- Applied November 13, 2026 for the agreed Invitational format.
-- Daily rounds November 15-18, Eastern; results/playoff November 22.
-- Keep the cut at a fixed 10 places, including everyone tied for 10th.
-- This changes configuration and the cut threshold; no entries or scores are edited.
begin;
do $change$
declare
  definition text;
  old_cut text := 'greatest(ceil(n * c.cut_pct / 100.0)::int, least(c.cut_min::bigint, n))';
  fixed_cut text := 'least(c.cut_min::bigint, n)';
begin
  if exists (select 1 from private.lbi_rounds) then
    raise exception 'Tournament rounds have already started; schedule change aborted';
  end if;
  if not exists (select 1 from private.lbi_config where id=1 and locked_at is null) then
    raise exception 'Tournament is missing or results are locked';
  end if;
  select pg_get_functiondef('private.lbi_board_data(boolean)'::regprocedure) into definition;
  if strpos(definition, old_cut)>0 then
    execute replace(definition, old_cut, fixed_cut);
  elsif strpos(definition, 'rn <= ' || fixed_cut)=0 then
    raise exception 'Unexpected cut formula; inspect before proceeding';
  end if;
  -- cut_min now specifies the fixed number of advancing places.
  -- The existing score-threshold comparison includes all tied players.
  -- cut_pct is retained for schema/API compatibility but no longer determines the cut.
  update private.lbi_config set
    reg_close='2026-11-16T05:00:00Z',
    r1_start='2026-11-15T05:00:00Z', r1_end='2026-11-16T05:00:00Z',
    r2_start='2026-11-16T05:00:00Z', r2_end='2026-11-17T05:00:00Z',
    r3_start='2026-11-17T05:00:00Z', r3_end='2026-11-18T05:00:00Z',
    r4_start='2026-11-18T05:00:00Z', r4_end='2026-11-19T05:00:00Z',
    cut_min=10, updated_at=now()
  where id=1;
end $change$;
commit;
