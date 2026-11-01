const assert=require('node:assert/strict');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const clients=[];
async function connect(){
  const c={messages:[],state:null,session:null,ws:new WebSocket(process.env.WWPO_TEST_URL || 'ws://127.0.0.1:7000')};
  c.send=(type,payload={})=>c.ws.send(JSON.stringify({type,payload,version:1,intent_id:crypto.randomUUID()}));
  c.ws.addEventListener('message',e=>{
    const m=JSON.parse(e.data);c.messages.push(m);
    if(m.type==='STATE')c.state=m.payload;
    if(['ROOM_CREATED','JOIN_ACCEPTED'].includes(m.type))c.session=m.payload;
    if(m.type==='PING')c.send('PONG');
  });
  clients.push(c);
  await new Promise((r,j)=>{c.ws.addEventListener('open',r,{once:true});c.ws.addEventListener('error',j,{once:true})});
  return c;
}
async function wait(fn,label){
  for(let i=0;i<200;i++){if(fn())return;await delay(30);}
  throw Error('timeout '+label);
}
(async()=>{
  const host=await connect();
  host.send('CREATE_ROOM',{player_name:'Host7'});
  await wait(()=>host.session&&host.state,'create');
  const code=host.session.room_code;
  for(let n=1;n<7;n++){
    const c=await connect();c.send('JOIN_ROOM',{player_name:'Player'+n,room_code:code});
    await wait(()=>c.session&&c.state,'join');
  }
  const overflow=await connect();overflow.send('JOIN_ROOM',{player_name:'Eighth',room_code:code});
  await wait(()=>overflow.messages.some(m=>m.type==='JOIN_REJECTED'),'room full');
  assert(overflow.messages.find(m=>m.type==='JOIN_REJECTED').payload.message.includes('đầy'));
  const seven=clients.slice(0,7);
  assert(seven.every(c=>c.state.public.players.length===7));
  host.send('START_MATCH');await delay(200);
  assert(!host.state.public.started,'cannot bypass readiness');
  for(const c of seven){c.send('SET_READY');await delay(100);}
  host.send('START_MATCH');
  await wait(()=>seven.every(c=>c.state?.public.phase==='CHARACTER_SELECTION'),'start seven');
  const options=seven.flatMap(c=>c.state.private.character_options.map(x=>x.character_id));
  assert.equal(new Set(options).size,14);
  assert(seven.every(c=>c.state.public.players.every(p=>!p.character_id&&!p.character_options)));
  for(const c of seven){c.send('SELECT_CHARACTER',{character:c.state.private.character_options[0].character_id,match_id:c.state.public.match_id});await delay(100);}
  await wait(()=>seven.every(c=>c.state.public.players.every(p=>p.character_id)),'all characters public');
  const roles=seven.map(c=>c.state.private.role);
  assert.equal(roles.filter(x=>x==='SHERIFF').length,1);
  assert.equal(roles.filter(x=>x==='DEPUTY').length,2);
  assert.equal(roles.filter(x=>x==='OUTLAW').length,3);
  assert.equal(roles.filter(x=>x==='RENEGADE').length,1);
  for(const c of seven){
    assert(c.state.public.players.every(p=>!('hand'in p)&&!('role'in p)));
    assert(!JSON.stringify(c.state.public).includes(c.session.session_token));
  }
  const late=await connect();late.send('JOIN_ROOM',{player_name:'Late',room_code:code});
  await wait(()=>late.messages.some(m=>m.type==='JOIN_REJECTED'),'started room');
  assert(late.messages.find(m=>m.type==='JOIN_REJECTED').payload.message.includes('bắt đầu'));
  for(const c of seven){c.send('LEAVE_ROOM');await delay(80);}
  const gone=await connect();gone.send('JOIN_ROOM',{player_name:'Gone',room_code:code});
  await wait(()=>gone.messages.some(m=>m.type==='JOIN_REJECTED'),'empty room cleaned');
  assert(gone.messages.find(m=>m.type==='JOIN_REJECTED').payload.message.includes('không tồn tại'));
  console.log('PASS: seven-player room, eighth rejection, readiness, 14 private character offers, correct role pool, started-room rejection, empty-room cleanup');
})().catch(e=>{console.error(e.stack);process.exitCode=1}).finally(()=>{clients.forEach(c=>c.ws.close());setTimeout(()=>process.exit(process.exitCode||0),200)});
