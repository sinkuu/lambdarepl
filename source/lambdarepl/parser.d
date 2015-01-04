module lambdarepl.parser;


import lambdarepl.ast;

import pegged.grammar;

import std.exception;


private
{

mixin(grammar(`
Lambda:
    Term <- Primary Primary*
    Primary <- :space* ((:"(" Term :")") / Variable / Abstraction) :space*
    Abstraction <- ("\\"/"λ") Arguments "." Term
    Arguments <- (:space* Variable)+ :space*
    Variable <- [A-Za-z][A-Za-z0-9_]*
`));

}

Expression parseExpression(string s)
{
    auto tree = Lambda(s);
    enforce!ParseException(tree.successful, tree.failMsg);
    return convertTreeToAST(tree);
}

class ParseException : Exception
{
    this(string msg, string file = __FILE__, ulong line = __LINE__) @safe pure
    {
        super(msg, file, line);
    }
}

private Expression convertTreeToAST(ParseTree node)
{
    switch (node.name)
    {
        case "Lambda":
            return convertTreeToAST(node.children[0]);

        case "Lambda.Term":
            assert(node.children.length >= 1);
            if (node.children.length == 1)
            {
                return convertTreeToAST(node.children[0]);
            }
            else
            {
                auto ae = new ApplyExpression(convertTreeToAST(node.children[0]),
                        convertTreeToAST(node.children[1]));
                foreach (p; node.children[2 .. $])
                {
                    ae = new ApplyExpression(ae, convertTreeToAST(p));
                }
                return ae;
            }

        case "Lambda.Primary":
            return convertTreeToAST(node.children[0]);

        case "Lambda.Abstraction":
            import std.algorithm : map, retro;
            auto vars = node.children[0].children.retro.map!(i => i.matches[0]),
                 term = node.children[1];

            auto abst = new AbstractExpression(vars[0], convertTreeToAST(term));

            foreach (v; vars[1 .. $])
            {
                abst = new AbstractExpression(v, abst);
            }

            return abst;

        case "Lambda.Variable":
            return new VarExpression(node.matches[0]);

        default:
            assert(0);
    }
}

unittest
{
    auto expr = parseExpression(`(\m n s z.n (m s) z) (\s z.s (s (s z))) (\s z.s (s z))`);
    while (expr.reduction()) {}
    assert(expr == parseExpression(`\s z.s (s (s (s (s (s z)))))`));
}

