module lambdarepl.ast;


import std.algorithm;
import std.container;
import std.conv;
import std.exception;
import std.functional;
import std.range;


abstract class Expression
{
    Expression dup() const
    {
        assert(0);
    }

    override string toString() const
    {
        assert(0);
    }
}


final class VarExpression : Expression
{
    string name;

    this(string n)
    {
        name = n;
    }

    override string toString() const
    {
        return name;
    }

    override bool opEquals(Object obj) const
    {
        if (auto var = cast(VarExpression)obj) return name == var.name;
        return false;
    }

    override Expression dup() const
    {
        return new VarExpression(name);
    }
}

VarExpression variable(string name)
{
    return new VarExpression(name);
}


final class AbstractExpression : Expression
{
    string var;

    Expression term;

    this(string v, Expression t)
    {
        var = v;
        term = t;
    }

    override bool opEquals(Object obj) const
    {
        if (auto lm = cast(AbstractExpression)obj) return lm.var == var && lm.term == term;
        return false;
    }

    override string toString() const
    {
        if (auto lm = cast(AbstractExpression)term)
        {
            auto vars = appender!(string[]);
            vars ~= var;

            AbstractExpression l = lm;
            do
            {
                lm = l;
                vars ~= lm.var;
                l = cast(AbstractExpression)lm.term;
            } while (l);

            // strip parenthesis
            if (auto a = cast(ApplyExpression) lm.term)
                return "(λ"~ vars.data.join(' ') ~ "." ~ lm.term.toString()[1 .. $-1] ~ ")";
            else
                return "(λ"~ vars.data.join(' ') ~ "." ~ lm.term.toString() ~ ")";
        }
        else
        {
            // strip parenthesis
            if (auto a = cast(ApplyExpression) term)
                return "(λ"~ var ~ "." ~ term.toString()[1 .. $-1] ~ ")";
            else
                return "(λ"~ var ~ "." ~ term.toString() ~ ")";
        }
    }

    override Expression dup() const
    {
        return new AbstractExpression(var, term.dup);
    }
}

AbstractExpression abstraction(string arg, Expression term)
{
    return new AbstractExpression(arg, term);
}

unittest
{
    Expression lm = abstraction("x", variable("x"));
    assert(lm.toString() == "(λx.x)");
}


final class ApplyExpression : Expression
{
    Expression func;

    Expression input;

    this(Expression f, Expression i)
    {
        func = f;
        input = i;
    }

    override bool opEquals(Object obj) const
    {
        if (auto app = cast(ApplyExpression)obj) return app.func == func && app.input == input;
        return false;
    }

    override string toString() const
    {
        auto apps = appender!(ApplyExpression[]);

        import std.typecons : Rebindable;
        Rebindable!(typeof(this)) a = this;
        while (a)
        {
            apps ~= cast(ApplyExpression)a;
            a = cast(ApplyExpression)a.func;
        }

        return "(" ~ apps.data[$-1].func.toString() ~ " " ~
            apps.data.retro.map!(a => a.input.toString()).join(' ') ~ ")";
    }

    override Expression dup() const
    {
        return application(func.dup, input.dup);
    }
}

ApplyExpression application(Expression l, Expression r)
{
    return new ApplyExpression(l, r);
}

unittest
{
    Expression expr = abstraction("x", abstraction("y", application(variable("x"), variable("y"))));
    assert(expr.toString() == "(λx y.x y)", expr.toString());
}


RedBlackTree!string freeVariables(in Expression expr)
{
    // Phobos BUG: castSwitch accepts only mutable Object
    return (cast()expr).castSwitch!(
        (in VarExpression v)
        {
            string[1] ar = v.name;
            return redBlackTree(ar);
        },
        (in AbstractExpression lm)
        {
            auto vars = freeVariables(lm.term);
            vars.removeKey(lm.var);
            return vars;
        },
        (in ApplyExpression app)
        {
            auto vars = freeVariables(app.func);
            vars.insert(freeVariables(app.input)[]);
            return vars;
        });
}

