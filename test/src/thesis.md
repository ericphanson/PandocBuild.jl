--- 
title: "Thesis"
author: "Eric Hanson"
linkReferences: true
header-includes: |
    ```{=latex}
    \usepackage{amsthm}
    \newtheorem{theorem}{Theorem}
    \theoremstyle{remark}
    \newtheorem{remark}{Remark}
    \usepackage{cleveref}
    ```
---

\newcommand{\inv}{^{-1}}

\newcommand{\bZ}{\mathbb{Z}}
\newcommand{\bR}{\mathbb{R}}
\newcommand{\R}{\mathbb{R}}

\newcommand{\cT}{\mathcal{T}}
\newcommand{\cC}{\mathcal{C}}
\newcommand{\cD}{\mathcal{D}}
\newcommand{\cE}{\mathcal{E}}
\newcommand{\cB}{\mathcal{B}}
\newcommand{\cM}{\mathcal{M}}
\newcommand{\cH}{\mathcal{H}}
\newcommand{\cA}{\mathcal{A}}
\newcommand{\cL}{\mathcal{L}}

\newcommand{\e}{\mathrm{e}}
\newcommand{\one}{\mathbf{1}}
\newcommand{\id}{\operatorname{id}}
\newcommand{\tr}{\operatorname{tr}}
\renewcommand{\d}{\operatorname{d\!}}
\newcommand{\ent}{\operatorname{Ent}}
\newcommand{\Ent}{\operatorname{Ent}}

\newcommand{\braket}[1]{\langle #1 \rangle}
\newcommand{\ket}[1]{| #1 \rangle}
\newcommand{\bra}[1]{\langle #1 |}

Test $𝔽$. 

Test $χ^3+2$
\[
𝔽=5
\]

In the following theorem (\Cref{thm:t1}), we will show that $μ^2 = 2$.

::: {.theorem #thm:t1}
We have that
\[
μ^2 = 2.
\]
:::

Here's an display equation:
\[
x^2 = 4
\] {#eq:5}

(-@eq:5) is a nice equation.

\[
x^2 = 4 + \int_0^\infty x^2 \mathrm{d}x
\label{eq:new}
\] 

\Cref{eq:new} is an even nicer equation.

\Cref{thm:t1} says that $μ^2=1$.rstt

::: {.remark #rem:r1}
This is a remark. Note that $μ^2 = 2$ as shown in \Cref{thm:t1}.
:::


\[
\ket{\phi}\bra{\psi}
\]
