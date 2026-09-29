// Offline adapter for cubejs 1.3.2 (MIT). Validate endpoints before exposing a plan.
function checkedCube(s) {
  if(typeof s!=="string" || s.length!==54) throw Error("状态长度错误");
  var c=Cube.fromString(s);
  function permutation(a,n){return a.length===n && new Set(a).size===n && a.every(x=>Number.isInteger(x)&&x>=0&&x<n);}
  function parity(a){var p=0;for(var i=0;i<a.length;i++)for(var j=i+1;j<a.length;j++)if(a[i]>a[j])p^=1;return p;}
  if(!permutation(c.cp,8)||!permutation(c.ep,12)||c.co.some(x=>x<0||x>2)||c.eo.some(x=>x<0||x>1) ||
    c.co.reduce((a,b)=>a+b,0)%3 || c.eo.reduce((a,b)=>a+b,0)%2 || parity(c.cp)!==parity(c.ep) || c.asString()!==s) throw Error("魔方状态不合法");
  return c;
}
function inverseCube(c){
  var d=new Cube();
  for(var i=0;i<8;i++){d.cp[c.cp[i]]=i;d.co[c.cp[i]]=(3-c.co[i])%3;}
  for(var j=0;j<12;j++){d.ep[c.ep[j]]=j;d.eo[c.ep[j]]=c.eo[j];}
  return d;
}
var shortTable;
var shortMoves=['U',"U'",'U2','R',"R'",'R2','F',"F'",'F2','D',"D'",'D2','L',"L'",'L2','B',"B'",'B2'];
function shortSolve(start){
  function expand(frontier,seen){var next=[];for(var node of frontier){for(var m of shortMoves){if(node.path.length&&node.path[node.path.length-1][0]===m[0])continue;var cube=new Cube(node.cube).move(m),key=cube.asString();if(seen.has(key))continue;var item={cube:cube,path:node.path.concat(m)};seen.set(key,item.path);next.push(item);}}return next;}
  if(!shortTable){shortTable=new Map();shortTable.set(new Cube().asString(),[]);var front=[{cube:new Cube(),path:[]}];for(var d=0;d<3;d++)front=expand(front,shortTable);}
  var seen=new Map(),front=[{cube:start,path:[]}];seen.set(start.asString(),[]);
  for(var depth=0;depth<=3;depth++){
    for(var node of front){var tail=shortTable.get(node.cube.asString());if(tail)return node.path.concat(Cube.inverse(tail.join(' ')).split(' ').filter(Boolean)).join(' ');}
    if(depth<3)front=expand(front,seen);
  }
  return null;
}
function solveBetween(a,b) {
  var current=checkedCube(a),target=checkedCube(b);
  if(a===b)return "";
  // moves multiply on the right: solve target^-1 * current to identity.
  var relative=inverseCube(target).multiply(current);
  var result=shortSolve(relative);
  if(result===null)result=relative.solve(22);
  if(checkedCube(a).move(result).asString()!==b)throw Error("解法终点验证失败");
  return result;
}

