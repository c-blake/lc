import std/[os,posix,sets,tables,terminal,strutils,algorithm,nre,critbits],
  cligen/[osUt,posixUt,unixUt,statx,strUt,textUt,humanUt,abbrev,cfUt,tab,magic]
import cligen, cligen/sysUt; from std/unicode import runeLen
when not declared(File): import std/syncio

type       # fileName Dtype Stat lnTgt ACL Magic Capability
  DataSrc* = enum dsD, dsS, dsT, dsA, dsM, dsC ## Dirent,Stat,Tgt,Access,Mag,Cap
  DataSrcs* = set[DataSrc]

  Fil {.acyclic.}= object #Abstract file metadata including classification stuff
    st: Statx                    ##filesystem metadata
    kind: seq[uint8]             ##kind nums for independent format dimensions
    dtype, r, w, x, brok: int8   ##dtype, perms, lnSt (0 unknown, 1: no, 2: yes)
    acl, cap: bool               ##flags: has an ACL, has a Linux capability
    base, sext, lext, depth: int16 ##offset of basenms,shortest|longest extens
    usr, grp, name, abb, mag: string ##ids; here to sort, name, abbrev, magic
    tgt: ref Fil                 ##symlnk target

  Test  = tuple[ds: DataSrcs, test: proc(f:var Fil):bool]          #unattributed
  Kind  = tuple[attr:string, kord:uint8, icon:string, test:proc(f:var Fil):bool]
  Cmp   = tuple[sgn: int, cmp: proc(x, y: ptr Fil): int]           #1-level cmp
  Field = tuple[prefix: string; left: bool; c: char; hdr: string,  #1-field fmt
                fmt: proc(f: var Fil): string]
  ExtFmt = proc(qpath: cstring): cstring {.noconv.} ##Library must manage any..
  ExtTest = proc(path: cstring): int {.noconv.}     ##call-to-call prog state.

  LsCf* = object    #User set config fields early; Computed/intern fields later
    kind*, colors*, color*, ageFmt*: seq[string]            ##usrDefd kind/colrs
    incl*, excl*: seq[string]                               ##usrDefd filters
    order*, format*, glyph*, extra*, ext1*, ext2*,
     maxName*, maxTgt*, maxUnm*, maxGnm*: string
    recurse*, nColumn*, padMax*, widest*, width*, indent*, jobs*, jobsN*: int
    dirs*, binary*, dense*, deref*, tgtDref*, plain*,       ##various bool flags
     unzipF*, header*, access*, total*, quote*, n1*, reFit*, hyperlink*: bool
    paths*: seq[string]                                     ##paths to list
    t0: Timespec                                            #ref time for fAges
    nError: int
    kinds: seq[Kind]                                        #kinds user colors
    ukind: seq[seq[uint8]]                                  #USED kind dim seqs
    sin, sex: set[uint8]                                    #compiled filters
    nin, nex: int                                           #fast cardinality
    cmps: seq[Cmp]                                          #compares for sort
    fields: seq[Field]                                      #fields to format
    need: DataSrcs                                          #data needs(above 6)
    needKin, dirLabel, wrote: bool                          #flags
    usr: Table[Uid, string]                                 #user table
    grp: Table[Gid, string]                                 #group table
    tmFmtL, tmFmtU, tmFmtP: seq[tuple[age:int, fmt:string]] #(age,tFmt)lo/up/pln
    nAbb, tAbb, uAbb, gAbb: Abbrev
    a0: string                                              #if plain: ""
    attrSize: array[0..25, string]  #CAP letter-indexed with ord(x) - ord('A')
    attrPerm: array[0..7, string]   #indexed by 3-bit perm of this proc on files
    tests: CritBitTree[Test]
    kslot: CritBitTree[tuple[slot: uint8, ds: DataSrcs, dim: int]] #for filters
    pfx: string                                             #qualified prefix
    did: HashSet[PathId]                                    #inf.recurse block
    cl0, cl1: seq[string]
    cwd: string
    ext1c, ext2c: ExtFmt
    hostname: string              #required for hyperlink
    when haveMagic: mc: magic_t

###### Documentation/CLI; Early to use lsCfFromCL in for local config tweaks.
const nimbleFile = staticRead "lc.nimble"
clCfg.version = nimbleFile.fromNimble("version") &
  "\n\nTEXT ATTRIBUTE SPECIFICATION:\n" & addPrefix("  ", textAttrHelp)
proc c_getenv(env: cstring): cstring {.importc: "getenv", header: "<stdlib.h>".}
let cfDfl* = LsCf(format: "%f", glyph: " -> ", recurse: 1, nColumn: 999, jobs:1,
                  jobsN: 150, padMax: 999, plain: (c_getenv("NO_COLOR") != nil))

const ess: seq[string] = @[]
initGen(cfDfl, LsCf, "paths", @["ALL AFTER paths"], "inLsCf")
dispatchGen(inLsCf, "lc", usage="$command $args\n${doc}$options", doc="""
List Classified files in *paths* (CWD if none).  The following 1-letter codes
work for **BOTH format AND order specs**:
  *f* fileName      *u* numeric uid *a*|*A* access time  *i* inode-number *0* ord0|fmtDim0
  *F* baseName      *U* user name   *m*|*M* modify time  *k* st_blksize   *1* ord1|fmtDim1
  *s* humRdSz|devNo *g* numeric gid *c*|*C* create time  *D* major devno  *2* ord2|fmtDim2
  *K* file blocks   *G* group name  *v*|*V* vsnTm=mx(cm) *d* minor devno
  *n* link count    *p* rwx perms   *b*|*B* birth time   *o* %sz occupied

For **format specs ONLY** capitals mean an alternate time format & there are also:
  *r* readlink        *S* size(bytes)  *l* ls-KindCode(dl-..)  *x* stxAttrCode
  *R* lnk w/color tgt *P* Octal Perms  *L* ls-KindCode(/@\\*|=)  *Q* "+" if hasAcl
  *Z* selinux label   *q* "rwx" perms *e|E* ExternProgOutput   *I* ICON from --color
 *3-8* fmtDim3-8     *9./* tgtFmtDim0-2 *t* tree indent

For **MULTI-LEVEL order specs ONLY** +- mean incr(dfl)/decreasing &there are also:
  *e* shortestExtension(LAST'.'->END) *N* NumericFileName *A* AbbreviatedFileName
  *E* longestExtension(FIRST'.'->END) *L* fileNameLength  *3-5|6-8|9./* ~ fK|tkO|tK""",
            help = {"version": "Emit Version & *HELP SETTING COLORS*",
                    "kind":"""file kinds: **NAME**<WSPC>**RELATION**<WSPC>**PARAMS**
where <RELATION> says base names match:
  *cset* param=str of chars base name can have
  *SFX|sfx* case-(|in)sensitive name suffixes
  *PFX|pfx* case-(|in)sensitive name prefixes
  *uid|gid* numeric uids|gids (or Uid|Gid)
  *usr|grp* exact string users or groups
  *pcr*  White-sep Perl-Compatible Regexes
  *mag*  pcRegexs against file(1) type descrip
  *any|all|none*  earlier defd kind test names
  *ext*      x.so:func(qpath: cstring)->cint
BUILTIN *reg* *dir* *block* *char* *fifo* *sock* *symlink*
 *+-sym* *hard* *exec* *sUGid* *tmpDir* *worldW* *unR* *odd*
 *Linux COMPR IMMUT APPEND NODUMP ENCRYPT*
       *CAP* hasLinuxCapability *ACL* hasACL""",
                    "colors" : "color aliases; Syntax: name = ATTR1 ATTR2..",
                    "color"  : """text attrs for file kind/fields. Syntax:
  **NAME[[:KEY][:SLOT]] ATTR ATTR..**
**NAME** kind as above | *size{BKMGT}* | *perm{0-7}*
**KEY** a 0..255 *SORT/ORD* key **SLOT** dimension no.
**ATTR** specs: see --version output""",
                    "ageFmt":"""Syntax: *FILEAGE@[-+]STRFTIME_FMT* where:
  *FILEAGE* in {seconds,'FUTURE','ANYTIME'}
  '+' means AltFmt, '-' means plain mode fmt
  strftime %CODEs are any strftime & %DIGIT""",
                    "order"    : "[-]x[-]y[-]z.. keys to sort files by",
                    "format"   : "\"%a %b ..\" dirent format; %-X left-aligns",
                    "recurse"  : "recurse N levels; 0 => unbounded",
                    "dirs"     : "list dirs as themselves, not contents",
                    "binary"   : "K=size/1024, M=size/1024/1024 (vs /1000..)",
                    "dense"    : "no blanks between multiple dir listings",
                    "deref"    : "deref symlinks generally",
                    "access"   : "use 3\\*access(2) not st_mode for RWX perms",
                    "plain"    : "plain text; No color escape sequences",
                    "header"   : "add a row at start of data with col names",
                    "padMax"   : "max spaces by which to pad major columns",
                    "nColumn"  : "max major columns to use",
                    "widest"   : "only list this many widest entries",
                    "width"    : "override auto-detected terminal width",
                    "indent"   : "size of indent for %t tree indent",
                    "jobs"     : "parallelism for -5|-6 abbrevs; 0 => nCPU",
                    "jobsN"    : "threshold num dirents to go parallel",
                    "maxName"  : parseAbbrevHelp,
                    "maxTgt"   : "like maxName for symlink targets; No auto",
                    "maxUnm"   : "like maxName for user names",
                    "maxGnm"   : "like maxName for group names",
                    "unzipF"   : "negate default all-after-%[fF] column zip",
                    "glyph"    : "how to render arrow in %[rR] formats",
                    "extra"    : "add cf ARG~/.lc (.=SAME,trl/=PARS,//PR,/.r)",
                    "tgtDref"  : "fully classify %R formats on their own",
                    "ext1"     : "%e output from x.so:func(qpath: cstr)->cstr",
                    "ext2"     : "%E output from x.so:func(qpath: cstr)->cstr",
                    "reFit"    : "expand abbrevs up to padded column widths",
                    "quote"    : "quote filenames with unprintable chars",
                    "n1"       : "same as -n1; mostly to bind short form -1",
                    "hyperlink": "add hyperlinks",
                    "total"    : "print total of blocks before entries",
                    "excl"     : "kinds to exclude",
                    "incl"     : "kinds to include" },
            short = {"deref":'L', "dense":'D', "access":'A', "width":'W',
              "padMax":'P', "excl":'x', "n1":'1', "header":'H', "indent":'I',
              "maxTgt":'M', "maxUnm":'U', "maxGnm":'G', "tgtDref":'l',
              "extra":'X', "colors":'C', "ext2":'E', "reFit":'F', "jobsN":'J'},
            alias = @[ ("Style",'S',"DEFINE an output style arg bundle",@[ess]),
                       ("style",'s',"APPLY an output style",@[ess]) ],
            dispatchName = "lsCfFromCL")
