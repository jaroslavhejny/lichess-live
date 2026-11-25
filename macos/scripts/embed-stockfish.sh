#!/bin/sh
set -eu
archive="${DERIVED_FILE_DIR}/stockfish-19-macos-universal.tar.gz"
engine_dir="${DERIVED_FILE_DIR}/stockfish-19"
engine="${engine_dir}/stockfish/stockfish-macos-universal"
expected=a1f0e3bcc5a6927a11fe6fc8e54a779754645f3c2bae2cf13420fd1957adaa77
if [ ! -f "$engine" ] || [ ! -f "${engine_dir}/stockfish/Copying.txt" ]; then
  mkdir -p "$engine_dir"
  if [ ! -f "$archive" ]; then
    /usr/bin/curl --fail --location --silent --show-error --retry 2 --max-time 300 \
      'https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-macos-universal.tar.gz' \
      -o "${archive}.download"
    mv "${archive}.download" "$archive"
  fi
  actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    echo 'error: Stockfish archive checksum did not match; delete the cached archive and rebuild.' >&2
    exit 1
  fi
  /usr/bin/tar -xzf "$archive" -C "$engine_dir" stockfish/stockfish-macos-universal stockfish/src stockfish/Copying.txt stockfish/README.md stockfish/AUTHORS
fi
destination="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/stockfish"
mkdir -p "$(dirname "$destination")"
/usr/bin/ditto "$engine" "$destination"
source_destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Stockfish"
mkdir -p "$source_destination"
/usr/bin/ditto "${engine_dir}/stockfish/src" "${source_destination}/src"
/usr/bin/ditto "${engine_dir}/stockfish/Copying.txt" "${source_destination}/COPYING.txt"
/usr/bin/ditto "${engine_dir}/stockfish/README.md" "${source_destination}/README.md"
/usr/bin/ditto "${engine_dir}/stockfish/AUTHORS" "${source_destination}/AUTHORS"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --entitlements "${SRCROOT}/Stockfish.entitlements" "$destination"
fi
