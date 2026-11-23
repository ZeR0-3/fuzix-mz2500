#!/usr/bin/env bash
# Copy this repository's files over a FUZIX source tree.
#   usage: ./install.sh /path/to/FUZIX-master
# Files in Kernel/, Applications/ and Library/ replace or extend the upstream files
# (see README.md for the list).  The mz2500/ directory is used in place.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dst="${1:?usage: $0 /path/to/FUZIX-master}"
[ -d "$dst/Kernel" ] || { echo "$dst does not look like a FUZIX tree" >&2; exit 1; }
for d in Kernel Applications Library; do
  cp -a "$here/$d/." "$dst/$d/"
done
echo "installed into $dst"
echo "now: export MZ_FUZIX=$dst   and see mz2500/README.md"
