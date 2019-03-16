var katex = require("katex");
var fs=require('fs');
out = JSON.parse(fs.readFileSync("/dev/stdin", "utf-8"));

for (var key in out)
    {
        out[key] = katex.renderToString(key[0],
            {
                "display": key[1]
            });
    }

process.stdout.write(JSON.stringify(out));