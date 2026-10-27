const originalGetContext=HTMLCanvasElement.prototype.getContext;
HTMLCanvasElement.prototype.getContext=function(type,...args){return type==='webgl'?null:originalGetContext.call(this,type,...args);};
