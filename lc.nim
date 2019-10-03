import os,posix, sets,tables, terminal,strutils,algorithm, nre, critbits,cligen,
 cligen/[osUt,posixUt,unixUt,statx,strUt,textUt,humanUt,abbrev,cfUt,tab,magic]

type       # fileName Dtype Stat lnTgt ACL Magic Capability
  DataSrc* = enum dsD, dsS, dsT, dsA, dsM, dsC      ## sources of meta data
  DataSrcs* = set[DataSrc]

  Fil = object      #Abstract file metadata including classification stuff
    st: Statx                    ##filesystem metadata
    kind: seq[uint8]             ##kind nums for independent format dimensions
    dtype, r, w, x, brok: int8   ##dtype & file perms (0 unknown, 1: no, 2: yes)
    acl, cap: bool               ##flags: has an ACL, has a Linux capability
    base, sext, lext: int16      ##offset of basenms,shortest|longest extens
    usr, grp, name, abb, mag: string ##ids; here to sort, name, abbrev, magic
    tgt: ptr Fil                 ##symlnk target

  Test  = tuple[ds: DataSrcs, test: proc(f:var Fil):bool]          #unattributed
  Kind  = tuple[attr:string, kord:uint8, icon:string, test:proc(f:var Fil):bool]
  Cmp   = tuple[sgn: int, cmp: proc(x, y: ptr Fil): int]           #1-level cmp
  Field = tuple[prefix: string; left: bool; c: char; hdr: string,  #1-field fmt
                fmt: proc(f: var Fil): string]

  LsCf* = object    #User set config fields early; Computed/intern fields later
    kind*, colors*, color*, ageFmt*: seq[string]            ##usrDefd kind/colrs
    incl*, excl*: seq[string]                               ##usrDefd filters
    order*, format*, glyph*, extra*, ext1*, ext2*,
     maxName*, maxTgt*, maxUnm*, maxGnm*: string
    recurse*, nColumn*, padMax*, widest*, width*: int       ##recursion,tweaks
    dirs*, binary*, dense*, deref*, tgtDref*, plain*,       ##various bool flags
     unzipF*, header*, access*, total*, quote*, n1*: bool
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
    when haveMagic: mc: magic_t

###### Documentation/CLI; Early to use lsCfFromCL in for local config tweaks.
const nimbleFile = staticRead "lc.nimble"
clCfg.version = nimbleFile.fromNimble "version"
let cfDfl* = LsCf(format:"%f", glyph:" -> ", recurse:1, nColumn:999, padMax:999)

