const fs=require('node:fs');
(async()=>{
  const pages=await(await fetch('http://127.0.0.1:9223/json/list')).json();
  for(const p of pages.filter(p=>p.url.startsWith('http://127.0.0.1:8080'))){
    const ws=new WebSocket(p.webSocketDebuggerUrl);
    await new Promise(r=>ws.addEventListener('open',r,{once:true}));
    ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:"JSON.stringify({status:document.getElementById('status')?.textContent,hook:window.__WWPO_TEST&&{id:window.__WWPO_TEST.player_id,error:window.__WWPO_TEST.error,phase:window.__WWPO_TEST.public.phase,room:window.__WWPO_TEST.room,size:window.__WWPO_TEST.size,controls:window.__WWPO_TEST.controls}})",returnByValue:true}}));
    await new Promise(resolve=>ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id===1){console.log(m.result?.result?.value);resolve()}},{once:true}));
    ws.close();
  }
})().catch(console.error);