var cg: ptr LsCf            #Lazy way out of making many little procs take LsCf

###### BUILT-IN CLASSIFICATION TESTS
template `~`(num, mask): untyped = (num.uint64 and mask.uint64) != 0 #mask true
proc qualPath(p: string): string =                        #maybe-pfx & name
  if cg.pfx.len > 0: cg.pfx & p else: p

let myUid = geteuid()               #Compute some globals assumed not to change
var myGrp = initHashSet[Gid]()      #len >= 1 once really initted w/`getgroups`

template defPermOk(z, zOk, Z_OK, S_IZUSR, S_IZGRP, S_IZOTH): untyped {.dirty.} =
  proc zOk(f: var Fil): bool =
    if f.z.int > 0: return f.z == 2         #cached result (grp hash in/access)
    if cg.access:         #system call slow, but sorta need for net FS accuracy
      result = access(f.name.qualPath.cstring, Z_OK) == 0
    else: #order: world,justMe,grpOfMine is designed to bool short circuit fast
      if myGrp.len == 0: getgroups(myGrp)
      result = f.st.st_mode ~ S_IZOTH or
              (f.st.st_mode ~ S_IZUSR and myUid == f.st.st_uid) or
              (f.st.st_mode ~ S_IZGRP and f.st.st_gid in myGrp)
    f.z = if result: 2 else: 1
defPermOk(r, rOk, R_OK, S_IRUSR, S_IRGRP, S_IROTH)
defPermOk(w, wOk, W_OK, S_IWUSR, S_IWGRP, S_IWOTH)
defPermOk(x, xOk, X_OK, S_IXUSR, S_IXGRP, S_IXOTH)
proc S_IUSR(m: Mode): int = (m.int and 0o700) shr 6 #Usr perms
proc S_IGRP(m: Mode): int = (m.int and 0o070) shr 3 #Grp perms
proc S_IOTH(m: Mode): int = (m.int and 0o007)       #Oth perms

proc maybeSt(f: var Fil): bool =
  if f.brok > 0: return f.brok == 1
  var st: Statx
  result = stat(f.name.qualPath.cstring, st) != -1
  f.brok = if result: 1 else: 2

template stModeOrDtype(f: Fil, stMoTy: proc(m:Mode):bool, dt: int8): bool =
  (if f.brok > 0: stMoTy(f.st.st_mode) else: f.dtype == dt)
proc isReg(f: var Fil): bool = f.stModeOrDtype(S_ISREG, DT_REG)
proc isDir(f: var Fil): bool = f.stModeOrDtype(S_ISDIR, DT_DIR)
proc isLnk(f: var Fil): bool = f.stModeOrDtype(S_ISLNK, DT_LNK)
proc isStickyDir(f: var Fil): bool = f.st.st_mode ~ 0o1000 and f.isDir
proc util(st: Statx): float =
  if st.st_blocks == 0 and st.st_size == 0: 100.0
  else: st.st_blocks.float * 51200.0 / max(st.st_size, 1).float

var builtin: CritBitTree[Test]
template tAdd(name, ds, t: untyped) {.dirty.} =
  builtin[name] = (ds, proc(f: var Fil): bool {.closure.} = t.bool)
tAdd("unknown",{})   : true
tAdd("regular",{dsD}): f.stModeOrDtype(S_ISREG , DT_REG)
tAdd("directory",{dsD}): f.stModeOrDtype(S_ISDIR , DT_DIR)
tAdd("blockDevice",{dsD}): f.stModeOrDtype(S_ISBLK , DT_BLK)
tAdd("charDevice" ,{dsD}): f.stModeOrDtype(S_ISCHR , DT_CHR)
tAdd("bdev"   ,{dsD}): f.stModeOrDtype(S_ISBLK , DT_BLK)  # Should deprecate..
tAdd("cdev"   ,{dsD}): f.stModeOrDtype(S_ISCHR , DT_CHR)  #..um, SOMEHOW..
tAdd("fifo"   ,{dsD}): f.stModeOrDtype(S_ISFIFO, DT_FIFO)
tAdd("socket" ,{dsD}): f.stModeOrDtype(S_ISSOCK, DT_SOCK)
tAdd("symlink",{dsD}): f.stModeOrDtype(S_ISLNK , DT_LNK)      #Any symlink
tAdd("-symlink",{dsD}): f.dtype == DT_LNK and not f.maybeSt   #Broken symlink
tAdd("+symlink",{dsD}): f.dtype == DT_LNK and f.maybeSt       #Good symlink
tAdd("executable",{dsD}): not (f.isDir or f.isLnk) and f.maybeSt and f.xOk
tAdd("hardLinks" ,{dsD}): not f.isDir and f.maybeSt and f.st.st_nlink > 1.Nlink
tAdd("suid"   ,{dsD}): f.isReg and f.maybeSt and f.st.st_mode ~ 0o4000 and
                       f.st.st_mode ~ 0o0111                  #exec by *someone*
tAdd("sgid"   ,{dsS}): f.st.st_mode ~ 0o2000
tAdd("tmpDir" ,{dsS}): f.isStickyDir and f.st.st_mode ~ 7
tAdd("worldWritable",{dsS}): f.st.st_mode ~ 2 and f.dtype != DT_LNK and
                             not f.isStickyDir
