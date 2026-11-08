/* Experimental metadata accelerator. No repository/index/ref operations live here. */
#include <git2.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

typedef struct { unsigned char *data; size_t len, cap; } buffer;
typedef struct { const char *kind, *key, *value; } operation;

static int fail(const char *message) {
    fprintf(stderr, "error: metadata helper: %s\n", message);
    return 1;
}

static int append(buffer *b, const void *data, size_t count) {
    size_t need, cap;
    unsigned char *next;
    if (count > SIZE_MAX - b->len - 1) return fail("input is too large");
    need = b->len + count + 1;
    if (need > b->cap) {
        cap = b->cap ? b->cap : 4096;
        while (cap < need) {
            if (cap > SIZE_MAX / 2) { cap = need; break; }
            cap *= 2;
        }
        next = (unsigned char *)realloc(b->data, cap);
        if (!next) return fail("out of memory");
        b->data = next; b->cap = cap;
    }
    if (count) memcpy(b->data + b->len, data, count);
    b->len += count; b->data[b->len] = 0;
    return 0;
}

static int read_input(buffer *b) {
    unsigned char chunk[8192];
    size_t count;
    while ((count = fread(chunk, 1, sizeof(chunk), stdin)) != 0) {
        if (append(b, chunk, count)) return 1;
    }
    if (ferror(stdin)) return fail("could not read input");
    return 0;
}

static int octal(buffer *b, unsigned char value) {
    unsigned char encoded[5] = {'\\', '0', '0', '0', '0'};
    encoded[2] = (unsigned char)('0' + (value >> 6));
    encoded[3] = (unsigned char)('0' + ((value >> 3) & 7));
    encoded[4] = (unsigned char)('0' + (value & 7));
    return append(b, encoded, sizeof(encoded));
}

/* Match the current Git -> od -> awk snapshot byte for byte. Git still reads
 * every configuration source, including includes, worktrees and command scope. */
static int encode_snapshot(const buffer *input) {
    buffer canonical = {0}, readable = {0};
    size_t start = 0, i, keylen, length;
    const unsigned char *end, *separator, *record;
    int sentinel, rc = 1;
    while (start < input->len) {
        record = input->data + start;
        end = (const unsigned char *)memchr(record, 0, input->len - start);
        if (!end) break; /* An incomplete Git read cannot publish its OK marker. */
        length = (size_t)(end - record); start += length + 1;
        separator = (const unsigned char *)memchr(record, '\n', length);
        if (!separator) continue;
        keylen = (size_t)(separator - record);
        sentinel = keylen == strlen("__review_config_ok__") &&
            !memcmp(record, "__review_config_ok__", keylen);
        if (append(&canonical, record, keylen) || append(&canonical, "\t", 1)) goto done;
        if (!sentinel && (append(&readable, record, keylen) || append(&readable, "\t", 1))) goto done;
        for (i = keylen + 1; i < length; ++i) {
            unsigned char byte = record[i];
            if (octal(&canonical, byte)) goto done;
            if (!sentinel) {
                if (byte < 32 || byte == 92 || byte == 127) {
                    if (octal(&readable, byte)) goto done;
                } else if (append(&readable, &byte, 1)) goto done;
            }
        }
        if (append(&canonical, "\n", 1)) goto done;
        if (!sentinel && append(&readable, "\n", 1)) goto done;
    }
    if (canonical.len && fwrite(canonical.data, 1, canonical.len, stdout) != canonical.len) goto output_error;
    if (fputs("__review_config_values__\n", stdout) == EOF) goto output_error;
    if (readable.len && fwrite(readable.data, 1, readable.len, stdout) != readable.len) goto output_error;
    if (fputs("__review_config_end__\n", stdout) == EOF || fflush(stdout)) goto output_error;
    rc = 0; goto done;
output_error:
    fail("could not write snapshot");
done:
    free(canonical.data); free(readable.data);
    return rc;
}

static const char *next_field(const buffer *input, size_t *cursor) {
    const unsigned char *at, *end;
    if (*cursor >= input->len) return NULL;
    at = input->data + *cursor;
    end = (const unsigned char *)memchr(at, 0, input->len - *cursor);
    if (!end) return NULL;
    *cursor += (size_t)(end - at) + 1;
    return (const char *)at;
}

#ifdef _WIN32
static wchar_t *wide_path(const char *path) {
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    wchar_t *wide;
    if (!size) return NULL;
    wide = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
    if (wide && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, size)) {
        free(wide); return NULL;
    }
    return wide;
}

