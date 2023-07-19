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

Can maybe distribute some lib for VC-status kinding/indirect deps on VC libs.

FORMATTING
----------
Symbolic link targets could be abbreviated on a component-by-component basis.
{ This may be expensive for many symlinks, but abbreviation is already on the
expensive side. }  Abbreviating multi-component a/b/c names is also buggy.

selinux security context labels (ls -Z)
(first do some cligen/selinux.nim:getfilecon,etc.  Then should be easy.)

Though current "just has it" kinding works to color by ACL/Linux capability,
it'd be nicer to actually format out the text. { Capabilities are short-ish,
but ACL spellings are typically not table-friendly.  So maybe just caps. }

Make -H take an attr instead of being a bool; Render header only if .len>0.
So, space can render without attrs.  Leading + can replicate headers across
major columns.  Best to apply attr to start of 1st header and turn off attrs at
end of last so intermediate space is all e.g., underlined.
