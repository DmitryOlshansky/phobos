module std.mini.algorithm;

import std.traits;
import core.stdc.string, std.exception;

public:

// MinType
template MinType(T...)
{
    static assert(T.length >= 2);
    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
            alias CommonType!(T[0 .. 2]) MinType;
        else
        {
            enum hasMostNegative = is(typeof(mostNegative!(T[0]))) &&
                                   is(typeof(mostNegative!(T[1])));
            static if (hasMostNegative && mostNegative!(T[1]) < mostNegative!(T[0]))
                alias T[1] MinType;
            else static if (hasMostNegative && mostNegative!(T[1]) > mostNegative!(T[0]))
                alias T[0] MinType;
            else static if (T[1].max < T[0].max)
                alias T[1] MinType;
            else
                alias T[0] MinType;
        }
    }
    else
    {
        alias MinType!(MinType!(T[0 .. 2]), T[2 .. $]) MinType;
    }
}

// min
/**
Returns the minimum of the passed-in values. The type of the result is
computed by using $(XREF traits, CommonType).
*/
MinType!(T1, T2, T) min(T1, T2, T...)(T1 a, T2 b, T xs)
    if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 && isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
                immutable chooseB = b < a && a > 0;
            else
                immutable chooseB = b < a || b < 0;
        }
        else
            immutable chooseB = b < a;
        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return min(min(a, b), xs);
    }
}


// MaxType
template MaxType(T...)
{
    static assert(T.length >= 2);
    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
            alias CommonType!(T[0 .. 2]) MaxType;
        else static if (T[1].max > T[0].max)
            alias T[1] MaxType;
        else
            alias T[0] MaxType;
    }
    else
    {
        alias MaxType!(MaxType!(T[0], T[1]), T[2 .. $]) MaxType;
    }
}

// max
/**
Returns the maximum of the passed-in values. The type of the result is
computed by using $(XREF traits, CommonType).

Example:
----
int a = 5;
short b = 6;
double c = 2;
auto d = max(a, b);
assert(is(typeof(d) == int));
assert(d == 6);
auto e = min(a, b, c);
assert(is(typeof(e) == double));
assert(e == 2);
----
*/
MaxType!(T1, T2, T) max(T1, T2, T...)(T1 a, T2 b, T xs)
    if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 && isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
                immutable chooseB = b > a || a < 0;
            else
                immutable chooseB = b > a && b > 0;
        }
        else
            immutable chooseB = b > a;
        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return max(max(a, b), xs);
    }
}


// move
/**
Moves $(D source) into $(D target) via a destructive
copy. Specifically: $(UL $(LI If $(D hasAliasing!T) is true (see
$(XREF traits, hasAliasing)), then the representation of $(D source)
is bitwise copied into $(D target) and then $(D source = T.init) is
evaluated.)  $(LI Otherwise, $(D target = source) is evaluated.)) See
also $(XREF exception, pointsTo).

Preconditions:
$(D &source == &target || !pointsTo(source, source))
*/
void move(T)(ref T source, ref T target)
{
    assert(!pointsTo(source, source));
    static if (is(T == struct))
    {
        if (&source == &target) return;
        // Most complicated case. Destroy whatever target had in it
        // and bitblast source over it
        static if (hasElaborateDestructor!T) typeid(T).destroy(&target);

        memcpy(&target, &source, T.sizeof);

        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
        static if (hasElaborateDestructor!T || hasElaborateCopyConstructor!T)
        {
            static T empty;
            static if (T.tupleof.length > 0 &&
                       T.tupleof[$-1].stringof.length > 4 
                       && T.tupleof[$-1].stringof[$-4..$] == "this")
            {
                // If T is nested struct, keep original context pointer
                memcpy(&source, &empty, T.sizeof - (void*).sizeof);
            }
            else
            {
                memcpy(&source, &empty, T.sizeof);
            }
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        target = source;
        // static if (is(typeof(source = null)))
        // {
        //     // Nullify the source to help the garbage collector
        //     source = null;
        // }
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    Object obj1 = new Object;
    Object obj2 = obj1;
    Object obj3;
    move(obj2, obj3);
    assert(obj3 is obj1);

    static struct S1 { int a = 1, b = 2; }
    S1 s11 = { 10, 11 };
    S1 s12;
    move(s11, s12);
    assert(s11.a == 10 && s11.b == 11 && s12.a == 10 && s12.b == 11);

    static struct S2 { int a = 1; int * b; }
    S2 s21 = { 10, null };
    s21.b = new int;
    S2 s22;
    move(s21, s22);
    assert(s21 == s22);

    // Issue 5661 test(1)
    static struct S3
    {
        static struct X { int n = 0; ~this(){n = 0;} }
        X x;
    }
    static assert(hasElaborateDestructor!S3);
    S3 s31, s32;
    s31.x.n = 1;
    move(s31, s32);
    assert(s31.x.n == 0);
    assert(s32.x.n == 1);

    // Issue 5661 test(2)
    static struct S4
    {
        static struct X { int n = 0; this(this){n = 0;} }
        X x;
    }
    static assert(hasElaborateCopyConstructor!S4);
    S4 s41, s42;
    s41.x.n = 1;
    move(s41, s42);
    assert(s41.x.n == 0);
    assert(s42.x.n == 1);
}

/// Ditto
T move(T)(ref T source)
{
    // Can avoid to check aliasing.

    T result = void;
    static if (is(T == struct))
    {
        // Can avoid destructing result.

        memcpy(&result, &source, T.sizeof);

        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
        static if (hasElaborateDestructor!T || hasElaborateCopyConstructor!T)
        {
            static T empty;
            static if (T.tupleof.length > 0 &&
                       T.tupleof[$-1].stringof.length > 4 
                       && T.tupleof[$-1].stringof[$-4..$] == "this")
            {
                // If T is nested struct, keep original context pointer
                memcpy(&source, &empty, T.sizeof - (void*).sizeof);
            }
            else
            {
                memcpy(&source, &empty, T.sizeof);
            }
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        result = source;
    }
    return result;
}