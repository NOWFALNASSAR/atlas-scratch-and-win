-- =====================================================================
-- Atlas Maharani Scratch & Win  -  Supabase database setup
-- Supabase > SQL Editor > New query > paste this whole file > Run
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists public.branches (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  pin_hash    text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

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

create table if not exists public.prizes (
  id           bigint generated always as identity primary key,
  name         text not null,
  type         text not null check (type in ('voucher','gift','bumper')),
  weight       numeric not null default 1 check (weight >= 0),
  daily_limit  int not null default 0 check (daily_limit >= 0),  -- per branch per day, 0 = unlimited
  active       boolean not null default true,
  sort         int not null default 0
);

insert into public.prizes (name, type, weight, daily_limit, sort)
select * from (values
  ('₹100 Voucher',              'voucher', 45,  0, 1),
  ('₹200 Voucher',              'voucher', 25,  0, 2),
  ('10% Discount Coupon',     'voucher', 10,  0, 3),
  ('Free Handkerchief',             'gift',    10, 20, 4),
  ('Free Towel',                  'gift',     6, 10, 5),
  ('Free Mundu',               'gift',     2,  5, 6),
  ('Silver Coin',              'bumper', 1.5, 1, 7),
  ('₹5000 Gift Voucher',      'bumper', 0.5, 1, 8)
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
create unique index if not exists scratches_bill_uq on public.scratches (branch_id, lower(bill_no));
create index if not exists scratches_day_idx    on public.scratches (day);
create index if not exists scratches_mobile_idx on public.scratches (mobile, day);

-- ---------- Security: tables only for logged-in Head Office admins ----------
alter table public.branches  enable row level security;
alter table public.campaign  enable row level security;
alter table public.prizes    enable row level security;
alter table public.scratches enable row level security;

drop policy if exists admin_all on public.branches;
drop policy if exists admin_all on public.campaign;
drop policy if exists admin_all on public.prizes;
drop policy if exists admin_all on public.scratches;
create policy admin_all on public.branches  for all to authenticated using (true) with check (true);
create policy admin_all on public.campaign  for all to authenticated using (true) with check (true);
create policy admin_all on public.prizes    for all to authenticated using (true) with check (true);
create policy admin_all on public.scratches for all to authenticated using (true) with check (true);
grant select, insert, update, delete on public.branches, public.campaign, public.prizes, public.scratches to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on public.branches, public.campaign, public.prizes, public.scratches from anon;
-- Counter tablets (anon) cannot read any table. They only call the functions below.

-- ---------- Helper: find branch from PIN ----------
create or replace function public._branch_by_pin(p_pin text)
returns bigint language sql stable security definer
set search_path = public, extensions as $$
  select id from public.branches
  where active and pin_hash = crypt(coalesce(p_pin,''), pin_hash)
  limit 1
$$;

create or replace function public._today() returns date language sql stable as $$
  select (now() at time zone 'Asia/Kolkata')::date
$$;

-- ---------- Counter: login with PIN ----------
create or replace function public.branch_login(p_pin text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_id bigint; v_name text; c public.campaign;
begin
  v_id := public._branch_by_pin(p_pin);
  if v_id is null then raise exception 'BRANCH_PIN'; end if;
  select name into v_name from public.branches where id = v_id;
  select * into c from public.campaign where id = 1;
  return json_build_object('branch', v_name, 'campaign', c.name, 'min_bill', c.min_bill);
end $$;

-- ---------- Counter: do one scratch (prize is decided HERE, on the server) ----------
create or replace function public.do_scratch(p_pin text, p_bill text, p_amount numeric, p_name text, p_mobile text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_branch bigint; v_bname text; c public.campaign; v_day date := public._today();
  v_total numeric; v_r numeric; v_pid bigint; v_last bigint; rec record;
  v_prize public.prizes; v_code text; v_exp date;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  select name into v_bname from public.branches where id = v_branch;

  select * into c from public.campaign where id = 1;
  if not c.active
     or (c.start_date is not null and v_day < c.start_date)
     or (c.end_date   is not null and v_day > c.end_date) then
    raise exception 'CAMPAIGN_OFF';
  end if;

  p_bill   := trim(coalesce(p_bill,''));
  p_name   := trim(coalesce(p_name,''));
  p_mobile := regexp_replace(coalesce(p_mobile,''), '\D', '', 'g');
  if p_bill = '' then raise exception 'BILL_EMPTY'; end if;
  if p_amount is null or p_amount < c.min_bill then raise exception 'MIN_BILL'; end if;
  if p_name = '' then raise exception 'NAME_EMPTY'; end if;
  if p_mobile !~ '^[6-9][0-9]{9}$' then raise exception 'MOBILE_BAD'; end if;

  -- one scratch at a time per branch, so daily limits are never crossed
  perform pg_advisory_xact_lock(v_branch);

  if exists (select 1 from public.scratches where branch_id = v_branch and lower(bill_no) = lower(p_bill)) then
    raise exception 'BILL_USED';
  end if;
  if c.once_per_day and exists (select 1 from public.scratches where mobile = p_mobile and day = v_day) then
    raise exception 'MOBILE_TODAY';
  end if;

  -- prizes still available today at this branch
  select coalesce(sum(p.weight),0) into v_total
  from public.prizes p
  where p.active and p.weight > 0
    and (p.daily_limit = 0 or (select count(*) from public.scratches s
         where s.branch_id = v_branch and s.day = v_day and s.prize_id = p.id) < p.daily_limit);

  if v_total > 0 then
    v_r := random() * v_total;
    for rec in
      select p.id, p.weight from public.prizes p
      where p.active and p.weight > 0
        and (p.daily_limit = 0 or (select count(*) from public.scratches s
             where s.branch_id = v_branch and s.day = v_day and s.prize_id = p.id) < p.daily_limit)
      order by p.sort, p.id
    loop
      v_last := rec.id;
      v_r := v_r - rec.weight;
      if v_r <= 0 then v_pid := rec.id; exit; end if;
    end loop;
    v_pid := coalesce(v_pid, v_last);
  else
    -- every limited prize is finished: give the most common unlimited prize
    select id into v_pid from public.prizes where active and daily_limit = 0 order by weight desc limit 1;
  end if;
  if v_pid is null then raise exception 'NO_PRIZE'; end if;
  select * into v_prize from public.prizes where id = v_pid;

  loop
    v_code := 'ATL-' || (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random()*31)::int, 1), '')
                         from generate_series(1,5));
    exit when not exists (select 1 from public.scratches where code = v_code);
  end loop;
  v_exp := v_day + c.validity_days;

  insert into public.scratches (branch_id, bill_no, amount, customer_name, mobile, prize_id, prize_name, prize_type, code, expires_on)
  values (v_branch, p_bill, p_amount, p_name, p_mobile, v_prize.id, v_prize.name, v_prize.type, v_code, v_exp);

  return json_build_object('prize', v_prize.name, 'type', v_prize.type, 'code', v_code,
                           'expires_on', v_exp, 'branch', v_bname, 'campaign', c.name,
                           'name', p_name, 'mobile', p_mobile);
end $$;

-- ---------- Counter: check a coupon ----------
create or replace function public.check_coupon(p_pin text, p_code text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare s public.scratches; v_b text; v_ub text;
begin
  if public._branch_by_pin(p_pin) is null then raise exception 'BRANCH_PIN'; end if;
  select * into s from public.scratches where code = upper(trim(p_code));
  if s.id is null then return json_build_object('found', false); end if;
  select name into v_b  from public.branches where id = s.branch_id;
  select name into v_ub from public.branches where id = s.used_branch_id;
  return json_build_object('found', true, 'code', s.code, 'prize', s.prize_name, 'type', s.prize_type,
    'status', s.status, 'expired', (s.status = 'new' and s.expires_on < public._today()),
    'expires_on', s.expires_on, 'name', s.customer_name,
    'mobile', '******' || right(s.mobile, 4), 'branch', v_b, 'day', s.day, 'bill', s.bill_no,
    'used_at', s.used_at, 'used_branch', v_ub);
end $$;

-- ---------- Counter: redeem a coupon ----------
create or replace function public.redeem_coupon(p_pin text, p_code text)
returns json language plpgsql security definer
set search_path = public, extensions as $$
declare v_branch bigint; v_n int;
begin
  v_branch := public._branch_by_pin(p_pin);
  if v_branch is null then raise exception 'BRANCH_PIN'; end if;
  update public.scratches
     set status = 'used', used_at = now(), used_branch_id = v_branch
   where code = upper(trim(p_code)) and status = 'new' and expires_on >= public._today();
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'NOT_REDEEMABLE'; end if;
  return json_build_object('ok', true);
end $$;

-- ---------- Admin: add / edit branch with PIN ----------
create or replace function public.admin_save_branch(p_id bigint, p_name text, p_pin text, p_active boolean)
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare v_id bigint;
begin
  if auth.uid() is null then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'NAME_EMPTY'; end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{6}$' then raise exception 'PIN_FORMAT'; end if;
    if exists (select 1 from public.branches where pin_hash = crypt(p_pin, pin_hash) and id is distinct from p_id) then
      raise exception 'PIN_TAKEN';
    end if;
  end if;
  if p_id is null then
    if p_pin is null or p_pin = '' then raise exception 'PIN_FORMAT'; end if;
    insert into public.branches (name, pin_hash, active)
    values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true))
    returning id into v_id;
  else
    update public.branches
       set name = trim(p_name), active = coalesce(p_active, active),
           pin_hash = case when p_pin is null or p_pin = '' then pin_hash else crypt(p_pin, gen_salt('bf')) end
     where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- ---------- Admin: dashboard numbers ----------
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
revoke all on function public._branch_by_pin(text) from public, anon, authenticated;
revoke all on function public.branch_login(text) from public;
revoke all on function public.do_scratch(text,text,numeric,text,text) from public;
revoke all on function public.check_coupon(text,text) from public;
revoke all on function public.redeem_coupon(text,text) from public;
revoke all on function public.admin_save_branch(bigint,text,text,boolean) from public, anon;
revoke all on function public.admin_stats(date,date) from public, anon;

grant execute on function public.branch_login(text)                       to anon, authenticated;
grant execute on function public.do_scratch(text,text,numeric,text,text)  to anon, authenticated;
grant execute on function public.check_coupon(text,text)                  to anon, authenticated;
grant execute on function public.redeem_coupon(text,text)                 to anon, authenticated;
grant execute on function public.admin_save_branch(bigint,text,text,boolean) to authenticated;
grant execute on function public.admin_stats(date,date)                   to authenticated;