tAdd("unReadable", {dsS}): myUid != 0 and (not f.rOk or (f.isDir and not f.xOk))
tAdd("oddPerm",{dsS}):    #Check very odd st_mode's. Rare but legit wr-only in:
  let m = f.st.st_mode    #.. /dev/tty* /var/cache/man /var/spool /proc /sys
  (m ~ 0o4000 and ((m and 0o111)==0 or not f.isReg)) or      #suid&(!x|!reg)
   (m ~ 0o2000 and (m and 0o010)==0) or                      #sgid & g-x
   (f.isStickyDir and (m and 2) == 0) or                        #sticky & !o+w
   not (m.S_IUSR >= m.S_IGRP and m.S_IGRP >= m.S_IOTH) or       #!(u >= g >= o)
   (m.S_IUSR and 0o6)==2 or (m.S_IGRP and 0o6)==2 or (m.S_IOTH and 0o6)==2 #w&!r

when haveStatx:           # Linux only via statx
  tAdd("COMPRESSED",{dsS}): f.st.stx_attributes ~ STATX_ATTR_COMPRESSED
  tAdd("IMMUTABLE" ,{dsS}): f.st.stx_attributes ~ STATX_ATTR_IMMUTABLE
  tAdd("APPENDONLY",{dsS}): f.st.stx_attributes ~ STATX_ATTR_APPEND
  tAdd("NODUMP"    ,{dsS}): f.st.stx_attributes ~ STATX_ATTR_NODUMP
  tAdd("ENCRYPTED" ,{dsS}): f.st.stx_attributes ~ STATX_ATTR_ENCRYPTED
when defined(linux): tAdd("CAPABILITY",{dsC}): f.cap
tAdd("ACL",{dsA}): f.acl

###### USER-DEFINED CLASSIFICATION TESTS
proc testPCRegex(rxes: seq[Regex], f: var Fil): bool =
  result = false
  for r in rxes:
    if f.name[f.base..^1].contains(r): return true

proc testCharSet(cs: set[char], f: var Fil): bool =
  if f.name.len - f.base < 2: return false #Avoid 'R','X', etc. matching capsdoc
  result = true
  for c in f.name[f.base..^1]:
    if c notin cs: return false

proc testPreSuf(strs: seq[string], mode: char, f: var Fil): bool =
  for s in strs:
    if   mode == 'P' and f.name[f.base..^1].startsWith(s): return true
    elif mode == 'p' and f.name[f.base..^1].startsWithI(s): return true
    elif mode == 'S' and f.name[f.base..^1].endsWith(s): return true
    elif mode == 's' and f.name[f.base..^1].endsWithI(s): return true

proc testOwnId[Id](owns: HashSet[Id], f: var Fil): bool =
  when Id is Uid: f.st.st_uid in owns
  else: f.st.st_gid in owns

proc testUsr(nms: HashSet[string], f: var Fil): bool = f.usr in nms
proc testGrp(nms: HashSet[string], f: var Fil): bool = f.grp in nms

proc testAll(tsts: seq[Test], f: var Fil): bool =
  result = true
  for i, t in tsts:
    if not(t.test f): return false

proc testAny(tsts: seq[Test], f: var Fil): bool =
  for t in tsts:                    #bool result defaults to false
    if t.test f: return true

proc testNone(tsts: seq[Test], f: var Fil): bool =
  result = true
  for t in tsts:
    if t.test f: return false

proc testExt(tst: ExtTest; f: var Fil): bool =    #External shlib kind test
  result = tst(f.name.qualPath.cstring) == 1.cint #User code returns 1 for pass

proc addPCRegex(cf: var LsCf; mode, nm, s: string) =    #Q: add flags/modes?
  var rxes: seq[Regex]
  for pattern in s.splitWhitespace: rxes.add pattern.re
  cf.tests[nm] = ({}, proc(f: var Fil): bool = rxes.testPCRegex f)

proc addCSet(cf: var LsCf; nm, s: string) = #Could inline into `parseKind` with
  var cs: set[char]                         #..sugar.capture,but this is cleaner
  for c in s: cs.incl(c)
  cf.tests[nm] = ({}, proc(f: var Fil): bool = cs.testCharSet f)

proc addPreSuf(cf: var LsCf; md: char; nm, s: string) =
  let param = (if md == md.toLowerAscii: s.toLowerAscii else: s).splitWhitespace
  cf.tests[nm] = ({}, proc(f: var Fil): bool = param.testPreSuf(md, f))

proc addOwnId(cf: var LsCf; md: char; nm, s: string) =
  var s: HashSet[Uid] | HashSet[Gid] = if md == 'u': s.splitWhitespace.toUidSet
                                       else: s.splitWhitespace.toGidSet
  cf.tests[nm] = ({dsS}, proc(f: var Fil): bool = s.testOwnId(f))

proc addOwner(cf: var LsCf; md: char; nm, s: string) =
  var s = s.splitWhitespace.toHashSet
  if md == 'u':
    cf.tests[nm] = ({dsS}, proc(f: var Fil): bool = s.testUsr(f))
    if cf.usr.len == 0: cf.usr = users()        #ensure mkFil sets f.usr
  else:
    cf.tests[nm] = ({dsS}, proc(f: var Fil): bool = s.testGrp(f))
    if cf.grp.len == 0: cf.grp = groups()       #ensure mkFil sets f.grp

proc addCombo(cf: var LsCf; tester: auto; nm, s: string) =
  var tsts: seq[Test]
  var ds: DataSrcs
  for t in s.splitWhitespace:
    try:
      let tt = cf.tests[t]; tsts.add tt; ds = ds + tt.ds
    except Ce: Value !! "bad kind: \"" & t & "\""
  cf.tests[nm] = (ds, proc(f: var Fil): bool = tester(tsts, f))

proc addExt(cf: var LsCf; nm, s: string) =
  cf.tests[nm]=({},proc(f: var Fil): bool = cast[ExtTest](s.loadSym).testExt(f))

when haveMagic:
  proc testMagic(rxes: seq[Regex], f: var Fil): bool =
    result = false
    for r in rxes:
      if r in f.mag: return true

  var magicErrWritten = false
  proc addMagic(cf: var LsCf; mode, nm, s: string) =
    if cf.mc == nil:
      cf.mc = magic_open(0)
      if cf.mc == nil or magic_load(cf.mc, nil) != 0:
        if not magicErrWritten:
          stderr.write("cannot load magic DB: %s\x0A\n", magic_error(cf.mc))
          magicErrWritten = true
        magic_close(cf.mc)
        cf.mc = nil
    var rxes: seq[Regex]
    for pattern in s.splitWhitespace: rxes.add pattern.re
    cf.tests[nm] = ({dsM}, proc(f: var Fil): bool = rxes.testMagic f)
else:
  var magicMsgWritten = false
  proc addMagic(cf: var LsCf; mode, nm, s: string) =
    if not magicMsgWritten:
      stderr.write "lc was not compiled with file/libmagic support.\n"
      magicMsgWritten = true

proc parseKind(cf: var LsCf) =
  for kin in cf.kind:
    let col = kin.splitWhitespace(maxsplit=2)
    if col.len < 3: Value !! "bad kind: \"" & kin & "\""
    if col[1].toLower in ["pcr","perlRx"]: cf.addPCRegex(col[1], col[0], col[2])
    elif col[1] in ["cset", "asciiChars"]: cf.addCSet(col[0], col[2])
    elif col[1].toLower.endsWith("fx") or col[1].toLower.endsWith("fix"):
      cf.addPreSuf(col[1][0], col[0], col[2])
    elif col[1].endsWith("id"):cf.addOwnId(col[1][0].toLowerAscii,col[0],col[2])
    elif col[1] in ["usr", "user"]: cf.addOwner(col[1][0], col[0], col[2])
    elif col[1] in ["grp", "group"]: cf.addOwner(col[1][0], col[0], col[2])
    elif col[1] == "any": cf.addCombo(testAny, col[0], col[2])
    elif col[1] == "all": cf.addCombo(testAll, col[0], col[2])
    elif col[1] == "none": cf.addCombo(testNone, col[0], col[2])
    elif col[1] in ["ext", "extension"]: cf.addExt(col[0], col[2])
    elif col[1] in ["mag", "magic"]: cf.addMagic(col[1], col[0], col[2])
    else: Value !! "bad kind: \"" & kin & "\""

