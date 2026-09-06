// Captura del IDE real en Xvfb. Los comandos se entregan a CaptureActivity,
// que acciona las APIs del editor y del plugin dentro del host real.
const fs=require('node:fs'), cp=require('node:child_process'), assert=require('node:assert/strict');
const out='/src/demo/marketing/jetbrains', repo='/film/rate-limit';
const delay=ms=>new Promise(r=>setTimeout(r,ms));
let sequence=Date.now(), started, recorder;
const chapters=[];
const git=(...args)=>cp.execFileSync('git',args,{cwd:repo,encoding:'utf8'}).trim();
async function command(name){
 const id=`${++sequence} ${name}`;
 fs.writeFileSync('/tmp/jb-command',id);
 for(let i=0;i<150;i++){
  if(fs.existsSync('/tmp/jb-error')) throw new Error(fs.readFileSync('/tmp/jb-error','utf8'));
  if(fs.existsSync('/tmp/jb-done')&&fs.readFileSync('/tmp/jb-done','utf8')===id) return;
  await delay(200);
 }
 throw new Error(`Timeout: ${name}`);
}
async function waitBranch(name){for(let i=0;i<50;i++){if(git('branch','--show-current')===name)return;await delay(200);}throw new Error(`Expected branch ${name}`);}
async function mark(name){await delay(800);chapters.push({name,time:(Date.now()-started)/1000});fs.writeFileSync(`${out}/chapters.json`,JSON.stringify(chapters,null,2));cp.execFileSync('ffmpeg',['-y','-loglevel','error','-f','x11grab','-video_size','1440x900','-i',':99','-frames:v','1',`${out}/${name}.png`]);console.log(`CAPTURE ${name}`);}
(async()=>{
 assert.equal(git('branch','--show-current'),'rate-limit');
 await command('before'); await delay(1000);
 fs.rmSync(`${out}/verification.json`, {force:true});
 recorder=cp.spawn('ffmpeg',['-y','-loglevel','error','-f','x11grab','-framerate','30','-video_size','1440x900','-i',':99','-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p',`${out}/raw.mp4`],{stdio:['pipe','ignore','inherit']});started=Date.now();
 try{
  await mark('before'); await delay(2000);
  await command('start'); await waitBranch('review/rate-limit'); await delay(1500);
  assert.ok(git('review','status','--porcelain').includes('walk'));
  await command('reading'); await mark('reading'); await delay(6000);
  await command('next'); await delay(1500); await command('open'); await mark('reason'); await delay(6000);
  await command('select'); await mark('edit'); await delay(1700);
  await command('edit'); await delay(3300);
  const tests=cp.spawnSync('node',['--test'],{cwd:repo,encoding:'utf8'});assert.equal(tests.status,0,tests.stdout+tests.stderr);
  await command('tests'); await delay(1500);cp.execFileSync('xdotool',['mousemove','800','585','mousedown','1','mousemove','800','450','mouseup','1'],{env:{...process.env,DISPLAY:':99'}});await mark('tests');await delay(6000);
  await command('hideTests');await command('finish');await waitBranch('review-fixes/rate-limit');await mark('finish');await delay(8000);
  const patch=git('diff','--cached');assert.equal(git('diff','--cached','--name-only'),'src/rate-limit.js');assert.ok(patch.includes('+  if (attempts >= limit)'));
  assert.equal(git('diff','--name-only'),'');
  assert.ok(git('show','rate-limit:src/rate-limit.js').includes('attempts > limit'));
  fs.writeFileSync(`${out}/verification.json`,JSON.stringify({client:'JetBrains 0.4.0',host:'IntelliJ IDEA 2026.1 Linux',branch:git('branch','--show-current'),tests:tests.stdout,patch},null,2));
  await command('result');await delay(1200);cp.execFileSync('xdotool',['mousemove','190','101','click','1','key','Down','Return'],{env:{...process.env,DISPLAY:':99'}});await mark('result');await delay(5000);
 }finally{recorder.stdin.write('q');await new Promise(r=>recorder.on('exit',r));}
})().catch(e=>{console.error(e);process.exitCode=1});
