/* Real local HTTP/UI; existing disposable fixture, synthetic camera/providers. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { chromium, launchOptions } = require('./browser_tools.cjs');
const frontend = path.resolve(__dirname,'..'), backend=path.resolve(frontend,'../backend');
const output=path.join(frontend,'.validation'); fs.mkdirSync(output,{recursive:true});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function main(){
 const scenario=process.argv[2]||'recognized';
 const root=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'bingo-recapture-ui-'));
 const control=data=>fs.writeFileSync(path.join(root,'control.json'),JSON.stringify(data)); control(scenario==='rejected'?{reject:true}:scenario==='temporary'?{vision_failure:true}:{});
 const reservation=http.createServer(); await new Promise(r=>reservation.listen(0,'127.0.0.1',r));
 const port=reservation.address().port; await new Promise(r=>reservation.close(r));
 const origin=`http://127.0.0.1:${port}`, env={...process.env};
 for(const k of Object.keys(env)) if(/^(BINGO_|SUPABASE_|AWS_|GEMINI_|GOOGLE_)/i.test(k)||/^(https?_proxy|all_proxy|no_proxy)$/i.test(k)) delete env[k];
 const server=spawn(path.join(backend,'.venv/Scripts/python.exe'),['-B','tests/dev_frontend_fixture.py','--root',root,'--port',String(port),'--vision'],{cwd:backend,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
 let logs='',browser,stopped=false; const closed=new Promise(r=>server.once('close',()=>{stopped=true;r();}));
 server.stdout.on('data',b=>logs+=b); server.stderr.on('data',b=>logs+=b);
 const request=async(p,b)=>{const r=await fetch(origin+p,{method:b?'POST':'GET',headers:{'Content-Type':'application/json','X-Totem-Request':'1'},...(b?{body:JSON.stringify(b)}:{})}); assert.ok(r.ok,`${r.status} ${p}`);return r.json();};
 const S='/local/simulation/sessions';
 const stats=()=>JSON.parse(fs.readFileSync(path.join(root,'stats.json')));
 const wait=async(fn)=>{for(let i=0;i<150;i++){if(await fn())return;await pause(100);}throw Error('Timed out');};
 try{
  await wait(async()=>{try{return (await request('/health')).status==='ok';}catch{return false;}});
  const data=await request('/local/dev/context');
  const start=await request(S,{command_id:crypto.randomUUID()}),event=start.session.event_id;
  await request(`/local/dev/sessions/${event}/identity`,{class_id:data.classes[0].id,student_id:data.students[0].id,pin:'0012'});
  await request(`${S}/${event}/safety`,{has_risk:false});
  assert.equal((await request(`${S}/${event}`)).session.state,'INSERTION_READY');
  await request(`${S}/${event}/hand-removed`,{mechanical_command_id:crypto.randomUUID(),hand_removed:true});
  await wait(async()=> (await request(`${S}/${event}`)).session.state===(scenario==='rejected'?'RETURN_REQUIRED':scenario==='temporary'?'TECHNICAL_FAILURE':'REVIEW'));
  const first=await request(`${S}/${event}`);
  browser=await chromium.launch(launchOptions); const page=await browser.newPage({viewport:{width:600,height:1024}});
  page.setDefaultTimeout(15000); page.setDefaultNavigationTimeout(15000);
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>{assert.equal(new URL(route.request().url()).origin,origin);return route.continue();});
  await page.goto(origin);
  if(scenario==='temporary'){
    await page.getByText('Tentar análise novamente',{exact:true}).waitFor();
    assert.equal(await page.getByText('Tirar outra foto',{exact:true}).count(),1);
    control({});await page.locator('[data-dev-op="retry-analysis"]').click();
    await page.locator('[data-session-photo][src^="blob:"]').waitFor();
    assert.equal((await request(`${S}/${event}`)).vision.capture_id,first.vision.capture_id);
    assert.equal(stats().camera.length,1);assert.equal(stats().primary,2);
  }
  let options=3;
  if(scenario==='rejected'){
    await page.getByText('Tirar outra foto',{exact:true}).waitFor();
    assert.equal(await page.locator('[data-dev-op="retry-analysis"]').count(),0);
  }else{
    await page.locator('[data-session-photo][src^="blob:"]').waitFor();
    await page.locator('[data-dev-op="correction"]').click();
    options=await page.locator('[data-dev-op="correct-item"]').count();assert.equal(options,3);
  }
  await page.locator('[data-dev-op="recapture"]').waitFor();
  const priorAnalyses=stats().primary;
  await page.screenshot({path:path.join(output,'recapture-correction.png')});
  control({hold_capture:true});let intent,posts=0;
  page.on('request',r=>{if(r.method()==='POST'&&r.url().endsWith('/vision-recapture'))posts++;});
  await page.route('**/vision-recapture',async route=>{intent=route.request().postDataJSON();await route.fetch();await route.abort('timedout');},{times:1});
  await page.locator('[data-dev-op="recapture"]').click();
  await page.locator('#kiosk[data-operational-state="CAPTURING"]').waitFor();
  await page.reload(); await page.getByText('Fotografando seu eletrônico...',{exact:true}).waitFor();
  await request(`${S}/${event}/vision-recapture`,intent); assert.equal(posts,1);
  control({hold_classification:true});
  await page.getByText('Analisando seu eletrônico...',{exact:true}).waitFor();
  control({}); await page.locator('[data-session-photo][src^="blob:"]').waitFor();
  const second=await request(`${S}/${event}`);
  assert.equal(second.session.event_id,event);assert.notEqual(second.vision.capture_id,first.vision.capture_id);
  assert.deepEqual(second.commands,first.commands);assert.deepEqual(second.identity,first.identity);
  assert.equal(second.vision.capture_history.length,1);assert.equal(second.session.receipt,null);
  assert.equal(stats().camera.length,2);assert.equal(stats().primary,priorAnalyses+1);
  assert.equal(await page.locator('.reward-number').count(),0);
  await page.screenshot({path:path.join(output,'recapture-confirmation.png')});
  await page.locator('[data-dev-op="correction"]').click();assert.equal(await page.locator('[data-dev-op="correct-item"]').count(),options);
  assert.deepEqual(errors,[]);
  const report={scenario,checks:8,hosted:false,errors,requests:posts,captures:stats().camera.length,analyses:stats().primary};
  fs.writeFileSync(path.join(output,`recapture-browser-${scenario}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 }catch(error){
  if(browser){const page=browser.contexts()[0]?.pages()[0];if(page){console.error(await page.locator('#kiosk').innerText());await page.screenshot({path:path.join(output,'recapture-failure.png')});}}
  console.error('fixture',JSON.stringify(stats()));throw error;
 }finally{
  control({});fs.writeFileSync(path.join(root,'stop'),'');
  if(browser)await browser.close();await Promise.race([closed,pause(5000)]);
  if(!stopped){server.kill();await Promise.race([closed,pause(2000)]);}
  fs.writeFileSync(path.join(output,'recapture-server.log'),logs);
  assert.ok(stopped,'Owned fixture stopped before cleanup');
  fs.rmSync(root,{recursive:true,force:true,maxRetries:20,retryDelay:100});
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