proc parseColor(cf: var LsCf) =
  var unknown = 255.uint8
  for spec in cf.color:
    let cols = spec.splitWhitespace()
    if cols.len<2: Value !! "bad color: \"" & spec & "\""
    let nmKoD = cols[0].split(':')
    let nm    = nmKoD[0].strip()
    let ko    = (if nmKoD.len>1: parseHexInt(nmKoD[1].strip()) else: 255).uint8
    let dim   = if nmKoD.len>2: parseInt(nmKoD[2].strip()) else: 0
    let icon  = if nmKoD.len>3: nmKoD[3] else: ""
    let attrs = textAttrOn(cols[1..^1], cf.plain)
    try:
      let ok = nm.len == 5 and (nm.startsWith("size") or nm.startsWith("perm"))
      let (key, test) = cf.tests.match(nm, "kind", if ok: nil else: stderr)
      let kno = cf.kinds.len.uint8                #Found test; add to used kinds
      cf.kslot[key] = (kno, test.ds, dim)         #Record kind number, DataSrc
      cf.kinds.add (attr: attrs, kord: ko, icon: icon, test: test.test)
      if dim + 1 > cf.ukind.len: cf.ukind.setLen(dim + 1)
      cf.ukind[dim].add kno
      cf.need = cf.need + test.ds
      if nm == "unknown": unknown = kno
    except KeyError:
      if nm.len == 5:
        if   nm.startsWith("size"):
          if nm[4] notin { 'B', 'K', 'M', 'G', 'T', 'S' }:
            Value !! "unknown color key: \""&nm&"\""
          cf.attrSize[ord(nm[4]) - ord('A')] = attrs
        elif nm.startsWith("perm"):
          if nm[4] notin {'0'..'7'}: Value!!"bad perm \""&nm&"\". Octal digit."
          cf.attrPerm[ord(nm[4]) - ord('0')] = attrs
      else: Value !! "unknown color key: \""&nm&"\""
  if unknown == 255: # auto-terminate .kinds if usr gave no attrs for "unknown"
    cf.kinds.add ("", 255.uint8, "", proc(f: var Fil): bool {.closure.} = true)

###### FILTERING
proc compileFilter(cf: var LsCf, spec: seq[string], msg: string): set[uint8] =
  for nm in spec:
    try:
      let k = cf.kslot.match(nm, "colored kind").val
      result.incl(k.slot)
      cf.need = cf.need + k.ds
      cf.needKin = true   #must fully classify if any kind is used as a filter
    except Ce: Value !! msg & " name \"" & nm & "\""

proc parseFilters(cf: var LsCf) =
  cf.sin = cf.compileFilter(cf.incl, "incl filter"); cf.nin = cf.sin.card
  cf.sex = cf.compileFilter(cf.excl, "excl filter"); cf.nex = cf.sex.card

proc contains(s: set[uint8], es: seq[uint8]): bool =
  for e in es:
    if e in s: return true

proc failsFilters(cf: LsCf; f: Fil): bool =
  (cf.nex > 0 and f.kind in cf.sex) or (cf.nin > 0 and f.kind notin cf.sin)

###### SORTING
proc tKind(f: Fil): seq[uint8] =
  if f.tgt != nil: f.tgt.kind else: newSeq[uint8](cg.ukind.len)

var cmpOf: Table[char, tuple[ds: DataSrcs, cmp: proc(x, y:ptr Fil):int]]
template cAdd(code, ds, cmpr, T, data: untyped) {.dirty.} =
  cmpOf[code] = (ds, proc(a, b: ptr Fil): int {.closure.} =
                   proc get(f: Fil): T = data   #AVAILABLE: hjlqrtwxyz
                   cmpr(get(a[]), get(b[])))    #           BCHIJMOPQRSTVWXYZ
proc abbr(f: Fil): string = (if f.abb.len > 0: f.abb else: f.name)
cAdd('f', {}   , cmp , string  ): f.name              # Basic thing ls/glob do
cAdd('A', {}   , cmp , string  ): f.abbr              # Our auto-glob-abbrevs
cAdd('F', {}   , cmp , string  ): f.name[f.base..^1]  # Just *base*name(if diff)
cAdd('e', {}   , cmpN, string  ): f.name[f.sext..^1]  # File extensions; See..
cAdd('E', {}   , cmpN, string  ): f.name[f.lext..^1]  #.. cligen/humanUt.cmpN
cAdd('N', {}   , cmpN, string  ): f.name              # Name w/number tuples
cAdd('L', {}   , cmp , uint    ): f.abbr.len.uint     # Savagely compact table
cAdd('s', {dsS}, cmp , uint    ): f.st.st_size.uint   # File-address space
cAdd('K', {dsS}, cmp , uint    ): f.st.st_blocks.uint  # KiB usually cap 'K'
cAdd('k', {dsS}, cmp , uint    ): f.st.st_blksize.uint # Arguably not useful
cAdd('n', {dsS}, cmp , uint    ): f.st.st_nlink.uint  # Num hard-links/SubDirs
cAdd('u', {dsS}, cmp , uint    ): f.st.st_uid.uint    # Most know root=0..
cAdd('g', {dsS}, cmp , uint    ): f.st.st_gid.uint    #   or wheel=0
cAdd('U', {dsS}, cmp , string  ): f.usr # Could hashmap->an Id each time here,
cAdd('G', {dsS}, cmp , string  ): f.grp #..but usr/grp names are mostly short
cAdd('p', {dsS}, cmp , uint    ): f.st.st_mode.uint and 4095  #P)ermissions
cAdd('a', {dsS}, cmp , Timespec): f.st.st_atim  # File times: a)ccess, m)odify,
cAdd('m', {dsS}, cmp , Timespec): f.st.st_mtim  #          c)hangeInode, b)irth
cAdd('c', {dsS}, cmp , Timespec): f.st.st_ctim
cAdd('v', {dsS}, cmp , Timespec): f.st.st_vtim  # v-time is max(c,m)=V)ersionTm
cAdd('b', {dsS}, cmp , Timespec): f.st.st_btim
cAdd('D', {dsS}, cmp , Dev     ): f.st.st_rmaj  # Major&minor dev & i-node nums
cAdd('d', {dsS}, cmp , Dev     ): f.st.st_rmin
cAdd('i', {dsS}, cmp , uint    ): f.st.st_ino.uint
cAdd('o', {dsS}, cmp , float   ): f.st.util     # o)ccupancy; '%' instead?
# User-defined (hard to make memorable) 1st 3dims of kord,fKind & for symLn tgts
# If do cligen/strUt.MacroCall, could instead be: fko0-9, fk0-9, tko0-9, tk0-9.
cAdd('0', {dsS}, cmp , uint8   ): cg.kinds[f.kind[0]].kord  #{dsS} should be..
cAdd('1', {dsS}, cmp , uint8   ): cg.kinds[f.kind[1]].kord  #..union of all data
cAdd('2', {dsS}, cmp , uint8   ): cg.kinds[f.kind[2]].kord  #..needs in tests
cAdd('3', {dsS}, cmp , uint8   ): f.kind[0]                 #..for each dim.
cAdd('4', {dsS}, cmp , uint8   ): f.kind[1]
cAdd('5', {dsS}, cmp , uint8   ): f.kind[2]
cAdd('6', {dsT}, cmp , uint8   ): cg.kinds[f.tKind[0]].kord
cAdd('7', {dsT}, cmp , uint8   ): cg.kinds[f.tKind[1]].kord
cAdd('8', {dsT}, cmp , uint8   ): cg.kinds[f.tKind[2]].kord
cAdd('9', {dsT}, cmp , uint8   ): f.tKind[0]
cAdd('.', {dsT}, cmp , uint8   ): f.tKind[1]
cAdd('/', {dsT}, cmp , uint8   ): f.tKind[2]

