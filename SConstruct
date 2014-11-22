# Phobos library SConstruct file
#
#   Detects OS/Arch, then sets proper environment, output directories,
#   builder primitives and forwards to the actual BUILD instructions.

import platform
import os
from os.path import relpath, abspath # used to normalize unix path to OS path (might be better way?)

osNames = { # python's uname() --> standardized identifier
    "Windows" : "windows",
    "Linux" : "linux"
}

OS, _, _, _, MODEL, _ = platform.uname()
OS = osNames[OS]

if MODEL in ["AMD64", "x86_64", "amd64"]:
    MODEL=64
else:
    MODEL=32

BUILD = ARGUMENTS.get('BUILD', "release")
if BUILD != "release" and BUILD != "debug":
    print "BUILD can only be 'release' or 'debug'."
    exit(1)
MODEL = int(ARGUMENTS.get('MODEL', MODEL))

print "[INFO] Building %s %s-bit version." % (OS, MODEL)

buildDir = 'generated/%s/%s/%s' % (OS, BUILD, MODEL)
if OS == "windows" and MODEL == 32: 
    # DMC toolchain is not represented in SCons out of the box,
    # so we override defaults (which is MS VC) to avoid them polluting our ENV 
    env = Environment(
        TOOLS=['filesystem'],
        # expect DMC to be in PATH
        ENV = { 'PATH' : os.environ["PATH"] },
        CC="dmc", AR="lib", CFLAGS = Split("-6 -o")
    )
else:
    env = Environment() # use defaults, SCons does miracles with VS and GCC

env.Replace(
    DMD =  os.environ.get("DMD", relpath("../dmd/src/dmd")), # allow to override $DMD
    DFLAGS ="",
    MODEL=MODEL,
    OS=OS,
    DRUNTIME_PATH = relpath("../druntime"),
    WEBSITE_DIR = abspath("../web")
)

env.Append(DRUNTIME_IMPORT = relpath(env.subst("$DRUNTIME_PATH/import")))
env.Append(DFLAGS = Split("-w -m$MODEL -I$DRUNTIME_IMPORT $PIC"))
env.Append(DDOC=env.subst("$DMD $DFLAGS -o- -version=StdDdoc"))
if OS == "linux":
        env.Append(DFLAGS="-L-ldl")
#print env.Dump()
# old OS-specific druntime paths
if OS == "windows":
    if MODEL == 32:
        env.Append(DRUNTIME = abspath(env.subst("$DRUNTIME_PATH/lib/${LIBPREFIX}druntime$LIBSUFFIX")))
    else:
        env.Append(DRUNTIME = abspath(env.subst("$DRUNTIME_PATH/lib/${LIBPREFIX}druntime64$LIBSUFFIX")))
else:
    env.Append(
        DRUNTIME = abspath(env.subst("$DRUNTIME_PATH/lib/${LIBPREFIX}druntime-$OS$MODEL$LIBSUFFIX")),
        DRUNTIME_DLL = abspath(env.subst("$DRUNTIME_PATH/lib/libdruntime-$OS$MODELso.a"))
    )
# Pick suitable C compiler flags
for cc in [ "cc", "gcc", "clang", "icc", "egcc"]:
    if env["CC"].startswith(cc):
        if BUILD == "release":
            env.Append(CFLAGS = "-O3")
        else:
            env.Append(CFLAGS = "-g")

# D release vs debug flags
if BUILD == "release":
    env.Append(DFLAGS=Split("-O -release"))
else:
    env.Append(DFLAGS=Split("-g -debug"))

# roll our own builder for DMC, crude but does the job.
if OS == "windows" and MODEL == 32:
    # DMC's syntax not supported by SCons out of the box
    cobj = Builder(action="$CC -c $CFLAGS $SOURCE -o$TARGET",
              suffix = env["OBJSUFFIX"],
              src_suffix = ".c")
    clib = Builder(action="$AR -c $TARGET $SOURCES",
              suffix = env["LIBSUFFIX"],
              src_suffix = env["OBJSUFFIX"])
else: # all other OS & compilers supported y SCons
    cobj = env["BUILDERS"]["Object"]
    clib = env["BUILDERS"]["Library"]

# custom builders for D: object file, library, dll and executable
# Note: there is native Scons support for D, but it's not as flexible as needed.
# In particular it can't represent the same build steps 
# as previous makefiles did. So let's keep it compatible and simple for starters.
dobj = Builder(action="$DMD -c $DFLAGS $SOURCE -of$TARGET",
            suffix = env["OBJSUFFIX"],
            src_suffix = ".d")
dlib = Builder(action="$DMD -lib -c $DFLAGS $SOURCES -of$TARGET",
            prefix=env["LIBPREFIX"],
            suffix = env["LIBSUFFIX"],
            src_suffix = env["OBJSUFFIX"])

env.Append(BUILDERS={
    'CObj' : cobj,
    'CLib' : clib,
    'DObj' : dobj,
    'DLib' : dlib,
  #  'DDll' : ddll,
  #  'DExe' : dexe
})

SConscript('SConscript', exports=['env', 'OS'], variant_dir=buildDir)
