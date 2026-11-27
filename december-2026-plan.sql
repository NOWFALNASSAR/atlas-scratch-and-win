-- =====================================================================
-- @less fashion Scratch & Win – December 2026 Prize Plan (exactly 14 prizes)
-- Run AFTER supabase.sql:  Supabase > SQL Editor > New query > paste ALL > Run
--
--  * keeps EXACTLY these 14 prizes; duplicates (any spelling / upper-lower case, e.g.
--    "BLUTOOTH SPEAKER", "PARK AVANUE", "100 CASH BACK") are merged into one, all other prizes are deleted
--  * merges duplicate gift items in the gift master (their stock is added together, nothing is lost)
--  * minimum bill ₹1,500, Christmas theme on
--  * 3 amount slabs with the odds from the plan (qty ÷ slab total):
--       ₹1,500–2,499 (13,350) · ₹2,500–4,999 (9,300) · ₹5,000 and above (3,550)
--  * blocks duplicate prize / gift names from now on
-- Old scratches keep their prize name. Does NOT add stock: use Purchase entry + Stock transfer.
-- Safe to run again. Runs as ONE statement (works in the Supabase SQL Editor).
-- =====================================================================
do $plan$
declare
  v_plan jsonb := $json$[
    {"key": "notebook", "name": "Notebook", "type": "gift", "has_stock": true, "rate": 15, "s1": 37.4534, "s2": 10.7527, "s3": 0.0, "sort": 1},
    {"key": "pv100", "name": "₹100 Purchase Voucher", "type": "voucher", "has_stock": false, "rate": 65, "s1": 14.9813, "s2": 10.7527, "s3": 0.0, "sort": 2},
    {"key": "pv200", "name": "₹200 Purchase Voucher", "type": "voucher", "has_stock": false, "rate": 130, "s1": 7.4906, "s2": 16.1294, "s3": 14.0845, "sort": 3},
    {"key": "pv500", "name": "₹500 Purchase Voucher", "type": "voucher", "has_stock": false, "rate": 330, "s1": 0.0, "s2": 0.5376, "s3": 4.2254, "sort": 4},
    {"key": "cb50", "name": "₹50 Cash Back", "type": "voucher", "has_stock": false, "rate": 50, "s1": 14.9813, "s2": 10.7527, "s3": 0.0, "sort": 5},
    {"key": "cb100", "name": "₹100 Cash Back", "type": "voucher", "has_stock": false, "rate": 100, "s1": 7.4906, "s2": 16.129, "s3": 14.0845, "sort": 6},
    {"key": "container", "name": "Food Container", "type": "gift", "has_stock": true, "rate": 60, "s1": 2.6217, "s2": 3.7634, "s3": 8.4507, "sort": 7},
    {"key": "bowl", "name": "Bowl", "type": "gift", "has_stock": true, "rate": 60, "s1": 2.6217, "s2": 3.7634, "s3": 8.4507, "sort": 8},
    {"key": "bucket", "name": "Bucket", "type": "gift", "has_stock": true, "rate": 50, "s1": 2.6217, "s2": 3.7634, "s3": 8.4507, "sort": 9},
    {"key": "parkavenue", "name": "Park Avenue", "type": "gift", "has_stock": true, "rate": 100, "s1": 2.6217, "s2": 3.7634, "s3": 8.4507, "sort": 10},
    {"key": "bottle", "name": "Water Bottle", "type": "gift", "has_stock": true, "rate": 50, "s1": 2.6217, "s2": 3.7634, "s3": 8.4507, "sort": 11},
    {"key": "speaker", "name": "Bluetooth Speaker", "type": "gift", "has_stock": true, "rate": 200, "s1": 1.4981, "s2": 5.3763, "s3": 8.4507, "sort": 12},
    {"key": "headset", "name": "Bluetooth Headset", "type": "gift", "has_stock": true, "rate": 120, "s1": 1.4981, "s2": 5.3763, "s3": 8.4507, "sort": 13},
    {"key": "earpods", "name": "Bluetooth Earpods", "type": "gift", "has_stock": true, "rate": 200, "s1": 1.4981, "s2": 5.3763, "s3": 8.4507, "sort": 14}
  ]$json$::jsonb;
  r record; v_item bigint; v_prize bigint; v_keep_prizes bigint[] := '{}'; v_keep_items bigint[] := '{}';
