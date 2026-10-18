() => {
const parse = s => { const m = s.match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return {r:p[0],g:p[1],b:p[2],a:p.length>3?p[3]:1}; };
const lum = c => { const f = v => { v/=255; return v<=0.03928? v/12.92 : Math.pow((v+0.055)/1.055,2.4); }; return 0.2126*f(c.r)+0.7152*f(c.g)+0.0722*f(c.b); };
const blend = (top, bot) => ({r: top.r*top.a + bot.r*(1-top.a), g: top.g*top.a + bot.g*(1-top.a), b: top.b*top.a + bot.b*(1-top.a), a:1});
const bgOf = el => { const chain=[]; for (let e=el; e; e=e.parentElement) chain.push(parse(getComputedStyle(e).backgroundColor)); let c={r:255,g:255,b:255,a:1}; const root = parse(getComputedStyle(document.documentElement).backgroundColor); if (root && root.a>0) c = blend(root,c); for (let i=chain.length-1;i>=0;i--) { const x=chain[i]; if (x && x.a>0) c=blend(x,c);} return c; };
const out=[]; const walker=document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
let n; while ((n=walker.nextNode())) { const t=n.textContent.trim(); if(!t) continue; const el=n.parentElement; const cs=getComputedStyle(el); if (cs.visibility==='hidden'||cs.display==='none'||el.offsetParent===null && cs.position!=='fixed') continue; if (el.closest('button:disabled')) continue;
 const fg0=parse(cs.color); const bg=bgOf(el); const fg=blend({...fg0, a: fg0.a*parseFloat(cs.opacity)}, bg); const L1=lum(fg), L2=lum(bg); const ratio=(Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05); const size=parseFloat(cs.fontSize), w=parseInt(cs.fontWeight); const large = size>=24 || (size>=18.66 && w>=700); out.push({t:t.slice(0,40), ratio:+ratio.toFixed(2), need: large?3:4.5, size}); }
const fails = out.filter(o=>o.ratio<o.need); out.sort((a,b)=>a.ratio-b.ratio);
const pb = parse(getComputedStyle(document.body).backgroundColor);
return JSON.stringify({theme: document.documentElement.getAttribute('data-theme')||'light', page_bg: getComputedStyle(document.body).backgroundColor, page_bg_luminance: +lum(pb).toFixed(3), text_nodes: out.length, below_wcag_aa: fails, lowest5: out.slice(0,5)});
}