const ess: seq[string] = @[]
initGen(cfDfl, LsCf, "paths", @["ALL AFTER paths"], "inLsCf")
dispatchGen(inLsCf,"lc",usage="Usage:\n  $command $args\n${doc}$options",doc="""
(L)ist (Classified/Colored/Customized/CBlake) files in `paths` (CWD if empty)
in a filtered/sorted/tabular way (like ls with better idea factoring).  Pre-cmd
options from ${LC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}/lc & $LC.  Config
files support [include__{relPath|ENVVAR}] & take only long-form options.
The following 1-letter codes work for BOTH format AND order specs:
  f fileName      u numeric uid a|A access time  i inode-number 0 ord0|fmtDim0
  F baseName      U user name   m|M modify time  k st_blksize   1 ord1|fmtDim1
  s humRdSz|devNo g numeric gid c|C create time  D major devno  2 ord2|fmtDim2
  K file blocks   G group name  v|V vsnTm=mx(cm) d minor devno
  n link count    p rwx perms   b|B birth time   o %sz occupied
For format specs only capitals mean an alternate time format & there are also:
  r readlink         S size(bytes)  l ls-KindCode(dl-..)  x stxAttrCode
  R lnk w/color tgt  P Octal Perms  L ls-KindCode(/@*|=)  Q "+" if hasAcl
  Z selinux label    q spaced perm  e|E ExternProgOutput  @ 4th:Col Of colorKind
  3-8 fmtDim3-8    9./ tgtFmtDim0-2
For MULTI-LEVEL order specs only +- mean incr(dfl)/decreasing & there are also:
  e shortestExtension(last.->end)   N numericFileName A abbreviatedFileName
  E longestExtension(first.->end)   L fileNameLength  3-5,6-8,9./ ~ fK,tO,tK 0-2
ATTR specs: plain, bold, italic, underline, blink, inverse, struck, NONE, black,
red, green, yellow, blue, purple, cyan, white; UPPERCASE =>HIGH intensity while
"on_" prefix => BACKGROUND color; 256-color xterm attrs are [fb][0..23] for
FORE/BACKgrnd grey scale & [fb]RGB a 6x6x6 color cube; each [RGB] is on [0,5].
xterm/st true colors are [fb]HHHHHH (usual R,G,B mapping).  Field AND strftime
formats both accept %{ATTR1 ATTR2..}CODE to set colors for any %CODE field.""",
            help = { "kind":  """file kinds: NAME<WS>RELATION<WS>PARAMS
where <RELATION> says base names match:
  cset param=str of chars base name can have
  SFX|sfx  case-(|in)sensitive name suffixes
  PFX|pfx  case-(|in)sensitive name prefixes
  uid|gid  numeric uids|gids (or Uid|Gid)
  usr|grp  exact string users or groups
  pcr  White-sep Perl-Compatible Regexes
  mag  pcRegexs against file(1) type descrip
  any|all|none  earlier defd kind test names
  ext      shell command (exit stat of cmd)
BUILTIN: reg dir bdev cdev fifo sock symlink
 +-sym hard exec s[ug]id tmpD worldW unR odd
 stx IMMUT APPEND COMPR ENCRYP NODUMP AUTOMT
 xatr: CAP hasLinuxCapability ACL hasACL""",
                      "colors" : "color aliases; Syntax: name = ATTR1 ATTR2..",
                      "color"  : """text attrs for file kind/fields. Syntax:
  NAME[[:KEY][:DIM]]<WS>ATTR<WS>ATTR..
NAME=kind nm as above|size{BKMGT}|perm{0-7}
KEY=a 0..255 sort/ord key, DIM=dimension no.
ATTR=attr specs as above""",
                      "ageFmt":"""Syntax: FILEAGE'@'[-+]STRFTIME_FMT where:
  FILEAGE in {seconds,'FUTURE','ANYTIME'},
  + means AltFmt, - means plain mode fmt,
  %CODEs are any strftime + %<DIGIT>.""",
                      "format" : "\"%[-]a %[-]b\" l/r aligned fields to ls",
                      "order"  : "[-]x[-]y[-]z.. keys to sort files by",
                      "recurse": "recurse N levels; 0 => unbounded",
                      "dirs"   : "list dirs as themselves, not contents",
                      "binary" : "K=size/1024, M=size/1024/1024 (vs /1000..)",
                      "dense"  : "no blanks between multiple dir listings",
                      "deref"  : "deref symlinks generally",
                      "access" : "use 3*access(2) not st_mode for RWX perms",
                      "plain"  : "plain text; aka no color escape sequences",
                      "header" : "add a row at start of data with col names",
                      "padMax" : "max spaces by which to pad major columns",
                      "nColumn": "max major columns to use",
                      "widest" : "only list this many widest entries",
                      "width"  : "override auto-detected terminal width",
                      "maxName": "auto|M[,head(M/2)[,tail(M-hd-sep)[,sep(*)]]]",
                      "maxTgt" : "like maxName for symlink targets; No auto",
                      "maxUnm" : "like maxName for user names",
                      "maxGnm" : "like maxName for group names",
                      "unzipF" : "negate default all-after-%[fF] column zip",
                      "glyph"  : "how to render arrow in %[rR] formats",
                      "extra"  : "add cf ARG~/.lc (.=SAME,trl/=PARS,//PR,/.r)",
                      "tgtDref": "fully classify %R formats on their own",
                      "ext1"   : "external shell cmd to get output for %e",
                      "ext2"   : "external shell cmd to get output for %E",
                      "quote"  : "quote filenames with unprintable chars",
                      "n1"     : "same as -n1",
                      "total"  : "print total of blocks before entries",
                      "excl"   : "kinds to exclude",
                      "incl"   : "kinds to include" },
            short = { "deref":'L', "dense":'D', "access":'A', "binary":'B',
                      "width":'W',"padMax":'P', "incl":'i',"excl":'x', "n1":'1',
                      "header":'H', "maxTgt":'M', "maxUnm":'U', "maxGnm":'G',
                      "tgtDref":'l', "version":'v', "extra":'X', "colors":'C',
                      "ext1":'e', "ext2":'E' },
            alias = @[ ("Style",'S',"DEFINE an output style arg bundle",@[ess]),
                       ("style",'s',"APPLY an output style",@[ess]) ],
            dispatchName = "lsCfFromCL")
var cg: ptr LsCf            #Lazy way out of making many little procs take LsCf

when NimVersion < "0.20.0":
  proc `[]`[T](s: seq[T]; i: uint8): T = s[i.int]
  proc `[]`(s: string; i: uint): char = s[i.int]

###### BUILT-IN CLASSIFICATION TESTS
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
      result = ((f.st.st_mode.cint and S_IZOTH)!=0) or
              (((f.st.st_mode.cint and S_IZUSR)!=0) and myUid == f.st.st_uid) or
              (((f.st.st_mode.cint and S_IZGRP)!=0) and f.st.st_gid in myGrp)
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
proc isStickyDir(f: var Fil): bool = (f.st.st_mode and 0o1000) != 0 and f.isDir
proc util(st: Statx): float =
  if st.st_blocks == 0 and st.st_size == 0: 100.0
  else: st.st_blocks.float * 51200.0 / max(st.st_size, 1).float

var builtin: CritBitTree[Test]
template tAdd(name, ds, t: untyped) {.dirty.} =
  builtin[name] = (ds, proc(f: var Fil): bool {.closure.} = t)
tAdd("unknown",{})   : true
tAdd("reg"    ,{dsD}): f.stModeOrDtype(S_ISREG , DT_REG)
tAdd("dir"    ,{dsD}): f.stModeOrDtype(S_ISDIR , DT_DIR)
tAdd("bdev"   ,{dsD}): f.stModeOrDtype(S_ISBLK , DT_BLK)
tAdd("cdev"   ,{dsD}): f.stModeOrDtype(S_ISCHR , DT_CHR)
tAdd("fifo"   ,{dsD}): f.stModeOrDtype(S_ISFIFO, DT_FIFO)
tAdd("socket" ,{dsD}): f.stModeOrDtype(S_ISSOCK, DT_SOCK)
tAdd("symlink",{dsD}): f.stModeOrDtype(S_ISLNK , DT_LNK)      #Any symlink
tAdd("-sym"   ,{dsD}): f.dtype == DT_LNK and not f.maybeSt    #Broken symlink
tAdd("+sym"   ,{dsD}): f.dtype == DT_LNK and f.maybeSt        #Good symlink
tAdd("exec"   ,{dsD}): not (f.isDir or f.isLnk) and f.maybeSt and f.xOk
tAdd("hard"   ,{dsD}): not f.isDir and f.maybeSt and f.st.st_nlink > 1.Nlink
tAdd("suid"   ,{dsD}): f.isReg and f.maybeSt and(f.st.st_mode and 0o4000)!=0 and
                       (f.st.st_mode and 0o0111) != 0         #exec by *someone*
