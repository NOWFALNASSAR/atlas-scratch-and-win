-- =====================================================================
-- @less fashion Scratch & Win  -  Supabase database (version 5: bill number range, chance slabs, 2nd scratch card)
-- Supabase > SQL Editor > New query > paste this whole file > Run
-- Safe to run on a new project AND on top of any earlier version (keeps all data).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function public._today() returns date language sql stable as $$
  select (now() at time zone 'Asia/Kolkata')::date
$$;

-- ---------- Core tables ----------
create table if not exists public.branches (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  pin_hash    text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table if exists public.branches add column if not exists bill_from numeric;  -- v5: valid bill number range
alter table if exists public.branches add column if not exists bill_to   numeric;

create table if not exists public.campaign (
  id             int primary key default 1 check (id = 1),
  name           text not null default 'December Mega Sale',
  min_bill       numeric not null default 1000,
  validity_days  int not null default 30,
  once_per_day   boolean not null default true,
  active         boolean not null default true,
  start_date     date,
  end_date       date
);
insert into public.campaign (id) values (1) on conflict (id) do nothing;
-- branding (v2)
alter table public.campaign add column if not exists brand_name text not null default '@less fashion';
alter table public.campaign add column if not exists logo       text;
alter table public.campaign add column if not exists color      text not null default '#741233';
alter table public.campaign add column if not exists accent     text not null default '#e2ad37';
alter table public.campaign add column if not exists second_card_min numeric;   -- v5: bills at/above this amount can get a 2nd card (empty = off)
alter table public.campaign add column if not exists terms      text not null default 'Valid at all @less fashion showrooms. Not exchangeable for cash.';

-- stock items (v2)
create table if not exists public.items (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  unit        text not null default 'pcs',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.prizes (
  id           bigint generated always as identity primary key,
  name         text not null,
  type         text not null check (type in ('voucher','gift','bumper')),
  weight       numeric not null default 1 check (weight >= 0),
  daily_limit  int not null default 0 check (daily_limit >= 0),  -- per branch per day, 0 = unlimited
  active       boolean not null default true,
  sort         int not null default 0
);
alter table public.prizes add column if not exists item_id bigint references public.items(id) on delete set null;
alter table public.prizes add column if not exists image   text;   -- small JPEG as data URL
-- bill range (v4): prize can only be won when the bill amount is inside this range (empty = no limit)
alter table public.prizes add column if not exists min_bill numeric;
alter table public.prizes add column if not exists max_bill numeric;

insert into public.prizes (name, type, weight, daily_limit, sort)
select * from (values
  ('₹100 Voucher',         'voucher', 45,  0, 1),
  ('₹200 Voucher',         'voucher', 25,  0, 2),
  ('10% Discount Coupon',  'voucher', 10,  0, 3),
  ('Free Handkerchief',    'gift',    10, 20, 4),
  ('Free Towel',           'gift',     6, 10, 5),
  ('Free Mundu',           'gift',     2,  5, 6),
  ('Silver Coin',          'bumper', 1.5,  1, 7),
  ('₹5000 Gift Voucher',   'bumper', 0.5,  1, 8)
) v(name, type, weight, daily_limit, sort)
where not exists (select 1 from public.prizes);

create table if not exists public.scratches (
  id              bigint generated always as identity primary key,
  created_at      timestamptz not null default now(),
  day             date not null default ((now() at time zone 'Asia/Kolkata')::date),
  branch_id       bigint not null references public.branches(id),
  bill_no         text not null,
  amount          numeric not null,
  customer_name   text not null,
  mobile          text not null,
  prize_id        bigint references public.prizes(id) on delete set null,
  prize_name      text not null,
  prize_type      text not null,
  code            text not null unique,
  expires_on      date not null,
  status          text not null default 'new' check (status in ('new','used')),
  used_at         timestamptz,
  used_branch_id  bigint references public.branches(id)
);
alter table public.scratches add column if not exists item_id bigint references public.items(id) on delete set null;
alter table public.scratches add column if not exists card_no int not null default 1;   -- v5: 1st or 2nd card for the same bill
drop index if exists public.scratches_bill_uq;
create unique index if not exists scratches_bill_card_uq on public.scratches (branch_id, lower(bill_no), card_no);
create index if not exists scratches_day_idx           on public.scratches (day);
create index if not exists scratches_mobile_idx        on public.scratches (mobile, day);
create index if not exists scratches_branch_day_idx    on public.scratches (branch_id, day, prize_id);
create index if not exists scratches_pending_idx       on public.scratches (branch_id, item_id) where status = 'new';

-- chance slabs by bill amount (v5): each slab has its own % for each prize
create table if not exists public.slabs (
  id          bigint generated always as identity primary key,
  min_amount  numeric not null default 0,
  max_amount  numeric,
  created_at  timestamptz not null default now()
);
create table if not exists public.slab_prizes (
  slab_id   bigint not null references public.slabs(id) on delete cascade,
  prize_id  bigint not null references public.prizes(id) on delete cascade,
  percent   numeric not null default 0 check (percent >= 0),
  primary key (slab_id, prize_id)
);

-- stock movements (v2). branch_id NULL = Head Office store. qty: + in, - out
create table if not exists public.stock_moves (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  day         date not null default ((now() at time zone 'Asia/Kolkata')::date),
  item_id     bigint not null references public.items(id),
  branch_id   bigint references public.branches(id),
  qty         numeric not null,
  kind        text not null check (kind in ('in','transfer_in','transfer_out','issue','adjust')),
  ref         text,
  note        text,
  by_user     text
);
create index if not exists stock_moves_loc_idx on public.stock_moves (branch_id, item_id, day);

-- daily closing (v2)
create table if not exists public.closings (
  id          bigint generated always as identity primary key,
  branch_id   bigint not null references public.branches(id),
  day         date not null,
  closed_at   timestamptz not null default now(),
  lines       jsonb not null,
  summary     jsonb not null,
  note        text,
  unique (branch_id, day)
);

-- ---------- Head Office users and roles (v3) ----------
-- admin = everything · marketing = edit prizes & campaign/branding, view the rest
-- sales = view only · accounts = view only (dashboard, closings, stock, log, Excel)
create table if not exists public.app_users (
  email       text primary key,
  name        text,
  role        text not null check (role in ('admin','marketing','sales','accounts')),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
-- The owner's login. CHANGE this email if a different person is the main admin.
insert into public.app_users (email, name, role) values ('nowfalnassar@gmail.com', 'Nowfal', 'admin') on conflict (email) do nothing;

create or replace function public._role() returns text language sql stable security definer
set search_path = public as $$
  select role from public.app_users where active and email = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

create or replace function public.my_role() returns json language sql stable security definer
set search_path = public as $$
  select json_build_object('email', lower(coalesce(auth.jwt() ->> 'email','')), 'role', public._role(),
    'name', (select name from public.app_users where email = lower(coalesce(auth.jwt() ->> 'email',''))))
$$;

-- ---------- Security: tables only for Head Office users with a role ----------
do $$ declare t text; w text; begin
  foreach t in array array['branches','campaign','prizes','scratches','items','stock_moves','closings','app_users','slabs','slab_prizes'] loop
    w := case when t in ('campaign','prizes','slabs','slab_prizes') then $q$public._role() in ('admin','marketing')$q$ else $q$public._role() = 'admin'$q$ end;
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format('drop policy if exists hq_read on public.%I', t);
    execute format('drop policy if exists hq_insert on public.%I', t);
    execute format('drop policy if exists hq_update on public.%I', t);
    execute format('drop policy if exists hq_delete on public.%I', t);
    execute format('create policy hq_read on public.%I for select to authenticated using (public._role() is not null)', t);
    execute format('create policy hq_insert on public.%I for insert to authenticated with check (%s)', t, w);
    execute format('create policy hq_update on public.%I for update to authenticated using (%s) with check (%s)', t, w, w);
    execute format('create policy hq_delete on public.%I for delete to authenticated using (%s)', t, w);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
grant usage, select on all sequences in schema public to authenticated;
-- Counter tablets (anon) cannot read any table. They only call the functions below.

-- ---------- Helpers ----------
create or replace function public._branch_by_pin(p_pin text)
returns bigint language sql stable security definer
set search_path = public, extensions as $$
  select id from public.branches
  where active and pin_hash = crypt(coalesce(p_pin,''), pin_hash)
  limit 1
$$;

-- last group of digits in a bill number: 'TDP/2026/1234' -> 1234
create or replace function public._bill_num(p_bill text)
returns numeric language sql immutable as $$
  select ((regexp_match(coalesce(p_bill,''), '(\d+)\D*$'))[1])::numeric
$$;

create or replace function public._stock(p_branch bigint, p_item bigint)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(qty),0) from public.stock_moves
  where item_id = p_item and branch_id is not distinct from p_branch
$$;

create or replace function public._pending(p_branch bigint, p_item bigint)
returns bigint language sql stable security definer set search_path = public as $$
  select count(*) from public.scratches
  where branch_id = p_branch and item_id = p_item and status = 'new' and expires_on >= public._today()
$$;

create or replace function public._settings_json()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('campaign', c.name, 'min_bill', c.min_bill, 'brand_name', c.brand_name,
    'logo', c.logo, 'color', c.color, 'accent', c.accent, 'terms', c.terms, 'validity_days', c.validity_days, 'second_card_min', c.second_card_min)
  from public.campaign c where id = 1
$$;

-- ---------- Counter: login / load (branding + prize pictures) ----------
create or replace function public.branch_login(p_pin text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_id bigint; v_name text; s json;
begin
  v_id := public._branch_by_pin(p_pin);
  if v_id is null then raise exception 'BRANCH_PIN'; end if;
  select name into v_name from public.branches where id = v_id;
  s := public._settings_json();
  return (s::jsonb || jsonb_build_object('branch', v_name,
    'prizes', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'type',type,'image',image) order by sort,id),'[]'::jsonb)
               from public.prizes where active)))::json;
