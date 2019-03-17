const katex = require("katex");
const fs = require('fs');

input = JSON.parse(fs.readFileSync("/dev/stdin", "utf-8"));

function render(pair)
{
    var str;
    var errmsg;
    try {
        str = katex.renderToString(pair[0], {"display": pair[1]});
        errmsg = "";
       } catch(error) {
           if (pair[1] === true)
           {
            str = `<div class='katex-error' style="color:red"> ${pair[0]} </div>`;
           } else {
            str = `<span class='katex-error' style="color:red"> ${pair[0]} </span>`;
           }
        errmsg = error.message;
       };
     return {
         'render' : str, 
         'error' : errmsg
        }
}
var output = input.map(render)

process.stdout.write(JSON.stringify(output));