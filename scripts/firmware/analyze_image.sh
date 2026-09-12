#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 IMAGE OUTPUT_DIRECTORY" >&2
    exit 2
fi

image="$(realpath -- "$1")"
output="$(realpath -m -- "$2")"

if [[ ! -f "${image}" ]]; then
    echo "Image does not exist: ${image}" >&2
    exit 2
fi
if [[ -e "${output}" ]]; then
    echo "Refusing to overwrite existing analysis directory: ${output}" >&2
    exit 2
fi

mkdir -p "${output}"
report="${output}/analysis.txt"

{
    echo "analysis_time=$(date --iso-8601=seconds)"
    echo "input=${image}"
    stat --printf='size=%s\n' "${image}"
    sha256sum "${image}"
    file "${image}"
    echo
    echo "[binwalk]"
    binwalk "${image}"
} | tee "${report}"

description="$(file -b "${image}")"
if [[ "${description}" == *Squashfs* ]]; then
    {
        echo
        echo "[unsquashfs-superblock]"
        unsquashfs -s "${image}"
    } | tee -a "${report}"
    # Stock images can contain device nodes.  An unprivileged analysis user may
    # be unable to recreate those nodes even though all ordinary files extract
    # correctly, so keep that condition visible without aborting the report.
    unsquashfs -no-exit-code -no-progress -d "${output}/rootfs" "${image}"
elif [[ "${description}" == *UBI* ]] || head -c 4 "${image}" | grep -q 'UBI#'; then
    ubireader_display_info "${image}" | tee -a "${report}"
    ubireader_extract_images -o "${output}/ubi-images" "${image}"
    ubireader_extract_files -o "${output}/ubi-files" "${image}"
else
    echo "No automatic filesystem extraction selected for: ${description}" | tee -a "${report}"
fi

echo "Analysis complete; input was not modified."