end $$;

-- ---------- Counter: one scratch (prize decided HERE, on the server) ----------
drop function if exists public.do_scratch(text,text,numeric,text,text);
create or replace function public.do_scratch(p_pin text, p_bill text, p_amount numeric, p_name text, p_mobile text, p_card int default 1)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_branch bigint; b public.branches; c public.campaign; v_day date := public._today();
  v_total numeric; v_r numeric; v_pid bigint; v_last bigint; v_ids bigint[]; v_ws numeric[];
  v_slab bigint; v_has_slabs boolean; v_num numeric; v_first public.scratches;
  v_prize public.prizes; v_code text; v_exp date;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  select * into b from public.branches where id = v_branch;

  select * into c from public.campaign where id = 1;
  if not c.active
     or (c.start_date is not null and v_day < c.start_date)
     or (c.end_date   is not null and v_day > c.end_date) then
    raise exception 'CAMPAIGN_OFF';
  end if;

  p_bill   := trim(coalesce(p_bill,''));
  p_mobile := regexp_replace(coalesce(p_mobile,''), '\D', '', 'g');
  p_card   := coalesce(p_card, 1);
  if p_bill = '' then raise exception 'BILL_EMPTY'; end if;
  if p_card not in (1, 2) then raise exception 'CARD_BAD'; end if;

  -- one scratch at a time per branch, so daily limits and stock are never crossed
  perform pg_advisory_xact_lock(v_branch);

  if p_card = 1 then
    if p_amount is null or p_amount < c.min_bill then raise exception 'MIN_BILL'; end if;
    if p_mobile !~ '^[6-9][0-9]{9}$' then raise exception 'MOBILE_BAD'; end if;
    -- bill number must be inside this branch's valid bill number range (if set)
    if b.bill_from is not null or b.bill_to is not null then
      v_num := public._bill_num(p_bill);
      if v_num is null or (b.bill_from is not null and v_num < b.bill_from) or (b.bill_to is not null and v_num > b.bill_to) then
        raise exception 'BILL_RANGE';
      end if;
    end if;
    if exists (select 1 from public.scratches where branch_id = v_branch and lower(bill_no) = lower(p_bill)) then
      raise exception 'BILL_USED';
    end if;
    if c.once_per_day and exists (select 1 from public.scratches where mobile = p_mobile and day = v_day and card_no = 1) then
      raise exception 'MOBILE_TODAY';
    end if;
  else
    -- second card: same bill, same branch, amount above the second-card limit, only once
    select * into v_first from public.scratches where branch_id = v_branch and lower(bill_no) = lower(p_bill) and card_no = 1;
    if v_first.id is null then raise exception 'NO_FIRST_CARD'; end if;
    if c.second_card_min is null or v_first.amount < c.second_card_min then raise exception 'NO_SECOND_CARD'; end if;
    if exists (select 1 from public.scratches where branch_id = v_branch and lower(bill_no) = lower(p_bill) and card_no = 2) then
      raise exception 'SECOND_USED';
    end if;
    p_amount := v_first.amount; p_mobile := v_first.mobile; p_bill := v_first.bill_no;
  end if;

  -- which chance table: the bill-amount slab, or (if no slabs are set up) the prize weights
  v_has_slabs := exists (select 1 from public.slabs);
  if v_has_slabs then
    select id into v_slab from public.slabs
    where p_amount >= min_amount and (max_amount is null or p_amount <= max_amount)
    order by min_amount desc limit 1;
    if v_slab is null then raise exception 'NO_SLAB'; end if;
  end if;

  -- prizes still available today at this branch (daily limit + free stock)
  select array_agg(p.id order by p.sort, p.id), array_agg(w.wt order by p.sort, p.id), coalesce(sum(w.wt),0)
    into v_ids, v_ws, v_total
  from public.prizes p
  cross join lateral (select case when v_has_slabs
       then (select sp.percent from public.slab_prizes sp where sp.slab_id = v_slab and sp.prize_id = p.id)
       else p.weight end as wt) w
  where p.active and coalesce(w.wt, 0) > 0
    and (p.daily_limit = 0 or (select count(*) from public.scratches s
         where s.branch_id = v_branch and s.day = v_day and s.prize_id = p.id) < p.daily_limit)
    and (p.item_id is null or public._stock(v_branch, p.item_id) - public._pending(v_branch, p.item_id) > 0);

  if v_total > 0 then
    v_r := random() * v_total;
    for i in 1 .. array_length(v_ids, 1) loop
      v_last := v_ids[i];
      v_r := v_r - v_ws[i];
      if v_r <= 0 then v_pid := v_ids[i]; exit; end if;
    end loop;
    v_pid := coalesce(v_pid, v_last);
  else
    -- everything in this slab is finished: give an unlimited, no-stock prize (from this slab if possible)
    select p.id into v_pid from public.prizes p
    where p.active and p.daily_limit = 0 and p.item_id is null
      and (not v_has_slabs or exists (select 1 from public.slab_prizes sp where sp.slab_id = v_slab and sp.prize_id = p.id))
    order by p.weight desc limit 1;
  end if;
  if v_pid is null then raise exception 'NO_PRIZE'; end if;
  select * into v_prize from public.prizes where id = v_pid;

  loop
    v_code := 'LESS-' || (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random()*31)::int, 1), '')
                         from generate_series(1,5));
    exit when not exists (select 1 from public.scratches where code = v_code);
  end loop;
  v_exp := v_day + c.validity_days;

  insert into public.scratches (branch_id, bill_no, amount, customer_name, mobile, prize_id, prize_name, prize_type, item_id, code, expires_on, card_no)
  values (v_branch, p_bill, p_amount, coalesce(trim(p_name),''), p_mobile, v_prize.id, v_prize.name, v_prize.type, v_prize.item_id, v_code, v_exp, p_card);

  return json_build_object('prize_id', v_prize.id, 'prize', v_prize.name, 'type', v_prize.type,
                           'has_item', v_prize.item_id is not null, 'code', v_code,
                           'expires_on', v_exp, 'branch', b.name, 'campaign', c.name,
                           'name', '', 'mobile', p_mobile, 'bill', p_bill, 'amount', p_amount,
                           'card_no', p_card,
                           'second_allowed', p_card = 1 and c.second_card_min is not null and p_amount >= c.second_card_min,
                           'at', now());
