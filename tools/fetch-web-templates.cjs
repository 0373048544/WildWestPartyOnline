'use strict';
// Fetch just the Web entries from the official export-template ZIP using HTTP ranges.
// Avoids downloading Android/iOS/Linux/Windows templates for a Web-only build.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
const url='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz';
async function range(start,end){
  const r=await fetch(url,{headers:{Range:'bytes='+start+'-'+end}});
  if(r.status!==206)throw Error('Server did not honor range request: '+r.status);
  return Buffer.from(await r.arrayBuffer());
}
(async()=>{
  const head=await fetch(url,{method:'HEAD'});
  if(!head.ok)throw Error('Official templates unavailable: '+head.status);
  const size=Number(head.headers.get('content-length'));
  const tail=await range(Math.max(0,size-131072),size-1);
  let eocd=-1;
  for(let i=tail.length-22;i>=0;i--)if(tail.readUInt32LE(i)===0x06054b50){eocd=i;break;}
  if(eocd<0)throw Error('ZIP directory not found');
  const length=tail.readUInt32LE(eocd+12),offset=tail.readUInt32LE(eocd+16);
  const directory=await range(offset,offset+length-1);
  const entries=[];
  for(let i=0;i<directory.length;){
    if(directory.readUInt32LE(i)!==0x02014b50)throw Error('Invalid ZIP directory');
    const nl=directory.readUInt16LE(i+28),el=directory.readUInt16LE(i+30),cl=directory.readUInt16LE(i+32);
    const name=directory.subarray(i+46,i+46+nl).toString();
    if(/web.*(debug|release).*\.zip$/.test(name))entries.push({name,method:directory.readUInt16LE(i+10),crc:directory.readUInt32LE(i+16),packed:directory.readUInt32LE(i+20),size:directory.readUInt32LE(i+24),offset:directory.readUInt32LE(i+42)});
    i+=46+nl+el+cl;
  }
  console.log('Official Web templates:',entries.map(e=>e.name).join(', '));
  const chosen=entries.filter(e=>/web_nothreads_(debug|release)\.zip$/.test(e.name));
  if(chosen.length!==2)throw Error('Expected single-thread Web debug/release templates');
  const destination=path.resolve(__dirname,'../build/templates');
  fs.mkdirSync(destination,{recursive:true});
  for(const entry of chosen){
    const header=await range(entry.offset,entry.offset+29);
    const start=entry.offset+30+header.readUInt16LE(26)+header.readUInt16LE(28);
    const packed=await range(start,start+entry.packed-1);
    const data=entry.method===0?packed:zlib.inflateRawSync(packed);
    if(data.length!==entry.size||zlib.crc32(data)!==entry.crc)throw Error('Template ZIP integrity failure');
    fs.writeFileSync(path.join(destination,path.basename(entry.name)),data);
    console.log('Saved',path.basename(entry.name),data.length,'bytes, CRC verified');
  }
})().catch(e=>{console.error(e);process.exitCode=1});
