const jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'Content-Type, Authorization',
};

const asNumber = (value, fallback = 0) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: jsonHeaders });

function isAuthorized(request, env) {
  const authorization = request.headers.get('authorization') || '';
  return Boolean(env.API_TOKEN) && authorization === `Bearer ${env.API_TOKEN}`;
}

function publicTest(row, includeReadings = false) {
  const test = {
    id: row.id,
    testId: row.id,
    serialNumber: row.serial_number,
    modelName: row.model_name,
    technicianName: row.technician_name,
    profileName: row.profile_name,
    status: row.status,
    verdictReason: row.verdict_reason,
    initialTemp: row.initial_temp,
    finalTemp: row.final_temp,
    targetTemp: row.target_temp,
    maxAllowedMinutes: row.max_allowed_minutes,
    durationMinutes: row.duration_minutes,
    coolingRate: row.cooling_rate,
    doorOpenEvents: row.door_open_events,
    compressorDutyCycle: row.compressor_duty_cycle,
    startTime: row.start_time,
    endTime: row.end_time,
    createdAt: row.created_at,
  };
  if (includeReadings) {
    try { test.readings = JSON.parse(row.readings_json || '[]'); }
    catch { test.readings = []; }
  }
  return test;
}

async function listTests(request, env) {
  const url = new URL(request.url);
  const status = url.searchParams.get('status');
  const search = url.searchParams.get('search');
  const conditions = [];
  const values = [];
  if (status && ['APROVADA', 'REPROVADA', 'INCONCLUSIVA'].includes(status)) {
    conditions.push('status = ?');
    values.push(status);
  }
  if (search) {
    conditions.push('(serial_number LIKE ? OR model_name LIKE ? OR technician_name LIKE ?)');
    const term = `%${search.slice(0, 80)}%`;
    values.push(term, term, term);
  }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const statement = env.DB.prepare(`SELECT * FROM tests ${where} ORDER BY created_at DESC LIMIT 500`).bind(...values);
  const result = await statement.all();
  return json(result.results.map((row) => publicTest(row)));
}

async function createTest(request, env) {
  let body;
  try { body = await request.json(); }
  catch { return json({ error: 'JSON inválido.' }, 400); }

  const serial = String(body.serialNumber || '').trim();
  const model = String(body.modelName || '').trim();
  const technician = String(body.technicianName || '').trim();
  const status = String(body.status || '').toUpperCase();
  if (!serial || !model || !technician) {
    return json({ error: 'Série, modelo e técnico são obrigatórios.' }, 400);
  }
  if (!['APROVADA', 'REPROVADA', 'INCONCLUSIVA'].includes(status)) {
    return json({ error: 'Status de ensaio inválido.' }, 400);
  }

  const id = String(body.testId || `TEST-${Date.now()}`).slice(0, 80);
  const readings = Array.isArray(body.readings) ? body.readings.slice(0, 5000) : [];
  await env.DB.prepare(`INSERT INTO tests (
    id, serial_number, model_name, technician_name, profile_name, status,
    verdict_reason, initial_temp, final_temp, target_temp, max_allowed_minutes,
    duration_minutes, cooling_rate, door_open_events, compressor_duty_cycle,
    start_time, end_time, readings_json, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
  ON CONFLICT(id) DO UPDATE SET
    serial_number=excluded.serial_number, model_name=excluded.model_name,
    technician_name=excluded.technician_name, profile_name=excluded.profile_name,
    status=excluded.status, verdict_reason=excluded.verdict_reason,
    initial_temp=excluded.initial_temp, final_temp=excluded.final_temp,
    target_temp=excluded.target_temp, max_allowed_minutes=excluded.max_allowed_minutes,
    duration_minutes=excluded.duration_minutes, cooling_rate=excluded.cooling_rate,
    door_open_events=excluded.door_open_events,
    compressor_duty_cycle=excluded.compressor_duty_cycle,
    start_time=excluded.start_time, end_time=excluded.end_time,
    readings_json=excluded.readings_json, updated_at=CURRENT_TIMESTAMP`)
    .bind(
      id, serial.slice(0, 120), model.slice(0, 160), technician.slice(0, 120),
      String(body.profileName || body.profile?.name || 'Perfil padrão').slice(0, 160),
      status, String(body.verdictReason || 'Ensaio finalizado.').slice(0, 2000),
      asNumber(body.initialTemp), asNumber(body.finalTemp), asNumber(body.targetTemp),
      Math.round(asNumber(body.maxAllowedMinutes)), Math.round(asNumber(body.durationMinutes)),
      asNumber(body.coolingRate), Math.round(asNumber(body.doorOpenEvents)),
      asNumber(body.compressorDutyCycle, 1), body.startTime || null, body.endTime || null,
      JSON.stringify(readings),
    ).run();

  return json({ success: true, testId: id, status }, 201);
}