end $$;

-- ---------- Counter: check a coupon ----------
create or replace function public.check_coupon(p_pin text, p_code text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare s public.scratches; v_b text; v_ub text; v_branch bigint;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  select * into s from public.scratches where code = upper(trim(p_code));
  if s.id is null then return json_build_object('found', false); end if;
  select name into v_b  from public.branches where id = s.branch_id;
  select name into v_ub from public.branches where id = s.used_branch_id;
  return json_build_object('found', true, 'code', s.code, 'prize', s.prize_name, 'type', s.prize_type,
    'status', s.status, 'expired', (s.status = 'new' and s.expires_on < public._today()),
    'expires_on', s.expires_on, 'name', s.customer_name,
    'mobile', '******' || right(s.mobile, 4), 'branch', v_b, 'day', s.day, 'bill', s.bill_no,
    'used_at', s.used_at, 'used_branch', v_ub,
    'has_item', s.item_id is not null,
    'stock_here', case when s.item_id is null then null else public._stock(v_branch, s.item_id) end);
end $$;

-- ---------- Counter: redeem a coupon (gift items are taken out of this branch's stock) ----------
create or replace function public.redeem_coupon(p_pin text, p_code text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_branch bigint; s public.scratches;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  perform pg_advisory_xact_lock(v_branch);
  select * into s from public.scratches where code = upper(trim(p_code)) for update;
  if s.id is null or s.status <> 'new' or s.expires_on < public._today() then raise exception 'NOT_REDEEMABLE'; end if;
  if s.item_id is not null then
    if public._stock(v_branch, s.item_id) < 1 then raise exception 'NO_STOCK'; end if;
    insert into public.stock_moves (item_id, branch_id, qty, kind, ref, note)
    values (s.item_id, v_branch, -1, 'issue', s.code, s.prize_name || ' to ' || s.customer_name);
  end if;
  update public.scratches set status = 'used', used_at = now(), used_branch_id = v_branch where id = s.id;
  return json_build_object('ok', true);
end $$;

-- ---------- Counter: stock at this branch ----------
create or replace function public.branch_stock(p_pin text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_branch bigint;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  return (select coalesce(json_agg(x order by x.name), '[]'::json) from (
    select i.id, i.name, i.unit, public._stock(v_branch, i.id) as stock, public._pending(v_branch, i.id) as pending
    from public.items i where i.active) x);
end $$;

-- ---------- Day closing (shared by counter and admin) ----------
create or replace function public._closing_data(p_branch bigint, p_day date)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'day', p_day,
    'branch', (select name from public.branches where id = p_branch),
    'lines', (select coalesce(json_agg(x order by x.name), '[]'::json) from (
      select i.id as item_id, i.name, i.unit,
        coalesce(sum(m.qty) filter (where m.day <  p_day), 0)                                   as opening,
        coalesce(sum(m.qty) filter (where m.day =  p_day and m.kind in ('in','transfer_in')), 0) as received,
        coalesce(-sum(m.qty) filter (where m.day = p_day and m.kind = 'issue'), 0)              as issued,
        coalesce(-sum(m.qty) filter (where m.day = p_day and m.kind = 'transfer_out'), 0)       as sent_out,
        coalesce(sum(m.qty) filter (where m.day =  p_day and m.kind = 'adjust'), 0)             as adjusted,
        coalesce(sum(m.qty) filter (where m.day <= p_day), 0)                                   as closing
      from public.items i
      left join public.stock_moves m on m.item_id = i.id and m.branch_id = p_branch
      where i.active or exists (select 1 from public.stock_moves z where z.item_id = i.id and z.branch_id = p_branch)
      group by i.id, i.name, i.unit) x),
    'summary', (select json_build_object(
        'scratches',      count(*),
        'bill_total',     coalesce(sum(amount),0),
        'vouchers_won',   count(*) filter (where prize_type = 'voucher'),
        'gifts_won',      count(*) filter (where prize_type <> 'voucher'))
      from public.scratches where branch_id = p_branch and day = p_day)::jsonb
      || jsonb_build_object('redeemed_here',
           (select count(*) from public.scratches where used_branch_id = p_branch
              and (used_at at time zone 'Asia/Kolkata')::date = p_day)),
    'closed', (select json_build_object('closed_at', closed_at, 'lines', lines, 'summary', summary, 'note', note)
               from public.closings where branch_id = p_branch and day = p_day)
  )
$$;

create or replace function public.closing_preview(p_pin text, p_day date)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_branch bigint;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  if p_day > public._today() then raise exception 'FUTURE_DAY'; end if;
  return public._closing_data(v_branch, p_day);
end $$;

-- p_counts: {"<item_id>": physical_count, ...}. Differences are booked as 'adjust' so the next day starts from the real count.
create or replace function public.save_closing(p_pin text, p_day date, p_counts jsonb, p_note text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_branch bigint; d json; l json; v_lines jsonb := '[]'::jsonb; v_phys numeric; v_diff numeric;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  if p_day > public._today() then raise exception 'FUTURE_DAY'; end if;
  perform pg_advisory_xact_lock(v_branch);
  if exists (select 1 from public.closings where branch_id = v_branch and day = p_day) then raise exception 'ALREADY_CLOSED'; end if;
  d := public._closing_data(v_branch, p_day);
  for l in select * from json_array_elements(d->'lines') loop
    v_phys := coalesce((p_counts ->> (l->>'item_id'))::numeric, (l->>'closing')::numeric);
    v_diff := v_phys - (l->>'closing')::numeric;
    if v_diff <> 0 then
      insert into public.stock_moves (item_id, branch_id, qty, kind, ref, note, day)
      values ((l->>'item_id')::bigint, v_branch, v_diff, 'adjust', 'closing ' || p_day, 'Physical count difference', p_day);
    end if;
    v_lines := v_lines || jsonb_build_array((l::jsonb) || jsonb_build_object('physical', v_phys, 'difference', v_diff));
  end loop;
  insert into public.closings (branch_id, day, lines, summary, note)
  values (v_branch, p_day, v_lines, (d->'summary')::jsonb, nullif(trim(coalesce(p_note,'')),''));
  return public._closing_data(v_branch, p_day);
end $$;

-- ---------- Admin ----------
drop function if exists public.admin_save_branch(bigint,text,text,boolean);
create or replace function public.admin_save_branch(p_id bigint, p_name text, p_pin text, p_active boolean, p_bill_from numeric default null, p_bill_to numeric default null)
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare v_id bigint;
begin
  if public._role() is distinct from 'admin' then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'NAME_EMPTY'; end if;
  if p_bill_from is not null and p_bill_to is not null and p_bill_from > p_bill_to then raise exception 'RANGE_BAD'; end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{6}$' then raise exception 'PIN_FORMAT'; end if;
    if exists (select 1 from public.branches where pin_hash = crypt(p_pin, pin_hash) and id is distinct from p_id) then
      raise exception 'PIN_TAKEN';
    end if;
  end if;
  if p_id is null then
    if p_pin is null or p_pin = '' then raise exception 'PIN_FORMAT'; end if;
    insert into public.branches (name, pin_hash, active, bill_from, bill_to)
    values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), p_bill_from, p_bill_to)
    returning id into v_id;
  else
    update public.branches
       set name = trim(p_name), active = coalesce(p_active, active), bill_from = p_bill_from, bill_to = p_bill_to,
           pin_hash = case when p_pin is null or p_pin = '' then pin_hash else crypt(p_pin, gen_salt('bf')) end
     where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- stock received at Head Office (or directly at a branch)
create or replace function public.admin_stock_in(p_item bigint, p_branch bigint, p_qty numeric, p_note text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if public._role() is distinct from 'admin' then raise exception 'NOT_ADMIN'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'QTY_BAD'; end if;
  insert into public.stock_moves (item_id, branch_id, qty, kind, note, by_user)
  values (p_item, p_branch, p_qty, 'in', nullif(trim(coalesce(p_note,'')),''), lower(auth.jwt() ->> 'email'));
  return json_build_object('ok', true, 'stock', public._stock(p_branch, p_item));
end $$;

-- transfer between Head Office (NULL) and branches
create or replace function public.admin_transfer(p_item bigint, p_from bigint, p_to bigint, p_qty numeric, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_ref text := 'TR-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD-HH24MISS'); v_user text;
begin
  if public._role() is distinct from 'admin' then raise exception 'NOT_ADMIN'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'QTY_BAD'; end if;
  if p_from is not distinct from p_to then raise exception 'SAME_LOCATION'; end if;
  perform pg_advisory_xact_lock(coalesce(p_from, 0));
  if public._stock(p_from, p_item) < p_qty then raise exception 'NO_STOCK'; end if;
  v_user := lower(auth.jwt() ->> 'email');
  insert into public.stock_moves (item_id, branch_id, qty, kind, ref, note, by_user)
  values (p_item, p_from, -p_qty, 'transfer_out', v_ref, nullif(trim(coalesce(p_note,'')),''), v_user),
         (p_item, p_to,    p_qty, 'transfer_in',  v_ref, nullif(trim(coalesce(p_note,'')),''), v_user);
  return json_build_object('ok', true, 'ref', v_ref,
    'from_stock', public._stock(p_from, p_item), 'to_stock', public._stock(p_to, p_item));
end $$;

-- stock of every item at Head Office and every branch
create or replace function public.admin_stock_summary()
returns json language plpgsql security definer set search_path = public as $$
begin
  if public._role() is null then raise exception 'NO_ROLE'; end if;
  return json_build_object(
    'items', (select coalesce(json_agg(json_build_object('id',id,'name',name,'unit',unit,'active',active) order by name),'[]'::json) from public.items),
    'stock', (select coalesce(json_agg(json_build_object('item_id',item_id,'branch_id',branch_id,'qty',q)),'[]'::json)
              from (select item_id, branch_id, sum(qty) q from public.stock_moves group by item_id, branch_id) s),
    'pending', (select coalesce(json_agg(json_build_object('item_id',item_id,'branch_id',branch_id,'qty',n)),'[]'::json)
              from (select item_id, branch_id, count(*) n from public.scratches
                    where status = 'new' and item_id is not null and expires_on >= public._today()
                    group by item_id, branch_id) p));
end $$;

create or replace function public.admin_closing(p_branch bigint, p_day date)
returns json language plpgsql security definer set search_path = public as $$
begin
  if public._role() is null then raise exception 'NO_ROLE'; end if;
  return public._closing_data(p_branch, p_day);
end $$;

create or replace function public.admin_stats(p_from date, p_to date)
returns json language sql stable security invoker
set search_path = public as $$
  with s as (select * from public.scratches where day between p_from and p_to)
  select json_build_object(
    'total',      (select count(*) from s),
    'today',      (select count(*) from public.scratches where day = public._today()),
    'used',       (select count(*) from s where status = 'used'),
    'customers',  (select count(distinct mobile) from s),
    'gifts',      (select count(*) from s where prize_type <> 'voucher'),
    'bill_total', (select coalesce(sum(amount),0) from s),
    'branches',   (select coalesce(json_agg(x order by x.name), '[]'::json) from (
        select b.name,
               count(s.id) as total,
               count(s.id) filter (where s.day = public._today()) as today,
               count(s.id) filter (where s.prize_type = 'gift')   as gifts,
               count(s.id) filter (where s.prize_type = 'bumper') as bumpers,
               count(s.id) filter (where s.status = 'used')       as redeemed,
               coalesce(sum(s.amount),0) as bill_total
        from public.branches b left join s on s.branch_id = b.id
        group by b.id, b.name) x)
  )
$$;

-- ---------- Who can run what ----------
do $$ declare f text; begin
  foreach f in array array['_branch_by_pin(text)','_stock(bigint,bigint)','_pending(bigint,bigint)','_settings_json()','_closing_data(bigint,date)','_bill_num(text)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
  end loop;
  -- _role() is used inside the table security rules, so logged-in users must be able to run it (it only returns their own role)
  revoke all on function public._role() from public, anon;
  grant execute on function public._role() to authenticated;
  foreach f in array array['branch_login(text)','do_scratch(text,text,numeric,text,text,int)','check_coupon(text,text)',
                           'redeem_coupon(text,text)','branch_stock(text)','closing_preview(text,date)','save_closing(text,date,jsonb,text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
  foreach f in array array['admin_save_branch(bigint,text,text,boolean,numeric,numeric)','admin_stats(date,date)','admin_stock_in(bigint,bigint,numeric,text)',
                           'admin_transfer(bigint,bigint,bigint,numeric,text)','admin_stock_summary()','admin_closing(bigint,date)','my_role()'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $$;

-- rename old Malayalam defaults if this database came from version 1
update public.campaign set name = 'December Mega Sale' where id = 1 and name = 'ഡിസംബർ മെഗാ സെയിൽ';
update public.prizes p set name = v.en from (values
  ('₹100 വൗച്ചർ','₹100 Voucher'),('₹200 വൗച്ചർ','₹200 Voucher'),('10% ഡിസ്കൗണ്ട് കൂപ്പൺ','10% Discount Coupon'),
  ('ഫ്രീ കർച്ചീഫ്','Free Handkerchief'),('ഫ്രീ ടവൽ','Free Towel'),('ഫ്രീ മുണ്ട്','Free Mundu'),
  ('സിൽവർ കോയിൻ','Silver Coin'),('₹5000 ഗിഫ്റ്റ് വൗച്ചർ','₹5000 Gift Voucher')
) v(ml, en) where p.name = v.ml;
