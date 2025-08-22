#!/usr/bin/env bash
# © Broadcom. All Rights Reserved.
# The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

set -e

follow_link() {
    local file="$1"
    while [[ -h "${file}" ]]; do
        file="$(readlink "${file}")"
        if [[ ! -e "${file}" ]]; then
        echo "Error: Broken symbolic link: $1" >&2
        exit 1
        fi
    done
    printf '%s\n' "${file}"
}

show_help() {
    local exit_after="${1:-exit}"
    local script_name="$(basename "$0")"

    printf 'Usage: %s [options] [config_path]\n\n' "${script_name}"
    printf 'Options:\n'
    printf '  --help, -h, -H       Display this help message.\n\n'
    printf 'config_path:\n'
    printf '  Path to save the generated configuration files. (Optional).\n\n'

    if [[ -z "${input}" ]]; then
        if [[ "${exit_after}" == "exit" ]]; then
        exit 0
        fi
    fi
    read -p "Press Enter to continue..."
}

script_path="$(dirname "$(follow_link "$0")")"

config_path="${1:-${script_path}/config}"

if [[ "$1" == "--help" || "$1" == "-h" || "$1" == "-H" ]]; then
    show_help
    exit 0
fi

if ! mkdir -p "${config_path}"; then
    echo "Error: Failed to create directory: ${config_path}" >&2
    exit 1
fi

backup_dir=""
backup_taken=0

if [[ -d "${config_path}" && "$(find "${config_path}" -maxdepth 1 -type f -name "*.hcl" -print -quit 2>/dev/null)" ]]; then
    echo "> Backing up existing configurations..."
    backup_time=$(date +%Y%m%d-%H%M%S)
    backup_dir="${config_path}/backup.${backup_time}"
    if ! mkdir -p "${backup_dir}"; then
        echo "Error: Failed to create backup directory: ${backup_dir}" >&2
        exit 1
    fi
    find "${config_path}" -maxdepth 1 -type f -name "*.hcl" -print0 |
        xargs -0 -I {} bash -c 'if mv "$1" "${2}/$(basename "$1")"; then :; else echo "Error moving $1"; exit 1; fi' -- {} "${backup_dir}"
    if [[ $? -ne 0 ]]; then
        echo "Error: Some configuration files failed to move to backup" >&2
        exit 1
    fi
    if ! rm -f "${config_path}"/*.hcl; then
        echo "Error: Failed to remove original configuration files" >&2
        exit 1
    fi
    backup_taken=1
    echo "> Backup created: ${backup_dir}"
fi

cp -av "${script_path}"/builds/*.pkrvars.hcl.example "${config_path}" 2>&1 >/dev/null

find "${script_path}"/builds/*/ -type f -name "*.pkrvars.hcl.example" -print0 | while IFS= read -r -d $'\0' srcfile; do
    srcdir=$(dirname "${srcfile}" | tr -s /)
    dstfile=$(echo "${srcdir#"${script_path}"/builds/}" | tr '/' '-')
    cp -av "${srcfile}" "${config_path}/${dstfile}.pkrvars.hcl.example" 2>&1 >/dev/null
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to copy ${srcfile} to ${config_path}/${dstfile}.pkrvars.hcl.example" >&2
    fi
done

if [[ $? -ne 0 ]]; then
    echo "Error: One or more copy operations failed." >&2
    exit 1
fi

for file in "${config_path}"/*.pkrvars.hcl.example; do
    if ! mv -- "${file}" "${file%.example}"; then
        echo "Error: Failed to rename ${file}" >&2
        exit 1
    fi
done

echo "> Configuration setup complete: ${config_path}"
