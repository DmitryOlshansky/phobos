# Phobos library SConstruct file
#
#   Detects OS/Arch, then sets proper environment, output directories,
#   builder primitives and forwards to the actual BUILD instructions.

import platform
import os
import re
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
env.Append(TESTRUNNER=abspath(env.subst("$DRUNTIME_PATH/src/test_runner.d")))
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
else: # all other OS & compilers supported by SCons
    cobj = env["BUILDERS"]["Object"]
    clib = env["BUILDERS"]["Library"]

# print env.Dump()
# Note: there is native Scons support for D, but it's not as flexible as needed.
# In particular it can't represent the same build steps 
# as previous makefiles did. Thus we use custom builder to do that.
# Let's keep it compatible and simple for starters.

# Handling DMD's deps output
depPattern = re.compile(""".*\((\S+)\)""")

def add_deps_target(target, source, env):
    for s in source:
        if s.path.endswith(".d"):
            target.append(File(target[0].get_path() + ".deps"))
    return target,source

def dtest(target, source, env):
    extras = []
    for s in source:
        if s.path.endswith(".deps"):
            deps = []
            print os.getcwd()
            for line in open(s.path):
                m = re.match(depPattern, line)
                if not m is None:
                    deps.append(m.groups()[0].replace("\\\\", "\\"))
            # filter, use "set" to sort & unique
            deps = set(filter(lambda x: x.find("druntime") < 0, deps))
            source.remove(s)
            extras += list(map(lambda p: File(p), deps))
    source += extras
    src = join(source.path)
    cmd = env.subst("$DMD $DFLAGS %s -of%s")
    subprocess.call(cmd % (src, target[0].path)
    print target, "<===", source
    return 1

# compile object file with unitest flag to tests/*.{o,obj}, write out dependencies to tests/*.dep files
# emitter used to notify SCons we actually get many targets out of 1 file
dtest_obj = Builder(action="$DMD -c -unittest $DFLAGS $SOURCES -deps=${TARGET}.deps -of$TARGET",
            suffix = env["OBJSUFFIX"],
            src_suffix = ".d",
            emitter = add_deps_target)

# build test runner from deps file, main obj and phobos library
dtest = Builder(action = dtest,
        suffix = env['PROGSUFFIX'],
        src_suffix = env["OBJSUFFIX"])

# build whole library in one compiler run
dlib = Builder(action="$DMD -lib -c $DFLAGS $SOURCES -of$TARGET",
            prefix=env["LIBPREFIX"],
            suffix = env["LIBSUFFIX"],
            src_suffix = env["OBJSUFFIX"])

env.Append(BUILDERS={
    'CObj' : cobj,
    'CLib' : clib, 
    'DLib' : dlib,
    'DTestObj' : dtest_obj, # object file of the test + deps list
    'DTest' : dtest # test executable itself from deps & obj file
  #  'DSharedLib' : dshlib,
  #  'DExe' : dexe
})

SConscript('SConscript', exports=['env', 'OS'], variant_dir=buildDir)