tAdd("sgid"   ,{dsS}): (f.st.st_mode and 0o2000) != 0
tAdd("tmpD"   ,{dsS}): f.isStickyDir and (f.st.st_mode and 7) != 0
tAdd("worldW" ,{dsS}): (f.st.st_mode and 2) != 0 and f.dtype != DT_LNK and
                       not f.isStickyDir
tAdd("unR"    ,{dsS}): not f.rOk or (f.isDir and not f.xOk)
tAdd("odd"    ,{dsS}):    #Check very odd st_mode's. Rare but legit wr-only in:
  let m = f.st.st_mode    #.. /dev/tty* /var/cache/man /var/spool /proc /sys
  ((m and 0o4000)!=0 and ((m and 0o111)==0 or not f.isReg)) or  #suid&(!x|!reg)
   ((m and 0o2000)!=0 and (m and 0o010)==0) or                  #sgid & g-x
   (f.isStickyDir and (m and 2) == 0) or                        #sticky & !o+w
   not (m.S_IUSR >= m.S_IGRP and m.S_IGRP >= m.S_IOTH) or       #!(u >= g >= o)
   (m.S_IUSR and 0o6)==2 or (m.S_IGRP and 0o6)==2 or (m.S_IOTH and 0o6)==2 #w&!r

when haveStatx:          #Linux only via statx
 tAdd("IMMUT" ,{dsS}):(f.st.stx_attributes and STATX_ATTR_IMMUTABLE.uint64)!=0
 tAdd("APPEND",{dsS}):(f.st.stx_attributes and STATX_ATTR_APPEND.uint64)!=0
 tAdd("COMPR" ,{dsS}):(f.st.stx_attributes and STATX_ATTR_COMPRESSED.uint64)!=0
 tAdd("ENCRYP",{dsS}):(f.st.stx_attributes and STATX_ATTR_ENCRYPTED.uint64)!=0
 tAdd("NODUMP",{dsS}):(f.st.stx_attributes and STATX_ATTR_NODUMP.uint64)!=0
 tAdd("AUTOMT",{dsS}):(f.st.stx_attributes and STATX_ATTR_AUTOMOUNT.uint64)!=0
when defined(linux): tAdd("CAP",{dsC}): f.cap
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

proc testStatus(cmd: string; f: var Fil): bool= #Ultimate user-defined kind test
  putEnv("FILE_NAME", f.name); putEnv("FILENAME", f.name) #XXX Replace w/dlopen
  try: result = execShellCmd(cmd) == 0          #Onus is on user to exit 0 for
  except: discard                               #.."passes",otherwise for "not".

proc addPCRegex(cf: var LsCf; mode, nm, s: string) =    #Q: add flags/modes?
  var rxes: seq[Regex]
  for pattern in s.splitWhitespace: rxes.add pattern.re
  cf.tests[nm] = ({}, proc(f: var Fil): bool = rxes.testPCRegex f)

proc addCSet(cf: var LsCf; nm, s: string) = #WTF: If this code is inlined into
  var cs: set[char]                         #..parseKind then closures break.
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
    except: raise newException(ValueError, "bad kind: \"" & t & "\"")
  cf.tests[nm] = (ds, proc(f: var Fil): bool = tester(tsts, f))

proc addStatus(cf: var LsCf; nm, s: string) =
  cf.tests[nm] = ({}, proc(f: var Fil): bool = s.testStatus(f))

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
    if col.len < 3: raise newException(ValueError, "bad kind: \"" & kin & "\"")
    if   col[1].toLower == "pcr": cf.addPCRegex(col[1], col[0], col[2])
    elif col[1] == "cset": cf.addCSet(col[0], col[2])
    elif col[1].toLower.endsWith("fx"): cf.addPreSuf(col[1][0], col[0], col[2])
    elif col[1].endsWith("id"):cf.addOwnId(col[1][0].toLowerAscii,col[0],col[2])
    elif col[1] == "usr": cf.addOwner(col[1][0], col[0], col[2])
    elif col[1] == "grp": cf.addOwner(col[1][0], col[0], col[2])
    elif col[1] == "any": cf.addCombo(testAny, col[0], col[2])
    elif col[1] == "all": cf.addCombo(testAll, col[0], col[2])
    elif col[1] == "none": cf.addCombo(testNone, col[0], col[2])
    elif col[1] == "ext": cf.addStatus(col[0], col[2])
    elif col[1] == "mag": cf.addMagic(col[1], col[0], col[2])
    else: raise newException(ValueError, "bad kind: \"" & kin & "\"")

