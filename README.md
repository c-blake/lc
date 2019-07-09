For the impatient, here is a screenshot:

![screenshot](https://raw.githubusercontent.com/c-blake/lc/master/ss.png)

This program is not and never will be a drop-in replacement for `ls` at the CLI
option compatibility level.  `ls` is a poorly factored mishmash of selection,
sorting, and formatting options.  With about half as many CLI option flags (but
beefier configuration) `lc` is many-fold more flexible and only a bit slower.
It can create similar output, but my main impetus to write `lc` was always a
better functionality factoring not mere recapitulation.  So, `lc` is *not* just
"ls in Nim".  If you disagree, `ls` probably isn't going anywhere and has giant
companies supporting it.

`lc` is also not `stat` or `find`.  Those have their roles for spot-checking or
generating program-consumed data streams.  `lc` is about human-friendly output,
creating output to help you see and create organization you want in your file
sets, and shining light on unexpected things as you go about everyday business
listing your files.  As such, absolute max performance is not a priority as
human reaction time is not so fast & large directories are usually ill-advised.
Even `find` cannot compete with some hypothetical `dcat` dumping dents to
stdout.  You may have pity-worthy giant dirs, but the doctors can only do so
much for you then. ;-)  More seriously, you cannot consume that output "as a
human" anyway.  You probably want something like a `dcat` then, not `lc`.

