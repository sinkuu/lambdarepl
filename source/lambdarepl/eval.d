module lambdarepl.eval;


import lambdarepl.ast;
import lambdarepl.parser;


struct Evaluator
{
    Expression[string] variables;

    EvalResult eval(string s)
    {
        Expression expr;

        try
        {
            expr = parseExpression(s);
        }
        catch (ParseException e)
        {
            return EvalResult(e.msg);
        }

        return eval(expr);
    }

    EvalResult eval(Expression expr)
    {
        foreach (id, e; variables)
        {
            expr.replace(id, e);
        }

        return EvalResult(expr.dup, Reductions(expr));
    }
}


private struct EvalResult
{
    Expression expression;
    Reductions reductions;
    string error;

    this(Expression expr, Reductions r)
    {
        expression = expr;
        reductions = r;
    }

    this(string e)
    {
        error = e;
    }
}


private struct Reductions
{
    private
    {
        Expression _expr;
        bool _done;
    }

    this(Expression e)
    {
        _expr = e;
        _done = !_expr.reduction();
    }

    @property bool empty() const
    {
        return _done;
    }

    Expression front()
    {
        return _expr.dup;
    }

    void popFront()
    {
        _done = !_expr.reduction();
    }

    @property auto save()
    {
        return Reductions(_expr.dup);
    }
}

