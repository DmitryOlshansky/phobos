module std.mini.range;

import std.traits;

public:

/+
/**
Returns $(D true) if $(D R) is an input range. An input range must
define the primitives $(D empty), $(D popFront), and $(D front). The
following code should compile for any input range.

----
R r;              // can define a range object
if (r.empty) {}   // can test for empty
r.popFront();     // can invoke popFront()
auto h = r.front; // can get the front of the range of non-void type
----

The semantics of an input range (not checkable during compilation) are
assumed to be the following ($(D r) is an object of type $(D R)):

$(UL $(LI $(D r.empty) returns $(D false) iff there is more data
available in the range.)  $(LI $(D r.front) returns the current
element in the range. It may return by value or by reference. Calling
$(D r.front) is allowed only if calling $(D r.empty) has, or would
have, returned $(D false).) $(LI $(D r.popFront) advances to the next
element in the range. Calling $(D r.popFront) is allowed only if
calling $(D r.empty) has, or would have, returned $(D false).))
 */
template isInputRange(R)
{
    enum bool isInputRange = is(typeof(
    (inout int = 0)
    {
        R r = void;       // can define a range object
        if (r.empty) {}   // can test for empty
        r.popFront();     // can invoke popFront()
        auto h = r.front; // can get the front of the range
    }));
}

/**
Returns $(D true) if $(D R) is a forward range. A forward range is an
input range $(D r) that can save "checkpoints" by saving $(D r.save)
to another value of type $(D R). Notable examples of input ranges that
are $(I not) forward ranges are file/socket ranges; copying such a
range will not save the position in the stream, and they most likely
reuse an internal buffer as the entire stream does not sit in
memory. Subsequently, advancing either the original or the copy will
advance the stream, so the copies are not independent.

The following code should compile for any forward range.

----
static assert(isInputRange!R);
R r1;
static assert (is(typeof(r1.save) == R));
----

Saving a range is not duplicating it; in the example above, $(D r1)
and $(D r2) still refer to the same underlying data. They just
navigate that data independently.

The semantics of a forward range (not checkable during compilation)
are the same as for an input range, with the additional requirement
that backtracking must be possible by saving a copy of the range
object with $(D save) and using it later.
 */
template isForwardRange(R)
{
    enum bool isForwardRange = isInputRange!R && is(typeof(
    (inout int = 0)
    {
        R r1 = void;
        static assert (is(typeof(r1.save) == R));
    }));
}


/**
Returns $(D true) if $(D R) is a bidirectional range. A bidirectional
range is a forward range that also offers the primitives $(D back) and
$(D popBack). The following code should compile for any bidirectional
range.

----
R r;
static assert(isForwardRange!R);           // is forward range
r.popBack();                               // can invoke popBack
auto t = r.back;                           // can get the back of the range
auto w = r.front;
static assert(is(typeof(t) == typeof(w))); // same type for front and back
----

The semantics of a bidirectional range (not checkable during
compilation) are assumed to be the following ($(D r) is an object of
type $(D R)):

$(UL $(LI $(D r.back) returns (possibly a reference to) the last
element in the range. Calling $(D r.back) is allowed only if calling
$(D r.empty) has, or would have, returned $(D false).))
 */
template isBidirectionalRange(R)
{
    enum bool isBidirectionalRange = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        r.popBack();
        auto t = r.back;
        auto w = r.front;
        static assert(is(typeof(t) == typeof(w)));
    }));
}