unittest
{
    assert(abstraction("x", application(variable("x"), variable("y"))).freeVariables[]
            .equal(only("y")));
    assert(abstraction("x", application(variable("a"), variable("a"))).freeVariables[]
            .equal(only("a")));
    assert(abstraction("x", application(variable("a"), variable("b"))).freeVariables[]
            .equal(only("a", "b")));
}


struct SubstituteVariableNames
{
    import std.ascii : lowercase;
    string alphas = lowercase;
    auto postfixes = chain(only(""), sequence!("n").map!(to!string));

    enum empty = false;

@safe pure:

    string front()
    {
        assert(!alphas.empty);
        return chain(only(alphas.front), postfixes.front).text;
    }

    void popFront()
    {
        alphas.popFront();

        if (alphas.empty)
        {
            alphas = lowercase;
            postfixes.popFront();
        }
    }
}

unittest
{
    static assert(isInputRange!SubstituteVariableNames);
    assert(SubstituteVariableNames().drop(26).startsWith(only("a0", "b0")));
}


void replace(ref Expression lm, string from, in Expression to, RedBlackTree!string freevars = null)
{
    lm.castSwitch!(
        (VarExpression var)
        {
            if (var.name == from) lm = to.dup;
        },
        (AbstractExpression ab)
        {
            if (ab.var == from) return;

            assert(!freevars || freevars[].equal(to.freeVariables[]));
            if (!freevars) freevars = to.freeVariables;
            if (ab.var in freevars)
            {
                auto vars = ab.term.freeVariables;
                string newv = SubstituteVariableNames()
                    /+.cache+/.filter!(i => i !in vars && i !in freevars).front;
                ab.term.replace(ab.var, new VarExpression(newv));
                ab.var = newv;
            }

            ab.term.replace(from, to, freevars);
        },
        (ApplyExpression app)
        {
            app.func.replace(from, to, freevars);
            app.input.replace(from, to.dup, freevars);
        });
}

unittest
{
    Expression lm =
        application(
                abstraction("i",
                    abstraction("y", variable("x"))),
                variable("x"));
    lm.replace("x", variable("i"));
    assert(lm ==
            application(
                abstraction("a",
                    abstraction("y", variable("i"))),
                variable("i")));

    import lambdarepl.parser;
    lm = parseExpression(`\y z.x`);
    lm.replace("x", application(variable("y"), variable("z")));
    assert(lm == abstraction("a", abstraction("a", application(variable("y"), variable("z")))), lm.toString());
}

enum EvaluationStrategy
{
    normalOrder,
    callByName,
    callByValue
}

bool reduction(ref Expression lm, EvaluationStrategy es = EvaluationStrategy.normalOrder)
{
    return lm.castSwitch!(
            (VarExpression _) => false,
            (AbstractExpression lm)
            {
                final switch (es)
                {
                    case EvaluationStrategy.normalOrder:
                        return lm.term.reduction(es);
                    case EvaluationStrategy.callByName, EvaluationStrategy.callByValue:
                        return false;
                }
            },
            (ApplyExpression app)
            {
                if (auto l = cast(AbstractExpression)app.func)
                {
                    l.term.replace(l.var, app.input);
                    lm = l.term;
                    return true;
                }

                if (EvaluationStrategy.callByValue)
                    return app.input.reduction(es) || app.func.reduction(es);
                else
                    return app.func.reduction(es) || app.input.reduction(es);
            });
}

unittest
{
    Expression lm = application(abstraction("x", abstraction("y", variable("x"))), variable("a"));
    lm.reduction();
    assert(lm == abstraction("y", variable("a")));

    import lambdarepl.parser;

    lm = parseExpression(`(\z.z) ((\z.z) (\z.(\z.z) z))`);
    while (lm.reduction(EvaluationStrategy.callByName)) {}
    assert(lm == parseExpression(`\z.(\z.z) z`));
}

