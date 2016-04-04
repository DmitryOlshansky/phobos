//Written in the D programming language
/*
    Implementation of Thompson NFA std.regex engine.
    Key point is evaluation of all possible threads (state) at each step
    in a breadth-first manner, thereby geting some nice properties:
        - looking at each character only once
        - merging of equivalent threads, that gives matching process linear time complexity
*/
module std.regex.internal.thompson;

package(std.regex):

import std.regex.internal.ir;
import std.range;

//State of VM thread
struct Thread(DataIndex)
{
    Thread* next;    //intrusive linked list
    uint pc;
    uint counter;    //loop counter
    uint uopCounter; //counts micro operations inside one macro instruction (e.g. BackRef)
    Group!DataIndex[1] matches;
}

//head-tail singly-linked list
struct ThreadList(DataIndex)
{
    Thread!DataIndex* tip = null, toe = null;
    //add new thread to the start of list
    void insertFront(Thread!DataIndex* t)
    {
        if(tip)
        {
            t.next = tip;
            tip = t;
        }
        else
        {
            t.next = null;
            tip = toe = t;
        }
    }
    //add new thread to the end of list
    void insertBack(Thread!DataIndex* t)
    {
        if(toe)
        {
            toe.next = t;
            toe = t;
        }
        else
            tip = toe = t;
        toe.next = null;
    }
    //move head element out of list
    Thread!DataIndex* fetch()
    {
        auto t = tip;
        if(tip == toe)
            tip = toe = null;
        else
            tip = tip.next;
        return t;
    }
    //non-destructive iteration of ThreadList
    struct ThreadRange
    {
        const(Thread!DataIndex)* ct;
        this(ThreadList tlist){ ct = tlist.tip; }
        @property bool empty(){ return ct is null; }
        @property const(Thread!DataIndex)* front(){ return ct; }
        @property popFront()
        {
            assert(ct);
            ct = ct.next;
        }
    }
    @property bool empty()
    {
        return tip == null;
    }
    ThreadRange opSlice()
    {
        return ThreadRange(this);
    }
}