template get1(results, cb, nm, msg, allow) {.dirty.} =
  let results = cb.getAll(nm)
  if results.len > 1:
    if not (allow):
      stderr.write("Ambiguous " & msg & " prefix \"" & nm & "\".  Matches:\n  ",
                   results.keys.join("\n  "), "\n")
    raise newException(ValueError, "")
  elif results.len == 0:
    if not (allow):
      stderr.write("Unknown " & msg & " \"" & nm & "\".")
      let sugg = suggestions(nm, cb.keys, cb.keys)
      if sugg.len >= 1:
        stderr.write "  Maybe you meant one of:\n  ", sugg.join("\n  "), "\n"
      else: stderr.write "\n"
    raise newException(ValueError, "")

proc parseColors(cf: var LsCf) =
  for spec in cf.colors:
    let cols = spec.split('=')
    textAttrAlias(cols[0].strip, cols[1].strip)

proc parseColor(cf: var LsCf) =
  var unknown = 255.uint8
  for spec in cf.color:
    let cols = spec.splitWhitespace()
    if cols.len<2: raise newException(ValueError, "bad color: \"" & spec & "\"")
    let nmKoD = cols[0].split(':')
    let nm    = nmKoD[0].strip()
    let ko    = (if nmKoD.len>1: parseHexInt(nmKoD[1].strip()) else: 255).uint8
    let dim   = if nmKoD.len>2: parseInt(nmKoD[2].strip()) else: 0
    let icon  = if nmKoD.len>3: nmKoD[3] else: ""
    let attrs = textAttrOn(cols[1..^1], cf.plain)
    try:
      let allow = nm.len==5 and (nm.startsWith("size") or nm.startsWith("perm"))
      get1(ts, cf.tests, nm, "kind", allow)
      let test = ts[0].val
      let kno = cf.kinds.len.uint8                #Found test; add to used kinds
      cf.kslot[ts[0].key] = (kno, test.ds, dim)   #Record kind number, DataSrc
      add(cf.kinds, (attr: attrs, kord: ko, icon: icon, test: test.test))
      if dim + 1 > cf.ukind.len: cf.ukind.setLen(dim + 1)
      cf.ukind[dim].add kno
      cf.need = cf.need + test.ds
      if nm == "unknown": unknown = kno
    except:
      if nm.len == 5:
        if   nm.startsWith("size"):
          if nm[4] notin { 'B', 'K', 'M', 'G', 'T', 'S' }:
            raise newException(ValueError, "unknown color key: \""&nm&"\"")
          cf.attrSize[ord(nm[4]) - ord('A')] = attrs
        elif nm.startsWith("perm"):
          if nm[4] notin { '0' .. '7' }:
            raise newException(ValueError, "bad perm \""&nm&"\". Octal digit.")
          cf.attrPerm[ord(nm[4]) - ord('0')] = attrs
      else: raise newException(ValueError, "unknown color key: \""&nm&"\"")
  if unknown == 255:  #Terminate .kinds if usr did not specify attrs for unknown
   add(cf.kinds, ("", 255.uint8, "", cf.tests["unknown"].test))

###### FILTERING
proc compileFilter(cf: var LsCf, spec: seq[string], msg: string): set[uint8] =
  for nm in spec:
    try:
      get1(ks, cf.kslot, nm, "colored kind", false)
      let k = ks[0].val
      result.incl(k.slot)
      cf.need = cf.need + k.ds
      cf.needKin = true   #must fully classify if any kind is used as a filter
    except: raise newException(ValueError, msg & " name \"" & nm & "\"")

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
when NimVersion < "0.20.0": cmpOf = initTable[char, tuple[ds: DataSrcs, cmp: proc(x,y:ptr Fil):int]]()
template cAdd(code, ds, cmpr, T, data: untyped) {.dirty.} =
  cmpOf[code] = (ds, proc(a, b: ptr Fil): int {.closure.} =
                   proc get(f: Fil): T = data   #AVAILABLE: hjlqrtwxyz
                   cmpr(get(a[]), get(b[])))    #           ABCHIJMOPQRSTVWXYZ
