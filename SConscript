# Phobos library SConscript file
#
#   Defines targets and relations between them.
#
#   Correct environment, build commands, etc. are defined by SConstruct.
import os
from os.path import relpath
from glob import glob
from fnmatch import fnmatch
Import('env', 'OS')

# ZLIB library C sources, not likely to change
zlibSrc = Split("""
    adler32.c compress.c crc32.c deflate.c gzclose.c gzlib.c gzread.c gzwrite.c
    infback.c inffast.c inflate.c inftrees.c trees.c uncompr.c zutil.c
""")
env.Append(CFLAGS=["-I", relpath("etc/c/zlib")])
zlibSrc = map(lambda x: relpath("etc/c/zlib/"+x), zlibSrc)
zobjs = [env.CObj(c) for c in zlibSrc]
zlib = env.CLib("zlib", zobjs) 

# Hackish glob to include 4 levels for now.
# May use more of Python to get fully recursive listing.
dsources = glob("std/*.d") + glob("etc/*.d") + glob("std/*/*.d") + glob("std/*/*/*.d") + \
    glob("std/*/*/*/*.d")
# Table to filter out some paths
blacklist = [ "windows", "linux", "freebsd", "osx"]
blacklist.remove(OS) # remove our OS from the list
def blacklisted(f):
    for os in blacklist:
        if f.find(os) != -1:
            return False
    if fnmatch(f, "std/c/*"):
        return False
    return True
dsources = filter(blacklisted, dsources)
druntime = [env.subst("$DRUNTIME")]
phobos = env.DLib("phobos", dsources + zlib + druntime)

for t in dsources:
    env.DTest([File(t), phobos])
    