'use strict';
// Original procedural sound design: no samples, recordings or third-party audio.
const fs=require('node:fs'),path=require('node:path'),rate=22050;
let seed=71231;function noise(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/2147483648-1;}
const groups={ui:['hover','button','confirm','join','error','ready','unready','turn','reaction','survive','tick'],cards:['draw','play','discard','place','select','release','fan','snatch','flip','dump'],weapons:['bang','volcanic','gatling','cock'],characters:['hit','dodge','death','heal','beer'],equipment:['barrel','lucky','fail','weapon','horse','scope','jail','unlock','fuse','explosion','pass','wagon','coins','glass','door_open','door_close'],stingers:['start','role','duel','danger','reward','sheriff_win','outlaw_win','renegade_win'],ambience:['saloon'],music:['piano']};
const manifest={};
groups.weapons.push('schofield','remington','carabine','winchester','ricochet');
groups.ambience.push('wood_creak');
groups.ui.push('duel_alert');
const guns={bang:[95,34],schofield:[125,39],remington:[65,25],carabine:[165,45],winchester:[135,32],volcanic:[145,52],gatling:[110,40]};
// Original 16-bar saloon waltz: fingerpicked accompaniment, bass and melody.
// Used exclusively on screens where Music is allowed by AudioManager.
function saloonWaltz(t){
 const beat=60/92,bar=beat*3,b=Math.floor(t/bar)%16,local=t%bar;
 const chords=[[50,57,62,65],[50,57,62,65],[55,59,62,67],[57,61,64,67],[53,57,60,65],[53,57,60,65],[52,55,60,64],[57,61,64,67],[50,57,62,65],[58,62,65,69],[55,59,62,67],[57,61,64,67],[53,57,60,65],[52,55,60,64],[57,61,64,67],[50,57,62,65]];
 const melody=[[74,77,76,74,69,0],[72,74,77,0,76,74],[71,74,79,78,74,71],[73,76,81,0,79,76],[77,81,79,77,72,0],[76,77,81,0,79,77],[76,79,84,83,79,76],[73,76,79,0,76,73],[74,77,81,79,77,74],[77,82,81,77,74,0],[79,78,74,71,74,0],[76,81,79,76,73,0],[77,76,72,69,72,77],[76,79,72,0,71,72],[73,76,79,76,73,69],[74,0,69,0,62,0]];
 const hz=m=>440*2**((m-69)/12);
 const pluck=(m,a,decay=5)=>a<0||a>2?0:(Math.sin(2*Math.PI*hz(m)*a)+.28*Math.sin(2*Math.PI*hz(m)*2.003*a)+.1*Math.sin(2*Math.PI*hz(m)*3*a))*Math.exp(-a*decay)*Math.min(1,a*250);
 let value=0;for(let k=0;k<6;k++){const a=local-k*beat/2;const note=melody[b][k];if(note)value+=pluck(note,a,4.8)*.13;value+=pluck(chords[b][1+k%3],a-.012,7)*.045;}
 value+=pluck(chords[b][0]-12,local,3.8)*.19;value+=pluck(chords[b][0]-5,local-1.5*beat,4)*.12;
 return value;
}
function synth(name,variant){
 const long=['saloon','piano'].includes(name),sting=['start','sheriff_win','outlaw_win','renegade_win'].includes(name);
 const duration=name==='piano'?16*3*60/92:long?8:name==='fuse'?2.5:name==='explosion'?1.2:sting?1.35:name==='gatling'?.65: guns[name]?.42:name==='wood_creak'?.7:.28;
 const n=Math.floor(duration*rate),pcm=Buffer.alloc(n*2);let low=0;
 for(let i=0;i<n;i++){
  const t=i/rate,u=t/duration,r=noise();low=low*.91+r*.09;let v=0;
  const tone=(f)=>Math.sin(2*Math.PI*f*t),env=Math.min(1,t*250)*Math.pow(1-u,3);
  if(name==='saloon')v=low*(.20+.08*Math.sin(2*Math.PI*t/8))*(.8+.2*Math.cos(2*Math.PI*t/4));
  else if(name==='piano')v=(saloonWaltz(t)+saloonWaltz((t+duration-.13)%duration)*.13)*Math.min(1,t*8,(duration-t)*8);
  else if(sting){const notes=name==='renegade_win'?[220,261.63,329.63,246.94]:name==='outlaw_win'?[196,246.94,293.66,392]:[261.63,329.63,392,523.25];const beat=.24;const a=t%beat;const f=notes[Math.floor(t/beat)%4]*(1+variant*.002);v=(Math.sin(2*Math.PI*f*a)+.35*Math.sin(2*Math.PI*f*2.002*a)+.12*Math.sin(2*Math.PI*f*3*a))*Math.exp(-a*10)*Math.min(1,a*200)*.34*Math.min(1,(duration-t)*10);}
  else if(guns[name]){const a=name==='gatling'?t%.095:t,[f,decay]=guns[name];const blast=(r*.95+low*1.8+Math.sin(2*Math.PI*(f+variant*3)*a)*.55)*Math.exp(-a*decay)*Math.min(1,a*2400);const reflection=a>.055?(low*.8+r*.14)*Math.exp(-(a-.055)*20):0;const metal=Math.sin(2*Math.PI*(1700+variant*130)*a)*Math.exp(-a*90)*.14;v=(blast+reflection+metal)*Math.min(1,(duration-t)*40);}
  else if(name==='explosion'){v=(low*3.2+tone(42+variant*4)*.7+r*.3)*Math.exp(-t*5)*Math.min(1,t*1600)+r*.18*Math.exp(-Math.abs(t-.19)*17);}
  else if(name==='ricochet')v=(Math.sin(2*Math.PI*(2100*t-1700*t*t))*.35+r*.1)*env;
  else if(['turn','reaction','duel_alert','tick','danger','survive','duel','reward','heal'].includes(name)){v=(low*.85+r*.16)*Math.exp(-t*45)+tone(name==='survive'?57:130)*Math.exp(-t*30)*.25;if(name==='duel')v+=low*.25*Math.sin(Math.PI*u);}
  else if(name==='wood_creak')v=(low*.4+tone(95+14*Math.sin(t*15))*.14)*Math.sin(Math.PI*u)**2;
  else if(['draw','play','discard','snatch','fan','flip','release','select'].includes(name)){v=(r-low)*env*(.18+.16*Math.sin(t*(180+variant*30))**2)+low*.12*env;if(['play','discard'].includes(name))v+=low*.8*Math.exp(-t*60);}
  else if(name==='fuse')v=(r-low)*.22*Math.sin(Math.PI*u)**.5;
  else if(name==='dodge'||name==='pass')v=(r-low)*Math.sin(Math.PI*u)**2*.35+.1*tone(700-500*u)*env;
  else if(name==='hit'||name==='death')v=(low*1.4+tone(110-55*u)*.32)*env;
  else if(name==='beer'||name==='heal')v=(tone(260+variant*10)*.2+low*.4)*env+.14*tone(660)*Math.exp(-Math.abs(t-.16)*35);
  else {const metallic=['weapon','scope','jail','unlock','lucky','coins','glass','turn','reaction','survive','join'].includes(name);const f=metallic?680+variant*60:['error','fail','dump','barrel','door_close'].includes(name)?110:280;v=(tone(f)*.3+tone(f*1.47)*.16+low*.35)*env;if(name==='door_open'||name==='horse'||name==='wagon')v+=tone(90+80*Math.sin(t*19))*env*.25;}
  pcm.writeInt16LE(Math.round(Math.tanh(v)*.60*32767),i*2);
 }
 const header=Buffer.alloc(44);header.write('RIFF');header.writeUInt32LE(36+pcm.length,4);header.write('WAVEfmt ',8);header.writeUInt32LE(16,16);header.writeUInt16LE(1,20);header.writeUInt16LE(1,22);header.writeUInt32LE(rate,24);header.writeUInt32LE(rate*2,28);header.writeUInt16LE(2,32);header.writeUInt16LE(16,34);header.write('data',36);header.writeUInt32LE(pcm.length,40);return Buffer.concat([header,pcm]);
}
for(const [group,names] of Object.entries(groups))for(const name of names){const count=['bang','draw','ricochet','wood_creak'].includes(name)?4:['schofield','remington','carabine','winchester','volcanic','play','discard','place','hit'].includes(name)?3:['dodge','jail','explosion'].includes(name)?2:1;manifest[name]=[];for(let v=0;v<count;v++){const relative=`assets/audio/${group}/${name}_${v+1}.wav`;fs.mkdirSync(path.dirname(relative),{recursive:true});fs.writeFileSync(relative,synth(name,v));manifest[name].push('res://'+relative);}}
fs.writeFileSync('assets/audio/manifest.json',JSON.stringify(manifest,null,2)+'\n');
console.log('Generated original audio: '+Object.keys(manifest).length+' semantic sounds');