cAdd('f', {}   , cmp , string  ): f.name
cAdd('A', {}   , cmp , string  ): f.abb
cAdd('F', {}   , cmp , string  ): f.name[f.base..^1]
cAdd('e', {}   , cmpN, string  ): f.name[f.sext..^1]
cAdd('E', {}   , cmpN, string  ): f.name[f.lext..^1]
cAdd('N', {}   , cmpN, string  ): f.name
cAdd('L', {}   , cmp , uint    ): f.abb.len.uint
cAdd('s', {dsS}, cmp , uint    ): f.st.st_size.uint
cAdd('K', {dsS}, cmp , uint    ): f.st.st_blocks.uint
cAdd('k', {dsS}, cmp , uint    ): f.st.st_blksize.uint
cAdd('n', {dsS}, cmp , uint    ): f.st.st_nlink.uint
cAdd('u', {dsS}, cmp , uint    ): f.st.st_uid.uint
cAdd('g', {dsS}, cmp , uint    ): f.st.st_gid.uint
cAdd('U', {dsS}, cmp , string  ): f.usr  #Could do a hash lookup each time here,
cAdd('G', {dsS}, cmp , string  ): f.grp  #..but usr/grp names are usually short.
cAdd('p', {dsS}, cmp , uint    ): f.st.st_mode.uint and 4095
cAdd('a', {dsS}, cmp , Timespec): f.st.st_atim
cAdd('m', {dsS}, cmp , Timespec): f.st.st_mtim
cAdd('c', {dsS}, cmp , Timespec): f.st.st_ctim
cAdd('v', {dsS}, cmp , Timespec): f.st.st_vtim
cAdd('b', {dsS}, cmp , Timespec): f.st.st_btim
cAdd('D', {dsS}, cmp , Dev     ): f.st.st_rmaj
cAdd('d', {dsS}, cmp , Dev     ): f.st.st_rmin
cAdd('i', {dsS}, cmp , uint    ): f.st.st_ino.uint
cAdd('o', {dsS}, cmp , float   ): f.st.util
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
  var cmpEntry: tuple[ds: DataSrcs, cmp: proc(x, y: ptr Fil): int]
  for c in cf.order:
    if   c == '-': sgn = -1; continue
    elif c == '+': sgn = +1; continue
    try   : cmpEntry = cmpOf[c]
    except: raise newException(ValueError, "unknown sort key code " & c.repr)
    cf.cmps.add((sgn, cmpEntry.cmp))
    cf.need = cf.need + cmpEntry.ds
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
    if aF.len != 2: raise newException(ValueError, "bad ageFmt:\"" & aFs & "\"")
    if aF[0].startsWith('+'): #2**31 =~ 68 yrs in future from when fin is run.
     try   : cf.tmFmtU.add((parseInt(aF[0]), hl(aF[1], strftimeCodes,cf.plain)))
     except: cf.tmFmtU.add((-2147483648.int, hl(aF[1], strftimeCodes,cf.plain)))
    elif aF[0].startsWith('-'): #plain mode formats
     try:    cf.tmFmtP.add((-parseInt(aF[0]),hl(aF[1], strftimeCodes,cf.plain)))
     except: cf.tmFmtP.add((-2147483648.int, hl(aF[1], strftimeCodes,cf.plain)))
    else:
     try   : cf.tmFmtL.add((parseInt(aF[0]), hl(aF[1], strftimeCodes,cf.plain)))
     except: cf.tmFmtL.add((-2147483648.int, hl(aF[1], strftimeCodes,cf.plain)))

proc kattr(f: Fil): string =
  for e in f.kind: result.add cg.kinds[e].attr

proc maybeQuote(cf: LsCf, path: string): string {.inline.} =  #WTF safeUnixChars
  if cf.quote: path.quoteShellPosix else: path                #..should incl ','

proc fmtName(f: Fil, p: string, abbrev=true): string =
  f.kattr & (if abbrev: f.abb else: cg[].maybeQuote(p)) & cg.a0

proc fmtTgtD(f: Fil): string =  #Colorize link targets (in deref|tgtDref mode)
  if cg.deref: return           #..according to stat|string type of *target*.
  if f.dtype != DT_LNK: return
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

proc fmtSzDevNo(st: Statx): string =
  proc sizeFmt(sz: string): string =            #colorized file size
    if sz[^1] in { '0' .. '9'}:
      cg.attrSize[ord('B') - ord('A')] & cg[].sp(st) & sz & cg.a0
    else:
      cg.attrSize[ord(sz[^1]) - ord('A')] & cg[].sp(st) & sz & cg.a0
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
  for tup in tfs:
    let (age, fmt) = tup                      #Can be in for loop @>=Nim-0.20.0
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
  if (m and 0o4000) != 0 and (m and 0o100) != 0: result[2]   = 's' #setuid,+x
  if (m and 0o4000) != 0 and (m and 0o100) == 0: result[2]   = 'S' #setuid,noX
  if (m and 0o2000) != 0 and (m and 0o010) != 0: result[5+o] = 's' #setgid,+x
  if (m and 0o2000) != 0 and (m and 0o010) == 0: result[5+o] = 'S' #setgid,noX
  if (m and 0o1000) != 0 and (m and 0o001) != 0: result[8+o] = 't' #sticky,+x
  if (m and 0o1000) != 0 and (m and 0o001) == 0: result[8+o] = 'T' #sticky,noX

proc fmtOperm(f: var Fil): string =
  let p = (f.rOk.uint shl 2) or (f.wOk.uint shl 1) or (f.xOk.uint)
  cg.attrPerm[p] & toOct(f.st.st_mode.int and 4095, 4) & cg.a0

proc fmtKindCode(st_mode: Mode): char =    #12=sticky,su,sg+9bits of UGO perms
  "-pc-d-b---l-s---"[st_mode.uint shr 12 and 0xF]  #Pretty standard across OSes

proc fmtAttrCode(stx_attr: uint64): string =
  when haveStatx:
    if   (stx_attr and STATX_ATTR_IMMUTABLE.uint64 ) != 0: "Im"
    elif (stx_attr and STATX_ATTR_APPEND.uint64    ) != 0: "Ap"
    elif (stx_attr and STATX_ATTR_COMPRESSED.uint64) != 0: "Cp"
    elif (stx_attr and STATX_ATTR_ENCRYPTED.uint64 ) != 0: "Ec"
    elif (stx_attr and STATX_ATTR_NODUMP.uint64    ) != 0: "Nd"
    elif (stx_attr and STATX_ATTR_AUTOMOUNT.uint64 ) != 0: "Am"
    else: "--"
  else: "--"

proc toHex(i: uint8): string = toHex(i.BiggestInt, 2)

proc fmtClassCode(f: var Fil): string =
  if   f.stModeOrDtype(S_ISDIR , DT_DIR) : result.add '/'
  elif f.stModeOrDtype(S_ISLNK , DT_LNK) : result.add '@'
  elif f.stModeOrDtype(S_ISFIFO, DT_FIFO): result.add '|'
  elif f.stModeOrDtype(S_ISSOCK, DT_SOCK): result.add '='
  elif f.xOk                             : result.add '*'