template ThompsonOps(E, S, bool withInput:true)
{
@trusted:
    static int op(IR code:IR.End)(E* e, S* state)
    {
        import std.stdio;
        writeln("End!");
        with(e) with(state)
        {
            finish(t, matches);
            //fix endpoint of the whole match
            matches[0].end = e.index;
            recycle(t);
            //cut off low priority threads
            recycle(clist);
            recycle(worklist);
            jitTarget = null;
            debug(std_regex_matcher) writeln("Finished thread ", matches);
            return 0; // no more state to eval
        }

    }

    static int op(IR code:IR.Wordboundary)(E* e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            //at start & end of input
            if(atStart && wordMatcher[front])
            {
                t.pc += IRL!(IR.Wordboundary);
                return -1;
            }
            else if(atEnd && s.loopBack(index).nextChar(back, bi)
                    && wordMatcher[back])
            {
                t.pc += IRL!(IR.Wordboundary);
                return -1;
            }
            else if(s.loopBack(index).nextChar(back, bi))
            {
                bool af = wordMatcher[front];
                bool ab = wordMatcher[back];
                if(af ^ ab)
                {
                    t.pc += IRL!(IR.Wordboundary);
                    return syncState!(code, true)(e);
                }
            }
            return popState!(code, true)(e);
        }
    }

    static int op(IR code:IR.Notwordboundary)(E* e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            //at start & end of input
            if(atStart && wordMatcher[front])
            {
                return popState!(code, true)(e);
            }
            else if(atEnd && s.loopBack(index).nextChar(back, bi)
                    && wordMatcher[back])
            {
                return popState!(code, true)(e);
            }
            else if(s.loopBack(index).nextChar(back, bi))
            {
                bool af = wordMatcher[front];
                bool ab = wordMatcher[back]  != 0;
                if(af ^ ab)
                {
                    return popState!(code, true)(e);
                }
            }
            t.pc += IRL!(IR.Notwordboundary);
            return -1;
        }
    }

    static int op(IR code:IR.Bol)(E* e, S* state)
    {
        with(e) with(state)
        {
            dchar back;
            DataIndex bi;
            if(atStart
                ||( (re.flags & RegexOption.multiline)
                && s.loopBack(index).nextChar(back,bi)
                && startOfLine(back, front == '\n')))
            {
                t.pc += IRL!(IR.Bol);
                return -1;
            }
            else
            {
                return popState!(code, true)(e);
            }
        }
    }

    static int op(IR code:IR.Eol)(E* e, S* state)
    {
        with(e) with(state)
        {
            debug(std_regex_matcher) writefln("EOL (front 0x%x) %s",  front, s[index..s.lastIndex]);
            dchar back;
            DataIndex bi;
            //no matching inside \r\n
            if(atEnd || ((re.flags & RegexOption.multiline)
                && endOfLine(front, s.loopBack(index).nextChar(back, bi)
                    && back == '\r')))
            {
                t.pc += IRL!(IR.Eol);
                return -1;
            }
            else
            {
                return popState!(code, true)(e);
            }
        }
    }

    static int op(IR code:IR.InfiniteStart)(E* e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteStart);
        return op!(IR.InfiniteEnd)(e,state);
    }

    static int op(IR code:IR.InfiniteBloomStart)(E* e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteBloomStart);
        return op!(IR.InfiniteBloomEnd)(e,state);
    }

    static int op(IR code:IR.InfiniteQStart)(E* e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.InfiniteQStart);
        return op!(IR.InfiniteQEnd)(e,state);
    }

    static int op(IR code:IR.RepeatStart)(E* e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.RepeatStart);
        return op!(IR.RepeatEnd)(e,state);
    }

    static int op(IR code:IR.RepeatQStart)(E* e, S* state)
    {
        with(e) with(state)
            t.pc += re.ir[t.pc].data + IRL!(IR.RepeatQStart);
        return op!(IR.RepeatQEnd)(e,state);
    }

    static int op(IR code)(E* e, S* state)
        if(code == IR.RepeatEnd || code == IR.RepeatQEnd)
    {
        with(e) with(state)
        {
            //len, step, min, max
                uint len = re.ir[t.pc].data;
                uint step =  re.ir[t.pc+2].raw;
                uint min = re.ir[t.pc+3].raw;
                if(t.counter < min)
                {
                    t.counter += step;
                    t.pc -= len;
                    return syncState!(code, true)(e);
                }
                if(merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
                {
                    debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                    t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                    merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
                }
                else
                {
                    debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                    t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                    return popState!(code, true)(e);
                }
                uint max = re.ir[t.pc+4].raw;
                if(t.counter < max)
                {
                    if(re.ir[t.pc].code == IR.RepeatEnd)
                    {
                        //queue out-of-loop thread
                        worklist.insertFront(fork(t, t.pc + IRL!(IR.RepeatEnd),  t.counter % step));
                        t.counter += step;
                        t.pc -= len;
                    }
                    else
                    {
                        //queue into-loop thread
                        worklist.insertFront(fork(t, t.pc - len,  t.counter + step));
                        t.counter %= step;
                        t.pc += IRL!(IR.RepeatEnd);
                    }
                }
                else
                {
                    t.counter %= step;
                    t.pc += IRL!(IR.RepeatEnd);
                }
                return syncState!(code, true)(e);
        }
    }

    static int op(IR code)(E* e, S* state)
        if(code == IR.InfiniteEnd || code == IR.InfiniteQEnd)
    {
        import std.stdio;
        writeln("InfiniteEnd");
        with(e) with(state)
        {
            if(merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                return popState!(code, true)(e);
            }
            uint len = re.ir[t.pc].data;
            uint pc1, pc2; //branches to take in priority order
            if(re.ir[t.pc].code == IR.InfiniteEnd)
            {
                pc1 = t.pc - len;
                pc2 = t.pc + IRL!(IR.InfiniteEnd);
            }
            else
            {
                pc1 = t.pc + IRL!(IR.InfiniteEnd);
                pc2 = t.pc - len;
            }
            worklist.insertFront(fork(t, pc2, t.counter));
            t.pc = pc1;
            return syncState!(code, true)(e);
        }
    }

    static int op(IR code)(E* e, S* state)
        if(code == IR.InfiniteBloomEnd)
    {
        with(e) with(state)
        {
            if(merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, index, genCounter, merge[re.ir[t.pc + 1].raw+t.counter] );
                return popState!(code, true)(e);
            }
            uint len = re.ir[t.pc].data;
            uint pc1, pc2; //branches to take in priority order
            pc1 = t.pc - len;
            pc2 = t.pc + IRL!(IR.InfiniteBloomEnd);
            uint filterIndex = re.ir[t.pc + 2].raw;
            if (re.filters[filterIndex][front])
                worklist.insertFront(fork(t, pc2, t.counter));
            t.pc = pc1;
            return syncState!(code, true)(e);
        }
    }

    static int op(IR code:IR.OrEnd)(E* e, S* state)
    {
        with(e) with(state)
        {
            if(merge[re.ir[t.pc + 1].raw+t.counter] < genCounter)
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) passed there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, s[index .. s.lastIndex], genCounter, merge[re.ir[t.pc + 1].raw + t.counter] );
                merge[re.ir[t.pc + 1].raw+t.counter] = genCounter;
                t.pc += IRL!(IR.OrEnd);
            }
            else
            {
                debug(std_regex_matcher) writefln("A thread(pc=%s) got merged there : %s ; GenCounter=%s mergetab=%s",
                                t.pc, s[index .. s.lastIndex], genCounter, merge[re.ir[t.pc + 1].raw + t.counter] );
                return popState!(code, true)(e);
            }
            return -1;
        }
    }

    static int op(IR code:IR.OrStart)(E* e, S* state)
    {
        with(e) with(state)
        {
            t.pc += IRL!(IR.OrStart);
            return op!(IR.Option)(e,state);
        }
    }

    static int op(IR code:IR.Option)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint next = t.pc + re.ir[t.pc].data + IRL!(IR.Option);
            //queue next Option
            if(re.ir[next].code == IR.Option)
            {
                worklist.insertFront(fork(t, next, t.counter));
            }
            t.pc += IRL!(IR.Option);
            return -1;
        }
    }

    static int op(IR code:IR.GotoEndOr)(E* e, S* state)
    {
        with(e) with(state)
        {
            t.pc = t.pc + re.ir[t.pc].data + IRL!(IR.GotoEndOr);
            syncState!(code, true)(e);
            return op!(IR.OrEnd)(e, state);
        }
    }

    static int op(IR code:IR.GroupStart)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            t.matches.ptr[n].begin = index;
            t.pc += IRL!(IR.GroupStart);
            return -1;
        }
    }
    static int op(IR code:IR.GroupEnd)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            t.matches.ptr[n].end = index;
            t.pc += IRL!(IR.GroupEnd);
            return -1;
        }
    }

    static int op(IR code:IR.Backref)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            Group!DataIndex* source = re.ir[t.pc].localRef ? t.matches.ptr : backrefed.ptr;
            assert(source);
            if(source[n].begin == source[n].end)//zero-width Backref!
            {
                t.pc += IRL!(IR.Backref);
                return -1;
            }
            else
            {
                size_t idx = source[n].begin + t.uopCounter;
                size_t end = source[n].end;
                if(s[idx..end].front == front)
                {
                    import std.utf : stride;

                    t.uopCounter += stride(s[idx..end], 0);
                    if(t.uopCounter + source[n].begin == source[n].end)
                    {//last codepoint
                        t.pc += IRL!(IR.Backref);
                        t.uopCounter = 0;
                    }
                    nlist.insertBack(t);
                }
                else
                    recycle(t);
                return switchState!(code, true)(e);
            }
        }
    }


    static int op(IR code)(E* e, S* state)
        if(code == IR.LookbehindStart || code == IR.NeglookbehindStart)
    {
        with(e) with(state)
        {
            uint len = re.ir[t.pc].data;
            uint ms = re.ir[t.pc + 1].raw, me = re.ir[t.pc + 2].raw;
            uint end = t.pc + len + IRL!(IR.LookbehindEnd) + IRL!(IR.LookbehindStart);
            bool positive = re.ir[t.pc].code == IR.LookbehindStart;
            static if(Stream.isLoopback)
                auto matcher = fwdMatcher(t.pc, end, subCounters.get(t.pc, 0));
            else
                auto matcher = bwdMatcher(t.pc, end, subCounters.get(t.pc, 0));
            matcher.re.ngroup = me - ms;
            matcher.backrefed = backrefed.empty ? t.matches : backrefed;
            //backMatch
            auto mRes = matcher.matchOneShot(t.matches.ptr[ms .. me], IRL!(IR.LookbehindStart));
            freelist = matcher.freelist;
            subCounters[t.pc] = matcher.genCounter;
            if((mRes == MatchResult.Match) ^ positive)
            {
                return popState!(code, true)(e);
            }
            t.pc = end;
            return syncState!(code, true)(e);
        }
    }

    static int op(IR code)(E* e, S* state)
        if(code == IR.LookaheadStart || code == IR.NeglookaheadStart)
    {
        with(e) with(state)
        {
            auto save = index;
            uint len = re.ir[t.pc].data;
            uint ms = re.ir[t.pc+1].raw, me = re.ir[t.pc+2].raw;
            uint end = t.pc+len+IRL!(IR.LookaheadEnd)+IRL!(IR.LookaheadStart);
            bool positive = re.ir[t.pc].code == IR.LookaheadStart;
            static if(Stream.isLoopback)
                auto matcher = bwdMatcher(t.pc, end, subCounters.get(t.pc, 0));
            else
                auto matcher = fwdMatcher(t.pc, end, subCounters.get(t.pc, 0));
            matcher.re.ngroup = me - ms;
            matcher.backrefed = backrefed.empty ? t.matches : backrefed;
            auto mRes = matcher.matchOneShot(t.matches.ptr[ms .. me], IRL!(IR.LookaheadStart));
            freelist = matcher.freelist;
            subCounters[t.pc] = matcher.genCounter;
            s.reset(index);
            next();
            if((mRes == MatchResult.Match) ^ positive)
            {
                return popState!(code, true)(e);
            }
            t.pc = end;
            return syncState!(code, true)(e);
        }
    }

    static int op(IR code)(E* e, S* state)
        if(code == IR.LookaheadEnd || code == IR.NeglookaheadEnd ||
            code == IR.LookbehindEnd || code == IR.NeglookbehindEnd)
    {
        with(e) with(state)
        {
            finish(t, matches.ptr[0 .. re.ngroup]);
            recycle(t);
            //cut off low priority threads
            recycle(clist);
            recycle(worklist);
            return false; // no more state
        }
    }

    static int op(IR code:IR.Nop)(E* e, S* state)
    {
        with(state) 
        {
            t.pc += IRL!(IR.Nop);
            return -1;
        }
    }

    static int op(IR code:IR.OrChar)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint len = re.ir[t.pc].sequence;
            uint end = t.pc + len;
            static assert(IRL!(IR.OrChar) == 1);
            for(; t.pc < end; t.pc++)
                if(re.ir[t.pc].data == front)
                    break;
            if(t.pc != end)
            {
                t.pc = end;
                nlist.insertBack(t);
            }
            else
                recycle(t);
            return switchState!(code, true)(e);
        }
    }

    static int op(IR code:IR.Char)(E* e, S* state)
    {
        import std.stdio;
        writeln("Char!");
        with(e) with(state)
        {
            if(front == re.ir[t.pc].data)
            {
                t.pc += IRL!(IR.Char);
                nlist.insertBack(t);
            }
            else
                recycle(t);
            return switchState!(code, true)(e);
        }
    }

    static int op(IR code:IR.Any)(E* e, S* state)
    {
        with(e) with(state)
        {
            t.pc += IRL!(IR.Any);
            if(!(re.flags & RegexOption.singleline)
                  && (front == '\r' || front == '\n'))
              recycle(t);
            else
              nlist.insertBack(t);
            return switchState!(code, true)(e);
        }
    }

    static int op(IR code:IR.CodepointSet)(E* e, S* state)
    {
        with(e) with(state)
        {
            if(re.charsets[re.ir[t.pc].data].scanFor(front))
            {
                t.pc += IRL!(IR.CodepointSet);
                nlist.insertBack(t);
            }
            else
            {
                recycle(t);
            }
            return switchState!(code, true)(e);
        }
    }

    static int op(IR code:IR.Trie)(E* e, S* state)
    {
        with(e) with(state)
        {
            if(re.matchers[re.ir[t.pc].data][front])
            {
                t.pc += IRL!(IR.Trie);
                nlist.insertBack(t);
            }
            else
            {
                recycle(t);
            }
            return switchState!(code, true)(e);
        }
    }

}

