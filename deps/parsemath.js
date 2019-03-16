var katex = require("katex");
var fs=require('fs');
out = JSON.parse(fs.readFileSync("/dev/stdin", "utf-8"));

var array = [];
for (var pair of out)
    {
         array.push(katex.renderToString(pair[0],
            {
                "display": pair[1]
            }))
    }

process.stdout.write(JSON.stringify(array));