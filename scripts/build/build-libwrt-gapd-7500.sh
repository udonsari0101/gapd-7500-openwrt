#!/usr/bin/env bash
set -euo pipefail

LIBWRT_URL="https://github.com/LiBwrt/LibWrt.git"
LIBWRT_COMMIT="0fd5daca26aed9cab74b4141690deb5d997383f1"
BUILD_TREE="${GAPD_BUILD_TREE:-/home/$(id -un)/gapd_7500_openwrt/.work/build/libwrt}"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CONFIG_SEED="${PROJECT_DIR}/configs/libwrt-gapd-7500.config"
FEED_LOCK="${PROJECT_DIR}/configs/libwrt-feeds.lock"
ARTIFACT_DIR="${PROJECT_DIR}/artifacts/openwrt"

if [[ ! -f "${CONFIG_SEED}" ]]; then
    echo "Missing config seed: ${CONFIG_SEED}" >&2
    exit 2
fi
if [[ ! -f "${FEED_LOCK}" ]]; then
    echo "Missing feed lock: ${FEED_LOCK}" >&2
    exit 2
fi

if [[ ! -d "${BUILD_TREE}/.git" ]]; then
    if [[ -e "${BUILD_TREE}" ]]; then
        echo "Refusing to replace non-Git path: ${BUILD_TREE}" >&2
        exit 2
    fi
    mkdir -p "$(dirname -- "${BUILD_TREE}")"
    git init "${BUILD_TREE}"
    git -C "${BUILD_TREE}" remote add origin "${LIBWRT_URL}"
    git -C "${BUILD_TREE}" fetch --depth 1 origin "${LIBWRT_COMMIT}"
    git -C "${BUILD_TREE}" checkout --detach FETCH_HEAD
fi

actual_commit="$(git -C "${BUILD_TREE}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${LIBWRT_COMMIT}" ]]; then
    echo "Build tree is at ${actual_commit}; expected ${LIBWRT_COMMIT}." >&2
    echo "Refusing to reset or overwrite an existing source tree." >&2
    exit 2
fi

cd "${BUILD_TREE}"

for local_patch in "${PROJECT_DIR}"/patches/*.patch; do
    [[ -e "${local_patch}" ]] || continue
    if git apply --check "${local_patch}"; then
        git apply "${local_patch}"
    elif git apply --reverse --check "${local_patch}"; then
        echo "Patch already applied: $(basename -- "${local_patch}")"
    else
        echo "Patch does not apply cleanly: ${local_patch}" >&2
        exit 2
    fi
done

./scripts/feeds update -a

while IFS='=' read -r feed commit; do
    [[ -n "${feed}" ]] || continue
    [[ "${feed}" == \#* ]] && continue
    if [[ ! "${feed}" =~ ^[A-Za-z0-9_]+$ ]] || [[ ! "${commit}" =~ ^[0-9a-f]{40}$ ]]; then
        echo "Invalid feed lock entry: ${feed}=${commit}" >&2
        exit 2
    fi

    feed_tree="${BUILD_TREE}/feeds/${feed}"
    if [[ ! -d "${feed_tree}/.git" ]]; then
        echo "Locked feed checkout is missing: ${feed_tree}" >&2
        exit 2
    fi
    if [[ -n "$(git -C "${feed_tree}" status --porcelain)" ]]; then
        echo "Refusing to overwrite dirty feed checkout: ${feed_tree}" >&2
        exit 2
    fi
    if ! git -C "${feed_tree}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
        git -C "${feed_tree}" fetch --depth 1 origin "${commit}"
    fi
    git -C "${feed_tree}" checkout --quiet --detach "${commit}"
    actual_feed_commit="$(git -C "${feed_tree}" rev-parse HEAD)"
    if [[ "${actual_feed_commit}" != "${commit}" ]]; then
        echo "Feed ${feed} resolved to ${actual_feed_commit}; expected ${commit}." >&2
        exit 2
    fi
    echo "Locked feed ${feed} at ${commit}"
done < "${FEED_LOCK}"

./scripts/feeds install -a
cp "${CONFIG_SEED}" .config
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)" V=sc

target_dir="${BUILD_TREE}/bin/targets/qualcommax/ipq60xx"
if [[ ! -d "${target_dir}" ]]; then
    echo "Expected target output is missing: ${target_dir}" >&2
    exit 3
fi

mkdir -p "${ARTIFACT_DIR}"
found=0
while IFS= read -r -d '' artifact; do
    cp -- "${artifact}" "${ARTIFACT_DIR}/"
    found=1
done < <(find "${target_dir}" -maxdepth 1 -type f -iname '*gapd-7500*' -print0)

if [[ "${found}" -ne 1 ]]; then
    echo "No GAPD-7500 artifacts were generated." >&2
    exit 3
fi

echo "Build complete. Untracked binaries copied to ${ARTIFACT_DIR}"
echo "Review image metadata and checksums before any device use."
