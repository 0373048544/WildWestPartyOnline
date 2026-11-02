'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const endpoint=process.env.WWPO_TEST_URL||'ws://127.0.0.1:17075';
const peers=[];
async function until(fn,label,ms=12000){const end=Date.now()+ms;while(!fn()){if(Date.now()>end)throw Error('Timeout '+label);await delay(10);}}
class Peer{
 constructor(name){this.name=name;this.messages=[];this.state=null;this.session=null;this.last=0;}
 async open(){this.ws=new WebSocket(endpoint);this.ws.addEventListener('message',e=>{const m=JSON.parse(e.data);this.messages.push(m);if(m.type==='STATE')this.state=m.payload;if(['ROOM_CREATED','JOIN_ACCEPTED','SESSION_RESUMED'].includes(m.type))this.session=m.payload;if(m.type==='PING')this.send('PONG');});await new Promise((r,j)=>{this.ws.addEventListener('open',r,{once:true});this.ws.addEventListener('error',j,{once:true});});}
 packet(type,payload={}){return {type,payload,version:1,intent_id:crypto.randomUUID()};}
 send(type,payload={}){this.ws.send(JSON.stringify(this.packet(type,payload)));}
 async intent(type,payload={}){await delay(Math.max(0,120-(Date.now()-this.last)));const revision=this.state?.public.revision||0;this.send(type,payload);this.last=Date.now();try{await until(()=>this.state?.public.revision>revision,type);}catch(e){console.error('Intent diagnostic',JSON.stringify({type,payload,player:this.session.player_id,phase:this.state.public.phase,turn:this.state.public.current_player,reaction:this.state.private.reaction,errors:this.messages.filter(m=>m.type==='ERROR').slice(-3)}));throw e;}}
 async resume(){const own=structuredClone(this.state.private),token=this.session.session_token;this.ws.close();await delay(100);await this.open();this.state=null;this.send('RESUME_SESSION',{session_token:token});await until(()=>this.state&&this.messages.at(-1)?.type==='STATE'&&this.state.public.players.find(p=>p.player_id===this.session.player_id)?.is_connected,'resume');assert.deepEqual(this.state.private.hand,own.hand);assert.equal(this.state.private.role,own.role);assert.equal(this.state.private.reaction?.request_id,own.reaction?.request_id);}
}
async function peer(name){const p=new Peer(name);peers.push(p);await p.open();return p;}
async function sync(group){await until(()=>{const rev=Math.max(...group.map(p=>p.state?.public.revision||0));return group.every(p=>p.state?.public.revision===rev);},'same atomic revision');}
function verify(group){
 const pub=group[0].state.public;const ids=[];let reserved=0;
 for(const p of group){assert.equal(p.state.public.revision,pub.revision);const row=pub.players.find(x=>x.player_id===p.session.player_id);assert.equal(row.hand_count,p.state.private.hand.length);ids.push(...p.state.private.hand.map(c=>c.instance_id));const r=p.state.private.reaction;if(r&&['judge','draw_choose'].includes(r.reaction_type)){ids.push(...r.cards.map(c=>c.instance_id));reserved+=r.cards.length;}}
 for(const row of pub.players){assert(!('hand'in row)&&!('role'in row)&&!('character_options'in row));if(row.weapon_card?.instance_id)ids.push(row.weapon_card.instance_id);ids.push(...(row.equipment_cards||[]).map(c=>c.instance_id));ids.push(...(row.delayed_cards||[]).map(c=>c.instance_id));}
 ids.push(...pub.market.map(c=>c.instance_id));assert.equal(new Set(ids).size,ids.length,'no duplicate physical cards across owners/in-play/reserved/market');
 assert.equal(ids.length+pub.draw_count+pub.discard_count,80,'80-card conservation over actual client views');assert(!('draw_pile'in pub)&&!('character_options'in pub));
}
async function match(count){
 const host=await peer('Host'+count);host.send('CREATE_ROOM',{player_name:host.name});await until(()=>host.session&&host.state,'create');const group=[host];
 for(let i=1;i<count;i++){const p=await peer('Bot'+i);p.send('JOIN_ROOM',{player_name:p.name,room_code:host.session.room_code});await until(()=>p.state&&p.session,'join');group.push(p);}
 // Replayed ready packet must never toggle twice, even after cooldown and resume.
 const duplicate=host.packet('SET_READY');host.ws.send(JSON.stringify(duplicate));await until(()=>host.state.public.players[0].ready,'ready');await delay(120);host.ws.send(JSON.stringify(duplicate));await delay(120);assert(host.state.public.players[0].ready,'duplicate ready ignored');
 await host.resume();host.ws.send(JSON.stringify(duplicate));await delay(120);assert.equal(host.state.public.players.find(p=>p.player_id===host.session.player_id).ready,false,'disconnect reset remains false; replay cannot set ready');await host.intent('SET_READY');
 for(const p of group.slice(1))await p.intent('SET_READY');const leader=group.find(p=>p.session.player_id===host.state.public.host_player_id);await leader.intent('START_MATCH');await sync(group);
 const pairs=group.map(p=>p.state.private.character_options.map(c=>c.character_id));assert.equal(new Set(pairs.flat()).size,count*2);
 await group.at(-1).resume();
 for(const p of group)await p.intent('SELECT_CHARACTER',{character:p.state.private.character_options[0].character_id,match_id:p.state.public.match_id});
 const checked=new Set();let actions=0;const coverage={};
 for(;actions<3500;actions++){
  await sync(group);verify(group);const pub=host.state.public;if(pub.winner)break;
  const reacting=group.find(p=>p.state.private.reaction?.request_id);
  if(reacting){const r=reacting.state.private.reaction;coverage[r.reaction_type]=(coverage[r.reaction_type]||0)+1;
   if(['store','duel','dodge'].includes(r.reaction_type)&&!checked.has(r.reaction_type)){checked.add(r.reaction_type);await reacting.resume();await sync(group);verify(group);}
   const payload={request:r.request_id,accept:true};if(r.cards)payload.cards=r.cards.slice(0,r.pick_count||1).map(c=>c.instance_id);else if(r.choices){const c=r.choices[0];payload.option=String(c.id);if(c.instance_id)payload.card_instance_id=c.instance_id;}else if(r.allowed_card_types?.length)payload.card_instance_id=r.allowed_card_types[0];else payload.accept=false;
   await reacting.intent('REACTION',payload);continue;
  }
  const p=group.find(p=>p.session.player_id===pub.current_player);assert(p,'active player exists');
  if(!checked.has('turn')){checked.add('turn');await p.resume();await sync(group);}
  if(pub.phase==='DISCARD_PHASE'){await p.intent('DISCARD_CARD',{card_instance_id:p.state.private.hand[0].instance_id});continue;}
  assert.equal(pub.phase,'ACTION_PHASE');
  const forbidden=p.state.private.hand.find(c=>c.card_data_id==='shoot'&&String(p.state.private.disabled_reasons?.[String(c.instance_id)]||'').includes('BANG'));
  if(forbidden&&!checked.has('bang_reconnect')){
    const uid=forbidden.instance_id,target=pub.players.find(row=>row.player_id!==p.session.player_id&&row.is_alive).player_id;
    await p.resume();await sync(group);
    assert.equal((p.state.private.targets[String(uid)]||[]).length,0,'resume cannot clear BANG restriction');
    for(let spam=0;spam<3;spam++)await p.intent('PLAY_CARD',{card_instance_id:uid,target_player_id:target});
    assert(p.state.private.hand.some(c=>c.instance_id===uid),'server rejects forged second BANG after reconnect');
    checked.add('bang_reconnect');
  }
  const legal=p.state.private.hand.filter(c=>p.state.private.targets[String(c.instance_id)]?.length);
  // Prefer attacks so the real-wire match finishes; exercise other legal cards too.
  const card=legal.find(c=>['shoot','gatling','indians','showdown'].includes(c.card_data_id))||legal[0];
  if(card){coverage[card.card_data_id]=(coverage[card.card_data_id]||0)+1;const targets=p.state.private.targets[String(card.instance_id)];const sheriff=pub.players.find(x=>x.public_role==='SHERIFF');const target=sheriff&&targets.includes(sheriff.player_id)&&p.state.private.role==='OUTLAW'?sheriff.player_id:targets[0];await p.intent('PLAY_CARD',{card_instance_id:card.instance_id,target_player_id:target});}
  else await p.intent('END_TURN');
 }
 assert(host.state.public.winner,'complete game must finish');await sync(group);verify(group);
 const before=host.state.public.match_id;const rematchHost=group.find(p=>p.session.player_id===host.state.public.host_player_id);await rematchHost.intent('RESTART_MATCH');await sync(group);assert(host.state.public.match_id>before);assert(group.every(p=>p.state.private.character_options.length===2));assert.equal(new Set(group.flatMap(p=>p.state.private.character_options.map(c=>c.character_id))).size,count*2);
 for(const p of group)p.send('LEAVE_ROOM');
 const result={players:count,actions,coverage,reconnectContexts:[...checked],rematch:true};console.log('PASS full WebSocket match '+JSON.stringify(result));return result;
}
(async()=>{const results=[];for(const count of [2,3,4,5,6,7])results.push(await match(count));fs.mkdirSync('tests/artifacts',{recursive:true});fs.writeFileSync('tests/artifacts/full-web-matches.json',JSON.stringify(results,null,2));})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(()=>{for(const p of peers)p.ws?.close();setTimeout(()=>process.exit(process.exitCode||0),300);});
