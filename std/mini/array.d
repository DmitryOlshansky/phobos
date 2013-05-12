module std.mini.array;


// overlap
/*
NOTE: Undocumented for now, overlap does not yet work with ctfe.
Returns the overlapping portion, if any, of two arrays. Unlike $(D
equal), $(D overlap) only compares the pointers in the ranges, not the
values referred by them. If $(D r1) and $(D r2) have an overlapping
slice, returns that slice. Otherwise, returns the null slice.

Example:
$(D_RUN_CODE
$(ARGS
----
int[] a = [ 10, 11, 12, 13, 14 ];
int[] b = a[1 .. 3];
assert(overlap(a, b) == [ 11, 12 ]);
b = b.dup;
// overlap disappears even though the content is the same
assert(overlap(a, b).empty);
----
), $(ARGS), $(ARGS), $(ARGS import std.array;))
*/
public inout(T)[] overlap(T)(inout(T)[] r1, inout(T)[] r2) @trusted pure nothrow
{
    alias inout(T) U;
    static U* max(U* a, U* b) nothrow { return a > b ? a : b; }
    static U* min(U* a, U* b) nothrow { return a < b ? a : b; }

    auto b = max(r1.ptr, r2.ptr);
    auto e = min(r1.ptr + r1.length, r2.ptr + r2.length);
    return b < e ? b[0 .. e - b] : null;
}