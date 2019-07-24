IDEAS
=============

GLOBAL BEHAVIOR
---------------
Expensive metadata blocking (`-b`).
  Default should be to probe for all implied needed by filter,sort,format but
  introduce an enum for each kind of data query/context and a way to omit/be
  empty upon user request.  Besides data probes like stat/readlink/ACL/magic,
  classifier groups run against the data should also be omittable (maybe only
  when there are no filters or all tests within some group/dimension use
  similar data that's been omit-requested).  This way a user can define a
  bunch of expensive-but-fast-enough-most-of-the-time things but have an easy
  out to speed-up execution in more expensive contexts like big directories,
  eg. "lc -bacl -bmag" or even "lc -sbasic" to revert to basic data only.
  The impl can maybe just be to unwind the cf.need system and ensure that a
  usable but "empty" default always exists.

Replace fork/exec driven program extending with C calls to `dlopen()`d .so
Can maybe distribute some lib for VC-status kinding/indirect deps on VC libs.

FORMATTING
----------
Post layout, expand `*`s up to the limit of the column for maximum context/best
readability.  This can maybe be optional behavior.  Probably just round robin
through each * taking a left char, then a right char, until extra space gone.

Symbolic link targets could be abbreviated on a component-by-component basis.
{ This may be expensive for many symlinks, but abbreviation is already on the
expensive side. }

selinux security context labels (ls -Z)
(first do some cligen/selinux.nim:getfilecon,etc.  Then should be easy.)

hyperlink-style %[fF] & %[rR] (eg. %^f) to render the extra esc seqs to make
clicking chase a file:///full/path.  Maybe %[hH] and %[jJ].  If icons get added
people will ask to click on those, too, though.  So, a global command option to
change rendering may be best.

Though current "just has it" kinding works to color/attribute by ACL, Linux
capability, but it'd be nicer to actually format out the text.  Capabilities
are at least short-ish, but ACL spellings are typically not table-friendly.
