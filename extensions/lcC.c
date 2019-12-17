/* Show how to extend 'lc' in C;  gcc -shared -fPIC lcC.c -o liblcC.so
   Be sure to install resulting lcNim.so somewhere in $LD_LIBRARY_PATH. */
#include <stdio.h>  /* snprintf FILE popen pclose */
#include <stdlib.h> /* system */

static char cmdBuf[4096];
static int cmdExitsOk(char *cmd, char *qualPath) {
    snprintf(cmdBuf, sizeof cmdBuf, "%s \"%s\"", cmd, qualPath);
    return WEXITSTATUS(system(cmdBuf)) == 0;
}

/* te == T)est E)xtension */
int te1(char *qualPath) { return cmdExitsOk("te1", qualPath); }
int te2(char *qualPath) { return cmdExitsOk("te2", qualPath); }

#include "cutil.c"          /* sequestered as not specifically interesting. */

static char  *res;          /* 'lc' uses format data `res` only BETWEEN calls */
static size_t nRes;

char *cmdOutput(char *cmd, char *qualPath) {
    FILE *f;
    if (!res) {
        res = (char *)malloc(nRes = 1);
        res[0] = '\0';
    }
    snprintf(cmdBuf, sizeof cmdBuf, "%s \"%s\"", cmd, qualPath);
    if (!(f = popen(cmdBuf, "r"))) {
        res[0] = '\0';
        return res;
    }
    freadAll(f, &res, &nRes);/* External command-based user-defined fmt field.*/
    pclose(f);               /* User must keep output easy on tabulation, but */
    return strip(res, &nRes);/* we do at least strip any trailing newline. */
}

/* fe == F)ormat E)xtension */
char *fe1(char *qualPath) { return cmdOutput("fe1", qualPath); }
char *fe2(char *qualPath) { return cmdOutput("fe2", qualPath); }
