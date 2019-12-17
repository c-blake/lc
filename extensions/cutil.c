#include <stdlib.h>     /* malloc realloc free */
#include <unistd.h>     /* write */
#include <ctype.h>      /* isspace */
#include <string.h>     /* memmove */

static void *reallocFree(void *ptr, size_t size) { /*realloc, free on failure */
    char szBuf[24], nSz;
    void *tmp = realloc(ptr, size);
    if (tmp)
        return tmp;
    if (write(2, "realloc(p, ", 11) != 11) {/**/}
    nSz = snprintf(szBuf, sizeof szBuf, "%ld", size);
    if (write(2, szBuf, nSz) != nSz) {/**/}
    if (write(2, ") failure\n", 10) != 10) {/**/}
    free(ptr);
    return tmp;
}

static void freadAll(FILE *f, char **pBuf, size_t *len) {   /* Read to EOF */
    size_t nR = 8192, n, off = 0;  /* read request size, return, buf offset */
    do {
        n    = fread(*pBuf + off, 1, nR, f);
        off += n;
        if (!(*pBuf = (char *)reallocFree(*pBuf, off + nR))) {
            *pBuf = calloc(1, *len = 1); return;    /* set to "" on failure */
        }
    } while (!feof(f));
    if (!(*pBuf = (char *)reallocFree(*pBuf, off + 1))) { /* right-size buf */
        *pBuf = calloc(1, *len = 1); return;    /* set to "" on failure */
    }
    (*pBuf)[off] = '\0';                      /* NUL-terminate just in case */
    if (len)
        *len = off;
}

static char *strip(char *buf, size_t *len) { /* Remove leading&trailing space */
    size_t i;
    for (i = *len; i > 0 && isspace(buf[i - 1]); i--) /**/;
    if (*len > 0)
        buf[i] = '\0';
    for (/**/; isspace(*buf); buf++) /**/;
    return buf;
}