proc slurp(cmd, name: string): string =         #Ultimate user-defined fmt field
  putEnv("FILE_NAME", name); putEnv("FILENAME", name)
  try:                                          #Onus is on user to keep output
    let f = popen(cmd.cstring, "r".cstring)     #..easy on tabulation INCLUDING
    result = f.readAll                          #..stripping newlines with e.g.
    f.close                                     #.." | tr -d \\n".
  except: discard #XXX Should replace this with a dlopen()d shared lib call.

var fmtCodes: set[char]   #left below is just dflt alignment. User can override.
var fmtOf: Table[char, tuple[ds: DataSrcs; left: bool; hdr: string;
                 fmt: proc(x: var Fil): string]]
when NimVersion < "0.20.0": fmtOf = initTable[char, tuple[ds: DataSrcs; left: bool; hdr: string; fmt: proc(x:var Fil):string]]()
template fAdd(code, ds, left, hdr, toStr: untyped) {.dirty.} =
  fmtCodes.incl(code)                           #AVAILABLE: hjtyz HIJNOTWXYZ
  fmtOf[code] = (ds, left.bool, hdr, proc(f:var Fil):string {.closure.} = toStr)
fAdd('f', {}   ,1, " Nm"  ): f.fmtName(f.name)
fAdd('F', {}   ,1, " Bs"  ): f.fmtName(f.name[f.base..^1])
fAdd('r', {dsT},1, "ln"   ): f.fmtTgtU
fAdd('R', {dsT},1, "Ln"   ): f.fmtTgtD
fAdd('S', {dsS},0, "ByDv" ): fmtSzDevNoL(f.st)
fAdd('s', {dsS},0, "SzDv" ): fmtSzDevNo(f.st)
fAdd('K', {dsS},0, "Bk"   ): $f.st.st_blocks.uint
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
fAdd('x', {dsS},0, "XA"   ): fmtAttrCode(f.st.stx_attributes)
fAdd('Q', {dsA},0, "A"    ): ["", "+"][f.acl.int]
fAdd('e', {}   ,0, "e1"   ): slurp(cg.ext1, f.name)
fAdd('E', {}   ,0, "e2"   ): slurp(cg.ext2, f.name)
fAdd('@', {}   ,0, "I"    ): f.fmtIcon

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
  var leftMost = true; var algn = '\0'
  var state = inPrefix
  var prefix = ""
  var fmtEntry: tuple[ds: DataSrcs; left: bool; hdr: string,
                      fmt: proc(f: var Fil): string]
  cf.fields.setLen(0)
  for c in specifierHighlight(cf.format, fmtCodes, cf.plain):
    case state
    of inField:
      if c in {'-', '+'}: algn = c; continue  #Any number of 'em;Last one wins
      state = inPrefix
      try   : fmtEntry = fmtOf[c]
      except: raise newException(ValueError, "unknown format code " & c.repr)
      let leftAlign = if algn != '\0': algn == '-' #User spec always wins else..
                      else:                        #..1st col left&field default
                        if leftMost: true else: fmtEntry.left
      cf.fields.add((prefix, leftAlign, c, fmtEntry.hdr, fmtEntry.fmt))
      leftMost = false; algn = '\0'
      prefix = ""
      cf.need = cf.need + fmtEntry.ds
      if   c == 'U' and cf.usr.len == 0: cf.usr = users()
      elif c == 'G' and cf.grp.len == 0: cf.grp = groups()
      elif c == '0': cf.needKin = not cf.plain          #heuristic only
      elif c in {'f', 'F', '1'..'9', '.', '/'}: cf.needKin = true
      elif c == 'r' or c == 'R': cf.need.incl(dsT)
    of inPrefix:
      if c == '%':
        state = inField
        continue
      prefix.add(c)

proc fieldF(cf: LsCf): int =  #Helper for zip (%f%R | %f%R%L etc.) to keep RHS
  result = -1                 #..maj col narrow & avoid high variation=>~dblspc.
  for j, fld in cf.fields:
    if fld.c in {'f', 'F'} and j+1 < cf.fields.len: return j

proc format(cf: LsCf, filps: seq[ptr Fil], wids: var seq[int],
            m: var int): seq[string] =
  let fj = if cf.unzipF: -1 else: cf.fieldF         #specific %[fF].. col zip
  m = if fj != -1: fj + 1 else: cf.fields.len
  let hdr = cf.header and filps.len > 0
  let n = if hdr: filps.len+1 else: filps.len
  let i0 = if hdr: 1 else: 0                        #AKA hdr.int
  result.setLen(n * m)
  wids.setLen(n * m)
  for i in 0 ..< n:
   var k = 0                                        #k is the output j
   for j in 0 ..< cf.fields.len:
    if hdr and i == 0:
      result[m*i+k].add cf.fields[j].hdr
    else:
      if cf.fields[j].prefix.len > 0:
        result[m*i+k].add cf.fields[j].prefix
      result[m*i+k].add cf.fields[j].fmt(filps[i-i0][])
    if cf.plain:  #Maybe auto-detect utf8 chars & use another flag here?
      wids[m*i+k] = (if cf.fields[j].left: -1 else: 1) * result[m*i+k].len
    else:
      wids[m*i+k] = (if cf.fields[j].left: -1 else: 1)*printedLen(result[m*i+k])
    if j < (if fj != -1: fj else: m): k.inc