template ThompsonOps(E,S, bool withInput:false)
{
@trusted:
    // can't match these without input
    static int op(IR code)(E* e, S* state)
        if (code == IR.Char || code == IR.OrChar || code == IR.CodepointSet
        || code == IR.Trie || code == IR.Char || code == IR.Any)
    {
        return state.popState!(code,false)(e);
    }

    // special case of zero-width backref
    static int op(IR code:IR.Backref)(E* e, S* state)
    {
        with(e) with(state)
        {
            uint n = re.ir[t.pc].data;
            Group!DataIndex* source = re.ir[t.pc].localRef ? t.matches.ptr : backrefed.ptr;
            assert(source);
            if(source[n].begin == source[n].end)//zero-width Backref!
            {
                t.pc += IRL!(IR.Backref);
                return -1;
            }
            else
                return popState!(code,false)(e);
        }
    }

    // forward all control flow to normal versions
    static int op(IR code)(E* e, S* state)
        if (code != IR.Char && code != IR.OrChar && code != IR.CodepointSet
        && code != IR.Trie && code != IR.Char && code != IR.Any && code != IR.Backref)
    {
        return ThompsonOps!(E,S,true).op!code(e,state);
    }
}

/+
   Thomspon matcher does all matching in lockstep,
   never looking at the same char twice
