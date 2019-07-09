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

Should replace fork/exec driven program calls with C calls to `dlopen()`d .so

Maybe a mode where users can type -X././ or something to NOT use a local .lc
config when recursing (at r > 1, say).

Maybe add a -U/-G options to abbreviate user names and group names similarly
to file names (`*` is a less compelling omission indicator here, though).

For just %f formats, mx = (W+1)/nColumn - 1 achieves nColumn output.  We could
maybe automate things so users can say, eg. -n-5 to auto-set -m such that they
will get 5 columns (unless all names are so short they are unabbreviated and
more columns are possible).  Formats with non-ahead-of-time-known widths are
harder to support this way, though.

KINDING
-------
VC status.  Using an external shell command is possible, but not so efficient.
Could also make a request/response protocol with a FIFO or socket to talk to
some caching demon the way Roman's fancy Zsh git prompt status thing works.
Probably makes sense to do this as a library after dlopen() extensions work.
This also applies to any new VC-related format.

FORMATTING
----------
More format fields could probably use specific value-conditional color scales.

Another field for `color` definitions that lets users define some string/UTF8
as a conceptual icon?  Includable in formats with %@ maybe?  Unfortunately,
icons do not overlap/overlay.  So, unlike text attributes only one of however
many kind dimensions can "win".  Maybe the first non-unknown dimension should
win?  I don't like icons, personally, but it seems popular, not hard to do, and
I do agree that redundant visual cues can be helpful.  Could also maybe let any
dimension have an icon and give each row 3-6 icons.  If users are judicious in
not allocating more than 1-3 icons then that might not be so bad.  This could
maybe even be an "alternate spelling" of the %0-%8 format dimensions.

selinux security context labels (ls -Z)
(first do some cligen/selinux.nim:getfilecon,etc.  Then should be easy.)

hyperlink-style %[fF] & %[rR] (eg. %^f) to render the extra esc seqs to make
clicking chase a file:///full/path.  Maybe %[hH] and %[jJ].  If icons get added
people will ask to click on those, too, though.  So, a global command option to
change rendering may be best.

Though current "just has it" kinding works to color/attribute by ACL, Linux
capability, but it'd be nicer to actually format out the text.  Capabilities
are at least short-ish, but ACL spellings are typically not table-friendly.
