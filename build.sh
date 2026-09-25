#!/usr/bin/env bash
# Sync the pinned LineageOS 23.2 sources for amogus_doha (Moto G8 Plus),
# apply the fixes in patches/ and build the flashable zip.
#
# Usage: ./build.sh [SOURCE_DIR]      (default: ./lineage)
#
# Environment:
#   JOBS          parallel build jobs (default: nproc)
#   SYNC_JOBS     parallel repo sync jobs (default: 4)
#   MANIFEST_URL  manifest repo to init from (default: this checkout)
#   SKIP_SYNC=1   don't run repo sync (patches are still re-applied)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(mkdir -p "${1:-$PWD/lineage}" && cd "${1:-$PWD/lineage}" && pwd)
JOBS=${JOBS:-$(nproc)}
# Most projects come from android.googlesource.com, which answers too many
# parallel fetches with HTTP 429 / RESOURCE_EXHAUSTED. repo then retries each
# failed fetch as a full fetch of every branch, which makes it worse.
SYNC_JOBS=${SYNC_JOBS:-4}
MANIFEST_URL=${MANIFEST_URL:-$HERE}
DEVICE=amogus_doha

# repo needs a git identity, and git refuses to read a checkout owned by
# another user (common when this runs in a container). Pass both as
# command-line config so nothing is written to ~/.gitconfig.
name=$(git config user.name || echo builder)
email=$(git config user.email || echo builder@localhost)
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1="$name"
export GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2="$email"

cd "$SRC"

if [ ! -d .repo ]; then
  repo init -u "$MANIFEST_URL" -b main -m default.xml --git-lfs -g default,-darwin
fi
if [ "${SKIP_SYNC:-0}" != 1 ]; then
  repo sync -c -j"$SYNC_JOBS" --retry-fetches=5 --force-sync --no-tags --no-clone-bundle
fi

# Each patches/<project path>.patch applies to that project. Reset the
# project first so re-running this script never applies a patch twice.
(cd "$HERE/patches" && find . -name '*.patch' | sort) | while read -r patch; do
  proj=${patch#./}
  proj=${proj%.patch}
  git -C "$proj" reset -q --hard
  git -C "$proj" clean -q -fd
  git -C "$proj" apply --whitespace=nowarn "$HERE/patches/$patch"
  echo "applied patches/${patch#./}"
done

# An empty *file* at this path stops AOSP from treating
# device/motorola/amogus_doha/kernel-headers as the device's kernel header
# directory (it is added to the include path whenever the path exists, and
# there's no opt-out). The real headers come from
# PRODUCT_VENDOR_KERNEL_HEADERS, set in patches/device/motorola/targets.patch.
: > device/motorola/amogus_doha/kernel-headers

export ALLOW_MISSING_DEPENDENCIES=true
if command -v ccache >/dev/null; then
  export USE_CCACHE=1 CCACHE_EXEC=$(command -v ccache)
fi

set +u # envsetup.sh and lunch aren't nounset-clean
source build/envsetup.sh
breakfast "$DEVICE" userdebug
mka -j"$JOBS" target-files-package bacon
set -u

echo
echo "Done. Zip:"
ls -1 "$SRC/out/target/product/$DEVICE"/lineage-*.zip
