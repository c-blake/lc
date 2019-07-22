Condensing copy-pastable representations of linux-5.2.2/scripts/
================================================================

We start at 70 rows and end at 8. (8.75X reduction) with gradual loss of
readability (obviously subjective vs. the objective space measurement or
unique pattern expansion):

Base full name directory (70 rows of 2 cols):

![0-base.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/0-base.png)

Sort by name length (35 rows of 4 cols):

![1-oL.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/1-oL.png)

Shortest such that mid-point `*` produes a unique pattern (35 rows of 4 cols):

![2-m,.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/2-m,.png)

Best same-column-for-`*` (28 rows of 5 cols):

![3-ma.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/3-ma.png)

Shortest prefix patterns (28 rows of 5 cols):

![4-m-2.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/4-m-2.png)

Shortest suffix patterns (24 rows of 6 cols):

![5-m-3.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/5-m-3.png)

Shorter of shortest prefix|suffix (18 rows of 8 cols):

![6-m-4.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/6-m-4.png)

Shortest unique single-`*` patterns (12 rows of 12 cols):

![7-m-5.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/7-m-5.png)

Shortest unique two-`*` patterns (10 rows of 14 cols) { Eventually, I want to
"re-expand `*`" so that, for example, the `Makefile.kcov` abbreviation goes from
`*v` to `*kcov` since `*asan` already forces a 5 text-column 4th `lc` column }:

![8-m-6.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/8-m-6.png)

Shortest unique two-`*` patterns, sorted by length (8 rows of 18 cols):

![9-m-6oL.png](https://raw.githubusercontent.com/c-blake/lc/master/screenshots/src-linux-script/9-m-6oL.png)