+/
@trusted struct ThompsonMatcher(Char, StreamType = Input!Char)
    if(is(Char : dchar))
{
    alias DataIndex = Stream.DataIndex;
    alias Stream = StreamType;
    alias OpFunc = int function(ThompsonMatcher*, State*);
    alias BackMatcher = ThompsonMatcher!(Char, BackLooper!(Stream));
    alias OpBackFunc = int function(BackMatcher*, BackMatcher.State*);
    Thread!DataIndex* freelist;
    ThreadList!DataIndex clist, nlist;
    DataIndex[] merge;
    Group!DataIndex[] backrefed;
    Regex!Char re;                  //regex program
    Stream s;
    dchar front;
    DataIndex index;
    DataIndex genCounter;           //merge trace counter, goes up on every dchar
    size_t[size_t] subCounters;     //a table of gen counter per sub-engine: PC -> counter
    OpFunc[] opCacheTrue;           // pointers to Op!(IR.xyz) for each bytecode
    OpFunc[] opCacheFalse;          // ditto
    OpBackFunc[] opCacheBackTrue;   // ditto
    OpBackFunc[] opCacheBackFalse;  // ditto
    Codegen jitCacheTrue;
    Codegen jitCacheFalse;
    size_t[] ir2jit;                // IR PC --> JIT address
    size_t threadSize;
    bool matched;
    bool exhausted;

    static struct State
    {
        Thread!DataIndex* t;
        ThreadList!DataIndex worklist;
        Group!DataIndex[] matches;
        void* jitTarget;

        // template to make multiple copies of function per each opcode
        int popState(IR code, bool withInput)(ThompsonMatcher* e)
        {
            with(e)
            {
                recycle(t);
                return switchState!(code, withInput)(e);
            }
        }

        int switchState(IR code, bool withInput)(ThompsonMatcher* e)
        {
            t = worklist.fetch();
            if(t != null)
            {
                return syncState!(code, withInput)(e);
            }
            else
            {
                jitTarget = null;
                return 0;
            }
        }

        int syncState(IR code, bool withInput)(ThompsonMatcher* e)
        {
            static if(withInput)
            {
                jitTarget = e.jitCacheTrue.base + e.ir2jit[t.pc];
            }
            else
            {
                jitTarget = e.jitCacheFalse.base + e.ir2jit[t.pc];
            }
            import std.stdio;
            writefln("JIT = 0x%x", jitTarget);
            return 0;
                
        }

    }

    static if(__traits(hasMember,Stream, "search"))
    {
        enum kicked = true;
    }
    else
        enum kicked = false;

    static size_t getThreadSize(const ref Regex!Char re)
    {
        return re.ngroup
            ? (Thread!DataIndex).sizeof + (re.ngroup-1)*(Group!DataIndex).sizeof
            : (Thread!DataIndex).sizeof - (Group!DataIndex).sizeof;
    }

    static size_t initialMemory(const ref Regex!Char re)
    {
        return getThreadSize(re)*re.threadCount + re.hotspotTableSize*size_t.sizeof
            +4*OpFunc.sizeof*re.ir.length;
    }

    //true if it's start of input
    @property bool atStart(){   return index == 0; }

    //true if it's end of input
    @property bool atEnd(){  return index == s.lastIndex && s.atEnd; }

    bool next()
    {
        if(!s.nextChar(front, index))
        {
            index =  s.lastIndex;
            return false;
        }
        return true;
    }

    static if(kicked)
    {
        bool search()
        {

            if(!s.search(re.kickstart, front, index))
            {
                index = s.lastIndex;
                return false;
            }
            return true;
        }
    }

    void initExternalMemory(void[] memory)
    {
        threadSize = getThreadSize(re);
        prepareFreeList(re.threadCount, memory);
        if(re.hotspotTableSize)
        {
            merge = arrayInChunk!(DataIndex)(re.hotspotTableSize, memory);
            merge[] = 0;
        }
        opCacheTrue = arrayInChunk!(OpFunc)(re.ir.length, memory);
        opCacheFalse = arrayInChunk!(OpFunc)(re.ir.length, memory);
        opCacheBackTrue = arrayInChunk!(OpBackFunc)(re.ir.length, memory);
        opCacheBackFalse = arrayInChunk!(OpBackFunc)(re.ir.length, memory);

        jitCacheFalse = new CodegenX86_64();
        jitCacheTrue = new CodegenX86_64();
        ir2jit = new size_t[re.ir.length];
        for(uint pc = 0; pc<re.ir.length; pc += re.ir[pc].length)
        {
            ir2jit[pc] = pc == 0 ? 0 : jitCacheTrue.offset; //account for prolog
        L_dispatch:
            switch(re.ir[pc].code)
            {
                foreach(e; __traits(allMembers, IR))
                {
            mixin(`case IR.`~e~`:
                    opCacheTrue[pc] = &Ops!(true).op!(IR.`~e~`);
                    opCacheBackTrue[pc] = &BackOps!(true).op!(IR.`~e~`);
                    opCacheFalse[pc] = &Ops!(false).op!(IR.`~e~`);
                    opCacheBackFalse[pc] = &BackOps!(false).op!(IR.`~e~`);
                    jitCacheTrue.genFunctionCall(&Ops!(true).op!(IR.`~e~`));
                    jitCacheTrue.genDispatch();
                    jitCacheFalse.genFunctionCall(&Ops!(false).op!(IR.`~e~`));
                    jitCacheFalse.genDispatch();
                break L_dispatch;
                `);
                }
            default:
                assert(0, "Unrecognized instruction "~re.ir[pc].mnemonic);
            }
        }
        jitCacheTrue.genEpilog();
        jitCacheFalse.genEpilog();
    }

    this()(Regex!Char program, Stream stream, void[] memory)
    {
        re = program;
        s = stream;
        initExternalMemory(memory);
        genCounter = 0;
    }

    this(ref ThompsonMatcher matcher, size_t lo, size_t hi, Stream stream)
    {
        s = stream;
        re = matcher.re;
        re.ir = re.ir[lo..hi];
        threadSize = matcher.threadSize;
        merge = matcher.merge;
        freelist = matcher.freelist;
        opCacheTrue = matcher.opCacheTrue[lo..hi];
        opCacheBackTrue = matcher.opCacheBackTrue[lo..hi];
        opCacheFalse = matcher.opCacheFalse[lo..hi];
        opCacheBackFalse = matcher.opCacheBackFalse[lo..hi];
        front = matcher.front;
        index = matcher.index;
    }

    this(ref BackMatcher matcher, size_t lo, size_t hi, Stream stream)
    {
        s = stream;
        re = matcher.re;
        re.ir = re.ir[lo..hi];
        threadSize = matcher.threadSize;
        merge = matcher.merge;
        freelist = matcher.freelist;
        opCacheTrue = matcher.opCacheBackTrue[lo..hi];
        opCacheBackTrue = matcher.opCacheTrue[lo..hi];
        opCacheFalse = matcher.opCacheBackFalse[lo..hi];
        opCacheBackFalse = matcher.opCacheFalse[lo..hi];
        front = matcher.front;
        index = matcher.index;
    }

    auto fwdMatcher()(size_t lo, size_t hi, size_t counter)
    {
        auto m = ThompsonMatcher!(Char, Stream)(this, lo, hi, s);
        m.genCounter = counter;
        return m;
    }

    auto bwdMatcher()(size_t lo, size_t hi, size_t counter)
    {
        alias BackLooper = typeof(s.loopBack(index));
        auto m = ThompsonMatcher!(Char, BackLooper)(this, lo, hi, s.loopBack(index));
        m.genCounter = counter;
        m.next();
        return m;
    }

    auto dupTo(void[] memory)
    {
        typeof(this) tmp = this;//bitblit
        tmp.initExternalMemory(memory);
        tmp.genCounter = 0;
        return tmp;
    }

    enum MatchResult{
        NoMatch,
        PartialMatch,
        Match,
    }

    bool match(Group!DataIndex[] matches)
    {
        debug(std_regex_matcher)
            writeln("------------------------------------------");
        if(exhausted)
        {
            return false;
        }
        if(re.flags & RegexInfo.oneShot)
        {
            next();
            exhausted = true;
            return matchOneShot(matches)==MatchResult.Match;
        }
        static if(kicked)
            if(!re.kickstart.empty)
                return matchImpl!(true)(matches);
        return matchImpl!(false)(matches);
    }

    //match the input and fill matches
    bool matchImpl(bool withSearch)(Group!DataIndex[] matches)
    {
        if(!matched && clist.empty)
        {
           static if(withSearch)
                search();
           else
                next();
        }
        else//char in question is  fetched in prev call to match
        {
            matched = false;
        }
        State state;
        state.matches = matches;

        if(!atEnd)//if no char
            for(;;)
            {
                genCounter++;
                debug(std_regex_matcher)
                {
                    writefln("Threaded matching threads at  %s", s[index..s.lastIndex]);
                    foreach(t; clist[])
                    {
                        assert(t);
                        writef("pc=%s ",t.pc);
                        write(t.matches);
                        writeln();
                    }
                }
                for(state.t = clist.fetch(); state.t; state.t = clist.fetch())
                {
                    eval!true(&state);
                }
                //if we already have match no need to push the engine
                if(!matched)
                {
                    state.t = createStart(index);
                    eval!true(&state);//new thread staring at this position
                }
                else if(nlist.empty)
                {
                    debug(std_regex_matcher) writeln("Stopped  matching before consuming full input");
                    break;//not a partial match for sure
                }
                clist = nlist;
                nlist = (ThreadList!DataIndex).init;
                if(clist.tip is null)
                {
                    static if(withSearch)
                    {
                        if(!search())
                            break;
                    }
                    else
                    {
                        if(!next())
                            break;
                    }
                }
                else if(!next())
                {
                    if (!atEnd) return false;
                    exhausted = true;
                    break;
                }
            }

        genCounter++; //increment also on each end
        debug(std_regex_matcher) writefln("Threaded matching threads at end");
        //try out all zero-width posibilities
        for(state.t = clist.fetch(); state.t; state.t = clist.fetch())
        {
            eval!false(&state);
        }
        if(!matched)
        {
            state.t = createStart(index);
            eval!false(&state);//new thread starting at end of input
        }
        if(matched)
        {//in case NFA found match along the way
         //and last possible longer alternative ultimately failed
            s.reset(matches[0].end);//reset to last successful match
            next();//and reload front character
            //--- here the exact state of stream was restored ---
            exhausted = atEnd || !(re.flags & RegexOption.global);
            //+ empty match advances the input
            if(!exhausted && matches[0].begin == matches[0].end)
                next();
        }
        return matched;
    }

    /+
        handle succesful threads
    +/
    void finish(const(Thread!DataIndex)* t, Group!DataIndex[] matches)
    {
        matches.ptr[0..re.ngroup] = t.matches.ptr[0..re.ngroup];
        debug(std_regex_matcher)
        {
            writef("FOUND pc=%s prog_len=%s",
                    t.pc, re.ir.length);
            if(!matches.empty)
                writefln(": %s..%s", matches[0].begin, matches[0].end);
            foreach(v; matches)
                writefln("%d .. %d", v.begin, v.end);
        }
        matched = true;
    }

    alias Ops(bool withInput) =  ThompsonOps!(ThompsonMatcher, State, withInput);
    alias BackOps(bool withInput) =  ThompsonOps!(BackMatcher, BackMatcher.State, withInput);

    /+
        match thread against codepoint, cutting trough all 0-width instructions
        and taking care of control flow, then add it to nlist
    +/
    void eval(bool withInput)(State* state)
    {
        debug(std_regex_matcher) writeln("---- Evaluating thread");
        static if(withInput)
        {
            auto func = cast(OpFunc)(jitCacheTrue.base+ir2jit[state.t.pc]);
            import std.stdio;
            writefln("pc=%s offset=%s addr=%x", state.t.pc, ir2jit[state.t.pc], func);
            func(&this, state);
        }
        else
        {
            auto func = cast(OpFunc)(jitCacheFalse.base+ir2jit[state.t.pc]);
            func(&this, state);
        }
    }
    enum uint RestartPc = uint.max;
    //match the input, evaluating IR without searching
    MatchResult matchOneShot(Group!DataIndex[] matches, uint startPc = 0)
    {
        debug(std_regex_matcher)
        {
            writefln("---------------single shot match ----------------- ");
        }
        alias evalFn = eval;
        assert(clist == (ThreadList!DataIndex).init || startPc == RestartPc); // incorrect after a partial match
        assert(nlist == (ThreadList!DataIndex).init || startPc == RestartPc);
        State state;
        state.matches = matches;
        if(!atEnd)//if no char
        {
            debug(std_regex_matcher)
            {
                writefln("-- Threaded matching threads at  %s",  s[index..s.lastIndex]);
            }
            if(startPc!=RestartPc)
            {
                state.t = createStart(index, startPc);
                genCounter++;
                evalFn!true(&state);
            }
            for(;;)
            {
                debug(std_regex_matcher) writeln("\n-- Started iteration of main cycle");
                genCounter++;
                debug(std_regex_matcher)
                {
                    foreach(t; clist[])
                    {
                        assert(t);
                    }
                }
                for(state.t = clist.fetch(); state.t; state.t = clist.fetch())
                {
                    evalFn!true(&state);
                }
                if(nlist.empty)
                {
                    debug(std_regex_matcher) writeln("Stopped  matching before consuming full input");
                    break;//not a partial match for sure
                }
                clist = nlist;
                nlist = (ThreadList!DataIndex).init;
                if(!next())
                {
                    if (!atEnd) return MatchResult.PartialMatch;
                    break;
                }
                debug(std_regex_matcher) writeln("-- Ended iteration of main cycle\n");
            }
        }
        genCounter++; //increment also on each end
        debug(std_regex_matcher) writefln("-- Matching threads at end");
        //try out all zero-width posibilities
        for(state.t = clist.fetch(); state.t; state.t = clist.fetch())
        {
            evalFn!false(&state);
        }
        if(!matched)
        {
            state.t = createStart(index, startPc);
            evalFn!false(&state);
        }

        return (matched?MatchResult.Match:MatchResult.NoMatch);
    }

    //get a dirty recycled Thread
    Thread!DataIndex* allocate()
    {
        assert(freelist, "not enough preallocated memory");
        Thread!DataIndex* t = freelist;
        freelist = freelist.next;
        return t;
    }

    //link memory into a free list of Threads
    void prepareFreeList(size_t size, ref void[] memory)
    {
        void[] mem = memory[0 .. threadSize*size];
        memory = memory[threadSize * size .. $];
        freelist = cast(Thread!DataIndex*)&mem[0];
        size_t i;
        for(i = threadSize; i < threadSize*size; i += threadSize)
            (cast(Thread!DataIndex*)&mem[i-threadSize]).next = cast(Thread!DataIndex*)&mem[i];
        (cast(Thread!DataIndex*)&mem[i-threadSize]).next = null;
    }

    //dispose a thread
    void recycle(Thread!DataIndex* t)
    {
        t.next = freelist;
        freelist = t;
    }

    //dispose list of threads
    void recycle(ref ThreadList!DataIndex list)
    {
        if(list.tip)
        {
            // just put this head-tail list in front of freelist
            list.toe.next = freelist;
            freelist = list.tip;
            list = list.init;
        }
    }

    //creates a copy of master thread with given pc
    Thread!DataIndex* fork(Thread!DataIndex* master, uint pc, uint counter)
    {
        auto t = allocate();
        t.matches.ptr[0..re.ngroup] = master.matches.ptr[0..re.ngroup];
        t.pc = pc;
        t.counter = counter;
        t.uopCounter = 0;
        return t;
    }

    //creates a start thread
    Thread!DataIndex* createStart(DataIndex index, uint pc = 0)
    {
        auto t = allocate();
        t.matches.ptr[0..re.ngroup] = (Group!DataIndex).init;
        t.matches[0].begin = index;
        t.pc = pc;
        t.counter = 0;
        t.uopCounter = 0;
        return t;
    }
}


