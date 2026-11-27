// Shared helpers for counter.html and admin.html
window.App = (() => {
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const C = window.APP_CONFIG || {};
  if (C.SUPABASE_URL) C.SUPABASE_URL = C.SUPABASE_URL.trim().replace(/\/(rest|auth)\/v1\/?$/, '').replace(/\/+$/, '');
  const configured = !!(C.SUPABASE_URL && !C.SUPABASE_URL.includes('YOUR-PROJECT') && C.SUPABASE_ANON_KEY && !C.SUPABASE_ANON_KEY.includes('PASTE') && window.supabase);
  const fmtD = s => { if (!s) return ''; const [y, m, d] = String(s).slice(0, 10).split('-'); return `${d}/${m}/${y}`; };
  const fmtDT = s => s ? new Date(s).toLocaleString('en-IN', {timeZone:'Asia/Kolkata', day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) : '';
  const rupee = n => (Number(n) < 0 ? '-₹' : '₹') + Math.abs(Number(n || 0)).toLocaleString('en-IN');
  const num = n => Number(n || 0).toLocaleString('en-IN');
  const today = () => new Date().toLocaleDateString('en-CA', {timeZone:'Asia/Kolkata'});
  const TYPES = {voucher:'Voucher', gift:'Free gift', bumper:'Bumper prize'};
  const store = {
    get(k){ try { return JSON.parse(localStorage.getItem('sw-' + k)); } catch(e) { return null; } },
    set(k, v){ try { localStorage.setItem('sw-' + k, JSON.stringify(v)); } catch(e) {} },
    del(k){ try { localStorage.removeItem('sw-' + k); } catch(e) {} }
  };
  const ERR = {
    BRANCH_PIN:'Wrong PIN, or this branch has been turned off.',
    CAMPAIGN_OFF:'The Scratch & Win offer is not running right now.',
    BILL_EMPTY:'Enter the bill number.',
    MIN_BILL:'This bill amount is below the minimum for a scratch.',
    NAME_EMPTY:'Enter a name.',
    MOBILE_BAD:'Enter a valid 10-digit mobile number.',
    BILL_USED:'This bill number has already been used for a scratch.',
    MOBILE_TODAY:'This mobile number has already scratched today.',
    NO_PRIZE:'No prize is set for this bill amount. Please call Head Office.',
    NO_SLAB:'This bill amount is not in any chance slab. Please call Head Office.',
    BILL_RANGE:'This bill number is not in the valid bill number range for this offer.',
    NO_FIRST_CARD:'This bill has no first scratch card yet.',
    NO_SECOND_CARD:'This bill amount does not qualify for a 2nd scratch card.',
    SECOND_USED:'This bill already got its 2nd scratch card.',
    RANGE_BAD:'"Bill no. from" must be smaller than "Bill no. to".',
    NOT_REDEEMABLE:'This coupon cannot be redeemed (already used or expired).',
    NO_STOCK:'Not enough stock for this item at this location.',
    ALREADY_CLOSED:'This day is already closed for this branch.',
    FUTURE_DAY:'You cannot close a future date.',
    QTY_BAD:'Enter a quantity above 0.',
    NO_LINES:'Add at least one line.',
    PRICE_BAD:'Price cannot be negative.',
    ITEM_BAD:'Choose a gift from the list.',
    SAME_LOCATION:'From and To cannot be the same.',
    PIN_TAKEN:'Another branch already uses this PIN. Choose a different PIN.',
    PIN_FORMAT:'PIN must be 6 digits (numbers only).',
    NOT_ADMIN:'Only the admin can do this.',
    NO_ROLE:'Your login has no access yet. Ask the admin to add you in Users.'
  };
  const errText = e => {
    const m = (e && e.message) || String(e || '');
    for (const k in ERR) if (m.includes(k)) return ERR[k];
    if (/duplicate key/i.test(m) && /name/i.test(m)) return 'This name already exists.';
    if (/row-level security/i.test(m)) return 'You do not have permission to change this.';
    return /fetch|network|Failed/i.test(m) ? 'Internet connection problem. Please try again.' : 'Something went wrong: ' + m;
  };
  const sb = configured ? window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY) : null;

  // ---------- branding ----------
  function applyBrand(s){
    s = s || {};
    const r = document.documentElement.style;
    if (/^#[0-9a-f]{6}$/i.test(s.color || '')) { r.setProperty('--mar', s.color); r.setProperty('--mar2', shade(s.color, -0.35)); document.querySelector('meta[name=theme-color]')?.setAttribute('content', s.color); }
    if (/^#[0-9a-f]{6}$/i.test(s.accent || '')) r.setProperty('--gold', s.accent);
    const name = s.brand_name || C.BRAND || '@less fashion';
    document.querySelectorAll('[data-brand]').forEach(el => el.textContent = name);
    document.querySelectorAll('[data-logo]').forEach(img => { if (s.logo) { img.src = s.logo; img.hidden = false; } else img.hidden = true; });
    return name;
  }
  function shade(hex, p){
    const n = parseInt(hex.slice(1), 16), f = v => Math.max(0, Math.min(255, Math.round(v + (p < 0 ? v * p : (255 - v) * p))));
    return '#' + [f(n >> 16), f((n >> 8) & 255), f(n & 255)].map(v => v.toString(16).padStart(2, '0')).join('');
  }

  // ---------- images: shrink before saving ----------
  function resizeImage(file, maxW, maxH, type){
    return new Promise((res, rej) => {
      const fr = new FileReader();
      fr.onerror = () => rej(new Error('Could not read the file'));
      fr.onload = () => {
        const img = new Image();
        img.onerror = () => rej(new Error('This file is not a picture'));
        img.onload = () => {
          const k = Math.min(1, maxW / img.width, maxH / img.height);
          const c = document.createElement('canvas');
          c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
          const x = c.getContext('2d');
          if (type === 'image/jpeg') { x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height); }
          x.drawImage(img, 0, 0, c.width, c.height);
          res(c.toDataURL(type || 'image/jpeg', 0.82));
        };
        img.src = fr.result;
      };
      fr.readAsDataURL(file);
    });
  }

  // ---------- thermal printing ----------
  function printSlip(html){
    const w = store.get('paper') || '80';
    let box = $('print');
    if (!box) { box = document.createElement('div'); box.id = 'print'; document.body.appendChild(box); }
    let st = $('pageStyle');
    if (!st) { st = document.createElement('style'); st.id = 'pageStyle'; document.head.appendChild(st); }
    st.textContent = `@page{size:${w}mm auto;margin:0 ${w === '58' ? 3 : 4}mm}#print{--pw:${w === '58' ? '48mm' : '72mm'}}`;
    box.innerHTML = `<div class="slip">${html}</div>`;
    const imgs = [...box.querySelectorAll('img')];
    Promise.all(imgs.map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; }))).then(() => setTimeout(() => window.print(), 50));
  }
  const kv = (k, v) => `<div class="kv"><span>${esc(k)}</span><span class="b">${esc(v)}</span></div>`;

  function confetti(){
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const cs = getComputedStyle(document.documentElement);
    const cols = [cs.getPropertyValue('--gold'), cs.getPropertyValue('--mar'), '#ffffff', '#1d8a4b'];
    for (let i = 0; i < 70; i++) {
      const s = document.createElement('span'); s.className = 'confetti';
      s.style.left = Math.random() * 100 + 'vw'; s.style.background = cols[i % cols.length]; s.style.animationDelay = Math.random() * .5 + 's';
      document.body.appendChild(s); setTimeout(() => s.remove(), 2600);
    }
  }

  // ---------- installable web app ----------
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('/sw.js').catch(() => {});

  return {$, esc, C, configured, sb, fmtD, fmtDT, rupee, num, today, TYPES, store, ERR, errText, applyBrand, resizeImage, printSlip, kv, confetti};
})();