proc fin*(cf: var LsCf, cl0: seq[string] = @[], cl1: seq[string] = @[],
          entry=Timespec(tv_sec: 0.Time, tv_nsec: 9.clong)) =
  ##Finalize cf ob post-user sets/updates, pre-``ls|ls1`` calls.  File ages are
  ##times relative to ``entry``.  Non-default => time of ``fin`` call.
  when NimVersion < "0.20.0":
    cf.usr = initTable[Uid, string](); cf.grp = initTable[Gid, string]()
    cf.did = initSet[PathId]()
  cf.t0 = if entry.tv_sec.clong==0 and entry.tv_nsec==9: getTime() else: entry
  if cf.n1: cf.nColumn = 1
  if cf.width == 0: cf.width = terminalWidth()
  if cf.recurse == 0: cf.recurse = 2147483647 #effectively infinite
  if cf.recurse != 0: cf.need.incl(dsD)       #Must type @least dirs to recurse
  cf.tests = builtin                          #Initially populate w/builtin
  cf.parseKind()                              #.kind to tests additions
  cf.parseColors()                            #.colors => registered aliases
  cf.parseColor()                             #.color => .attr
  cf.parseFilters()                           #(in|ex)cl => sets s(in|ex)
  cf.parseOrder()                             #.order => .cmps
  cf.parseAge()                               #.ageFmt => .tmFmt
  cf.parseFormat()                            #.format => .fields
  cf.nAbb = parseAbbrev(cf.maxName)           #Finalize within each directory
  cf.tAbb = parseAbbrev(cf.maxTgt)
  cf.uAbb = parseAbbrev(cf.maxUnm); cf.uAbb.realize(cf.usr)
  cf.gAbb = parseAbbrev(cf.maxGnm); cf.gAbb.realize(cf.grp)
  if dsA in cf.need or dsC in cf.need: cf.need.incl(dsS)  #To cache EOPNOTSUPP
  cf.a0    = if cf.plain: "" else: "\x1b[0m"
  cf.wrote = false
  cf.cl0   = cl0
  cf.cl1   = cl1
  cf.cwd   = getCurrentDir()
  cg       = cf.addr                          #Init global ptr

###### DRIVE ABOVE: BUILD AN FS-INTERROGATED AND CLASSIFIED Fil OBJECT
when NimVersion < "0.20.1": #Impl until 6dc648731145efbe736afea19f7dd5d262deb91d
  proc rfind(s: string, sub: char, start: int16): int =
    for i in countdown(s.high, start):
      if sub == s[i]: return i
    return -1

proc classify(cf: LsCf, f: var Fil, d: int): uint8 = #assign format kind [d]
  result = (cf.kinds.len - 1).uint8                  #all d use 1 unknown slot
  for i, k in cf.ukind[d]:
    if cf.kinds[k].test(f): return k.uint8

proc mkFil(cf: var LsCf; f: var Fil; name: string; dt: var int8, nDt:bool):bool=
  result = true                 #"Ok enough" unless early return says elsewise.
  var didLst = false            #dt clobbered when lstat was needed for it.
  var qP: string
  template iqP(): string = (if qP.len == 0: (qP = name.qualPath; qP) else: qP)
  shallowCopy(f.name, name)     #ls.args lives long enough.
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
    f.tgt = Fil.create                  #zeros allocated data
    f.tgt.name = readlink(iqP, stderr)
    f.tgt.name.GC_ref
    if f.tgt.name == "":
      cf.nError.inc; f.tgt.name.GC_unref; dealloc f.tgt; f.tgt = nil
    elif cf.tgtDref:                    #Below -> lstat? Maybe -L<number|enum>?
      f.tgt.brok = if stat(qP.cstring, f.tgt.st) == -1: 2 else: 1
      f.tgt.base = (1 + rfind(f.tgt.name, {DirSep, AltSep})).int16
      f.tgt.sext = max(0, rfind(f.tgt.name, '.', start=f.tgt.base)).int16
      f.tgt.lext = max(0, f.tgt.name.find('.', start=f.tgt.base)).int16
      f.tgt.dtype = stat2dtype(f.tgt.st.st_mode)
      if cf.needKin:                    #tgtDref populates f.st via stat.  So,
        when haveMagic:          #..only dsN really changes for classify
          if dsM in cf.need:
            f.tgt.mag = $magic_file(cf.mc, f.tgt.name.qualPath);f.tgt.mag.GC_ref
        f.tgt.kind = newSeq[uint8](cf.ukind.len)  #alloc did not init
        f.tgt.kind.GC_ref
        for d in 0 ..< cf.ukind.len: f.tgt.kind[d] = cf.classify(f.tgt[], d)
  if cf.needKin:                        #filter/sort may need even if cf.plain
    when haveMagic:
      if dsM in cf.need:
        f.mag = if cf.tgtDref and f.tgt != nil: f.tgt.mag else:
            $magic_file(cf.mc, if f.tgt != nil: f.tgt.name.qualPath else: iqP)
    f.kind.setLen(cf.ukind.len)
    for d in 0 ..< cf.ukind.len: f.kind[d] = cf.classify(f, d)