abstract class Codegen{
private:
    enum pageSize = 4<<10, pageMask = ~(pageSize-1);
    ubyte[] code;
    size_t idx;
protected:
    void resize(size_t size)
    {
        import core.sys.linux.sys.mman;
        size = (size+pageSize-1)&pageMask;
        if(code.ptr == null)
        {
            auto p = cast(ubyte*)mmap(null, size, 
                PROT_EXEC | PROT_WRITE | PROT_READ, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
            enforce(p != MAP_FAILED, "failed to map JIT region");
            code = p[0..size];
        }
        else
        {
            auto p = cast(ubyte*)mremap(code.ptr, code.length, size, MREMAP_MAYMOVE);
            enforce(p != MAP_FAILED, "failed to remap JIT region");
            code = p[0..size];
        }
    }

    void put(ubyte[] bytes...)
    {
        if(idx + bytes.length > code.length)
        {
            resize((code.length*3+1)/2);
        }
        code[idx..idx+bytes.length] = bytes[];
        idx += bytes.length;
    }

    void putReverse(T)(T arg)
    {
        foreach(_; 0..arg.sizeof)
        {
            put(arg & 0xFF);
            arg >>= 8;
        }
    }

    void finalize()
    {
        // flush CPU cache on windows
        import std.file;
        write("dump.bin", code[0..idx]);
    }

public:
    this()
    {
        resize(pageSize);
    }

    void* getIP()
    {
        return code.ptr + idx;
    }

    final void* base()
    {
        return code.ptr;
    }

    final size_t offset()
    {
        return idx;
    }

    ~this()
    {
        import core.sys.linux.sys.mman;
        if(code.ptr)
        {
            munmap(code.ptr, code.length);
        }
    }
// architecture specifics
    abstract Codegen genProlog();
    abstract Codegen genEpilog();
    abstract Codegen genFunctionCall(void* func);
    abstract Codegen genTwoWayDispatch(void* inside);
    abstract Codegen genDispatch();
}

class CodegenX86_64 : Codegen {