Enough disclaimers about what `lc` is *not*.  What *is* `lc`?  Why do we need
yet another file lister?  What's the point?  Well, `lc`

 - is clearly factored into independent actions and very configurable

 - has good CLI ergonomics (unique prefixes good enough, spellcheck, etc.)

 - supports multi-level sorting for many forward/reverse attributes

 - supports arbitrary assignment of "file kind order" for use in sorting

 - supports "multi-dimensional reasoning" about file attributes

 - supports both latter-day nanosecond file times and *very* abbreviated ages

 - has value-dependent coloring for file times, sizes, permissions, etc.

 - supports filename abbreviation via `-mNum` or shell glob-friendly `-ma`

 - supports "local tweak files" - extra config options in a local ".lc" (or a
   .lc in a shadow tree under a user's control if needed).  Nice for eg, NFS!

 - supports "theming" (operationally, environment-variable-keyed cfg includes)

 - supports latter-day Linux statx/b)irth times (but works on non-Linux, too)

 - supports file(1)/libmagic deep file inspection-based classification (though
   this facility can be very slow on large directories)

 - is extensible with fully user-defined file type tests & field formats

 - is compact (~1000 lines; ~300 is tables&help, ~300 of cligen/[tab, humanUt]
               might be part of `lc` if I didn't write both pkgs.)

 - has few dependencies (just cligen and the Nim stdlib)

 - is a work in progress, but a unique enough bundle of useful ideas to share.
   With so many features and just me as a user, there are surely many bugs.

The most osbcure of these is likely "multi-dimensional".  I mean this in the
mathematical "independent coordinate" sense **not** a Jurassic Park (1993)-esque
graphical file tree sense.  Examples of dimensions may help.  One file can be
both an executable regular file and some kind of script source.  Or both a
directory and a directory with a sticky bit set.  On the output side, you can
also set the foreground & background colors of text independently (as well as
blinking, and so on).  I happen to like `st` for its hackability which supports
bold, italic, blink, underline, struck, inverse all as 6 independent text
attributes. (Color inversion involves a mapping probably too complex to be a
useful visual aid.)  So, 7 usable output dimensions, with 5 being shallow 1-bit
dimensions.  Though subjective, I find text with all these embellishments at
once legible on my primary displays.  `lc` tries to aid "aligning" rendering or
output dimensions with classification or input dimensions.

On the input/data side there are a few natural "query" dimensions such as traits
based on dtype data, stat data, ACLs, .., that performance-sensitive folk may
like, but there are also *many* independent fields & bits just in `struct stat`.
Not much is mutually exclusive like the dtype.  So, `lc` users can configure
however many classification dimensions to line up against their picked poisons
of output dimensions.  Operationally, users just pick small integer labels for
dimensions/series of order-dependent tests.  The first test passing within a
given dimension wins that dimension.  To aid debugging kind assignments you can
do things like `lc -f%0%1%2%3%4%5\ %f` to see coordinates in the first 6 dims.

As for the bread and butter of file listing, many things that are hard-coded in
other file listers are fully user-defined in `lc`, like a concept of dot files.
Assuming you define a "dot" or "dotfile" type `lc -xdot` will probably exclude
those from a listing.  (Unique prefixes being adequate may mean a longer string
if you define other file kinds with names starting with "dot".)  I usually have
a shell alias that does the `-xdot` and a related alias ending with an "a" that
does not.  That mimics `ls` usage, but without spaces and '-'s to enter.  If the
listing is well organized, seeing dot files by default may be considered as much
a feature as a bug.  Including everything by default lets "dot" be user-defined.
You can also do `-idot` to see *only* the dot files (or any other user/system
defined file kind) which is not something available in most file listers.  It's
also not always easy to replicate via shell globbing the input list.  Eg., `lc
-r0 -idir -iodd` can often be illuminating on very aged file trees.

Multi-level sorting and format string are similar ideas to other tools like the
Linux `ps` or `stat -c` or `find -printf`.  Sorting by file kind is possible and
"kind orders" are user-configurable.  Between that and more multi-dimensionality
you can filter and group almost any way that makes sense, and none of that needs
any changing of `lc` proper - just your configuration.  Less can be more with
well thought out factoring.  `lc` is almost an "`ls`-Construction toolkit".

Because of all that flexibility, `lc` has a built in style/aliasing system.
This lets you name canned queries & reports and refer to them, like `lc -sl`.
My view is that there is no one-size-fits-all-or-even-most long-format listing.
`ls -sl` or a shorter `ll='lc -sl'` alias is the way to go.  Then you can make
columns included (and their `order`, `--header` or not, ..) all just how you
like.  I usually like 5 levels of long-ness, not 2, in my personal setup.

A feature I don't know of any terminal file listers using is abbreviation (GUIs
have this, though).  Most everyone has probably been annoyed at one time or
another by some pesky few overlong filenames in a directory messing up column
widths in a file listing.  `lc -m24` lets you limit displayed length to 24 (or
whatever) characters.  `lc` replaces the (user-definable) "middle slice" with a
user-definable string.  While you can use some UTF8 ellipsis, you probably want
`*` since that choice will make most abbreviations valid shell patterns that you
can copy-paste.  The shell may not expand it uniquely, but `lc` has you covered
with `lc -mauto` or just `lc -ma`.  That automatically finds the smallest limit
such that all displayed strings are unique, ensuring a unique shell expansion
(up to other shell meta-characters in file names, anyway).  An explicit figure
of `lc -ma` playing out may help here:

  ![ss-ma.png](https://raw.githubusercontent.com/c-blake/lc/master/ss-ma.png)

If you don't like my default "balanced" slice, you can adjust how much of the
head and tail of a name are used to form `head*tail`.  You can even create a
style that sets those so you only have to type `-sm` on the command-line.
There's a similar `-M` for symlink targets, but unfortunately the ones which
tend to be longest also range over the whole FS namespace, not just one dir.
So, `-Mauto` seems hard.

In many little ways, `lc` tries hard to let you get the most out of terminal
real estate, targeting max information per row, while staying within an easy
to visually parse table format.  Features along these lines are terse 4 column
octal permission codes, and with some rounding 3-column file ages, and 4 column
file sizes.  If it succeeds too well you can have fewer, more spaced columns out
more with `lc -n4` or something.  If it succeeds too poorly, you can use `-m`
or drop format fields *or* if you can/want to rename or move files then `lc -w5
-W$((COLUMNS+10))` shows the widest 5 files in each output column (that'd eg.
give you more output cols with 10 more terminal cols, say).  A hard-to-advocate-
but-possible way to save space is `lc -oL`.  Try it.  { I suspect this minimizes
rows within a table constraint, but the proof is too small to fit in the margin.
Maybe some 2D bin packing expert can weigh in with a counter example. }

In the other direction, `lc` supports informational bonuses like ns-resolution
file timestamps with `%1..%9` extensions to the `strftime` format language for
fractions of a second to that many places as per your discretion, rate of disk
utilization (`512*st_blocks/st_size` or allocation/addressable file bytes),
as well as newer Linux statx attributes and birth times.

`lc` also comes with boolean logic combiners for file kind tests, quite a few
built-in tests, and is also extensible for totally user-defined tests.  It also
has a couple external command extensible format fields.  So, if there's just a
thing or two missing then you can probably add it without much work.  It may
not run fast, but it might be "fast enough" for small dirs on fast devices.
Given how long it takes a person to read/assimilate a directory listing, even
doing a "du -s" inside a format program is not unthinkable, though unlikely to
be a popular default style.  Hard-coding Git support seems popular these days.
I do not do that yet, and I'm not sure I want the direct dependency, but you may
be able to hack something together.
