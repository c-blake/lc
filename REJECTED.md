CONSIDERED AND REJECTED IDEAS
=============================
`-l` long fmt for `ls` refugees.  The first thing I expect a new `lc` user to do
is decide what fields (& what order) they want for their `lc -sl`.  I strongly
suspect that will have combinatorially many different answers.  Also, I use `-l`
for something else right now although that could change.  It is a boolean flag
and doesn't outright fail.  As a guide, configs/cb0/style has "gls", though.

So, if you alias ll='ls -l' you could probably change that to `=lc -sgls` with
little perturbation, though you are better off learning more.

--------

So called --tree formats.  These don't interoperate very well with the simple
"one directory at a time" recursive structure of `proc ls`.  Unlike process
trees with usually few kids, there are often O(screenful) numbers of dents.
So, it's easy to lose track of alignment visually.  In as small scale as tree
likely works well in, many other things also probably work fine.  I.e., it's
value add is marginal.  It makes more sense in GUIs where you pick and choose
points of collapse or expansion.  There are likely other problems.

One way to add something sort of like this would be like [procs
display](https://github.com/c-blake/procs/blob/master/screenshots/basic.png)
indentation, but with indent proportional to directory depth.  This may help
some people with very shallow hierarchies and terminal rows to burn.  I'm not
very interested in this, but it would probably be easy to add.

--------

[Miller columns/cascading lists](https://en.wikipedia.org/wiki/Miller_columns).
What people want here is (approximately):
```
paste <(lc -1m25 ../..) <(lc -1m25 ..) <(lc -1m25 .) | less -x26
```
Doing this for one-off single directories can already be achieved with the above
snippet.[^1]  So, I doubt it makes sense as a built-in `lc` feature.  It's likely
enough to do a script with the above pipeline (being aware of how deep '.' is,
taking a number of levels, adding thatDir/../.. when needed, etc.)

`lc -mN` is better than other file listers for this application, since you can
bound the width (but not "height") of each listing being pasted ahead of time.
So, you can also know how many side-by-side major columns fit in $COLUMNS for a
given bound.  There are no scrollbars, exactly, but the terminal as a whole may
have them or a user can pipe the output to a pager.  Also note that fixed widths
like `-m25` cannot guarantee unique pattern expansions.  About all a built-in
`lc` feature might add would be i-node (vs. string) identification of where to
put some kind of "indicator string" to guide how levels of the hierarchy connect
E.g. a `**` after the right entry in the parent and parent-parent listings or
inversing whatever "." is within ".." and also inversing ".." within "../..".
Some visual connective might be possible via techniques of with ASCII art, but
this begins (!) to get far from usual terminal display behaviors.

[^1]: or more likely something nicer assuming TAB is not in any pathnames like
`paste <(lc -1m25 ../..) <(lc -1m25 ..) <(lc -1m25 .) | align -d $'\t' | less`.
