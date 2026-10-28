import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validMode, parseChoices, rememberChoice, captureSummary} from '../capture-guide-core.mjs';

test('guide accepts only known modes and valid project IDs',()=>{
  for(const mode of ['__proto__','constructor','lidar',null,{}]) assert.equal(validMode(mode),false);
  assert.equal(validMode('room'),true);assert.equal(validMode('object'),true);
  assert.throws(()=>rememberChoice([],'bad/id','room'));
  assert.throws(()=>rememberChoice([],'good-id','unknown'));
});
test('corrupt or future preference data cannot inject choices or prevent project use',()=>{
  for(const text of ['not json','null','{"version":2,"choices":[]}']) assert.deepEqual(parseChoices(text),[]);
  const text=JSON.stringify({version:1,choices:[['a','room'],['b','__proto__'],['bad/id','object'],['a','object'],null,['c','room','extra']]});
  assert.deepEqual(parseChoices(text),[['a','object']]);
});
test('guide preference is bounded, replaces one choice, and leaves input unchanged',()=>{
  const entries=Array.from({length:40},(_,i)=>['project-'+i,'room']);
  const next=rememberChoice(entries,'project-40','object');
  assert.equal(entries.length,40);assert.deepEqual(entries[0],['project-0','room']);
  assert.equal(next.length,40);assert.equal(next[0][0],'project-1');
  const changed=rememberChoice(next,'project-1','object');
  assert.equal(changed.length,40);assert.equal(changed.filter(([id])=>id==='project-1').length,1);
});
test('capture progress reports saved assets without claiming reconstruction or quality',()=>{
  assert.match(captureSummary(null),/første projekt/);
  assert.equal(captureSummary({photos:[{}],videos:[],model:null}),'1 foto · 0 videoer · ingen 3D-model endnu');
  assert.equal(captureSummary({photos:[],videos:[{}],model:{}}),'0 fotos · 1 video · model tilføjet');
  assert.equal(captureSummary({photos:Array(30),model:null}),'30 fotos · 0 videoer · ingen 3D-model endnu');
});
