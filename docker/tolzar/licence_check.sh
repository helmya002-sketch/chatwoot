#!/bin/sh
# Tolzar licence check: no GPL / AGPL / SSPL / BSL library may be linked into a Tolzar process.
# Runs INSIDE the image (busybox sh, apk). It ships in the image at /app/docker/tolzar/, or pipe it in:
#
#   docker run --rm -i --entrypoint sh IMAGE -s < docker/tolzar/licence_check.sh
#       every shared library any ELF file under /usr/local and /gems links to (ldd)
#   docker exec -i CONTAINER env MODE=maps sh -s < docker/tolzar/licence_check.sh
#       every shared library mapped into the running processes (/proc/*/maps); run it after
#       `rails tolzar:verify_image_variants` in the same container so libvips is loaded
#   sh /app/docker/tolzar/licence_check.sh
#       the same files check, run by the image build's final stage (a failure fails the build)
#
# Installed packages: every package whose licence names GPL / AGPL / SSPL / BSL (LGPL is fine) fails, except
# the ALLOWED libraries and BASE_PROGRAMS: the Alpine base programs the image cannot run without (busybox is
# the shell the entrypoints run in, apk-tools owns the package database this check reads, musl-utils is ldd).
# They are separate programs, never linked into a Tolzar process.
#
# Exit 0 = pass. Every library is mapped to the apk package that owns it and that package's licence
# (/lib/apk/db/installed). Libraries no package owns were built in the Dockerfile and are listed for review.
set -eu

MODE="${MODE:-files}"
DB=/lib/apk/db/installed
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Packages whose licence string names GPL but which may be linked into proprietary code:
#   libgcc libstdc++ libgomp  GCC Runtime Library Exception 3.1 (Alpine's string omits the exception)
#   gmp                       "LGPL-3.0-or-later OR GPL-2.0-or-later": used under LGPL-3.0 (Ruby bignums)
#   zstd-libs                 "BSD-3-Clause OR GPL-2.0-or-later": used under BSD-3-Clause
#   xz-libs                   liblzma itself is 0BSD; the GPL parts are the xz command-line scripts
ALLOWED="libgcc libstdc++ libgomp gmp zstd-libs xz-libs"
# scanelf (pax-utils) is a dependency of musl-utils.
BASE_PROGRAMS="alpine-baselayout alpine-baselayout-data apk-tools busybox busybox-binsh musl-utils scanelf"
# Must never be installed at all (the old image's findings).
FORBIDDEN="libimagequant fftw-double-libs fftw-single-libs fftw-long-double-libs imagemagick imagemagick-libs
readline gcc g++ binutils make patch git build-base libheif x265-libs ghostscript poppler"

awk '/^P:/ { p = substr($0, 3) } /^L:/ { print p "\t" substr($0, 3) }' "$DB" > "$TMP/licences"

if [ "$MODE" = maps ]; then
  cat /proc/[0-9]*/maps 2>/dev/null | awk '$6 ~ /\.so/ { print $6 }' | sort -u > "$TMP/libs"
else
  find /usr/local/bin /usr/local/lib /gems -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null \
    | while read -r f; do ldd "$f" 2>/dev/null || true; done \
    | awk '$2 == "=>" && $3 ~ /^\// { print $3 } $1 ~ /^\// { print $1 }' | sort -u > "$TMP/libs"
fi

fail=0
echo "== Shared libraries linked into Tolzar processes ($MODE)"
while read -r lib; do
  owner="$(apk info -W "$lib" 2>/dev/null | sed -n 's/.* is owned by //p' | head -n 1)"
  if [ -z "$owner" ]; then
    echo "UNMANAGED  $lib  (built in the Dockerfile: expect only libvips (LGPL-2.1+) and libruby (Ruby/BSD-2))"
    continue
  fi
  pkg="$(echo "$owner" | sed -E 's/-[0-9][^-]*-r[0-9]+$//')"
  licence="$(awk -F '\t' -v p="$pkg" '$1 == p { print $2 }' "$TMP/licences")"
  if echo "$licence" | grep -Eq '(^|[^L])GPL|SSPL|BUSL|BSL-1'; then
    case " $ALLOWED " in
      *" $pkg "*) echo "ALLOWED    $lib  $pkg  [$licence]" ;;
      *) echo "FAIL       $lib  $pkg  [$licence]"; fail=1 ;;
    esac
  else
    echo "ok         $lib  $pkg  [$licence]"
  fi
done < "$TMP/libs"

echo "== Forbidden packages"
for p in $FORBIDDEN; do
  if apk info -e "$p" > /dev/null 2>&1; then echo "FAIL       $p is installed"; fail=1; fi
done

echo "== Installed packages with a GPL-family licence"
while IFS="$(printf '\t')" read -r pkg licence; do
  echo "$licence" | grep -Eq '(^|[^L])GPL|SSPL|BUSL|BSL-1' || continue
  case " $ALLOWED $BASE_PROGRAMS " in
    *" $pkg "*) echo "ALLOWED    $pkg  [$licence]  (base program or allowed library, not linked into Tolzar)" ;;
    *) echo "FAIL       $pkg  [$licence]  (a GPL package in the runtime image)"; fail=1 ;;
  esac
done < "$TMP/licences"

if [ "$fail" -ne 0 ]; then
  echo "LICENCE CHECK FAILED"
  exit 1
fi
echo "LICENCE CHECK PASSED"
