-- Run once in Supabase > SQL Editor if your database was created with the Malayalam prize names
update public.campaign set name = 'December Mega Sale' where id = 1 and name = 'ഡിസംബർ മെഗാ സെയിൽ';
update public.prizes p set name = v.en from (values
  ('₹100 വൗച്ചർ','₹100 Voucher'),('₹200 വൗച്ചർ','₹200 Voucher'),('10% ഡിസ്കൗണ്ട് കൂപ്പൺ','10% Discount Coupon'),
  ('ഫ്രീ കർച്ചീഫ്','Free Handkerchief'),('ഫ്രീ ടവൽ','Free Towel'),('ഫ്രീ മുണ്ട്','Free Mundu'),
  ('സിൽവർ കോയിൻ','Silver Coin'),('₹5000 ഗിഫ്റ്റ് വൗച്ചർ','₹5000 Gift Voucher')
) v(ml, en) where p.name = v.ml;
alter table public.campaign alter column name set default 'December Mega Sale';
