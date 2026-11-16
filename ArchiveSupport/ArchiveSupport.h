#include <sys/types.h>
#include <stdint.h>

// macOS ships the libarchive 3 dylib and SDK stub without these headers.
// Keep the declarations limited to the stable reader ABI.
struct archive;
struct archive_entry;

struct archive *archive_read_new(void);
int archive_read_free(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_read_support_filter_gzip(struct archive *);
int archive_read_support_filter_bzip2(struct archive *);
int archive_read_support_filter_xz(struct archive *);
int archive_read_support_filter_lzma(struct archive *);
int archive_read_support_filter_compress(struct archive *);
int archive_read_support_filter_lzip(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
const char *archive_error_string(struct archive *);
int archive_format(struct archive *);
int archive_filter_count(struct archive *);

const char *archive_entry_pathname_utf8(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);

#define QING_ARCHIVE_EOF 1
#define QING_ARCHIVE_WARN (-20)
#define QING_ARCHIVE_FORMAT_RAW 0x90000