begin
  -- which of the 14 a name belongs to (ignores case, spaces, ₹ and common spelling mistakes)
  create or replace function public._gift_key(p text) returns text language sql immutable as $f$
    select case
      when n like '%notebook%' or n like '%notebuk%'                       then 'notebook'
      when n like '%purchasevoucher%' and d in ('100','200','500')         then 'pv' || d
      when n like '%cashback%' and d in ('50','100')                       then 'cb' || d
      when n like '%container%'                                            then 'container'
      when n like '%bowl%'                                                 then 'bowl'
      when n like '%bucket%'                                               then 'bucket'
      when n ~ 'park.*av'                                                  then 'parkavenue'
      when n like '%bottle%'                                               then 'bottle'
      when n like '%speaker%'                                              then 'speaker'
      when n ~ 'headset|neckband|headphone'                                then 'headset'
      when n ~ 'earpod|earbud|tws'                                         then 'earpods'
    end
    from (select lower(regexp_replace(coalesce(p,''), '[^a-zA-Z0-9]', '', 'g')) n,
                 substring(coalesce(p,'') from '[0-9]+') d) x
  $f$;

  update public.campaign set min_bill = 1500, theme = 'xmas' where id = 1;

  for r in select * from jsonb_to_recordset(v_plan) x(key text, name text, type text, has_stock boolean, rate numeric, s1 numeric, s2 numeric, s3 numeric, sort int) order by sort loop
    v_item := null;
    if r.has_stock then
      -- keep the gift item that already has the most stock movements, merge the others into it
      select i.id into v_item from public.items i
       where public._gift_key(i.name) = r.key
       order by (select count(*) from public.stock_moves m where m.item_id = i.id) desc, i.id limit 1;
      if v_item is null then
        insert into public.items (name, price, unit, active) values ('_tmp_' || r.key, r.rate, 'pcs', true) returning id into v_item;
      end if;
      update public.stock_moves set item_id = v_item where item_id in (select id from public.items where public._gift_key(name) = r.key and id <> v_item);
      update public.scratches   set item_id = v_item where item_id in (select id from public.items where public._gift_key(name) = r.key and id <> v_item);
      update public.prizes      set item_id = v_item where item_id in (select id from public.items where public._gift_key(name) = r.key and id <> v_item);
      delete from public.items where public._gift_key(name) = r.key and id <> v_item;
      update public.items set name = r.name, price = r.rate, active = true where id = v_item;
      v_keep_items := v_keep_items || v_item;
    end if;

    -- keep one prize (prefer one that already has a picture), merge the others into it
    select p.id into v_prize from public.prizes p
     where public._gift_key(p.name) = r.key
     order by (p.image is not null) desc, p.active desc, p.id limit 1;
    if v_prize is null then
      insert into public.prizes (name, type, weight, daily_limit, sort, active) values ('_tmp_' || r.key, r.type, 1, 0, r.sort, true) returning id into v_prize;
    end if;
    update public.scratches set prize_id = v_prize where prize_id in (select id from public.prizes where public._gift_key(name) = r.key and id <> v_prize);
    delete from public.prizes where public._gift_key(name) = r.key and id <> v_prize;
    update public.prizes set name = r.name, type = r.type, item_id = v_item, active = true, daily_limit = 0, weight = 1, sort = r.sort where id = v_prize;
    v_keep_prizes := v_keep_prizes || v_prize;
  end loop;

  -- everything that is not one of the 14 goes (old scratches keep their prize name)
  delete from public.prizes where id <> all(v_keep_prizes);
  delete from public.items i where i.id <> all(v_keep_items) and not exists (select 1 from public.stock_moves m where m.item_id = i.id);
  update public.items set active = false where id <> all(v_keep_items);

  -- amount slabs with the plan's odds
  delete from public.slabs;
  insert into public.slabs (min_amount, max_amount) values (1500, 2499), (2500, 4999), (5000, null);
  insert into public.slab_prizes (slab_id, prize_id, percent)
  select s.id, p.id, v.pct
    from jsonb_to_recordset(v_plan) x(name text, s1 numeric, s2 numeric, s3 numeric)
    join public.prizes p on p.name = x.name
    cross join lateral (values (1500, x.s1), (2500, x.s2), (5000, x.s3)) v(slab_min, pct)
    join public.slabs s on s.min_amount = v.slab_min
   where v.pct > 0;

  -- no duplicate names from now on (ignores upper/lower case)
  create unique index if not exists prizes_name_ci_uq on public.prizes (lower(trim(name)));
  create unique index if not exists items_name_ci_uq  on public.items  (lower(trim(name)));
end
$plan$;

-- check: 14 prizes, and each slab = 100
select count(*) as prizes from public.prizes;
select s.min_amount as slab_from, s.max_amount as slab_to, round(sum(sp.percent), 2) as total_percent, count(*) as prizes_in_slab
  from public.slabs s join public.slab_prizes sp on sp.slab_id = s.id group by s.id order by s.min_amount;