    override Codegen genProlog()
    {
        put(0x41, 0x54); // push R12
        put(0x41, 0x55); // push R13
        put(0x49, 0x89, 0xfc); // mov r12, rdi
        put(0x49, 0x89, 0xf5); // mov r13, rsi
        return this;
    }

    override Codegen genEpilog()
    {
        finalize();
        return this;
    }

    override Codegen genFunctionCall(void* func)
    {
        genProlog();
        put(0x4c, 0x89, 0xe7);      // mov rdi, r12
        put(0x4c, 0x89, 0xee);      // mov rsi, r13
        put(0x48, 0xb8);            // mov abs xxxxx
        putReverse(cast(ulong)func);
        put(0xff, 0xd0);            // call rax
        put(0x83, 0xf8, 0x00);      // cmp eax, 0
        return this;
    }

    override Codegen genTwoWayDispatch(void* inside)
    {
        void* cur = getIP;
        put(0x0F, 0x86);  // ja xxx
        putReverse(cast(uint)(inside - cur));
        genDispatch();
        return this;
    }

    override Codegen genDispatch()
    {
        put(0x0F, 0x82); // jb xxx
        putReverse(cast(uint)4 + 3 + 2 + 3 + 2*2 + 1 + 10); // 10 - sizeof of prolog
        put(0x49, 0x8b, 0x45, 0x28);    // mov rax, [R13+offset]
        put(0x48, 0x85, 0xc0);          // test rax, rax
        put(0x74, 0x03);                // je +3
        put(0x48, 0xff, 0xe0);          // jmp rax
        put(0x41, 0x5d);                // pop r13
        put(0x41, 0x5c);                // pop r12
        put(0xc3);                      // ret
        return this;
    }
};