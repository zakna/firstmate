(() => {
  const parse = s => { const m = s.match(/[\d.]+/g); return m ? m.map(Number) : null; };
  const lum = ([r,g,b]) => { const f = c => { c/=255; return c<=0.03928? c/12.92 : Math.pow((c+0.055)/1.055,2.4); }; return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b); };
  const blend = (top, bot) => { const a = top[3] ?? 1; return [0,1,2].map(i => top[i]*a + bot[i]*(1-a)); };
  const bgOf = el => { const stack=[]; for (let e=el; e; e=e.parentElement) { const c=parse(getComputedStyle(e).backgroundColor); if (c && (c[3]??1)>0) stack.push(c); } let base=[255,255,255]; for (const c of stack.reverse()) base=blend(c,base); return base; };
  const out=[]; let worst=99, n=0;
  for (const el of document.querySelectorAll('body *')) {
    const own=[...el.childNodes].some(c=>c.nodeType===3 && c.textContent.trim());
    if (!own) continue; const r=el.getBoundingClientRect(); if (!r.width||!r.height) continue;
    const cs=getComputedStyle(el); if (cs.visibility==='hidden'||+cs.opacity===0) continue;
    const bg=bgOf(el); const fg=blend(parse(cs.color),bg);
    const L1=lum(fg), L2=lum(bg); const ratio=(Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05); n++;
    const disabled = el.closest('button:disabled, [aria-disabled="true"]');
    if (!disabled) worst=Math.min(worst,ratio);
    if (ratio<4.5) out.push({text:el.textContent.trim().slice(0,40), ratio:+ratio.toFixed(2), size:cs.fontSize, disabled:!!disabled});
  }
  const pb = parse(getComputedStyle(document.body).backgroundColor);
  return JSON.stringify({theme:document.documentElement.getAttribute('data-theme')||'light', pageBg:getComputedStyle(document.body).backgroundColor, pageBgLuminance:+lum(pb).toFixed(3), checked:n, worstEnabled:+worst.toFixed(2), below45:out});
})()
