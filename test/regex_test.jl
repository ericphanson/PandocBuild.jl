
doc = raw"""
\DeclareMathOperator{\abc}{abc}

    \DeclareMathOperator{\abc}{abc}

\DeclareMathOperator{def}{def}

\DeclareMathOperator{\\\rastrata}{rsatsrata}
"""

doc2 =replace(doc, r"\\DeclareMathOperator{(\\.+)}{(.+)}" => s"\\newcommand{\1}{\\operatorname{\2}}")