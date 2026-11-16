const $ = (id) => document.getElementById(id);
const STORAGE_KEY = 'radar-uber-v02'; // Chave preservada para manter histórico e parâmetros das versões anteriores.
const DEFAULTS = { weeklyRent: 825, ethanolPrice: 4.20, kmPerLiter: 15, monthlyGoal: 1000, maxKm: 150, dailyHours: 6, daysPerWeek: 7 };
const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Math.max(0, Number(value)) : fallback;
const money = (value) => (Number(value) || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const localDateKey = (date = new Date()) => `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
const fmtTime = (ms) => { const mins=Math.floor(Math.max(0,ms)/60000); return `${Math.floor(mins/60)}h ${String(mins%60).padStart(2,'0')}min`; };
const readSettings = (obj={}) => ({
  weeklyRent: number(obj.weeklyRent, DEFAULTS.weeklyRent) || DEFAULTS.weeklyRent,
  ethanolPrice: number(obj.ethanolPrice, DEFAULTS.ethanolPrice),
  kmPerLiter: Math.max(0.1, number(obj.kmPerLiter, DEFAULTS.kmPerLiter) || DEFAULTS.kmPerLiter),
  monthlyGoal: number(obj.monthlyGoal, DEFAULTS.monthlyGoal),
  maxKm: Math.max(1, number(obj.maxKm, DEFAULTS.maxKm) || DEFAULTS.maxKm),
  dailyHours: Math.min(6, Math.max(0.5, number(obj.dailyHours, DEFAULTS.dailyHours) || DEFAULTS.dailyHours)),
  daysPerWeek: Math.min(7, Math.max(1, Math.round(number(obj.daysPerWeek, DEFAULTS.daysPerWeek) || DEFAULTS.daysPerWeek)))
});
const costs = (settings) => ({ fuelPerKm: settings.ethanolPrice/settings.kmPerLiter, rentPerDay: 0, personalPerDay: settings.monthlyGoal/30 });
const freshDay = () => ({ date: localDateKey(), km:0, elapsedMs:0, earnings:0, hasStarted:false, sessionStartedAt:null, sessionActive:false, settingsSnapshot:null, updatedAt:new Date().toISOString() });
function loadState(){
  try {
    const saved=JSON.parse(localStorage.getItem(STORAGE_KEY)||'null');
    if(!saved||typeof saved!=='object') return {settings:readSettings(),current:freshDay(),history:[]};
    const settings=readSettings(saved.settings||{});
    const history=Array.isArray(saved.history)?saved.history:[];
    let current=saved.current&&saved.current.date===localDateKey()?saved.current:freshDay();
    if(saved.current&&saved.current.date!==localDateKey()){
      const previous={...saved.current,sessionActive:false,sessionStartedAt:null};
      history.unshift(previous);
      const unique=history.filter((item,index,all)=>all.findIndex(x=>x.date===item.date)===index).slice(0,90);
      current=freshDay();
      return {settings,current,history:unique};
    }
    current.km=number(current.km); current.elapsedMs=number(current.elapsedMs); current.earnings=number(current.earnings);
    // Migra dias antigos: se já houve km, tempo ou recebimento, considera que o expediente começou.
    current.hasStarted=Boolean(current.hasStarted||current.km>0||current.elapsedMs>0||current.earnings>0);
    return {settings,current,history};
  } catch { return {settings:readSettings(),current:freshDay(),history:[]}; }
}
let state=loadState();
let settings=state.settings;
let km=state.current.km, earnings=state.current.earnings, elapsedBefore=state.current.elapsedMs, hasStarted=Boolean(state.current.hasStarted);
let active=Boolean(state.current.sessionActive), startAt=active?(Number(state.current.sessionStartedAt)||Date.now()):null, watchId=null, timer=null, lastPoint=null;
function elapsed(){return elapsedBefore+(active&&startAt?Date.now()-startAt:0);}
function currentCosts(){return costs(settings);}
function fuelCost(){return km*currentCosts().fuelPerKm;}
function dailyTarget(){const c=currentCosts();return c.rentPerDay+fuelCost()+c.personalPerDay;}
function netEstimate(){return hasStarted?earnings-fuelCost():null;}
function snapshot(){return {...settings};}
function saveState(){
  state.settings=settings;
  state.current={date:localDateKey(),km,elapsedMs:elapsed(),earnings,hasStarted,sessionStartedAt:active?startAt:null,sessionActive:active,settingsSnapshot:snapshot(),updatedAt:new Date().toISOString()};
  try{localStorage.setItem(STORAGE_KEY,JSON.stringify(state));}catch{$('gpsMessage').textContent='Não foi possível salvar. Exporte o histórico e verifique o espaço do navegador.';}
}
function archiveIfNewDay(){
  const today=localDateKey();
  if(state.current?.date&&state.current.date!==today){
    const old={...state.current,sessionActive:false,sessionStartedAt:null};
    state.history=[old,...state.history.filter(x=>x.date!==old.date)].slice(0,90);
    state.current=freshDay(); km=0; earnings=0; elapsedBefore=0; hasStarted=false; active=false; startAt=null; lastPoint=null;
    if(watchId!==null)navigator.geolocation.clearWatch(watchId);watchId=null;clearInterval(timer);timer=null;
  }
}
function dayNet(item){if(!(item.hasStarted||number(item.km)>0||number(item.elapsedMs)>0||number(item.earnings)>0))return null;const s=readSettings(item.settingsSnapshot||settings),c=costs(s);return number(item.earnings)-number(item.km)*c.fuelPerKm;}
function renderHistory(){
  const rows=[...state.history,{...state.current,date:localDateKey(),km,elapsedMs:elapsed(),earnings,settingsSnapshot:snapshot()}].filter((item,i,all)=>all.findIndex(x=>x.date===item.date)===i).sort((a,b)=>b.date.localeCompare(a.date)).slice(0,10);
  const tbody=$('historyBody');tbody.replaceChildren();
  for(const item of rows){const tr=document.createElement('tr');const vals=[new Date(`${item.date}T12:00:00`).toLocaleDateString('pt-BR'),`${number(item.km).toFixed(1).replace('.',',')} km`,fmtTime(number(item.elapsedMs)),money(item.earnings),dayNet(item)===null?'—':money(dayNet(item))];for(const value of vals){const td=document.createElement('td');td.textContent=value;tr.append(td);}tbody.append(tr);}
  if(!rows.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=5;td.textContent='Ainda não há dias registrados.';tr.append(td);tbody.append(tr);}
}
function renderSettings(){
  $('weeklyRent').value=settings.weeklyRent;$('ethanolPrice').value=settings.ethanolPrice;$('kmPerLiter').value=settings.kmPerLiter;$('monthlyGoal').value=settings.monthlyGoal;$('maxKm').value=settings.maxKm;$('dailyHours').value=settings.dailyHours;$('daysPerWeek').value=settings.daysPerWeek;
  const c=currentCosts();$('fuelPerKm').textContent=`${money(c.fuelPerKm)}/km`;$('rentPerDay').textContent='Controlado pela Uber';$('personalPerDay').textContent=money(c.personalPerDay);
}
function render(){
  archiveIfNewDay();const c=currentCosts(),target=dailyTarget(),remaining=Math.max(0,target-earnings),pct=target>0?Math.min(100,earnings/target*100):0,net=netEstimate();
  $('target').textContent=money(target);$('remaining').textContent=money(remaining);$('receivedLabel').textContent=`${money(earnings)} recebido`;$('progressFill').style.width=`${pct}%`;$('progressLabel').textContent=`${Math.round(pct)}%`;
  $('km').textContent=`${km.toFixed(1).replace('.',',')} km`;$('hours').textContent=fmtTime(elapsed());$('fuel').textContent=money(fuelCost());$('rent').textContent='Uber';$('personalDaily').textContent=money(c.personalPerDay);
  $('kmHint').textContent=km>=settings.maxKm?`Limite planejado de ${settings.maxKm} km atingido`:`Limite planejado: ${settings.maxKm} km`;
  $('hoursHint').textContent=`Meta: ${String(settings.dailyHours).replace('.',',')}h por dia`;
  $('net').textContent=net===null?'—':money(net);$('net').classList.toggle('negative',net!==null&&net<0);$('breakReceived').textContent=money(earnings);$('breakFuel').textContent=money(fuelCost());$('breakRent').textContent='Não duplicado';$('breakNet').textContent=net===null?'Aguardando início':money(net);$('breakNet').style.color=net!==null&&net<0?'#ff8990':net===null?'':'#62e4aa';
  $('netHint').textContent=net===null?'Inicie o expediente para calcular o saldo do dia.':net>=c.personalPerDay?'Meta pessoal diária alcançada após aluguel e combustível.':net>=0?`Faltam ${money(c.personalPerDay-net)} para sua meta pessoal diária.`:'Saldo após descontar aluguel e combustível.';
  $('status').textContent=active?'Em expediente':'Parado';$('startBtn').disabled=active;$('stopBtn').disabled=!active;$('startBtn').textContent=active?'▶ EXPEDIENTE EM ANDAMENTO':'▶ INICIAR EXPEDIENTE';
  $('goalMessage').textContent=earnings>=target?'✓ Meta de recebimento atingida. Você pode encerrar quando quiser.':'Meta ainda não atingida.';$('goalMessage').classList.toggle('achieved',earnings>=target);
  $('dailyDate').textContent=new Date(`${localDateKey()}T12:00:00`).toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
  // Não sobrescreve o campo enquanto o motorista está digitando.
  if(document.activeElement!==$('earnings'))$('earnings').value=earnings?earnings.toFixed(2).replace('.',','):'';
  renderHistory();
}
function distance(a,b){const R=6371000,rad=x=>x*Math.PI/180,dLat=rad(b.latitude-a.latitude),dLon=rad(b.longitude-a.longitude),x=Math.sin(dLat/2)**2+Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(dLon/2)**2;return 2*R*Math.atan2(Math.sqrt(x),Math.sqrt(1-x));}
function onPosition(pos){
  const c=pos.coords;if(c.accuracy>50){$('gpsMessage').textContent=`Precisão do GPS baixa (${Math.round(c.accuracy)} m). Aguardando sinal melhor.`;return;}
  const point={latitude:c.latitude,longitude:c.longitude,timestamp:pos.timestamp};
  if(lastPoint){const meters=distance(lastPoint,point),seconds=Math.max(0,(point.timestamp-lastPoint.timestamp)/1000);if(seconds>0&&seconds<=90&&meters>=8&&meters/seconds<44.45)km+=meters/1000;}
  lastPoint=point;$('gpsMessage').textContent=`GPS ativo • precisão aproximada de ${Math.round(c.accuracy)} m. Distância estimada; confira com o odômetro.`;saveState();render();
}
function onError(err){const messages={1:'Permissão de localização negada. Autorize a localização para este site nas configurações do navegador.',2:'Localização indisponível. Verifique o GPS e tente novamente.',3:'O GPS demorou para responder. Tente novamente.'};$('gpsMessage').textContent=messages[err.code]||'Não foi possível obter a localização.';}
function startTracking(){
  if(!navigator.geolocation){$('gpsMessage').textContent='Este navegador não oferece geolocalização.';return false;}
  if(!window.isSecureContext){$('gpsMessage').textContent='O GPS exige HTTPS ou localhost.';return false;}
  lastPoint=null;
  watchId=navigator.geolocation.watchPosition(onPosition,onError,{enableHighAccuracy:true,maximumAge:2000,timeout:15000});
  timer=setInterval(()=>{archiveIfNewDay();if(active&&elapsed()>=settings.dailyHours*3600000){if(watchId!==null)navigator.geolocation.clearWatch(watchId);watchId=null;active=false;elapsedBefore=settings.dailyHours*3600000;startAt=null;lastPoint=null;clearInterval(timer);timer=null;$('gpsMessage').textContent='Limite máximo da jornada atingido. O expediente foi encerrado automaticamente.';}saveState();render();},1000);
  return true;
}
$('startBtn').addEventListener('click',()=>{
  if(active)return;
  active=true;hasStarted=true;startAt=Date.now();$('gpsMessage').textContent='Iniciando expediente e solicitando localização...';
  if(!startTracking()){active=false;startAt=null;return;}
  saveState();render();
});
$('stopBtn').addEventListener('click',()=>{if(watchId!==null)navigator.geolocation.clearWatch(watchId);watchId=null;active=false;elapsedBefore=elapsed();startAt=null;lastPoint=null;clearInterval(timer);timer=null;$('gpsMessage').textContent='Expediente encerrado. Tempo, distância e valores foram salvos neste navegador.';saveState();render();});
$('saveEarnings').addEventListener('click',()=>{
  const raw=$('earnings').value.trim().replace(/\s/g,'').replace(',','.');const amount=Number(raw);
  if(!raw||!Number.isFinite(amount)||amount<0){$('earningsMessage').textContent='Informe um valor válido, por exemplo 194,50.';return;}
  earnings=amount;if(amount>0)hasStarted=true;saveState();$('earningsMessage').textContent='Recebimento diário salvo. Não é necessário registrar cada corrida.';render();
});
$('saveSettings').addEventListener('click',()=>{
  const vals={weeklyRent:$('weeklyRent').value,ethanolPrice:$('ethanolPrice').value,kmPerLiter:$('kmPerLiter').value,monthlyGoal:$('monthlyGoal').value,maxKm:$('maxKm').value,dailyHours:$('dailyHours').value,daysPerWeek:$('daysPerWeek').value};
  if(Object.values(vals).some(v=>v===''||!Number.isFinite(Number(v)))||Number(vals.kmPerLiter)<=0||Number(vals.maxKm)<=0||Number(vals.dailyHours)<=0||Number(vals.daysPerWeek)<1||Number(vals.daysPerWeek)>7){$('settingsMessage').textContent='Confira os campos: informe números válidos e consumo maior que zero.';return;}
  settings=readSettings(vals);state.settings=settings;saveState();renderSettings();render();$('settingsMessage').textContent='Parâmetros atualizados e salvos neste aparelho.';
});
$('exportBtn').addEventListener('click',()=>{
  const rows=[...state.history,{...state.current,date:localDateKey(),km,elapsedMs:elapsed(),earnings,settingsSnapshot:snapshot()}].filter((item,i,all)=>all.findIndex(x=>x.date===item.date)===i).sort((a,b)=>a.date.localeCompare(b.date));
  const csv=[['Data','Quilometros','Tempo_minutos','Recebido_R...rows.map(x=>{const s=readSettings(x.settingsSnapshot||settings),c=costs(s);return [x.date,number(x.km).toFixed(2).replace('.',','),Math.round(number(x.elapsedMs)/60000),number(x.earnings).toFixed(2).replace('.',','),'0,00',(number(x.km)*c.fuelPerKm).toFixed(2).replace('.',','),dayNet(x)===null?'':dayNet(x).toFixed(2).replace('.',',')].join(';');})].join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='radar-uber-historico.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
window.addEventListener('pagehide',()=>{if(active)saveState();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&active)saveState();else if(document.visibilityState==='visible'&&active){lastPoint=null;$('gpsMessage').textContent='Página voltou ao primeiro plano. O GPS está retomando; confira o odômetro para cobrir eventuais pausas.';saveState();}});
if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('./sw.js').catch(()=>{});
if(active){
  $('gpsMessage').textContent='Expediente recuperado automaticamente. O tempo foi preservado; o GPS está reconectando. Confira o odômetro para cobrir eventual pausa do navegador.';
  startTracking();
  saveState();
}
renderSettings();render();
,'Aluguel_rateado_R...rows.map(x=>{const s=readSettings(x.settingsSnapshot||settings),c=costs(s);return [x.date,number(x.km).toFixed(2).replace('.',','),Math.round(number(x.elapsedMs)/60000),number(x.earnings).toFixed(2).replace('.',','),c.rentPerDay.toFixed(2).replace('.',','),(number(x.km)*c.fuelPerKm).toFixed(2).replace('.',','),dayNet(x)===null?'':dayNet(x).toFixed(2).replace('.',',')].join(';');})].join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='radar-uber-historico.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
window.addEventListener('pagehide',()=>{if(active)saveState();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&active)saveState();else if(document.visibilityState==='visible'&&active){lastPoint=null;$('gpsMessage').textContent='Página voltou ao primeiro plano. O GPS está retomando; confira o odômetro para cobrir eventuais pausas.';saveState();}});
if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('./sw.js').catch(()=>{});
if(active){
  $('gpsMessage').textContent='Expediente recuperado automaticamente. O tempo foi preservado; o GPS está reconectando. Confira o odômetro para cobrir eventual pausa do navegador.';
  startTracking();
  saveState();
}
renderSettings();render();
,'Combustivel_estimado_R...rows.map(x=>{const s=readSettings(x.settingsSnapshot||settings),c=costs(s);return [x.date,number(x.km).toFixed(2).replace('.',','),Math.round(number(x.elapsedMs)/60000),number(x.earnings).toFixed(2).replace('.',','),c.rentPerDay.toFixed(2).replace('.',','),(number(x.km)*c.fuelPerKm).toFixed(2).replace('.',','),dayNet(x)===null?'':dayNet(x).toFixed(2).replace('.',',')].join(';');})].join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='radar-uber-historico.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
window.addEventListener('pagehide',()=>{if(active)saveState();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&active)saveState();else if(document.visibilityState==='visible'&&active){lastPoint=null;$('gpsMessage').textContent='Página voltou ao primeiro plano. O GPS está retomando; confira o odômetro para cobrir eventuais pausas.';saveState();}});
if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('./sw.js').catch(()=>{});
if(active){
  $('gpsMessage').textContent='Expediente recuperado automaticamente. O tempo foi preservado; o GPS está reconectando. Confira o odômetro para cobrir eventual pausa do navegador.';
  startTracking();
  saveState();
}
renderSettings();render();
,'Saldo_estimado_R...rows.map(x=>{const s=readSettings(x.settingsSnapshot||settings),c=costs(s);return [x.date,number(x.km).toFixed(2).replace('.',','),Math.round(number(x.elapsedMs)/60000),number(x.earnings).toFixed(2).replace('.',','),c.rentPerDay.toFixed(2).replace('.',','),(number(x.km)*c.fuelPerKm).toFixed(2).replace('.',','),dayNet(x)===null?'':dayNet(x).toFixed(2).replace('.',',')].join(';');})].join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='radar-uber-historico.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
window.addEventListener('pagehide',()=>{if(active)saveState();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&active)saveState();else if(document.visibilityState==='visible'&&active){lastPoint=null;$('gpsMessage').textContent='Página voltou ao primeiro plano. O GPS está retomando; confira o odômetro para cobrir eventuais pausas.';saveState();}});
if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('./sw.js').catch(()=>{});
if(active){
  $('gpsMessage').textContent='Expediente recuperado automaticamente. O tempo foi preservado; o GPS está reconectando. Confira o odômetro para cobrir eventual pausa do navegador.';
  startTracking();
  saveState();
}
renderSettings();render();
].join(';'),...rows.map(x=>{const s=readSettings(x.settingsSnapshot||settings),c=costs(s);return [x.date,number(x.km).toFixed(2).replace('.',','),Math.round(number(x.elapsedMs)/60000),number(x.earnings).toFixed(2).replace('.',','),c.rentPerDay.toFixed(2).replace('.',','),(number(x.km)*c.fuelPerKm).toFixed(2).replace('.',','),dayNet(x)===null?'':dayNet(x).toFixed(2).replace('.',',')].join(';');})].join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='radar-uber-historico.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
window.addEventListener('pagehide',()=>{if(active)saveState();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&active)saveState();else if(document.visibilityState==='visible'&&active){lastPoint=null;$('gpsMessage').textContent='Página voltou ao primeiro plano. O GPS está retomando; confira o odômetro para cobrir eventuais pausas.';saveState();}});
if('serviceWorker'in navigator&&location.protocol.startsWith('http'))navigator.serviceWorker.register('./sw.js').catch(()=>{});
if(active){
  $('gpsMessage').textContent='Expediente recuperado automaticamente. O tempo foi preservado; o GPS está reconectando. Confira o odômetro para cobrir eventual pausa do navegador.';
  startTracking();
  saveState();
}
renderSettings();render();