static int regular_target(const char *path) {
    wchar_t *wide = wide_path(path);
    DWORD flags, error;
    if (!wide) return 0;
    flags = GetFileAttributesW(wide); error = GetLastError(); free(wide);
    if (flags == INVALID_FILE_ATTRIBUTES)
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
    return !(flags & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
}

static int flush_target(const char *path) {
    wchar_t *wide = wide_path(path);
    int fd, rc;
    if (!wide) return 1;
    fd = _wopen(wide, _O_RDWR | _O_BINARY); free(wide);
    if (fd < 0) return 1;
    rc = _commit(fd); if (_close(fd)) rc = -1;
    return rc != 0;
}
#else
static int regular_target(const char *path) {
    struct stat st;
    if (lstat(path, &st)) return errno == ENOENT;
    return S_ISREG(st.st_mode);
}

static int flush_target(const char *path) {
    int fd = open(path, O_RDWR), rc;
    if (fd < 0) return 1;
    rc = fsync(fd); if (close(fd)) rc = -1;
    return rc != 0;
}
#endif

static int git_failure(void) {
    const git_error *error = git_error_last();
    return fail(error && error->message ? error->message : "configuration operation failed");
}

typedef struct { unsigned int roots, included; } entry_count;
static int count_entry(const git_config_entry *entry, void *payload) {
    entry_count *count = (entry_count *)payload;
    if (entry->include_depth == 0) { if (count->roots < 2) ++count->roots; }
    else ++count->included;
    return 0;
}

/* Exit 78 means no publication and permits the caller to use ordinary Git.
 * All other failures are final: never retry an uncertain committed write. */
static int needs_git_value(const char *value) {
    const unsigned char *p = (const unsigned char *)value;
    for (; *p; ++p) if (*p < 32 || *p == 127) return 1;
    return 0;
}

/* The whole message is parsed before opening config or taking its lock.
 * No shell evaluation, SQL, index/ref writes, or automatic retry after a commit. */
static int apply_changes(const buffer *input) {
    size_t cursor = 0, count = 0, i;
    const char *magic = next_field(input, &cursor), *path, *kind, *key, *value;
    operation *ops = NULL, *grown;
    git_config *config = NULL;
    git_transaction *transaction = NULL;
    int initialized = 0, rc = 1, status;
    entry_count entries;
    if (!magic || strcmp(magic, "git-review-meta-write-v1")) return fail("unsupported write protocol");
    path = next_field(input, &cursor);
    if (!path || !*path) return fail("missing config path");
    for (;;) {
        kind = next_field(input, &cursor);
        if (!kind) { fail("incomplete write message"); goto done; }
        if (!strcmp(kind, "end")) break;
        if (strcmp(kind, "set") && strcmp(kind, "unset")) { fail("unknown write operation"); goto done; }
        key = next_field(input, &cursor); value = next_field(input, &cursor);
        if (!key || !*key || !value) { fail("incomplete write operation"); goto done; }
        for (i = 0; i < count; ++i) {
            if (!strcmp(ops[i].key, key)) { fail("duplicate write operation"); goto done; }
        }
        if (count == SIZE_MAX / sizeof(operation)) { fail("too many operations"); goto done; }
        grown = (operation *)realloc(ops, (count + 1) * sizeof(operation));
        if (!grown) { fail("out of memory"); goto done; }
        ops = grown; ops[count].kind = kind; ops[count].key = key; ops[count].value = value; ++count;
    }
    if (cursor != input->len) { fail("trailing write data"); goto done; }
    for (i = 0; i < count; ++i) {
        if (needs_git_value(ops[i].value)) { rc = 78; goto done; }
    }
    if (!regular_target(path)) { rc = 78; goto done; }
    if (git_libgit2_init() < 0) { git_failure(); goto done; }
    initialized = 1;
    if (git_libgit2_opts(GIT_OPT_ENABLE_FSYNC_GITDIR, 1) < 0 ||
        git_config_open_ondisk(&config, path) < 0 ||
        git_config_lock(&transaction, config) < 0) { git_failure(); goto done; }
    /* Check eligibility under the file lock before queuing ANY changes. */
    for (i = 0; i < count; ++i) {
        entries.roots = 0; entries.included = 0;
        status = git_config_get_multivar_foreach(config, ops[i].key, NULL, count_entry, &entries);
        if (status == GIT_ENOTFOUND) status = 0;
        if (status < 0 && !strcmp(ops[i].kind, "set")) { git_failure(); goto done; }
        if (entries.included) { rc = 78; goto done; }
        if (entries.roots > 1 && !strcmp(ops[i].kind, "set")) {
            fail("multiple values for metadata key in root config"); goto done;
        }
    }
    for (i = 0; i < count; ++i) {
        if (!strcmp(ops[i].kind, "set")) {
            status = git_config_set_string(config, ops[i].key, ops[i].value);
        } else {
            (void)git_config_delete_entry(config, ops[i].key);
            status = 0;
        }
        if (status < 0) { git_failure(); goto done; }
    }
    if (git_transaction_commit(transaction) < 0) { git_failure(); goto done; }
    if (flush_target(path)) { fail("config was committed but could not be flushed"); goto done; }
    rc = 0;
done:
    git_transaction_free(transaction); git_config_free(config);
    if (initialized) git_libgit2_shutdown();
    free(ops); return rc;
}

int main(int argc, char **argv) {
    buffer input = {0};
    int rc;
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
#endif
    if (argc == 2 && !strcmp(argv[1], "--protocol-version")) {
        puts("git-review-meta\t1"); return 0;
    }
    if (argc != 2 || (strcmp(argv[1], "encode") && strcmp(argv[1], "apply")))
        return fail("expected encode or apply");
    if (read_input(&input)) { free(input.data); return 1; }
    rc = !strcmp(argv[1], "encode") ? encode_snapshot(&input) : apply_changes(&input);
    free(input.data); return rc;
}