proc parseOrder(cf: var LsCf) =
  cf.cmps.setLen(0)
  if cf.order == "-": return
  var sgn = +1
  for c in cf.order:
    if   c == '-': sgn = -1; continue
    elif c == '+': sgn = +1; continue
    try:
      let cmpE = cmpOf[c]
      cf.cmps.add (sgn, cmpE.cmp)
      cf.need = cf.need + cmpE.ds
    except Ce: Value !! "unknown sort key code " & c.repr
    if   c == 'U' and cf.usr.len == 0: cf.usr = users()
    elif c == 'G' and cf.grp.len == 0: cf.grp = groups()
    elif c in {'0'..'9', '.', '/'}: cf.needKin = true       #bludgeon
    sgn = +1

proc multiLevelCmp(a, b: ptr Fil): int =
  for i in 0 ..< cg.cmps.len:
    let val = cg.cmps[i].cmp(a, b)
    if val != 0: return cg.cmps[i].sgn * val
  return 0

###### FORMATTING ENGINE
proc parseAge(cf: var LsCf) =
  template hl(sp, co, pl): auto {.dirty.} = specifierHighlight(sp, co, pl)
  for aFs in cf.ageFmt:
    let aF = aFs.split('@')
    if aF.len != 2: Value !! "bad ageFmt:\"" & aFs & "\""
    if aF[0].startsWith('+'): #2**31 =~ 68 yrs in future from when fin is run.
     try      :cf.tmFmtU.add((aF[0].parseInt, hl(aF[1],strftimeCodes,cf.plain)))
     except Ce:cf.tmFmtU.add((-2147483648.int,hl(aF[1],strftimeCodes,cf.plain)))
    elif aF[0].startsWith('-'): #plain mode formats
     try      :cf.tmFmtP.add((-aF[0].parseInt,hl(aF[1],strftimeCodes,cf.plain)))
     except Ce:cf.tmFmtP.add((-2147483648.int,hl(aF[1],strftimeCodes,cf.plain)))
    else:
     try      :cf.tmFmtL.add((aF[0].parseInt, hl(aF[1],strftimeCodes,cf.plain)))
     except Ce:cf.tmFmtL.add((-2147483648.int,hl(aF[1],strftimeCodes,cf.plain)))

proc kattr(f: Fil): string =
  for e in f.kind: result.add cg.kinds[e].attr

proc maybeQuote(cf: LsCf, path: string): string {.inline.} =  #WTF safeUnixChars
  if cf.quote: path.quoteShellPosix else: path                #..should incl ','

proc fmtName(f: Fil, p: string, abbrev=true): string =
  f.kattr & (if abbrev: f.abbr else: cg[].maybeQuote(p)) & cg.a0

proc fmtTgtD(f: Fil): string =  #Colorize link targets (in deref|tgtDref mode)
  if cg.deref: return           #..according to stat|string type of *target*.
  if f.dtype != DT_LNK: return
  if f.tgt == nil: return cg.glyph & f.kattr & "HIDDEN" & cg.a0
  if cg.tgtDref:
    cg.glyph&f.tgt[].kattr & cg.tAbb.abbrev(cg[].maybeQuote(f.tgt.name)) & cg.a0
  else:
    cg.glyph&f.kattr & cg.tAbb.abbrev(cg[].maybeQuote(f.tgt.name)) & cg.a0

proc fmtTgtU(f: Fil): string =   #Should unclassified tgt grow a color|shr attr
  if cg.deref or f.dtype != DT_LNK: return #..of referrer? Mode 4 nm-only kind?
  cg.glyph & cg.tAbb.abbrev(cg[].maybeQuote(f.tgt.name))

proc fmtIcon(f: Fil): string =
  for e in f.kind: result.add cg.kinds[e].icon

proc sp(cf: LsCf, st: Statx): string =          #sparse attribute
  if st.util < 75: cg.attrSize[ord('S') - ord('A')] else: ""

let bDiv = max(1, if "POSIXLY_CORRECT".existsEnv: 1 else:
  try: (parseInt(getEnv("BLOCK_SIZE",getEnv("BLOCKSIZE", "1024").strip))div 512)
  except: 2).uint

proc fmtSzDevNo(st: Statx): string =
  proc sizeFmt(sz: string): string =            #colorized file size
    let ix = (if sz[^1] in Digits: 'B'.ord else: sz[^1].ord) - 'A'.ord
    let digs = sz.find Digits
    sz[0..<digs] & cg.attrSize[ix] & cg[].sp(st) & sz[digs..^1] & cg.a0
  if S_ISBLK(st.st_mode) or S_ISCHR(st.st_mode):
    toHex((((st.st_rmaj and 0xFF) shl 8) or (st.st_rmin and 0xFF)).BiggestInt,4)
  else: sizeFmt(align(humanReadable4(st.st_size.uint, cg.binary), 4))

proc fmtSzDevNoL(st: Statx): string =
  proc sc(st: Statx): char =
    let k = if cg.binary: float(1.uint shl 10) else: 1e3
    let m = if cg.binary: float(1.uint shl 20) else: 1e6
    let g = if cg.binary: float(1.uint shl 30) else: 1e9
    let b = st.st_size.float
    if b<=9999:'B' elif b < k*k:'K' elif b < k*m:'M' elif b < k*g:'G' else: 'T'
  if st.st_mode.S_ISCHR or st.st_mode.S_ISBLK: $st.st_rmaj & "," & $st.st_rmin
  else: cg.attrSize[ord(st.sc)-ord('A')] & cg[].sp(st) & $st.st_size.uint&cg.a0

proc fmtTime(ts: Timespec, alt=false): string =
  let tfs = if cg.plain: cg.tmFmtP elif alt: cg.tmFmtU else: cg.tmFmtL
  for (age, fmt) in tfs:
    let fage = (cg.t0.tv_sec - ts.tv_sec).int #tv_nsec can only make fage off
    if fage >= age:                           #..by <= 1 s.
      return if fmt[0] != '/': strftime(fmt, ts)
             else: fage.humanDuration(fmt[1..^1], cg.plain)
  strftime(if tfs.len > 0: tfs[^1][1] else: "%F:%T.%3", ts)

proc fmtPerm*(m: Mode, s=""): string =
  ## Call with ``.st_mode`` of some ``Stat`` to get rwxr-x..; ``s`` is optional
  ## separator string such as a space or a comma to enhance readabilty.
  let m = m.uint and 4095
  const rwx = ["---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx" ]
  result = rwx[(m shr 6) and 7] & s & rwx[(m shr 3) and 7] & s & rwx[m and 7]
  let o = s.len
  if m ~ 0o4000 and      m ~ 0o100 : result[2]   = 's' # setuid, +x
  if m ~ 0o4000 and not (m ~ 0o100): result[2]   = 'S' # setuid, noX
  if m ~ 0o2000 and      m ~ 0o010 : result[5+o] = 's' # setgid, +x
  if m ~ 0o2000 and not (m ~ 0o010): result[5+o] = 'S' # setgid, noX
  if m ~ 0o1000 and      m ~ 0o001 : result[8+o] = 't' # sticky, +x
  if m ~ 0o1000 and not (m ~ 0o001): result[8+o] = 'T' # sticky, noX

proc fmtOperm(f: var Fil): string =
  let p = (f.rOk.uint shl 2) or (f.wOk.uint shl 1) or (f.xOk.uint)
  cg.attrPerm[p] & toOct(f.st.st_mode.int and 4095, 4) & cg.a0

proc fmtKindCode(st_mode: Mode): char =    #12=sticky,su,sg+9bits of UGO perms
  "-pc-d-b---l-s---"[st_mode.uint shr 12 and 0xF]  #Pretty standard across OSes

proc fmtAttrCode(stx_attr: uint64): string =
  result = "------"                     # [5] presently unused; Sounds like..
  when haveStatx:                       # VERITY=>IMMUTABLE=>maybe 0..4 enough.
    if stx_attr ~ STATX_ATTR_COMPRESSED: result[0] = 'C'
    if stx_attr ~ STATX_ATTR_IMMUTABLE : result[1] = 'I'
    if stx_attr ~ STATX_ATTR_APPEND    : result[2] = 'A'
    if stx_attr ~ STATX_ATTR_NODUMP    : result[3] = 'N'
    if stx_attr ~ STATX_ATTR_ENCRYPTED : result[4] = 'E'
#   if stx_attr ~ STATX_ATTR_VERITY    : result[5]='V' #Need glibc for 5.8+

