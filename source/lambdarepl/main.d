module lambdarepl.main;


import lambdarepl.eval;

import std.range;
import std.stdio;
import std.string;


void main(string[] args)
{
    Evaluator evaluator;

    // TODO: command line arguments

    while (true)
    {
        write("λ> ");
        string line = readln().chomp;

        // TODO: support commands (like :load, :let)

        auto result = evaluator.eval(line);

        if (result.error !is null)
        {
            writeln(result.error);
            continue;
        }

        writeln("   ", result.expression);

        auto reductions = result.reductions;
        ulong steps = 200; // TODO: make configuratable
        while (!reductions.empty)
        {
            writeln("-> ", reductions.front.toString.stripParen);
            reductions.popFront();

            steps--;
            if (steps == 1 && !reductions.empty)
            {
                writeln("*** stopped reduction at 200 steps");
                break;
            }
        }
    }
}

string stripParen(string s) @safe pure nothrow @nogc
{
    if (s[0] == '(' && s[$-1] == ')') return s[1 .. $-1];
    else return s;
}
