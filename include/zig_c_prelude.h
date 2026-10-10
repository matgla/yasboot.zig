/* Force-included ahead of the C that Zig's C backend writes for yasboot.
 *
 * tcc defines __GNUC__, and zig.h prefers its gcc path over its tinyc one;
 * on the gcc path it asks __has_attribute(aligned) and friends, which tcc
 * answers "no", and alignment silently goes away.  Undefining __GNUC__ puts
 * zig.h on the zig_tinyc path.  The headers zig.h includes are pulled in
 * first, while __GNUC__ is still defined.
 *
 * Bare metal builds with -nostdinc against the freestanding headers next to
 * this file, so the same command works with the host's cross tcc and with
 * the device's tcc, whatever libc either was configured with; -Dmode=yasos
 * gets these headers from the yasos libc tcc is configured with. */
#include <stdarg.h>
#include <stddef.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <float.h>

#undef __GNUC__
#undef __GNUC_MINOR__
#undef __GNUC_PATCHLEVEL__