async function getTest(id, env) {
  const row = await env.DB.prepare('SELECT * FROM tests WHERE id = ?').bind(id).first();
  return row ? json(publicTest(row, true)) : json({ error: 'Ensaio não encontrado.' }, 404);
}

async function getStats(env) {
  const row = await env.DB.prepare(`SELECT COUNT(*) total,
    SUM(CASE WHEN status='APROVADA' THEN 1 ELSE 0 END) approved,
    SUM(CASE WHEN status='REPROVADA' THEN 1 ELSE 0 END) rejected
    FROM tests`).first();
  const total = row.total || 0;
  const approved = row.approved || 0;
  return json({ total, approved, rejected: row.rejected || 0,
    approvalRate: total ? Number((approved / total * 100).toFixed(1)) : 0 });
}

// Portal web — espelha as telas do app Flutter (mesmos tokens, cards e tipografia)
// e atualiza sozinho (laudos em tempo real por auto-refresh). Sem backticks e sem
// cifrão-chave aqui dentro: o template é String.raw e qualquer um deles quebraria.
const dashboard = String.raw`<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#f6f9fb"><title>AoFrio Test • Portal</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#f6f9fb;--ink:#102a43;--ocean:#087e8b;--ice:#eaf7f8;--snow:#f7fafc;
  --line:#d9e2ec;--slate:#526777;--ok:#177a55;--bad:#b42318;--white:#fff;
  --tileSub:#d6eef0;--failbg:#ffebee;
}
*{box-sizing:border-box}
html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:15px/1.45 Inter,ui-sans-serif,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
button,input{font:inherit;color:inherit}
.shell{max-width:1120px;margin:auto;padding:0 18px}
/* AppBar */
.top{position:sticky;top:0;z-index:20;background:rgba(246,249,251,.9);backdrop-filter:blur(14px);border-bottom:1px solid transparent}
.top.scrolled{border-bottom-color:var(--line)}
.nav{min-height:64px;display:flex;align-items:center;justify-content:space-between;gap:16px}
.brand{display:flex;align-items:center;gap:11px;font-weight:800;font-size:20px;letter-spacing:-.3px}
.mark{width:38px;height:38px;border-radius:13px;background:var(--ocean);display:grid;place-items:center;color:#fff;font-size:20px}
.live{display:flex;align-items:center;gap:7px;background:var(--ice);color:var(--ocean);padding:7px 12px;border-radius:999px;font-size:12px;font-weight:800}
.live .dot{width:8px;height:8px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 0 rgba(23,122,85,.5);animation:pulse 2s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(23,122,85,.45)}70%{box-shadow:0 0 0 7px rgba(23,122,85,0)}100%{box-shadow:0 0 0 0 rgba(23,122,85,0)}}
main{padding:8px 0 90px}
/* Hero tile (igual _LiveTile do app) */
.tile{background:var(--ocean);border-radius:22px;padding:20px;display:flex;align-items:center;gap:14px;color:#fff;margin:8px 0 16px}
.tile .ic{width:46px;height:46px;border-radius:14px;background:rgba(255,255,255,.18);display:grid;place-items:center;font-size:23px;flex:0 0 auto}
.tile h1{margin:0;font-size:16px;font-weight:800;letter-spacing:-.2px}
.tile p{margin:3px 0 0;font-size:12.5px;font-weight:500;color:#fff;opacity:.92}
.tile .cnt{margin-left:auto;text-align:right}
.tile .cnt b{display:block;font-size:30px;font-weight:900;line-height:1;letter-spacing:-1px;font-variant-numeric:tabular-nums}
.tile .cnt span{font-size:11px;opacity:.9}
/* Section cards (igual _SectionCard) */
.card{background:#fff;border:1px solid var(--line);border-radius:22px;padding:20px}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:16px}
.stat{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px}
.stat small{color:var(--slate);font-weight:700;font-size:12.5px}
.stat b{display:block;margin-top:5px;font-size:30px;font-weight:900;letter-spacing:-1px;font-variant-numeric:tabular-nums}
.stat.ok b{color:var(--ok)}.stat.bad b{color:var(--bad)}.stat.ocean b{color:var(--ocean)}
/* Toolbar */
.toolbar{display:flex;gap:12px;align-items:center;margin-bottom:14px;flex-wrap:wrap}
.search{flex:1;min-width:200px;background:#fff;border:1px solid var(--line);border-radius:16px;padding:14px 16px;outline:0}
.search:focus{border-color:var(--ocean);box-shadow:0 0 0 2px rgba(8,126,139,.18)}
.filters{display:flex;gap:7px}
.filter{border:0;border-radius:999px;background:#fff;border:1px solid var(--line);color:var(--slate);padding:11px 15px;font-weight:800;font-size:13px;cursor:pointer}
.filter.active{background:var(--ice);border-color:var(--ice);color:var(--ocean)}
/* Lista (igual aos laudos salvos do app) */
.list{display:flex;flex-direction:column;gap:12px}
.row{background:#fff;border:1px solid var(--line);border-radius:20px;padding:14px 16px;display:flex;align-items:center;gap:14px;cursor:pointer;transition:border-color .15s,transform .15s}
.row:hover{border-color:var(--ocean);transform:translateY(-1px)}
.row.fresh{animation:fresh 1.4s ease}
@keyframes fresh{0%{background:var(--ice)}100%{background:#fff}}
.av{width:44px;height:44px;border-radius:14px;display:grid;place-items:center;font-size:21px;flex:0 0 auto}
.av.ok{background:var(--ice);color:var(--ok)}.av.bad{background:var(--failbg);color:var(--bad)}
.rtxt{min-width:0;flex:1}
.rtxt .t{font-weight:800;font-size:14.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rtxt .s{color:var(--slate);font-size:12.5px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rmeta{text-align:right;flex:0 0 auto}
.badge{display:inline-flex;padding:5px 10px;border-radius:999px;font-size:10.5px;font-weight:900;letter-spacing:.3px}
.badge.ok{color:var(--ok);background:#e8f5ef}.badge.bad{color:var(--bad);background:#fff0ee}
.rmeta .d{color:var(--slate);font-size:11.5px;margin-top:5px}
.chev{color:var(--line);font-size:22px;flex:0 0 auto}
.empty{background:#fff;border:1px dashed var(--line);border-radius:20px;text-align:center;padding:48px 20px;color:var(--slate)}
.spin{width:26px;height:26px;border:2.6px solid var(--line);border-top-color:var(--ocean);border-radius:50%;animation:rot 1s linear infinite;margin:0 auto 14px}
@keyframes rot{to{transform:rotate(360deg)}}
/* Modal laudo (igual TestReportScreen) */
dialog{border:0;padding:0;background:transparent;max-width:760px;width:calc(100% - 28px);margin:auto}
dialog::backdrop{background:rgba(16,42,67,.5);backdrop-filter:blur(4px)}
.sheet{background:var(--bg);border-radius:24px;max-height:92vh;overflow:auto;padding:18px}
.sheet .bar{display:flex;justify-content:flex-end;position:sticky;top:0}
.close{border:0;background:#fff;border:1px solid var(--line);border-radius:50%;width:40px;height:40px;cursor:pointer;font-size:18px;color:var(--slate)}
.verdict{display:flex;gap:14px;align-items:flex-start}
.vIc{width:52px;height:52px;border-radius:50%;display:grid;place-items:center;font-size:27px;flex:0 0 auto}
.vIc.ok{background:rgba(23,122,85,.12);color:var(--ok)}.vIc.bad{background:rgba(180,35,24,.12);color:var(--bad)}
.eyebrow{font-size:12px;font-weight:900;letter-spacing:1px}.eyebrow.ok{color:var(--ok)}.eyebrow.bad{color:var(--bad)}
.vSerial{font-size:22px;font-weight:800;letter-spacing:-.4px;margin-top:2px}
.vReason{margin-top:16px;font-size:15px;line-height:1.45}
.grid2{display:grid;grid-template-columns:3fr 2fr;gap:16px;margin-top:16px}
.ctitle{font-size:16px;font-weight:800}.csub{color:var(--slate);font-size:13px;margin-top:2px}
.curve{height:240px;margin-top:18px}
.curve svg{width:100%;height:100%;overflow:visible}
.chips{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
.chip{background:var(--snow);border-radius:12px;padding:10px 13px;font-size:12px;color:var(--slate)}
.chip b{color:var(--ink);font-weight:900;font-variant-numeric:tabular-nums}
.drow{display:flex;gap:16px;align-items:flex-start;padding:11px 0;border-bottom:1px solid var(--line)}
.drow:last-child{border-bottom:0}
.drow .k{width:120px;color:var(--slate);font-size:12px;flex:0 0 auto}
.drow .v{flex:1;text-align:right;font-weight:800;font-size:13px}
.toast{position:fixed;left:50%;bottom:22px;transform:translateX(-50%);background:var(--ink);color:#fff;padding:12px 18px;border-radius:14px;font-weight:700;font-size:13px;opacity:0;pointer-events:none;transition:opacity .25s;z-index:40}
.toast.show{opacity:1}
@media(max-width:780px){.stats{grid-template-columns:1fr 1fr}.grid2{grid-template-columns:1fr}}
@media(max-width:460px){.shell{padding:0 14px}.stats{grid-template-columns:1fr 1fr}.rmeta .d{display:none}.filter{padding:11px 11px}}
</style></head><body>
<header class="top" id="top"><div class="shell nav">
  <div class="brand"><div class="mark">❄</div><div>AoFrio Test</div></div>
  <div class="live"><span class="dot"></span><span id="liveLabel">ao vivo</span></div>
</div></header>
<main class="shell">
  <section class="tile">
    <div class="ic">🌡</div>
    <div><h1>Ensaios em tempo real</h1><p>Atualiza sozinho conforme os técnicos salvam os laudos.</p></div>
    <div class="cnt"><b id="tileTotal">—</b><span>ensaios</span></div>
  </section>

  <section class="stats">
    <article class="stat"><small>Total de ensaios</small><b id="total">—</b></article>
    <article class="stat ok"><small>Aprovados</small><b id="approved">—</b></article>
    <article class="stat bad"><small>Reprovados</small><b id="rejected">—</b></article>
    <article class="stat ocean"><small>Conformidade</small><b id="rate">—</b></article>
  </section>

  <section class="toolbar">
    <input id="search" class="search" placeholder="Buscar série, modelo ou técnico" oninput="render()">
    <div class="filters">
      <button class="filter active" data-value="TODOS">Todos</button>
      <button class="filter" data-value="APROVADA">Aprovados</button>
      <button class="filter" data-value="REPROVADA">Reprovados</button>
    </div>
  </section>

  <section id="list" class="list"><div class="empty"><div class="spin"></div>Carregando ensaios…</div></section>
</main>

<dialog id="report"><div class="sheet">
  <div class="bar"><button class="close" onclick="report.close()" aria-label="Fechar">×</button></div>
  <section class="card">
    <div class="verdict">
      <div id="vIc" class="vIc"></div>
      <div style="min-width:0"><div id="vEye" class="eyebrow"></div><div id="vSerial" class="vSerial"></div></div>
    </div>
    <div id="vReason" class="vReason"></div>
  </section>
  <div class="grid2">
    <section class="card">
      <div class="ctitle">Curva de resfriamento</div><div class="csub">Temperatura registrada ao longo do ensaio.</div>
      <div id="curve" class="curve"></div>
      <div id="chips" class="chips"></div>
    </section>
    <section class="card">
      <div class="ctitle" style="margin-bottom:10px">Dados do ensaio</div>
      <div id="details"></div>
    </section>
  </div>
</div></dialog>

<div id="toast" class="toast"></div>

<script>
var tests=[],active='TODOS',lastSig='',token=localStorage.getItem('aofrio_api_token')||'',failures=0,firstPaint=true;
var el=function(id){return document.getElementById(id)};
var temp=function(v){return Number(v).toFixed(1)+'°C'};
var safe=function(v){return String(v==null?'':v).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})};
function authFetch(u){return fetch(u,{headers:{Authorization:'Bearer '+token}})}
function toast(m){var t=el('toast');t.textContent=m;t.classList.add('show');setTimeout(function(){t.classList.remove('show')},2600)}

window.addEventListener('scroll',function(){el('top').classList.toggle('scrolled',window.scrollY>4)});

function freshIds(list){ // ids novos desde o último render, pra animar
  var prev={};tests.forEach(function(t){prev[t.id]=1});
  return list.filter(function(t){return !prev[t.id]}).map(function(t){return t.id});
}

async function load(){
  if(!token){token=prompt('Informe a chave de acesso do Portal AoFrio:')||'';if(token)localStorage.setItem('aofrio_api_token',token);else{return}}
  try{
    var r=await Promise.all([authFetch('/api/tests'),authFetch('/api/stats')]);
    if(r[0].status===401||r[1].status===401){localStorage.removeItem('aofrio_api_token');token='';el('list').innerHTML='<div class="empty">Chave inválida. Recarregue a página e informe a chave de novo.</div>';return}
    var d=await Promise.all([r[0].json(),r[1].json()]);
    var incoming=d[0],s=d[1];
    el('total').textContent=s.total;el('tileTotal').textContent=s.total;
    el('approved').textContent=s.approved;el('rejected').textContent=s.rejected;el('rate').textContent=s.approvalRate+'%';
    var fresh=firstPaint?[]:freshIds(incoming);
    if(!firstPaint&&fresh.length){toast(fresh.length+(fresh.length===1?' novo ensaio recebido':' novos ensaios recebidos'))}
    tests=incoming;
    render(fresh);
    failures=0;firstPaint=false;
    el('liveLabel').textContent='ao vivo';
  }catch(e){
    failures++;
    if(firstPaint)el('list').innerHTML='<div class="empty">Não foi possível carregar. Nova tentativa em instantes…</div>';
    el('liveLabel').textContent=failures>2?'reconectando…':'ao vivo';
  }
}

function render(fresh){
  fresh=fresh||[];
  var q=el('search').value.toLowerCase();
  var list=tests.filter(function(t){return (active==='TODOS'||t.status===active)&&[t.serialNumber,t.modelName,t.technicianName].join(' ').toLowerCase().indexOf(q)>-1});
  if(!list.length){el('list').innerHTML='<div class="empty">Nenhum ensaio encontrado.</div>';return}
  el('list').innerHTML=list.map(function(t){
    var ok=t.status==='APROVADA';
    return '<div class="row'+(fresh.indexOf(t.id)>-1?' fresh':'')+'" onclick="openReport(\''+encodeURIComponent(t.id)+'\')">'
      +'<div class="av '+(ok?'ok':'bad')+'">'+(ok?'✓':'!')+'</div>'
      +'<div class="rtxt"><div class="t">'+safe(t.serialNumber)+'  •  '+safe(t.modelName)+'</div>'
      +'<div class="s">'+t.durationMinutes+' min  •  '+temp(t.finalTemp)+'  •  '+safe(t.technicianName)+'</div></div>'
      +'<div class="rmeta"><span class="badge '+(ok?'ok':'bad')+'">'+(ok?'APROVADA':'REPROVADA')+'</span>'
      +'<div class="d">'+new Date(t.createdAt).toLocaleDateString('pt-BR')+'</div></div>'
      +'<div class="chev">›</div></div>';
  }).join('');
}

async function openReport(id){
  var t;
  try{t=await authFetch('/api/tests/'+id).then(function(r){return r.json()})}catch(e){toast('Falha ao abrir o laudo');return}
  var ok=t.status==='APROVADA';
  el('vIc').className='vIc '+(ok?'ok':'bad');el('vIc').textContent=ok?'✓':'⚠';
  el('vEye').className='eyebrow '+(ok?'ok':'bad');el('vEye').textContent=ok?'QUALIFICAÇÃO APROVADA':'QUALIFICAÇÃO REPROVADA';
  el('vSerial').textContent=t.serialNumber;
  el('vReason').textContent=t.verdictReason;
  el('chips').innerHTML=[['Inicial',temp(t.initialTemp)],['Final',temp(t.finalTemp)],['Taxa',Number(t.coolingRate).toFixed(2)+'°C/min'],['Duração',t.durationMinutes+' min']]
    .map(function(c){return '<div class="chip">'+c[0]+'  <b>'+c[1]+'</b></div>'}).join('');
  el('details').innerHTML=[['Modelo',t.modelName],['Técnico',t.technicianName],['Perfil',(t.profileName||'—').split(' (')[0]],['Setpoint',temp(t.targetTemp)],['Tempo permitido',t.maxAllowedMinutes+' min'],['ID do laudo',t.id]]
    .map(function(d){return '<div class="drow"><div class="k">'+d[0]+'</div><div class="v">'+safe(d[1])+'</div></div>'}).join('');
  draw(t.readings||[],ok);
  el('report').showModal();
}

function draw(points,ok){
  var box=el('curve');
  if(points.length<2){box.innerHTML='<div class="empty" style="height:100%;display:grid;place-items:center">Curva indisponível</div>';return}
  var step=Math.max(1,Math.floor(points.length/120));
  var pts=points.filter(function(_,i){return i%step===0});
  var start=new Date(pts[0].timestamp).getTime();
  var xs=pts.map(function(p){return (new Date(p.timestamp).getTime()-start)/60000});
  var ys=pts.map(function(p){return Number(p.temperature)});
  var W=680,H=210,PADL=34,PADB=24;
  var xmin=0,xmax=Math.max(1,xs[xs.length-1]);
  var ymin=Math.min.apply(null,ys),ymax=Math.max.apply(null,ys);var yr=(ymax-ymin)||1;ymin-=yr*0.12;ymax+=yr*0.12;
  var X=function(v){return PADL+((v-xmin)/((xmax-xmin)||1))*(W-PADL)};
  var Y=function(v){return ((ymax-v)/((ymax-ymin)||1))*(H-PADB)};
  var line=xs.map(function(x,i){return (i?'L':'M')+X(x).toFixed(1)+' '+Y(ys[i]).toFixed(1)}).join(' ');
  var area=line+' L'+X(xs[xs.length-1]).toFixed(1)+' '+(H-PADB)+' L'+X(xs[0]).toFixed(1)+' '+(H-PADB)+' Z';
  var col=ok?'#177a55':'#b42318';
  var grid='';var yticks=4;
  for(var g=0;g<=yticks;g++){var yv=ymax-(g/yticks)*(ymax-ymin);var yy=Y(yv).toFixed(1);
    grid+='<line x1="'+PADL+'" y1="'+yy+'" x2="'+W+'" y2="'+yy+'" stroke="#d9e2ec" stroke-width="1"/>';
    grid+='<text x="'+(PADL-8)+'" y="'+(Number(yy)+4)+'" text-anchor="end" font-size="11" fill="#526777">'+Math.round(yv)+'°</text>';}
  var xticks=4,xl='';
  for(var h=0;h<=xticks;h++){var xv=(h/xticks)*xmax;xl+='<text x="'+X(xv).toFixed(1)+'" y="'+(H-6)+'" text-anchor="middle" font-size="11" fill="#526777">'+Math.round(xv)+'m</text>';}
  box.innerHTML='<svg viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none" role="img" aria-label="Curva de resfriamento">'
    +grid
    +'<path d="'+area+'" fill="'+col+'" fill-opacity="0.08"/>'
    +'<path d="'+line+'" fill="none" stroke="'+col+'" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
    +xl+'</svg>';
}

document.querySelectorAll('.filter').forEach(function(b){b.onclick=function(){document.querySelectorAll('.filter').forEach(function(x){x.classList.remove('active')});b.classList.add('active');active=b.dataset.value;render()}});

load();
setInterval(load,7000); // laudos em tempo real
</script>
</body></html>`;

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: jsonHeaders });
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/health') return json({ ok: true, service: 'aofrio-refrigeration' });
      if (url.pathname.startsWith('/api/') && !isAuthorized(request, env)) {
        return json({ error: 'Não autorizado.' }, 401);
      }
      if (url.pathname === '/api/tests' && request.method === 'GET') return listTests(request, env);
      if (url.pathname === '/api/tests' && request.method === 'POST') return createTest(request, env);
      if (url.pathname === '/api/stats' && request.method === 'GET') return getStats(env);
      const match = url.pathname.match(/^\/api\/tests\/([^/]+)$/);
      if (match && request.method === 'GET') return getTest(decodeURIComponent(match[1]), env);
      if (url.pathname.startsWith('/api/')) return json({ error: 'Rota não encontrada.' }, 404);
      return new Response(dashboard, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
    } catch (error) {
      console.error(error);
      return json({ error: 'Falha interna ao processar a solicitação.' }, 500);
    }
  },
};
