'use strict';
const assert = require('node:assert/strict');
const delay = ms => new Promise(r => setTimeout(r, ms));
const URL = process.env.WWPO_TEST_URL || 'ws://127.0.0.1:7000';
class Client {
  constructor(name) { this.name=name; this.messages=[]; this.state=null; this.session=null; }
  async open() {
    this.ws = new WebSocket(URL);
    this.ws.addEventListener('message', e => {
      const m=JSON.parse(e.data); this.messages.push(m);
      if (m.type==='PING') this.send('PONG');
      if (m.type==='STATE') this.state=m.payload;
      if (['ROOM_CREATED','JOIN_ACCEPTED','SESSION_RESUMED'].includes(m.type)) this.session=m.payload;
    });
    await new Promise((resolve,reject) => { this.ws.addEventListener('open',resolve,{once:true}); this.ws.addEventListener('error',reject,{once:true}); });
  }
  send(type,payload={}) { this.ws.send(JSON.stringify({type,payload,version:1})); }
  async wait(predicate, label, ms=10000) {
    const end=Date.now()+ms;
    while (!predicate()) { if(Date.now()>end) throw Error(this.name+': timeout '+label); await delay(30); }
  }
  async intent(type,payload={}) { await delay(100); this.send(type,payload); await delay(150); }
}
const clients=[];
async function client(name) { const c=new Client(name); clients.push(c); await c.open(); return c; }
async function react(c) {
  const r=c.state?.private?.reaction;
  if(!r || !r.request_id) return false;
  let payload={request:r.request_id,accept:true};
  if(r.cards) payload.cards=r.cards.slice(0,r.pick_count||1).map(x=>x.instance_id);
  else if(r.choices) payload.option=String(r.choices[0].id);
  else if(r.allowed_card_types?.length) payload.card_instance_id=r.allowed_card_types[0];
  else payload.accept=false;
  await c.intent('REACTION',payload);
  return true;
}
(async()=>{
  const a=await client('A'), b=await client('B'), other=await client('OtherRoom');
  a.send('CREATE_ROOM',{player_name:'Thắng'});
  await a.wait(()=>a.session&&a.state,'create');
  const code=a.session.room_code;
  assert.match(code,/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/);
  assert.equal(a.state.public.started,false);
  assert.notEqual(a.session.player_id,1,'dedicated server is not a player');
  b.send('JOIN_ROOM',{player_name:'Minh',room_code:code});
  await b.wait(()=>b.state?.public.players.length===2,'join');
  await a.wait(()=>a.state.public.players.length===2,'same room');
  assert.equal(b.state.public.room_code,code);
  other.send('CREATE_ROOM',{player_name:'Phòng riêng'});
  await other.wait(()=>other.session&&other.state,'isolation');
  assert.notEqual(other.session.room_code,code);
  assert.equal(other.state.public.players.length,1);
  const bad=await client('BadCode');
  bad.send('JOIN_ROOM',{player_name:'X',room_code:'XXXXXX'});
  await bad.wait(()=>bad.messages.some(m=>m.type==='JOIN_REJECTED'),'unknown room');
  const invalid=await client('BadName');
  invalid.send('CREATE_ROOM',{player_name:''});
  await invalid.wait(()=>invalid.messages.some(m=>m.type==='JOIN_REJECTED'),'invalid name');
  await a.intent('SET_READY');
  await b.intent('SET_READY');
  assert(a.state.public.players.every(p=>p.ready));
  await b.intent('START_MATCH');
  assert.equal(a.state.public.started,false,'only room host starts');
  // Temporary host disconnect hands administration to B without killing A.
  const oldSession=a.session;
  a.ws.close();
  await b.wait(()=>b.state.public.host_player_id===b.session.player_id,'host migration');
  await a.open();
  a.send('RESUME_SESSION',{session_token:oldSession.session_token});
  await a.wait(()=>a.messages.some(m=>m.type==='SESSION_RESUMED')&&a.state.public.players.every(p=>p.is_connected),'resume');
  assert.equal(a.session.player_id,oldSession.player_id);
  assert.equal(a.state.public.host_player_id,b.session.player_id);
  // Lobby disconnect cleared A's ready flag. Both must ready before host starts.
  await a.intent('SET_READY');
  await b.intent('START_MATCH');
  await a.wait(()=>a.state.public.phase==='CHARACTER_SELECTION','character selection');
  assert.equal(a.state.private.character_options.length,2);
  assert.equal(b.state.private.character_options.length,2);
  const aOptions=a.state.private.character_options.map(c=>c.character_id);
  const bOptions=b.state.private.character_options.map(c=>c.character_id);
  assert(aOptions.every(x=>!bOptions.includes(x)));
  assert(a.state.public.players.every(p=>!p.character_id));
  for(const c of [a,b]) {
    const pick=c.state.private.character_options.find(x=>!['draw_choose','draw_steal','draw_discard'].includes(x.ability_id)) || c.state.private.character_options[0];
    await c.intent('SELECT_CHARACTER',{character:pick.character_id});
  }
  for(let i=0;i<20;i++) {
    await react(a); await react(b);
    if(a.state.public.phase==='ACTION_PHASE') break;
  }
  const sheriff=a.state.public.players.find(p=>p.public_role==='SHERIFF');
  assert.equal(a.state.public.current_player,sheriff.player_id);
  assert.equal(a.state.public.players.filter(p=>p.public_role==='SHERIFF').length,1);
  for(const c of [a,b]) {
    assert(c.state.private.hand.length>=3);
    assert(c.state.public.players.every(p=>!('hand'in p)&&!('role'in p)));
    assert(!('draw_pile'in c.state.public));
    assert(!JSON.stringify(c.state.public).includes(oldSession.session_token));
    assert(c.messages.filter(m=>m.type==='STATE').every(m=>!('character_options'in m.payload.public)));
  }
  assert.equal(other.state.public.started,false,'other room untouched');
  // Mid-match refresh restores the exact same owner-only hand and role.
  const beforeIds=a.state.private.hand.map(c=>c.instance_id);
  const beforeRole=a.state.private.role;
  const token=a.session.session_token;
  a.ws.close();
  await delay(300); await a.open();
  a.send('RESUME_SESSION',{session_token:token});
  await delay(300);
  assert.deepEqual(a.state.private.hand.map(c=>c.instance_id),beforeIds);
  assert.equal(a.state.private.role,beforeRole);
  assert(a.state.public.players.find(p=>p.player_id===a.session.player_id).is_alive);
  // Play real available intentions through the authoritative server.
  let played=0, ended=0;
  for(let i=0;i<30 && !a.state.public.winner;i++) {
    for(const c of [a,b]) if(await react(c)) played++;
    const c=[a,b].find(c=>c.session.player_id===a.state.public.current_player);
    if(!c) break;
    if(c.state.public.phase==='DISCARD_PHASE') {
      await c.intent('DISCARD_CARD',{card_instance_id:c.state.private.hand[0].instance_id}); continue;
    }
    if(c.state.public.phase!=='ACTION_PHASE') continue;
    const card=c.state.private.hand.find(x=>(c.state.private.targets[String(x.instance_id)]||[]).length);
    if(card && played<8) {
      const target=c.state.private.targets[String(card.instance_id)][0];
      await c.intent('PLAY_CARD',{card_instance_id:card.instance_id,target_player_id:target}); played++;
    } else { await c.intent('END_TURN'); ended++; }
    if(ended>=2) break;
  }
  assert(played>0&&ended>0,'card interactions and full turn exercised');
  const forged=await client('StolenToken');
  forged.send('RESUME_SESSION',{session_token:'f'.repeat(64)});
  await forged.wait(()=>forged.messages.some(m=>m.type==='JOIN_REJECTED'),'forged token');
  for(const c of [a,b,other]) c.send('LEAVE_ROOM');
  await delay(200);
  console.log('PASS: WebSocket rooms, isolation, names/ready, authority, private characters/hands, host migration, refresh/resume, card interactions and turn flow');
})().catch(e=>{ console.error(e.stack); process.exitCode=1; }).finally(()=>{ for(const c of clients) c.ws?.close(); setTimeout(()=>process.exit(process.exitCode||0),300); });
