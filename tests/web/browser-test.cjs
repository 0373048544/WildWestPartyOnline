'use strict';
// No npm dependencies: Node 22+ native WebSocket speaks Chrome DevTools Protocol.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const root=path.resolve(__dirname,'../..');
const edge=process.env.WWPO_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
let browser,ws,next=1;
const keepAlive=setInterval(()=>{},1000);
const mobile=process.argv.includes('--mobile');
const cdpPort=Number(process.env.WWPO_CDP_PORT||9223);
const touchPages=new Set();
const testPages=[];
const calls=new Map(), errors=[];
function command(method,params={},sessionId) {
  return new Promise((resolve,reject)=>{
    const id=next++; calls.set(id,{resolve,reject});
    ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));
    setTimeout(()=>{if(calls.has(id)){calls.delete(id);reject(Error('CDP timeout '+method));}},30000).unref();
  });
}
async function wait(fn,label,ms=45000) {
  const end=Date.now()+ms;
  while(Date.now()<end){const value=await fn();if(value)return value;await delay(200);}
  throw Error('Browser timeout '+label);
}
async function evaluate(page,expression) {
  const r=await command('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},page);
  if(r.exceptionDetails) throw Error(r.exceptionDetails.text);
  return r.result.value;
}
async function snapshot(page) {
  // Web rendering pauses in background tabs: sample a fresh visible frame.
  await command('Page.bringToFront',{},page);
  await delay(160);
  const value=await evaluate(page,'JSON.stringify(window.__WWPO_TEST || null)');return value?JSON.parse(value):null;
}
async function clickAt(page,x,y) {
  await command('Page.bringToFront',{},page);
  const s=await snapshot(page);
  const rect=await evaluate(page,"JSON.stringify((()=>{let r=document.querySelector('canvas').getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height}})())");
  const r=JSON.parse(rect); x=r.x+x*r.w/s.size.x; y=r.y+y*r.h/s.size.y;
  if(touchPages.has(page)){
    await command('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y,id:0}]},page);
    await command('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]},page);
  }else{
    await command('Input.dispatchMouseEvent',{type:'mouseMoved',x,y},page);
    await command('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x,y},page);
    await command('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x,y},page);
  }
  await delay(250);
}
async function click(page,predicate) {
  const c=await wait(async()=>{const s=await snapshot(page); return s?.controls.find(predicate);},'control');
  await clickAt(page,c.x,c.y);
}
async function input(page,name,value) {
  await click(page,c=>c.kind==='input'&&(!name||c.name===name));
  await command('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2},page);
  await command('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2},page);
  for(const character of value){
    await command('Input.dispatchKeyEvent',{type:'keyDown',key:character,text:character,unmodifiedText:character},page);
    await command('Input.dispatchKeyEvent',{type:'keyUp',key:character},page);
  }
  await wait(async()=>{const s=await snapshot(page);return s?.controls.some(c=>c.kind==='input'&&(!name||c.name===name)&&c.text===value)},'text input '+name);
}
async function newPage(width=1440,height=900) {
  if(mobile){width=844;height=390;}
  const context=await command('Target.createBrowserContext');
  const target=await command('Target.createTarget',{url:'about:blank',browserContextId:context.browserContextId});
  const session=await command('Target.attachToTarget',{targetId:target.targetId,flatten:true});
  const page=session.sessionId;
  testPages.push(page);
  await command('Runtime.enable',{},page);
  await command('Page.enable',{},page);
  if(process.env.WWPO_TEST_URL) {
    await command('Page.addScriptToEvaluateOnNewDocument',{source:'Object.defineProperty(window,"WWPO_CONFIG",{get:()=>({serverUrl:'+JSON.stringify(process.env.WWPO_TEST_URL)+'}),set:()=>{}});'},page);
  }
  await command('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<900},page);
  if(mobile){touchPages.add(page);await command('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:1},page);}
  await command('Page.navigate',{url:(process.env.WWPO_TEST_HTTP || 'http://127.0.0.1:8080/')+'?e2e=1'},page);
  await wait(async()=>{const s=await snapshot(page);return s?.controls.length;},'Godot loaded',90000);
  return page;
}
async function choose(page) {
  await wait(async()=>{const s=await snapshot(page);return s?.private.character_options?.length===2;},'private characters');
  await click(page,c=>c.name==='CharacterOption0');
  await click(page,c=>c.name==='ConfirmCharacter'&&!c.disabled);
}
async function handleChoice(page) {
	const initial = await snapshot(page);
	if(initial?.controls.some(c=>c.text==='TIẾP TỤC')) await click(page,c=>c.text==='TIẾP TỤC');
  const s=await snapshot(page), r=s?.private.reaction;
  if(!r?.request_id) return;
  if(r.cards) {
    for(let i=0;i<(r.pick_count||1);i++) await click(page,c=>c.card_index===i);
    if((r.pick_count||1)>1) await click(page,c=>c.text==='XÁC NHẬN LỰA CHỌN'&&!c.disabled);
  } else if(r.choices) {
    // Draw deck/table choices are deliberately tested through physical picking.
    if(['draw_steal','draw_discard'].includes(r.reaction_type)) {
      const points=s.objects||{};
      if(points.deck) await clickAt(page,points.deck.x,points.deck.y);
    }
  } else {
    const allowed=r.allowed_card_types||[];
    const index=s.private.hand.findIndex(c=>allowed.includes(c.instance_id));
    if(index>=0) await click(page,c=>c.card_index===index&&!c.disabled);
    else await click(page,c=>c.text==='CHỊU ĐÒN'||c.text==='KHÔNG CỨU');
  }
}
async function save(page,name) {
  const result=await command('Page.captureScreenshot',{format:'png'},page);
  fs.mkdirSync(path.join(root,'tests/artifacts/web'),{recursive:true});
  fs.writeFileSync(path.join(root,'tests/artifacts/web',(mobile?'mobile-':'')+name+'.png'),Buffer.from(result.data,'base64'));
}
(async()=>{
  browser=spawn(edge,['--headless=new','--remote-debugging-port='+cdpPort,'--remote-allow-origins=*',
    '--user-data-dir='+path.join(root,'tests/artifacts/browser-profile-'+cdpPort),'--no-first-run','--no-default-browser-check',
    '--disable-extensions','--disable-sync','--disable-features=msEdgeSignin,msEdgeFirstRunExperience',
    '--disable-background-timer-throttling','--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding',
    '--enable-unsafe-swiftshader','--use-angle=swiftshader','--autoplay-policy=no-user-gesture-required','about:blank'],
    {windowsHide:true,stdio:'ignore'});
  const endpoint=await wait(async()=>{try{return await(await fetch('http://127.0.0.1:'+cdpPort+'/json/version')).json()}catch{return null}},'browser launch');
  ws=new WebSocket(endpoint.webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true})});
  ws.addEventListener('message',e=>{
    const m=JSON.parse(e.data);
    if(m.id&&calls.has(m.id)){const c=calls.get(m.id);calls.delete(m.id);m.error?c.reject(Error(m.error.message)):c.resolve(m.result||{});}
    if(m.method==='Runtime.exceptionThrown') errors.push(JSON.stringify(m.params));
    if(m.method==='Runtime.consoleAPICalled'&&m.params.type==='error') {
      const text=m.params.args.map(a=>a.value||a.description||'').join(' ');
      if(/SCRIPT ERROR|Parse Error|Invalid call|Nonexistent|Failed to load script/.test(text)) errors.push(text);
    }
  });
  const a=await newPage(),b=await newPage();
  await click(a,c=>c.text==='TẠO PHÒNG');
  await input(a,null,'Thang');
  assert(!(await snapshot(a)).controls.some(c=>c.text==='Cổng'||c.text==='Địa chỉ IP'));
  await click(a,c=>c.text==='TẠO PHÒNG');
  const room=await wait(async()=>{const s=await snapshot(a);return s?.room;},'room created');
  await save(a,'created');
  await click(b,c=>c.text==='THAM GIA');
  await input(b,null,'Minh');
  await input(b,'RoomCode',room);
  await click(b,c=>c.text==='THAM GIA');
  await wait(async()=>{const s=await snapshot(b);return s?.public.players?.length===2;},'same lobby');
  assert.equal((await snapshot(a)).room,(await snapshot(b)).room);
  await click(a,c=>c.name==='ReadyButton');
  await click(b,c=>c.name==='ReadyButton');
  await wait(async()=>(await snapshot(a)).public.players.every(p=>p.ready),'ready synchronized');
  await save(b,'lobby');
  await click(a,c=>c.name==='StartButton'&&!c.disabled);
  await choose(a); await choose(b);
  await wait(async()=>{for(const p of[a,b])await handleChoice(p);return (await snapshot(a)).public.phase==='ACTION_PHASE'},'table and draw');
  for(const p of[a,b]){
    let s=await snapshot(p);
    assert.equal(s.client_registry_count,0,'browser has no authoritative player registry');
    assert(s.private.hand.length>=3);
    assert(s.public.players.every(x=>!('hand'in x)&&!('role'in x)));
    if(s.controls.some(c=>c.text==='TIẾP TỤC'))await click(p,c=>c.text==='TIẾP TỤC');
  }
  const s=await snapshot(a);
  await wait(async()=>{const mix=(await snapshot(a)).profile;return !mix.music_allowed&&!mix.music_playing},'active match has no music');
  assert.equal(s.public.current_player,s.public.players.find(p=>p.public_role==='SHERIFF').player_id);
  await save(a,'table');
  // Refresh A's actual browser tab; sessionStorage should recover identity/hand.
  const before=await snapshot(a);
  await command('Page.reload',{},a);
  await wait(async()=>{const r=await snapshot(a);return r?.player_id===before.player_id&&r?.private.hand?.length>0},'browser refresh recovery',90000);
  const after=await snapshot(a);
  assert.equal(after.private.role,before.private.role);
  assert.deepEqual(after.private.hand.map(c=>c.instance_id),before.private.hand.map(c=>c.instance_id));
  if(after.controls.some(c=>c.text==='TIẾP TỤC'))await click(a,c=>c.text==='TIẾP TỤC');
  // Use legal cards/turns until an actual Shoot can be aimed at a 3D character.
  let targeted=false,turns=0;
  for(let step=0;step<45&&!targeted;step++){
    for(const p of[a,b])await handleChoice(p);
    const sa=await snapshot(a),sb=await snapshot(b);
    if(sa.public.winner)break;
    const page=sa.public.current_player===sa.player_id?a:b;
    const current=page===a?sa:sb;
    if(current.public.phase==='DISCARD_PHASE'){
      await click(page,c=>c.card_index===0&&!c.disabled);continue;
    }
    if(current.public.phase!=='ACTION_PHASE'){await delay(250);continue;}
    const index=current.private.hand.findIndex(c=>['shoot','dodge'].includes(c.card_data_id)&&(current.private.targets[String(c.instance_id)]||[]).some(id=>id!==current.player_id));
    if(index>=0){
      const card=current.private.hand[index];
      const target=current.private.targets[String(card.instance_id)][0];
      await click(page,c=>c.card_index===index&&!c.disabled);
      await wait(async()=>(await snapshot(page)).selected===card.instance_id,'Shoot selection');
      const aim=(await snapshot(page)).avatars[String(target)];
      await clickAt(page,aim.x,aim.y);
      if(mobile){
        const preview=await snapshot(page);
        assert.equal(preview.selected,card.instance_id,'first touch does not commit');
        assert(preview.targeting.guide&&preview.targeting.reticle,'first touch shows aim preview');
        await save(page,'aim');
        await clickAt(page,aim.x,aim.y);
      }
      await wait(async()=>!(await snapshot(page)).private.hand.some(c=>c.instance_id===card.instance_id),'accepted 3D targeting');
      targeted=true;
      await save(page,'shot');
    }else{
      await click(page,c=>c.name==='EndTurn');turns++;
    }
  }
  assert(targeted,'browser selects Shoot and clicks actual 3D avatar');
  await handleChoice(a);await handleChoice(b);
  assert.equal(errors.length,0,'Godot browser errors: '+errors.join('\n'));
  console.log('PASS: two isolated '+(mobile?'touch/mobile-emulated':'desktop')+' browser clients create/join by code, ready, character selection, private hands, Sheriff starts, 3D Shoot targeting, refresh/reconnect; turns='+turns);
  await command('Browser.close');
})().catch(async e=>{
  console.error(e.stack);process.exitCode=1;
  for(let i=0;i<testPages.length;i++)try {
    const s=await snapshot(testPages[i]);
    fs.writeFileSync(path.join(root,'tests/artifacts/web/failure-'+i+'.json'),JSON.stringify(s,null,2));
    await save(testPages[i],'failure-'+i);
  } catch {}
  try{if(ws?.readyState===1)await command('Browser.close')}catch{}
}).finally(()=>{
	clearInterval(keepAlive);
  ws?.close();if(browser&&!browser.killed)browser.kill();setTimeout(()=>process.exit(process.exitCode||0),500);
});
