const katex = require("katex");
const fs = require('fs');

input = JSON.parse(fs.readFileSync("/dev/stdin", "utf-8"));

var array = [];
for (var pair of input)
    {
        var str;
        var errmsg;
        try {
            str = katex.renderToString(pair[0], {"display": pair[1]});
            errmsg = "";
           } catch(error) {
               if (pair[1] === "true")
               {
                str = `<div class='error' style="color:red"> ${pair[0]} </div>`;
               } else {
                str = `<span class='error' style="color:red"> ${pair[0]} </span>`;
               }
            errmsg = error.message;
           };
         array.push({
             'render' : str, 
             'error' : errmsg
         });
    }

process.stdout.write(JSON.stringify(array));