proc toHex(i: uint8): string = toHex(i.BiggestInt, 2)

proc fmtClassCode(f: var Fil): string =
  if   f.stModeOrDtype(S_ISDIR , DT_DIR) : result.add '/'
  elif f.stModeOrDtype(S_ISLNK , DT_LNK) : result.add '@'
  elif f.stModeOrDtype(S_ISFIFO, DT_FIFO): result.add '|'
  elif f.stModeOrDtype(S_ISSOCK, DT_SOCK): result.add '='
  elif f.xOk                             : result.add '*'

var fmtCodes: set[char]   #left below is just dflt alignment. User can override.
var fmtOf: Table[char, tuple[ds: DataSrcs; left: bool; hdr: string;
                 fmt: proc(x: var Fil): string]]
template fAdd(code, ds, left, hdr, toStr: untyped) {.dirty.} =
  fmtCodes.incl(code)                           #AVAILABLE: hjyz HJNOTWXYZ
  fmtOf[code] = (ds, left.bool, hdr, proc(f:var Fil):string {.closure.} = toStr)
# Undelimited 1char-wide fields like '[lQI]' exist on purpose, but a junk way to
# ensure delimits for sparser stuff is leading ' ' in hdr for left-align fields.
fAdd('f', {}   ,1, " Nm"  ): f.fmtName(f.name)
fAdd('F', {}   ,1, " Bs"  ): f.fmtName(f.name[f.base..^1])
fAdd('r', {dsT},1, "ln"   ): f.fmtTgtU
fAdd('R', {dsT},1, "Ln"   ): f.fmtTgtD
fAdd('S', {dsS},0, "ByDv" ): fmtSzDevNoL(f.st)
fAdd('s', {dsS},0, "SzDv" ): fmtSzDevNo(f.st)
fAdd('K', {dsS},0, "Bk"   ): $(f.st.st_blocks.uint div bDiv)
fAdd('k', {dsS},0, "BkZ"  ): $f.st.st_blksize.uint
fAdd('o', {dsS},0, "%o"   ): (if f.st.util > 99.0: "99" else: $f.st.util.int)
fAdd('n', {dsS},0, "N"    ): $f.st.st_nlink.uint
fAdd('u', {dsS},0, "uid"  ): $f.st.st_uid.uint
fAdd('U', {dsS},1, " Usr" ): cg.uAbb.abbrev f.usr
fAdd('g', {dsS},0, "gid"  ): $f.st.st_gid.uint
fAdd('G', {dsS},1, " Grp" ): cg.gAbb.abbrev f.grp
fAdd('P', {dsS},0, "perm" ): f.fmtOperm                   #octal,color
fAdd('p', {dsS},1, " permUGO"): fmtPerm(f.st.st_mode)
fAdd('q', {dsS},1, " permUGO"): fmtPerm(f.st.st_mode, " ")
fAdd('a', {dsS},0, " atm" ): fmtTime(f.st.st_atim)
fAdd('m', {dsS},0, " mtm" ): fmtTime(f.st.st_mtim)
fAdd('c', {dsS},0, " ctm" ): fmtTime(f.st.st_ctim)
fAdd('v', {dsS},0, " vtm" ): fmtTime(f.st.st_vtim)
fAdd('b', {dsS},0, " btm" ): fmtTime(f.st.st_btim)
fAdd('A', {dsS},0, " Atm" ): fmtTime(f.st.st_atim, true)
fAdd('M', {dsS},0, " Mtm" ): fmtTime(f.st.st_mtim, true)
fAdd('C', {dsS},0, " Ctm" ): fmtTime(f.st.st_ctim, true)
fAdd('V', {dsS},0, " Vtm" ): fmtTime(f.st.st_vtim, true)
fAdd('B', {dsS},0, " Btm" ): fmtTime(f.st.st_btim, true)
fAdd('D', {dsS},0, "Mj"   ): $f.st.st_rmaj
fAdd('d', {dsS},0, "Mn"   ): $f.st.st_rmin
fAdd('i', {dsS},0, "inode"): $f.st.st_ino.uint
fAdd('l', {dsS},0, "l"    ): $f.st.st_mode.fmtKindCode
fAdd('L', {dsS},1, "L"    ): f.fmtClassCode
fAdd('x', {dsS},0,"LinExA"): fmtAttrCode(f.st.stx_attributes)
fAdd('Q', {dsA},0, "A"    ): ["", "+"][f.acl.int]
fAdd('e', {}   ,0, "e1"   ): $cg.ext1c(f.name.qualPath.cstring)
fAdd('E', {}   ,0, "e2"   ): $cg.ext2c(f.name.qualPath.cstring)
fAdd('@', {}   ,0, "I"    ): f.fmtIcon
fAdd('I', {}   ,0, "I"    ): f.fmtIcon
fAdd('t', {}   ,0, ""     ):(if cg.indent>0:repeat(' ',cg.indent*max(0,f.depth))
                             else: "")

template dBody(i): untyped {.dirty.} =
  if f.kind.len>i: cg.kinds[f.kind[i]].attr & f.kind[i].toHex & cg.a0 else: "xx"
fAdd('0', {dsS},0, "D0"): dBody(0)
fAdd('1', {dsS},0, "D1"): dBody(1)
fAdd('2', {dsS},0, "D2"): dBody(2)
fAdd('3', {dsS},0, "D3"): dBody(3)
fAdd('4', {dsS},0, "D4"): dBody(4)
fAdd('5', {dsS},0, "D5"): dBody(5)
fAdd('6', {dsS},0, "D6"): dBody(6)
fAdd('7', {dsS},0, "D7"): dBody(7)
fAdd('8', {dsS},0, "D8"): dBody(8)

template tBody(i): untyped {.dirty.} =
  if f.tKind.len>i: cg.kinds[f.tKind[i]].attr&f.tKind[i].toHex&cg.a0 else: "xx"
fAdd('9', {dsS},0, "L0"): tBody(0)
fAdd('.', {dsS},0, "L1"): tBody(1)
fAdd('/', {dsS},0, "L2"): tBody(2)

proc parseFormat(cf: var LsCf) =
  type State = enum inPrefix, inField
  var frst = true; var algn = '\0'
  var state = inPrefix
  var prefix = ""
  cf.fields.setLen 0
  for c in specifierHighlight(cf.format, fmtCodes, cf.plain):
    case state
    of inField:
      if c in {'-', '+'}: algn = c; continue  #Any number of 'em;Last one wins
      state = inPrefix
      try:
        let fmtE = fmtOf[c]
        let lA = if algn != '\0': algn=='-'   # User spec always wins else frst
                 else: (if frst: true else: fmtE.left) #..left else field dflt
        cf.fields.add (prefix[0..^1], lA, c, fmtE.hdr[0..^1], fmtE.fmt)
        cf.need = cf.need + fmtE.ds
        frst = false; algn = '\0'; prefix.setLen 0
      except Ce: Value !! "unknown format code " & c.repr
      if   c == 'U' and cf.usr.len == 0: cf.usr = users()
      elif c == 'G' and cf.grp.len == 0: cf.grp = groups()
      elif c == '0': cf.needKin = not cf.plain          #heuristic only
      elif c in {'f', 'F', '1'..'9', '.', '/'}: cf.needKin = true
      elif c == 'r' or c == 'R': cf.need.incl dsT
    of inPrefix:
      if c == '%': state = inField; continue
      prefix.add c

proc fieldF(cf: LsCf): int =  #Helper for zip (%f%R | %f%R%L etc.) to keep RHS
  result = -1                 #..maj col narrow & avoid high variation=>~dblspc.
  for j, fld in cf.fields:
    if fld.c in {'f', 'F'} and j+1 < cf.fields.len: return j

