-- =====================================================================
-- @less fashion Scratch & Win – December 2026 Prize Plan
-- Source: "Scratch & Win – December 2026 Prize Plan" (Nov 27, 2026)
-- Run AFTER supabase.sql:  Supabase > SQL Editor > New query > paste > Run
--
-- What it does:
--   * minimum bill ₹1,500 (bills below ₹1,500 get no scratch), Christmas theme on
--   * 9 gift items with rate (price) in the gift master; 5 vouchers / cash backs (no stock needed)
--   * 3 amount slabs with the odds % from the plan:
--       ₹1,500–2,499 · ₹2,500–4,999 · ₹5,000 and above (the plan says up to ₹25,000;
--       bills above ₹25,000 are kept in the top slab so they never get an error)
--   * prizes that are not in this plan are switched Off (not deleted)
--   * old amount slabs are replaced
-- It does NOT add stock: do Purchase entry and Stock transfer in the app (Stock tab).
-- Safe to run again.
-- =====================================================================
begin;

update public.campaign set min_bill = 1500, theme = 'xmas' where id = 1;

create temp table _plan (name text, type text, has_stock boolean, rate numeric, s1 numeric, s2 numeric, s3 numeric, sort int) on commit drop;
insert into _plan values
  ('Notebook', 'gift', true, 15, 37.4534, 10.7527, 0.0, 1),
  ('₹100 Purchase Voucher', 'voucher', false, 65, 14.9813, 10.7527, 0.0, 2),
  ('₹200 Purchase Voucher', 'voucher', false, 130, 7.4906, 16.1294, 14.0845, 3),
  ('₹500 Purchase Voucher', 'voucher', false, 330, 0.0, 0.5376, 4.2254, 4),
  ('₹50 Cash Back', 'voucher', false, 50, 14.9813, 10.7527, 0.0, 5),
  ('₹100 Cash Back', 'voucher', false, 100, 7.4906, 16.129, 14.0845, 6),
  ('Food Container', 'gift', true, 60, 2.6217, 3.7634, 8.4507, 7),
  ('Bowl', 'gift', true, 60, 2.6217, 3.7634, 8.4507, 8),
  ('Bucket', 'gift', true, 50, 2.6217, 3.7634, 8.4507, 9),
  ('Park Avenue', 'gift', true, 100, 2.6217, 3.7634, 8.4507, 10),
  ('Water Bottle', 'gift', true, 50, 2.6217, 3.7634, 8.4507, 11),
  ('Bluetooth Speaker', 'gift', true, 200, 1.4981, 5.3763, 8.4507, 12),
  ('Bluetooth Headset', 'gift', true, 120, 1.4981, 5.3763, 8.4507, 13),
  ('Bluetooth Earpods', 'gift', true, 200, 1.4981, 5.3763, 8.4507, 14);

-- gift master (only real gift items need stock)
insert into public.items (name, price, unit, active)
select name, rate, 'pcs', true from _plan where has_stock
on conflict (name) do update set price = excluded.price, active = true;

-- prizes: update the ones that already exist, add the missing ones
update public.prizes p
   set type = pl.type, active = true, daily_limit = 0, weight = 1, sort = pl.sort,
       item_id = case when pl.has_stock then (select id from public.items i where i.name = pl.name) else null end
  from _plan pl where p.name = pl.name;
insert into public.prizes (name, type, item_id, weight, daily_limit, sort, active)
select pl.name, pl.type, case when pl.has_stock then (select id from public.items i where i.name = pl.name) end, 1, 0, pl.sort, true
  from _plan pl where not exists (select 1 from public.prizes p where p.name = pl.name);
update public.prizes set active = false where name not in (select name from _plan);

-- amount slabs with the plan's odds
delete from public.slabs;
insert into public.slabs (min_amount, max_amount) values (1500, 2499), (2500, 4999), (5000, null);
insert into public.slab_prizes (slab_id, prize_id, percent)
select s.id, p.id, x.pct
  from _plan pl
  join public.prizes p on p.name = pl.name
  cross join lateral (values (1500, pl.s1), (2500, pl.s2), (5000, pl.s3)) x(slab_min, pct)
  join public.slabs s on s.min_amount = x.slab_min
 where x.pct > 0;

commit;

-- check: each slab should show 100
select s.min_amount as slab_from, s.max_amount as slab_to, round(sum(sp.percent), 2) as total_percent, count(*) as prizes
  from public.slabs s join public.slab_prizes sp on sp.slab_id = s.id group by s.id order by s.min_amount;
