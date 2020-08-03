#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -e -u

iso_name=archlinux
iso_label="ARCH_$(date +%Y%m)"
iso_version=$(date +%Y.%m.%d)
install_dir=arch
arch=$(uname -m)
work_dir=work
out_dir=out

script_path="$( cd -P "$( dirname "$(readlink -f "$0")" )" && pwd )"

umask 0022

# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e "${work_dir}/build.${1}_${arch}" ]]; then
        "$1"
        touch "${work_dir}/build.${1}_${arch}"
    fi
}

# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    local _cache_dirs
    _cache_dirs=("$(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g')")
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n "${_cache_dirs[@]}")|g" \
        "${script_path}/pacman.conf" > "${work_dir}/pacman.conf"
}

# Prepare working directory and copy custom airootfs files (airootfs)
make_custom_airootfs() {
    local _airootfs="${work_dir}/airootfs"
    mkdir -p -- "${_airootfs}"

    if [[ -d  "${script_path}/airootfs" ]]; then
        cp -af --no-preserve=ownership -- "${script_path}/airootfs/." "${_airootfs}"
        [[ -e "${_airootfs}/etc/shadow" ]] && chmod -f 0400 -- "${_airootfs}/etc/shadow"
        [[ -e "${_airootfs}/etc/gshadow" ]] && chmod -f 0400 -- "${_airootfs}/etc/gshadow"

        # Set up user home directories and permissions
        if [[ -e "${_airootfs}/etc/passwd" ]]; then
            while IFS=':' read -a passwd -r; do
                [[ "${passwd[5]}" == '/' ]] && continue

                if [[ -d "${_airootfs}${passwd[5]}" ]]; then
                    chown -hR -- "${passwd[2]}:${passwd[3]}" "${_airootfs}${passwd[5]}"
                    chmod -f 0750 -- "${_airootfs}${passwd[5]}"
                else
                    install -d -m 0750 -o "${passwd[2]}" -g "${passwd[3]}" -- "${_airootfs}${passwd[5]}"
                fi
             done < "${_airootfs}/etc/passwd"
        fi
    fi
}

# Packages (airootfs)
make_packages() {
    mkarchiso -v -w "${work_dir}" -C "${work_dir}/pacman.conf" -D "${install_dir}" \
        -p "$(grep -h -v '^#' "${script_path}/packages.x86_64"| sed ':a;N;$!ba;s/\n/ /g')" install
}

# Prepare ${install_dir}/boot/
make_boot() {
    mkdir -p "${work_dir}/iso/${install_dir}/boot/${arch}"
    cp "${work_dir}/airootfs/boot/archiso.img" "${work_dir}/iso/${install_dir}/boot/${arch}/archiso.img"
    cp "${work_dir}/airootfs/boot/vmlinuz-linux" "${work_dir}/iso/${install_dir}/boot/${arch}/"
}

# Prepare /${install_dir}/boot/syslinux
make_syslinux() {
    mkdir -p "${work_dir}/iso/${install_dir}/boot/syslinux"
    sed "s|%ARCHISO_LABEL%|${iso_label}|g;
         s|%INSTALL_DIR%|${install_dir}|g;
         s|%ARCH%|${arch}|g" "${script_path}/syslinux/syslinux.cfg" > \
             "${work_dir}/iso/${install_dir}/boot/syslinux/syslinux.cfg"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/ldlinux.c32" "${work_dir}/iso/${install_dir}/boot/syslinux/"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/menu.c32" "${work_dir}/iso/${install_dir}/boot/syslinux/"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/libutil.c32" "${work_dir}/iso/${install_dir}/boot/syslinux/"
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p "${work_dir}/iso/isolinux"
    sed "s|%INSTALL_DIR%|${install_dir}|g" "${script_path}/isolinux/isolinux.cfg" > \
        "${work_dir}/iso/isolinux/isolinux.cfg"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/isolinux.bin" "${work_dir}/iso/isolinux/"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/isohdpfx.bin" "${work_dir}/iso/isolinux/"
    cp "${work_dir}/airootfs/usr/lib/syslinux/bios/ldlinux.c32" "${work_dir}/iso/isolinux/"
}

# Build airootfs filesystem image
make_prepare() {
    mkarchiso -v -w "${work_dir}" -D "${install_dir}" prepare
}

# Build ISO
make_iso() {
    mkarchiso -v -w "${work_dir}" -D "${install_dir}" -L "${iso_label}" -o "${out_dir}" iso \
        "${iso_name}-${iso_version}-${arch}.iso"
}

run_once make_custom_airootfs
run_once make_pacman_conf
run_once make_packages
run_once make_boot
run_once make_syslinux
run_once make_isolinux
run_once make_prepare
run_once make_iso