/**
Returns $(D true) if $(D R) is a random-access range. A random-access
range is a bidirectional range that also offers the primitive $(D
opIndex), OR an infinite forward range that offers $(D opIndex). In
either case, the range must either offer $(D length) or be
infinite. The following code should compile for any random-access
range.

----
// range is finite and bidirectional or infinite and forward.
static assert(isBidirectionalRange!R ||
              isForwardRange!R && isInfinite!R);

R r = void;
auto e = r[1]; // can index
static assert(is(typeof(e) == typeof(r.front))); // same type for indexed and front
static assert(!isNarrowString!R); // narrow strings cannot be indexed as ranges
static assert(hasLength!R || isInfinite!R); // must have length or be infinite

// $ must work as it does with arrays if opIndex works with $
static if(is(typeof(r[$])))
{
    static assert(is(typeof(r.front) == typeof(r[$])));

    // $ - 1 doesn't make sense with infinite ranges but needs to work
    // with finite ones.
    static if(!isInfinite!R)
        static assert(is(typeof(r.front) == typeof(r[$ - 1])));
}
----

The semantics of a random-access range (not checkable during
compilation) are assumed to be the following ($(D r) is an object of
type $(D R)): $(UL $(LI $(D r.opIndex(n)) returns a reference to the
$(D n)th element in the range.))

Although $(D char[]) and $(D wchar[]) (as well as their qualified
versions including $(D string) and $(D wstring)) are arrays, $(D
isRandomAccessRange) yields $(D false) for them because they use
variable-length encodings (UTF-8 and UTF-16 respectively). These types
are bidirectional ranges only.
 */
template isRandomAccessRange(R)
{
    enum bool isRandomAccessRange = is(typeof(
    (inout int = 0)
    {
        static assert(isBidirectionalRange!R ||
                      isForwardRange!R && isInfinite!R);
        R r = void;
        auto e = r[1];
        static assert(is(typeof(e) == typeof(r.front)));
        static assert(!isNarrowString!R);
        static assert(hasLength!R || isInfinite!R);

        static if(is(typeof(r[$])))
        {
            static assert(is(typeof(r.front) == typeof(r[$])));

            static if(!isInfinite!R)
                static assert(is(typeof(r.front) == typeof(r[$ - 1])));
        }
    }));
}

/**
Returns $(D true) iff $(D R) supports the $(D moveFront) primitive,
as well as $(D moveBack) and $(D moveAt) if it's a bidirectional or
random access range.  These may be explicitly implemented, or may work
via the default behavior of the module level functions $(D moveFront)
and friends.
 */
template hasMobileElements(R)
{
    enum bool hasMobileElements = is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveFront(r);
    }))
    && (!isBidirectionalRange!R || is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveBack(r);
    })))
    && (!isRandomAccessRange!R || is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveAt(r, 0);
    })));
}

/**
The element type of $(D R). $(D R) does not have to be a range. The
element type is determined as the type yielded by $(D r.front) for an
object $(D r) of type $(D R). For example, $(D ElementType!(T[])) is
$(D T) if $(D T[]) isn't a narrow string; if it is, the element type is
$(D dchar). If $(D R) doesn't have $(D front), $(D ElementType!R) is
$(D void).
 */
template ElementType(R)
{
    static if (is(typeof((inout int = 0){ R r = void; return r.front; }()) T))
        alias T ElementType;
    else
        alias void ElementType;
}

/**
The encoding element type of $(D R). For narrow strings ($(D char[]),
$(D wchar[]) and their qualified variants including $(D string) and
$(D wstring)), $(D ElementEncodingType) is the character type of the
string. For all other types, $(D ElementEncodingType) is the same as
$(D ElementType).
 */
template ElementEncodingType(R)
{
    static if (isNarrowString!R)
        alias typeof((inout int = 0){ R r = void; return r[0]; }()) ElementEncodingType;
    else
        alias ElementType!R ElementEncodingType;
}

/**
Returns $(D true) if $(D R) is a forward range and has swappable
elements. The following code should compile for any range
with swappable elements.

----
R r;
static assert(isForwardRange!(R));   // range is forward
swap(r.front, r.front);              // can swap elements of the range
----
 */
template hasSwappableElements(R)
{
    enum bool hasSwappableElements = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        swap(r.front, r.front);             // can swap elements of the range
    }));
}


/**
Returns $(D true) if $(D R) is a forward range and has mutable
elements. The following code should compile for any range
with assignable elements.

----
R r;
static assert(isForwardRange!R);  // range is forward
auto e = r.front;
r.front = e;                      // can assign elements of the range
----
 */
template hasAssignableElements(R)
{
    enum bool hasAssignableElements = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        static assert(isForwardRange!(R)); // range is forward
        auto e = r.front;
        r.front = e;                       // can assign elements of the range
    }));
}

