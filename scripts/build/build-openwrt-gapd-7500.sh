#!/usr/bin/env bash
set -euo pipefail

# Windows can leak relative entries such as "Files/Common" into WSL PATH.
# GNU find -execdir rejects that PATH, so use only absolute Linux directories.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

OPENWRT_URL="https://github.com/openwrt/openwrt.git"
OPENWRT_COMMIT="9f62ca8ff14d701928b425b53d0093de80eb0df6"
PORT_TREE="94fa35b23dae1987967bc8696a5c07c832e870b2"
PATCH_SHA256="1f5d23412e2e916677875420032fe776796d4a7a5667033bf1087cce27851a6c"
BDF_SHA256="7d283ff5677c35009dc07b9f816f4a64fa80ab224db3610c74ef5370f4421fbb"
INITRAMFS_BYTES=14802824
INITRAMFS_SHA256="7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400"
FACTORY_BYTES=13762560
FACTORY_SHA256="fe306d8fab0eb96c47649dadd3ee9fb731bdbbbcb587a45a5a8f00722edb892b"
BUILD_TREE="${GAPD_OPENWRT_BUILD_TREE:-/home/$(id -un)/gapd_7500_openwrt/.work/build/openwrt}"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PATCH_FILE="${PROJECT_DIR}/patches/official-openwrt/0001-qualcommax-add-LG-GAPD-7500-support.patch"
CONFIG_SEED="${PROJECT_DIR}/configs/openwrt-gapd-7500.config"
FEED_LOCK="${PROJECT_DIR}/configs/openwrt-feeds.lock"
VERIFY_SCRIPT="${PROJECT_DIR}/scripts/build/verify-gapd-initramfs.py"
ARTIFACT_DIR="${PROJECT_DIR}/artifacts/openwrt-gapd-7500-release"

for required_file in "${PATCH_FILE}" "${CONFIG_SEED}" "${FEED_LOCK}" "${VERIFY_SCRIPT}"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "Missing required file: ${required_file}" >&2
        exit 2
    fi
done