proc tfree(f: var Fil) {.inline.} =   #maybe release tgt.name, tgt.kind, tgt.mag
  if f.tgt != nil:
    f.tgt.name.GC_unref; f.tgt.kind.GC_unref
    when haveMagic:
      if f.tgt.mag != "": f.tgt.mag.GC_unref
    discard f.tgt.resize 0; f.tgt = nil

proc sortFmtWrite(cf: var LsCf, fils: var seq[Fil]) {.inline.} =   ###ONE-BATCH
  if cf.nAbb.isAbstract:
    var nms: seq[string]
    for f in fils: nms.add cf.maybeQuote(f.name)
    cf.nAbb.realize nms
  if cf.nAbb.mx == 0:           #Populate .abb w/name ref when not abbreviating
    for i, f in fils: fils[i].abb.shallowCopy fils[i].name #..s.t. just use .abb
  else:
    for i, f in fils: fils[i].abb = cf.nAbb.abbrev(f.name)
  var filps = newSeq[ptr Fil](fils.len)    #Fil is 200B-ish => sort by ptr
  for i in 0 ..< fils.len: filps[i] = fils[i].addr
  if cf.cmps.len > 0: filps.sort(multiLevelCmp)
  var wids: seq[int]
  var nrow, ncol, m: int
  var strs = format(cf, filps, wids, m)
  for i in 0 ..< fils.len: fils[i].tfree
  var colWs = layout(wids, cf.width, gap=1, cf.nColumn, m, nrow, ncol)
  colPad(colWs, cf.width, cf.padMax, m)
  #XXX If -F/--reFit then re-format here w/partially unabbreviated names,tgts
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

proc ls*(cf: var LsCf, paths: seq[string], pfx="", r=0, dts: ptr seq[int8]=nil)=
  proc maybePfx(cwd, h: string): string =
    if h.startsWith("/"): h else: cwd & "/" & h
  template zeroCont(x) {.dirty.} =
    x.tfree; zeroMem(x.addr, x.sizeof); continue
  let pf = if pfx.len > 0 and pfx != ".": pfx & $DirSep else: ""
  shallowCopy(cg.pfx, pf)               #only need pfx for duration of this proc
  cf.dirLabel = r > 0 or paths.len > 1 or cf.recurse > 1
  var fils = newSeq[Fil](paths.len)
  var dirs: seq[int]
  var labels: seq[string]
  let recurse = not cf.dirs and r < cf.recurse
  var j = 0
  var tot = 0
  for i, p in paths:
    var dt: int8 = if dts != nil: dts[][i] else: 0
    if not cf.mkFil(fils[j], p, dt, dsD in cf.need or recurse): fils[j].zeroCont
    tot += fils[j].st.st_blocks
    if r == 0 or not cf.failsFilters(fils[j]):  #A kept entry
      if dt == DT_DIR or (cf.deref and dt == DT_LNK and fils[j].isDir):
        if recurse:                             #will recurse: add dirs,labels
          dirs.add(i); labels.add fils[j].fmtName(pf & p, abbrev=false)
          if r == 0: fils[j].zeroCont           #skip dir paths @1st recurse lvl
      j.inc
    else: fils[j].zeroCont                      #Re-use [j] safely
  if cf.total and r > 0: stdout.write "total ", tot, "\n"
  if j > 0: fils.setLen j; cf.sortFmtWrite fils; cf.wrote = true
  if recurse:
    for k, i in dirs:
      let here = pf & paths[i]
      var dts: seq[int8]                        #Inits to 0 == DT_UNKNOWN
      let ents = cf.maybeGetDents(here, dts.addr)
      if cf.dirLabel and ents.len == dts.len:   #Blocked rec.loop gets no label
        if not cf.dense and cf.wrote: stdout.write "\n"
        stdout.write labels[k], ":\n"; cf.wrote = true
      cf.dirLabel = true
      var c: LsCf; let cg0 = cg                 #Maybe merge local extras
      if cf.extra.len > 0 and (cf.recurse == 1 or (cf.recurse > 1 and
           (cf.extra.endsWith("//") or cf.extra.endsWith("/.")))):
        var d = if not cf.extra.startsWith('/'): maybePfx(cf.cwd, here)
                else: simplifyPath(cf.extra & "/" & maybePfx(cf.cwd, here),true)
        while true:
          try:
            let x = cfToCL(d & "/.lc", quiet=true)
            c = lsCfFromCL(cf.cl0 & x & cf.cl1)
            c.fin(cf.cl0, cf.cl1, cf.t0); cg = c.addr
            break                               #done at first success
          except: discard                       #tweak files are very optional
          if not cf.extra.endsWith('/') or
               (cf.extra == "./" and d.len < 1) or d.len < cf.extra.len:
            break           #Either not looking in par dirs or topped out @root
          d = d.parentDir   #No .lc file here, look in parent
      cg[].ls(ents, here, r + 1, dts.addr)
      cg = cg0

when isMainModule:                      ### DRIVE COMMAND-LINE INTERFACE
  try:
    let cfd = getEnv("LC_CONFIG", getConfigDir() & "lc")
    var cl0 = cfToCL(if cfd.dirExists: cfd&"/config" else: cfd, "", true, true)
    cl0.add envToCL("LC")
    var cf = lsCfFromCL(cl0 & os.commandLineParams())
    cf.fin(cl0, os.commandLineParams() - cf.paths)
    cf.ls(if cf.paths.len > 0: cf.paths else: @[ "." ])
    quit(min(255, cf.nError))
  except HelpOnly, VersionOnly: quit(0)
  except ParseError: quit(1)
