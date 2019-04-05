
doc = raw"""
\DeclareMathOperator{\abc}{abc}

    \DeclareMathOperator{\abc}{abc}

\DeclareMathOperator{def}{def}

\DeclareMathOperator{\\\rastrata}{rsatsrata}
"""

doc2 =replace(doc, r"\\DeclareMathOperator{(\\.+)}{(.+)}" => s"\\newcommand{\1}{\\operatorname{\2}}")

m = raw"""
x^2 = 5 \label{eq:test}
"""

out = match(r"\\label{(eq\:.+)}", m)