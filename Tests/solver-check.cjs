const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const context={};vm.createContext(context);
for(const name of ['cube','solve','bridge'])vm.runInContext(fs.readFileSync('Core/Resources/'+name+'.js','utf8'),context);
vm.runInContext('Cube.initSolver()',context);
for(const [a,b] of [['R U F2',''],['R U F2',"D L B'"],['','R U']]){
  context.a=a;context.b=b;
  const result=vm.runInContext('solveBetween(new Cube().move(a).asString(),new Cube().move(b).asString())',context);
  assert.equal(typeof result,'string');console.log(a,'->',b,':',result);
}
assert.throws(()=>vm.runInContext('checkedCube("U".repeat(54))',context));
console.log('Offline solver endpoint checks passed');
