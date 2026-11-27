// Christmas theme: night sky, snow, trees, twinkling lights and Christmas Pappaji flying in with gifts.
// All drawings are original SVG made for this app.
window.Xmas = (() => {
  let active = false, snowRaf = 0;
  const GIFT = (body, ribbon) => `<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg"><rect x="4" y="14" width="32" height="24" rx="3" fill="${body}"/><rect x="2" y="9" width="36" height="8" rx="2" fill="${body}" stroke="#0002"/><rect x="17" y="9" width="6" height="29" fill="${ribbon}"/><path d="M20 9c-6-9-14-3-8 0M20 9c6-9 14-3 8 0" fill="none" stroke="${ribbon}" stroke-width="3"/></svg>`;

  const SLEIGH = `<svg viewBox="0 0 560 210" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="sl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e0262f"/><stop offset="1" stop-color="#8e0f17"/></linearGradient>
  <linearGradient id="gd" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffe9a3"/><stop offset="1" stop-color="#d49a1f"/></linearGradient></defs>
  <g fill="#fff8d6" opacity=".9"><circle cx="540" cy="70" r="3"/><circle cx="525" cy="95" r="2"/><circle cx="548" cy="120" r="2.5"/><circle cx="515" cy="60" r="1.6"/></g>
  ${[0, 120].map((dx, k) => `<g transform="translate(${dx},${k ? 8 : 0})">
    <path d="M58 122 l-18 32 M70 124 l-6 34 M108 122 l16 30 M118 118 l26 22" stroke="#5b3716" stroke-width="7" stroke-linecap="round"/>
    <ellipse cx="88" cy="112" rx="46" ry="21" fill="#8b5a2b"/><ellipse cx="92" cy="120" rx="30" ry="10" fill="#c79a66"/>
    <path d="M52 104 q-8-22 -18-30 l12-6 q16 12 22 32z" fill="#8b5a2b"/>
    <ellipse cx="32" cy="72" rx="18" ry="12" fill="#8b5a2b"/><circle cx="16" cy="76" r="${k ? 4 : 6}" fill="${k ? '#3b2410' : '#ff2d2d'}"/>
    <circle cx="30" cy="68" r="2.4" fill="#111"/>
    <path d="M38 62 q-4-18 -16-24 M38 62 q4-14 -2-28 M30 42 l-8 -6 M36 44 l6 -8" fill="none" stroke="#6b4423" stroke-width="4" stroke-linecap="round"/>
    <path d="M132 104 q8 -6 14 -2" fill="none" stroke="#8b5a2b" stroke-width="6" stroke-linecap="round"/>
    <rect x="60" y="100" width="40" height="7" rx="3" fill="#c0262f"/><circle cx="80" cy="110" r="4" fill="url(#gd)"/></g>`).join('')}
  <path d="M100 104 C180 96 230 104 296 112 M220 112 C250 112 270 112 296 118" fill="none" stroke="url(#gd)" stroke-width="3"/>
  <path d="M296 150 Q282 96 330 92 L478 92 Q510 92 508 128 L506 158 L320 158 Q298 158 296 150Z" fill="url(#sl)"/>
  <path d="M300 128 L506 128" stroke="url(#gd)" stroke-width="5"/>
  <path d="M286 182 L500 182 Q534 182 530 152" fill="none" stroke="url(#gd)" stroke-width="7" stroke-linecap="round"/>
  <path d="M330 158 L326 182 M470 158 L474 182" stroke="url(#gd)" stroke-width="6"/>
  <g transform="translate(430,30)">
    <ellipse cx="18" cy="44" rx="40" ry="34" fill="#2f7d3c"/><path d="M-6 16 q24 -16 46 0" fill="none" stroke="#1f5a2a" stroke-width="6"/>
    <g transform="translate(-14,-10) rotate(-12)">${GIFT('#e0262f', '#ffd23b').replace('<svg', '<svg width="34" height="34"')}</g>
    <g transform="translate(16,-16) rotate(10)">${GIFT('#1f8a4c', '#fff').replace('<svg', '<svg width="30" height="30"')}</g>
    <g transform="translate(34,0) rotate(18)">${GIFT('#3b7bd6', '#ffd23b').replace('<svg', '<svg width="26" height="26"')}</g>
  </g>
  <g transform="translate(332,0)">
    <ellipse cx="30" cy="96" rx="40" ry="34" fill="#d81f2a"/><rect x="-8" y="96" width="76" height="10" fill="#1a1a1a"/><rect x="24" y="94" width="14" height="14" rx="2" fill="url(#gd)"/>
    <path d="M-6 82 C-30 80 -44 92 -46 106" stroke="#d81f2a" stroke-width="16" fill="none" stroke-linecap="round"/>
    <circle cx="-48" cy="108" r="9" fill="#1a1a1a"/>
    <circle cx="24" cy="44" r="22" fill="#f6c9a5"/>
    <path d="M2 48 Q4 84 26 86 Q48 84 46 48 Q36 60 24 56 Q12 60 2 48Z" fill="#fff"/>
    <path d="M10 54 q14 8 28 0" fill="none" stroke="#e9e9e9" stroke-width="5" stroke-linecap="round"/>
    <circle cx="16" cy="40" r="2.6" fill="#222"/><circle cx="31" cy="40" r="2.6" fill="#222"/><circle cx="24" cy="48" r="4" fill="#e9967a"/>
    <path d="M0 30 Q22 -6 62 8 Q72 14 74 26 L48 30Z" fill="#d81f2a"/><circle cx="76" cy="28" r="8" fill="#fff"/>
    <rect x="-2" y="24" width="52" height="11" rx="5.5" fill="#fff"/>
  </g></svg>`;

  function background(){
    const W = 1600, H = 900;
    let stars = '', trees = '';
    for (let i = 0; i < 90; i++) stars += `<circle cx="${(i * 197) % W}" cy="${(i * 73) % 520}" r="${(i % 3) * .6 + .7}" fill="#fff" opacity="${.35 + (i % 5) * .13}"><animate attributeName="opacity" values="1;.2;1" dur="${2 + (i % 4)}s" repeatCount="indefinite" begin="${(i % 7) * .4}s"/></circle>`;
    const tree = (x, y, s, star) => `<g transform="translate(${x},${y}) scale(${s})"><rect x="-8" y="0" width="16" height="26" fill="#5b3a1a"/>
      <path d="M0 -150 L60 -60 L32 -60 L80 0 L-80 0 L-32 -60 L-60 -60Z" fill="#1f6b3a"/>
      <path d="M0 -150 L22 -116 Q0 -108 -22 -116Z M-60 -60 Q-30 -70 0 -62 Q30 -70 60 -60 L46 -56 Q20 -64 0 -56 Q-20 -64 -46 -56Z" fill="#ffd56b" opacity=".75"/>
      ${[[-30, -30, '#ff3b3b'], [26, -24, '#ffd23b'], [-8, -90, '#3bb8ff'], [12, -62, '#ff3b3b'], [-42, -8, '#38d66b'], [44, -6, '#ffd23b']].map(([a, b, c]) => `<circle cx="${a}" cy="${b}" r="5" fill="${c}"/>`).join('')}
      ${star ? '<path d="M0 -176 l7 15 16 2 -12 11 3 16 -14 -8 -14 8 3 -16 -12 -11 16 -2z" fill="#ffd23b"/>' : ''}</g>`;
    [[110, 800, 1.1, 1], [270, 830, .7], [1330, 815, 1.25, 1], [1500, 840, .8], [80, 860, .5], [520, 845, .85, 1], [610, 870, .55], [990, 850, .95, 1], [1100, 875, .6], [455, 880, .45], [1150, 885, .5]].forEach(([x, y, s, st]) => { trees += tree(x, y, s, st); });
    return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMax slice" xmlns="http://www.w3.org/2000/svg">
      <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a0207"/><stop offset=".65" stop-color="#6e0812"/><stop offset="1" stop-color="#a3111f"/></linearGradient>
      <radialGradient id="moon"><stop offset=".6" stop-color="#fff8dc"/><stop offset="1" stop-color="#fff8dc" stop-opacity="0"/></radialGradient></defs>
      <rect width="${W}" height="${H}" fill="url(#sky)"/>${stars}
      <circle cx="1380" cy="150" r="110" fill="url(#moon)" opacity=".35"/><circle cx="1380" cy="150" r="58" fill="#ffd56b"/>
      <path d="M0 760 Q300 690 620 750 T1250 730 T1600 750 L1600 900 L0 900Z" fill="#5c0610"/>
      <g transform="translate(700,770)"><rect x="0" y="-70" width="150" height="80" fill="#7a3b2b"/><path d="M-14 -66 L75 -130 L164 -66Z" fill="#e2ad37"/>
        <rect x="22" y="-48" width="30" height="26" fill="#ffd56b"/><rect x="98" y="-48" width="30" height="26" fill="#ffd56b"/><rect x="62" y="-34" width="26" height="44" fill="#4a2418"/></g>
      ${trees}
      <path d="M0 840 Q400 790 800 835 T1600 830 L1600 900 L0 900Z" fill="#3d030a"/></svg>`;
  }

  function snow(){
    const c = document.createElement('canvas'); c.id = 'snow'; document.body.appendChild(c);
    const x = c.getContext('2d'); let W, H, flakes = [];
    const size = () => { W = c.width = innerWidth; H = c.height = innerHeight; };
    size(); addEventListener('resize', size);
    for (let i = 0; i < 140; i++) flakes.push({x: Math.random() * W, y: Math.random() * H, r: Math.random() * 2.6 + .8, s: Math.random() * .9 + .4, d: Math.random() * 6.28});
    const tick = () => {
      x.clearRect(0, 0, W, H); x.fillStyle = 'rgba(255,226,160,.85)'; x.beginPath();
      flakes.forEach(f => { f.y += f.s; f.d += .01; f.x += Math.sin(f.d) * .5; if (f.y > H) { f.y = -5; f.x = Math.random() * W; } x.moveTo(f.x, f.y); x.arc(f.x, f.y, f.r, 0, 6.28); });
      x.fill(); snowRaf = requestAnimationFrame(tick);
    };
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches) tick();
  }

  function enable(){
    if (active) return; active = true;
    document.body.classList.add('xmas');
    const bg = document.createElement('div'); bg.id = 'xmasBg'; bg.innerHTML = background(); document.body.prepend(bg);
    snow();
    const h = document.querySelector('header');
    if (h) { const l = document.createElement('div'); l.id = 'lights'; l.innerHTML = '<i></i>'.repeat(Math.max(12, Math.round(innerWidth / 46))); h.appendChild(l); }
  }
  function disable(){
    if (!active) return; active = false; document.body.classList.remove('xmas');
    cancelAnimationFrame(snowRaf); ['xmasBg', 'snow', 'lights'].forEach(id => document.getElementById(id)?.remove());
  }

  // Pappaji flies across with his sleigh and drops gifts
  function santa(message){
    if (!active || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    document.getElementById('santaFly')?.remove(); document.getElementById('santaMsg')?.remove();
    const f = document.createElement('div'); f.id = 'santaFly'; f.innerHTML = SLEIGH; document.body.appendChild(f);
    const m = document.createElement('div'); m.id = 'santaMsg'; m.textContent = message || 'Ho ho ho! Pappaji brought your gift!'; document.body.appendChild(m);
    const colors = [['#e0262f', '#ffd23b'], ['#1f8a4c', '#fff'], ['#3b7bd6', '#ffd23b'], ['#ffd23b', '#e0262f']];
    let n = 0;
    const iv = setInterval(() => {
      const r = f.getBoundingClientRect();
      if (r.right > 0 && r.left < innerWidth) {
        const g = document.createElement('div'); g.className = 'giftDrop';
        const [b, rb] = colors[n % colors.length]; g.innerHTML = GIFT(b, rb);
        g.style.left = (r.left + r.width * .82) + 'px'; g.style.top = (r.top + r.height * .25) + 'px';
        document.body.appendChild(g); setTimeout(() => g.remove(), 1500);
      }
      if (++n > 14) clearInterval(iv);
    }, 210);
    setTimeout(() => { f.remove(); m.remove(); }, 3600);
  }

  return {enable, disable, santa, get active(){ return active; }};
})();