/**
Tests whether $(D R) has lvalue elements.  These are defined as elements that
can be passed by reference and have their address taken.
*/
template hasLvalueElements(R)
{
    enum bool hasLvalueElements = is(typeof(
    (inout int = 0)
    {
        void checkRef(ref ElementType!R stuff) {}
        R r = void;
        static assert(is(typeof(checkRef(r.front))));
    }));
}

/**
Returns $(D true) if $(D R) has a $(D length) member that returns an
integral type. $(D R) does not have to be a range. Note that $(D
length) is an optional primitive as no range must implement it. Some
ranges do not store their length explicitly, some cannot compute it
without actually exhausting the range (e.g. socket streams), and some
other ranges may be infinite.

Although narrow string types ($(D char[]), $(D wchar[]), and their
qualified derivatives) do define a $(D length) property, $(D
hasLength) yields $(D false) for them. This is because a narrow
string's length does not reflect the number of characters, but instead
the number of encoding units, and as such is not useful with
range-oriented algorithms.
 */
template hasLength(R)
{
    enum bool hasLength = !isNarrowString!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        static assert(is(typeof(r.length) : ulong));
    }));
}

/**
Returns $(D true) if $(D R) is an infinite input range. An
infinite input range is an input range that has a statically-defined
enumerated member called $(D empty) that is always $(D false),
for example:

----
struct MyInfiniteRange
{
    enum bool empty = false;
    ...
}
----
 */

template isInfinite(R)
{
    static if (isInputRange!R && __traits(compiles, { enum e = R.empty; }))
        enum bool isInfinite = !R.empty;
    else
        enum bool isInfinite = false;
}

/**
Returns $(D true) if $(D R) offers a slicing operator with integral boundaries
that returns a forward range type.

For finite ranges, the result of $(D opSlice) must be of the same type as the
original range type. If the range defines $(D opDollar), then it must support
subtraction.

For infinite ranges, when $(I not) using $(D opDollar), the result of
$(D opSlice) must be the result of $(LREF take) or $(LREF takeExactly) on the
original range (they both return the same type for infinite ranges). However,
when using $(D opDollar), the result of $(D opSlice) must be that of the
original range type.

The following code must compile for $(D hasSlicing) to be $(D true):

----
R r = void;

static if(isInfinite!R)
    typeof(take(r, 1)) s = r[1 .. 2];
else
{
    static assert(is(typeof(r[1 .. 2]) == R));
    R s = r[1 .. 2];
}

s = r[1 .. 2];

static if(is(typeof(r[0 .. $])))
{
    static assert(is(typeof(r[0 .. $]) == R));
    R t = r[0 .. $];
    t = r[0 .. $];

    static if(!isInfinite!R)
    {
        static assert(is(typeof(r[0 .. $ - 1]) == R));
        R u = r[0 .. $ - 1];
        u = r[0 .. $ - 1];
    }
}

static assert(isForwardRange!(typeof(r[1 .. 2])));
static assert(hasLength!(typeof(r[1 .. 2])));
----
 */
template hasSlicing(R)
{
    enum bool hasSlicing = isForwardRange!R && !isNarrowString!R && is(typeof(
    (inout int = 0)
    {
        R r = void;

        static if(isInfinite!R)
            typeof(take(r, 1)) s = r[1 .. 2];
        else
        {
            static assert(is(typeof(r[1 .. 2]) == R));
            R s = r[1 .. 2];
        }

        s = r[1 .. 2];

        static if(is(typeof(r[0 .. $])))
        {
            static assert(is(typeof(r[0 .. $]) == R));
            R t = r[0 .. $];
            t = r[0 .. $];

            static if(!isInfinite!R)
            {
                static assert(is(typeof(r[0 .. $ - 1]) == R));
                R u = r[0 .. $ - 1];
                u = r[0 .. $ - 1];
            }
        }

        static assert(isForwardRange!(typeof(r[1 .. 2])));
        static assert(hasLength!(typeof(r[1 .. 2])));
    }));
}
+/