case "${BUILD_TREE}" in
    /mnt/*)
        echo "Build tree must use a native Linux filesystem, not /mnt: ${BUILD_TREE}" >&2
        exit 2
        ;;
esac

actual_patch_sha256="$(sha256sum "${PATCH_FILE}" | awk '{print $1}')"
if [[ "${actual_patch_sha256}" != "${PATCH_SHA256}" ]]; then
    echo "Port patch SHA-256 mismatch: ${actual_patch_sha256}" >&2
    exit 2
fi

if [[ ! -d "${BUILD_TREE}/.git" ]]; then
    if [[ -e "${BUILD_TREE}" ]]; then
        echo "Refusing to replace non-Git path: ${BUILD_TREE}" >&2
        exit 2
    fi
    mkdir -p "$(dirname -- "${BUILD_TREE}")"
    git init "${BUILD_TREE}"
    git -C "${BUILD_TREE}" remote add origin "${OPENWRT_URL}"
    git -C "${BUILD_TREE}" fetch --depth 1 origin "${OPENWRT_COMMIT}"
    git -C "${BUILD_TREE}" checkout --detach FETCH_HEAD
fi

actual_commit="$(git -C "${BUILD_TREE}" rev-parse HEAD)"
actual_tree="$(git -C "${BUILD_TREE}" rev-parse 'HEAD^{tree}')"
if [[ "${actual_tree}" == "${PORT_TREE}" ]]; then
    if [[ -n "$(git -C "${BUILD_TREE}" status --porcelain --untracked-files=no)" ]]; then
        echo "Refusing dirty patched build tree: ${BUILD_TREE}" >&2
        exit 2
    fi
elif [[ "${actual_commit}" == "${OPENWRT_COMMIT}" ]]; then
    if [[ -n "$(git -C "${BUILD_TREE}" status --porcelain --untracked-files=no)" ]]; then
        echo "Refusing dirty base build tree: ${BUILD_TREE}" >&2
        exit 2
    fi
    git -C "${BUILD_TREE}" -c user.name="GAPD Build" -c user.email=build@localhost \
        am "${PATCH_FILE}"
    actual_tree="$(git -C "${BUILD_TREE}" rev-parse 'HEAD^{tree}')"
    if [[ "${actual_tree}" != "${PORT_TREE}" ]]; then
        echo "Applied port tree is ${actual_tree}; expected ${PORT_TREE}." >&2
        exit 2
    fi
else
    echo "Build tree commit is ${actual_commit}, not pinned OpenWrt ${OPENWRT_COMMIT}." >&2
    echo "Refusing to reset or overwrite the existing tree." >&2
    exit 2
fi

cd "${BUILD_TREE}"
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
    if [[ "$(git -C "${feed_tree}" rev-parse HEAD)" != "${commit}" ]]; then
        echo "Feed ${feed} did not resolve to ${commit}." >&2
        exit 2
    fi
    echo "Locked feed ${feed} at ${commit}"
done < "${FEED_LOCK}"

./scripts/feeds uninstall -a
./scripts/feeds install luci
cp -- "${CONFIG_SEED}" .config
make defconfig

for required_config in \
    CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_lg_gapd-7500=y \
    CONFIG_TARGET_ROOTFS_INITRAMFS=y \
    CONFIG_TARGET_INITRAMFS_COMPRESSION_GZIP=y \
    CONFIG_PACKAGE_luci=y \
    CONFIG_PACKAGE_ethtool=y \
    CONFIG_PACKAGE_iw-full=y; do
    if ! grep -qxF "${required_config}" .config; then
        echo "Required build setting is missing: ${required_config}" >&2
        exit 2
    fi
done

make download -j"$(nproc)"
make -j"$(nproc)" V=sc

target_dir="${BUILD_TREE}/bin/targets/qualcommax/ipq60xx"
initramfs="${target_dir}/openwrt-qualcommax-ipq60xx-lg_gapd-7500-initramfs-uImage.itb"
factory="${target_dir}/openwrt-qualcommax-ipq60xx-lg_gapd-7500-squashfs-factory.ubi"
if [[ ! -f "${initramfs}" || ! -f "${factory}" ]]; then
    echo "Expected GAPD-7500 images are missing from ${target_dir}." >&2
    exit 3
fi

report_release_file() {
    local file="$1"
    local expected_bytes="$2"
    local expected_sha256="$3"
    local actual_bytes actual_sha256

    actual_bytes="$(stat -c '%s' "${file}")"
    actual_sha256="$(sha256sum "${file}" | awk '{print $1}')"
    echo "Built $(basename -- "${file}"): ${actual_bytes} bytes; SHA-256 ${actual_sha256}"
    if [[ "${actual_bytes}" != "${expected_bytes}" || "${actual_sha256}" != "${expected_sha256}" ]]; then
        echo "This is not byte-identical to the hardware-tested release reference." >&2
        if [[ "${GAPD_REQUIRE_TESTED_HASHES:-0}" == "1" ]]; then
            echo "GAPD_REQUIRE_TESTED_HASHES=1; refusing the non-reference output." >&2
            exit 3
        fi
    fi
}

report_release_file "${initramfs}" "${INITRAMFS_BYTES}" "${INITRAMFS_SHA256}"
report_release_file "${factory}" "${FACTORY_BYTES}" "${FACTORY_SHA256}"

factory_bytes="$(stat -c '%s' "${factory}")"
if (( factory_bytes == 0 || factory_bytes > 0x2620000 || factory_bytes % 0x20000 != 0 )); then
    echo "Factory UBI does not fit the 0x2620000-byte slot or PEB geometry." >&2
    exit 3
fi

mapfile -t built_bdfs < <(
    find "${BUILD_TREE}/build_dir" -type f \
        -path '*/root-qualcommax/lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin'
)
if [[ "${#built_bdfs[@]}" -eq 0 ]]; then
    echo "GAPD BDF is missing from the built root filesystem." >&2
    exit 3
fi
for built_bdf in "${built_bdfs[@]}"; do
    if [[ "$(sha256sum "${built_bdf}" | awk '{print $1}')" != "${BDF_SHA256}" ]]; then
        echo "Built GAPD BDF SHA-256 mismatch: ${built_bdf}" >&2
        exit 3
    fi
done

python3 "${VERIFY_SCRIPT}" "${initramfs}"
mkdir -p "${ARTIFACT_DIR}"
install -m 0644 "${initramfs}" "${ARTIFACT_DIR}/$(basename -- "${initramfs}")"
install -m 0644 "${factory}" "${ARTIFACT_DIR}/$(basename -- "${factory}")"
for metadata in config.buildinfo feeds.buildinfo manifest profiles.json version.buildinfo; do
    if [[ -f "${target_dir}/${metadata}" ]]; then
        install -m 0644 "${target_dir}/${metadata}" "${ARTIFACT_DIR}/${metadata}"
    fi
done
(
    cd "${ARTIFACT_DIR}"
    sha256sum \
        "$(basename -- "${initramfs}")" \
        "$(basename -- "${factory}")" > SHA256SUMS
)
"${BUILD_TREE}/staging_dir/host/bin/mkimage" -l "${initramfs}" \
    > "${ARTIFACT_DIR}/$(basename -- "${initramfs}").fit.txt"

echo "Verified initramfs and factory UBI copied to ${ARTIFACT_DIR}"
echo "The unverified sysupgrade image was intentionally not copied."
echo "No device transfer, boot, flash, MTD, UBI, or environment write was performed."