proc encodeHyperlink(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    if c.ord in 32..126:
      result.add c
    else:
      result.add '%'
      result.add toHex(ord(c), 2)

proc getHyperlinkPrefix(cf: LsCf, pathAbsolute: bool): string =
  let path =
    if pathAbsolute:
      ""
    elif cf.pfx.len == 0:
      cf.cwd & '/'
    elif cf.pfx == "//":
      "/"
    elif cf.pfx.isAbsolute:
      cf.pfx
    else:
      cf.cwd / cf.pfx
  result = "\e]8;;file://" & encodeHyperlink(cf.hostname & path)

proc format(cf: LsCf; filps: seq[ptr Fil]; ab0, ab1, wids: var seq[int];
            m, jRet: var int; reFit, toplevel: bool): seq[string] =
  let fj = if cf.unzipF: -1 else: cf.fieldF         #specific %[fF].. col zip
  m = if fj != -1: fj + 1 else: cf.fields.len
  let hdr = cf.header and filps.len > 0
  let i0 = if hdr: 1 else: 0                        #AKA hdr.int
  let n = filps.len + i0
  let pfx = if not toplevel and cf.hyperlink:
              getHyperlinkPrefix(cf, filps[0].name.isAbsolute) else: ""
  result.setLen(n * m)
  wids.setLen(n * m)
  if reFit:
    ab0.setLen(n); ab1.setLen(n)
    for j in 0 ..< cf.fields.len:
      if cf.fields[j].c == 'f': jRet = j
  for i in 0 ..< n:
    var k = 0                                        #k is the output j
    for j in 0 ..< cf.fields.len:
      let idx = m * i + k
      if hdr and i == 0:
        result[idx].add cf.fields[j].hdr
      else:
        let file = filps[i-i0]
        if cf.fields[j].prefix.len > 0:
          result[idx].add cf.fields[j].prefix
        if reFit and cf.fields[j].c == 'f':
          ab0[i] = result[idx].len + file[].kattr.len
        let formatted = cf.fields[j].fmt(file[])
        if formatted.len > 0:
          if cf.hyperlink:
            result[idx].add if toplevel:
              getHyperlinkPrefix(cf, file[].name.isAbsolute)
            else:
              pfx
            result[idx].add file[].name.encodeHyperlink
            result[idx].add "\e\\"
          result[idx].add formatted
          if cf.hyperlink:
            result[idx].add "\e]8;;\e\\"
        if reFit and cf.fields[j].c == 'f':
          ab1[i] = result[idx].len - cf.a0.len
      wids[idx] = (if cf.fields[j].left: -1 else: 1) *
                  (if cf.plain and not cf.hyperlink:
                    result[idx].runeLen else: result[idx].printedLen)
      if j < (if fj != -1: fj else: m): k.inc

var efRefDid = false
proc efRef(qp: cstring): cstring =
  if efRefDid: return
  stderr.write("%e/%E referenced but no --ext[12] setting given\n")
  efRefDid = true

proc fin*(cf: var LsCf, cl0: seq[string] = @[], cl1: seq[string] = @[],
          entry=Timespec(tv_sec: 0.Time, tv_nsec: 9.clong)) =
  ##Finalize cf ob post-user sets/updates, pre-``ls|ls1`` calls.  File ages are
  ##times relative to ``entry``.  Non-default => time of ``fin`` call.
  cf.t0 = if entry.tv_sec.clong==0 and entry.tv_nsec==9: getTime() else: entry
  if cf.n1: cf.nColumn = 1
  if cf.width == 0: cf.width = terminalWidth()
  if cf.recurse == 0: cf.recurse = 2147483647 #effectively infinite
  if cf.recurse != 0: cf.need.incl(dsD)       #Must type @least dirs to recurse
  cf.tests = builtin                          #Initially populate w/builtin
  cf.parseKind                                #.kind to tests additions
  cf.colors.textAttrRegisterAliases           #.colors => registered aliases
  cf.parseColor                               #.color => .attr
  cf.parseFilters                             #(in|ex)cl => sets s(in|ex)
  cf.parseOrder                               #.order => .cmps
  cf.parseAge                                 #.ageFmt => .tmFmt
  cf.parseFormat                              #.format => .fields
  cf.nAbb = parseAbbrev(cf.maxName)           #Finalize within each directory
  cf.tAbb = parseAbbrev(cf.maxTgt)
  cf.uAbb = parseAbbrev(cf.maxUnm); cf.uAbb.realize(cf.usr)
  cf.gAbb = parseAbbrev(cf.maxGnm); cf.gAbb.realize(cf.grp)
  if dsA in cf.need or dsC in cf.need: cf.need.incl(dsS)  #To cache EOPNOTSUPP
  cf.a0    = if cf.plain: "" else: textAttrOff
  cf.wrote = false
  cf.cl0   = cl0
  cf.cl1   = cl1
  try      : cf.cwd = getCurrentDir() # Caller can validly `lc` absolute paths
  except Ce: discard                  #.. from inside a deleted directory.
  template x(e, d): untyped =
    cast[ExtFmt](if e.len > 0: e.loadSym else: cast[pointer](d))
  cf.ext1c = x(cf.ext1, efRef)
  cf.ext2c = x(cf.ext2, efRef)
  cg       = cf.addr                          #Init global ptr

###### DRIVE ABOVE: BUILD AN FS-INTERROGATED AND CLASSIFIED Fil OBJECT

proc classify(cf: LsCf, f: var Fil, d: int): uint8 = #assign format kind [d]
  result = (cf.kinds.len - 1).uint8                  #all d use 1 unknown slot
  for i, k in cf.ukind[d]:
    if cf.kinds[k].test(f): return k.uint8

proc mkFil(cf: var LsCf; f: var Fil; name: string; dt: var int8, nDt:bool):bool=
  result = true                 #"Ok enough" unless early return says elsewise.
  var didLst = false            #dt clobbered when lstat was needed for it.
  var qP: string
  template iqP(): string = (if qP.len == 0: (qP = name.qualPath; qP) else: qP)
  f.name = name
  f.base = (1 + rfind(name, {DirSep, AltSep})).int16    #ix(basenm);0 if unqual
  f.sext = max(0, rfind(name, '.', f.base)).int16       #ix(shortest exten|0)
  f.lext = max(0, name.find('.', f.base)).int16         #ix(longest exten|0)
  if nDt and dt == DT_UNKNOWN:
    if lstat(iqP.cstring, f.st) == -1:  #vanished|->inaccessible since readdir
      stderr.write qP, ": ", strerror(errno), "\n"
      cf.nError.inc; return false
    didLst = true                       #could instead save old dt value
    dt = stat2dtype(f.st.st_mode)
  if dsS in cf.need:
    if cf.deref or (cf.tgtDref and dsT in cf.need): #Maybe clobber lstat w/stat
      f.brok = if stat(iqP.cstring, f.st) == -1: 2 else: 1
    elif not didLst:                    #Have not yet done lstat, but need to.
      if lstat(iqP.cstring,f.st) == -1: #vanished|->inaccessible since readdir
        stderr.write qP, ": ", strerror(errno), "\n"
        cf.nError.inc; return false
      if dt == DT_UNKNOWN: dt = stat2dtype(f.st.st_mode)
  f.dtype = dt
  if cf.usr.len > 0: f.usr = cf.usr.getOrDefault(f.st.st_uid, $f.st.st_uid)
  if cf.grp.len > 0: f.grp = cf.grp.getOrDefault(f.st.st_gid, $f.st.st_gid)
  if f.brok != 2:
    let d = f.st.st_dev
    if dsA in cf.need: f.acl=qP.getxattr("system.posix_acl_access", d) != -1 or
                 (f.isDir and qP.getxattr("system.posix_acl_default", d) != -1)
    when defined(linux):
      if dsC in cf.need: f.cap = qP.getxattr("security.capability", d) != -1
  if dt == DT_LNK and dsT in cf.need:
    f.tgt = Fil.new                     #zeros allocated data
    f.tgt.name = readlink(iqP, stderr)
    if f.tgt.name == "":
      cf.nError.inc; f.tgt = nil
    elif cf.tgtDref:                    #Below -> lstat? Maybe -L<number|enum>?
      f.tgt.brok = if stat(qP.cstring, f.tgt.st) == -1: 2 else: 1
      f.tgt.base = (1 + rfind(f.tgt.name, {DirSep, AltSep})).int16
      f.tgt.sext = max(0, rfind(f.tgt.name, '.', start=f.tgt.base)).int16
      f.tgt.lext = max(0, f.tgt.name.find('.', start=f.tgt.base)).int16
      f.tgt.dtype = stat2dtype(f.tgt.st.st_mode)
      if cf.needKin:                    #tgtDref populates f.st via stat.  So,
        when haveMagic:                 #..only dsNm really changes for classify
          if dsM in cf.need:
            f.tgt.mag = $magic_file(cf.mc, f.tgt.name.qualPath.cstring)
        f.tgt.kind = newSeq[uint8](cf.ukind.len)  #alloc did not init
        for d in 0 ..< cf.ukind.len: f.tgt.kind[d] = cf.classify(f.tgt[], d)
  if cf.needKin:                        #filter/sort may need even if cf.plain
    when haveMagic:
      if dsM in cf.need:
        f.mag = if cf.tgtDref and f.tgt != nil: f.tgt.mag else:
            $magic_file(cf.mc, cstring(if f.tgt != nil: f.tgt.name.qualPath
                                       else: iqP))
    f.kind.setLen(cf.ukind.len)
    for d in 0 ..< cf.ukind.len: f.kind[d] = cf.classify(f, d)

proc sortFmtWrite(cf: var LsCf, fils: var seq[Fil],
                  toplevel: bool) {.inline.} =   ###ONE-BATCH
  var nmAbb = cf.nAbb           #realize can mutate cf.nAbb; So use a copy.
  if nmAbb.isAbstract:
    var nms: seq[string]
    for f in fils: nms.add cf.maybeQuote(f.name)
    nmAbb.realize nms, cf.jobs, cf.jobsN
  if nmAbb.mx != 0:
    for i, f in fils: fils[i].abb = nmAbb.abbrev(f.name)
  var filps = newSeq[ptr Fil](fils.len)    #Fil is 200B-ish => sort by ptr
  for i in 0 ..< fils.len: filps[i] = fils[i].addr
  if cf.cmps.len > 0: filps.sort(multiLevelCmp)
  var ab0, ab1, wids: seq[int]
  var nrow, ncol, m, j: int
  let reFit = cf.reFit and nmAbb.isAbstract
  var strs = format(cf, filps, ab0, ab1, wids, m, j, reFit, toplevel)
  for i in 0 ..< fils.len: fils[i].tgt = nil
  var colWs = layout(wids, cf.width, gap=1, cf.nColumn, m, nrow, ncol)
  if reFit:
    nmAbb.expandFit(strs, ab0, ab1, wids, colWs, cf.width, j, m, nrow, ncol)
  colPad(colWs, cf.width, cf.padMax, m)
  if cf.widest > 0: sortByWidth(strs, wids, m, nrow, ncol)
  stdout.write(strs, wids, colWs, m, nrow, ncol, cf.widest, "")

proc maybeGetDents(cf:var LsCf, path: string, dts: ptr seq[int8]): seq[string] =
  let fd = open(path, O_RDONLY)         #This proc may be getdents-optimizable
  if fd == -1:
    stderr.write "open(\"", path, "\"): ", strerror(errno), "\n"
    cf.nError.inc; return
  var st: Stat                          #block infinite recursion loops
  discard fstat(fd, st)
  if not cg.did.containsOrIncl((st.st_dev, st.st_ino)):
    return getDents(fd, st, dts)        #closes the open directory
  stderr.write "\nlc: skipping symlink loop at \"", path, "\"\n"
  dts[].add 1                           #Inform caller recursive loop detected

proc ls*(cf: var LsCf, paths: seq[string], pfx="", r=0, dts: ptr seq[int8]=nil,
         toplevel=true) =
  proc maybePfx(cwd, h: string): string =
    if h.startsWith("/"): h else: cwd & "/" & h
  template zeroCont(x) {.dirty.} =
    x.tgt = nil; zeroMem(x.addr, x.sizeof); continue
  let pf = if pfx.len > 0 and pfx != ".": pfx & $DirSep else: ""
  cg.pfx = pf
  cf.dirLabel = r > 0 or paths.len > 1 or cf.recurse > 1 or cf.indent > 0
  var fils = newSeq[Fil](paths.len)
  var dirs: seq[int]
  var labels: seq[string]
  let recurse = not cf.dirs and r < cf.recurse
  var j = 0
  var tot = 0'u
  for i, p in paths:
    var dt: int8 = if dts != nil: dts[][i] else: 0
    if not cf.mkFil(fils[j], p, dt, dsD in cf.need or recurse): fils[j].zeroCont
    fils[j].depth = r.int16
    tot += fils[j].st.st_blocks.uint
    if r == 0 or not cf.failsFilters(fils[j]):  #A kept entry
      if dt == DT_DIR or (cf.deref and dt == DT_LNK and fils[j].isDir):
        if recurse:                             #will recurse: add dirs,labels
          dirs.add(i); labels.add fils[j].fmtName(pf & p, abbrev=false)
          if r == 0: fils[j].zeroCont           #skip dir paths @1st recurse lvl
      j.inc
    else: fils[j].zeroCont                      #Re-use [j] safely
  if cf.total and r > 0: stdout.write "total ", tot div bDiv, "\n"
  if j > 0: fils.setLen j; cf.sortFmtWrite(fils, toplevel); cf.wrote = true
  if recurse:
    let indent = if cg.indent>0: repeat(' ', cg.indent*max(0, r)) else: ""
    for k, i in dirs:
      let here = pf & paths[i]
      var dts: seq[int8]                        #Inits to 0 == DT_UNKNOWN
      let ents = cf.maybeGetDents(here, dts.addr)
      if cf.dirLabel and ents.len == dts.len:   #Blocked rec.loop gets no label
        if not cf.dense and cf.wrote: stdout.write "\n"
        stdout.write indent, labels[k], ":\n"; cf.wrote = true
      cf.dirLabel = true
      var c: LsCf; let cg0 = cg                 #Maybe merge local extras
      if cf.extra.len > 0 and (cf.recurse == 1 or (cf.recurse > 1 and
           (cf.extra.endsWith("//") or cf.extra.endsWith("/.")))):
        var d = if not cf.extra.startsWith('/'): maybePfx(cf.cwd, here)
                else: simplifyPath(cf.extra & "/" & maybePfx(cf.cwd, here),true)
        while true:
          try:
            var merged = cf.cl0; merged.add cfToCL(d & "/.lc", quiet=true)
            merged.add cf.cl1; c = lsCfFromCL(merged)
            c.fin(cf.cl0, cf.cl1, cf.t0); cg = c.addr
            break                               #done at first success
          except Ce: discard                    #tweak files are very optional
          if not cf.extra.endsWith('/') or
               (cf.extra == "./" and d.len < 1) or d.len < cf.extra.len:
            break           #Either not looking in par dirs or topped out @root
          d = d.parentDir   #No .lc file here, look in parent
      cg[].ls(ents, here, r + 1, dts.addr, toplevel=false)
      cg = cg0

when isMainModule:                      ### DRIVE COMMAND-LINE INTERFACE
  const lcEtc {.strdefine.} = ""    # Override smart-ish etc search w/-d:lcEtc=
  let argv {.importc: "cmdLine".}: cstringArray   #NOTE MUST be in main module
  from std/nativesockets import getHostname
  try:
    let cfd = getEnv("LC_CONFIG", getConfigDir() & "/lc")
    var cl0 = cfToCL(if cfd.dirExists: cfd&"/config" else: cfd, "", true, true)
    cl0.add envToCL("LC")   # Can use e.g. LC=-w0 to cfg all in wrapper script
    if cl0.len == 0:        # No config; Try "system" config
      let etc = if lcEtc.len > 0: lcEtc else: argv.findAssociated("etc/lc")
      cl0.add cfToCL(if etc.dirExists: etc/"config" else: etc, "", true, true)
    let nCl0 = cl0.len; cl0.add os.commandLineParams()
    var cf = lsCfFromCL(cl0); cl0.setLen nCl0
    cf.fin(cl0, os.commandLineParams() - cf.paths)
    if cf.hyperlink:
      cf.hostname = getHostname()
    cf.ls(if cf.paths.len > 0: cf.paths else: @[ "." ])
    quit(min(127, cf.nError))
  except HelpOnly, VersionOnly: quit(0)
  except ParseError: quit(1)
