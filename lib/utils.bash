#!/usr/bin/env bash

set -euo pipefail

# TODO: Ensure this is the correct GitHub homepage where releases can be downloaded for atlas.
GH_REPO="https://github.com/ariga/atlas"
TOOL_NAME="atlas"
TOOL_TEST="atlas version"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if atlas is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	git ls-remote --tags --refs "$GH_REPO" | \
		grep -o 'refs/tags/.*' | \
		cut -d/ -f3-
}

list_all_versions() {
	list_github_tags | \
		grep -e '^v'
}

download_release() {
	local version filename url
	version="$1"
	filename="$2"

	get_architecture
	url="https://release.ariga.io/atlas/atlas-community-$OS-$PLATFORM-$version"
	if [[ "$OS" == *"windows"* ]];
	then
		url=$url.exe
	fi

	echo "* Downloading $TOOL_NAME release $version..."
	curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

		# TODO: Assert atlas executable exists.
		local tool_cmd
		tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
		test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}

get_architecture() {
    local _ostype _cputype _os
    _ostype="$(uname -s)"
    _cputype="$(uname -m)"

    if [ "$_ostype" = Darwin ] && [ "$_cputype" = i386 ]; then
        # Darwin `uname -m` lies
        if sysctl hw.optional.x86_64 | grep -q ': 1'; then
            _cputype=x86_64
        fi
    fi

    CHIPSET="$_cputype"

    case "$_cputype" in
    xscale | arm | armv6l | armv7l | armv8l | aarch64 | arm64)
        _cputype=arm64
        ;;
    x86_64 | x86-64 | x64 | amd64)
        _cputype=amd64
        ;;
    *)
        err "unknown CPU type: $_cputype"
        ;;
    esac

    case "$_ostype" in
    Linux | FreeBSD | NetBSD | DragonFly)
        _ostype=linux
        _os=Linux
        # If the requested Atlas Version is prior to v0.12.1, the libc implementation is musl,
        # or the glibc version is <2.31, use the musl build.
        if [ "$ATLAS_VERSION" != "latest" ] &&
            [ "$(printf '%s\n' "v0.12.1" "$ATLAS_VERSION" | sort -V | head -n1)" = "$ATLAS_VERSION" ]; then
            if ldd --version 2>&1 | grep -q 'musl' ||
                [ "$(version \"$(ldd --version | awk '/ldd/{print $NF}')\")" -lt "$(version '2.31')" ]; then
                _cputype="$_cputype-musl"
            fi
        fi
        ;;
    Darwin)
        _ostype=darwin
        _os=MacOS
        # We only provide arm64 builds for Mac starting with v0.12.1. If the requested version below
        # v0.12.1, fallback to amd64 builds, since M1 chips are capable of running amd64 binaries.
        if [ "$ATLAS_VERSION" != "latest" ] &&
            [ "$(printf '%s\n' "v0.12.1" "$ATLAS_VERSION" | sort -V | head -n1)" = "$ATLAS_VERSION" ]; then
            _cputype=amd64
        fi
        ;;
    *)
        err "unrecognized OS type: $_ostype"
        ;;
    esac

    PLATFORM="$_ostype-$_cputype"
    OS="$_os"
}



#!/bin/sh

# This is a little script that can be downloaded from the internet to install the Atlas CLI.
# It attempts to determine architecture and distribution to download and install the correct binary.
# It runs on most Unix shells like {a,ba,da,k,z}sh.

# set -u

# ATLAS_NO_UPDATE_NOTIFIER=true

# ATLAS_UPDATE_SRV="${ATLAS_UPDATE_SRV:-https://release.ariga.io/atlas}"
# ATLAS_VERSION="${ATLAS_VERSION:-latest}"
# ATLAS_DEBUG="${ATLAS_DEBUG:-false}"
# CI="${CI:-false}"

# C_VERSION="0.2.0"
# C_FLAVOR_COMMUNITY="community"
# C_DEFAULT_ATLAS_INSTALL_PATH="/usr/local/bin/atlas"

# main() {
#     # Prerequisites
#     need_cmd uname
#     need_cmd mktemp
#     need_cmd chmod
#     need_cmd chown
#     need_cmd mkdir

#     local _skip_prompt=false
#     local _install=true
#     local _path=$C_DEFAULT_ATLAS_INSTALL_PATH
#     local _path_set=false
#     local _community=false
#     local _user_platform _ua_extend
#     # Consume flags
#     while [ $# -gt 0 ]; do
#         case "$1" in
#         "-y" | "--yes")
#             _skip_prompt=true
#             ;;
#         "-o" | "--output")
#             shift
#             _path=$1
#             _path_set=true
#             ;;
#         "--community")
#             _community=true
#             ;;
#         "--platform")
#             shift
#             _user_platform=$1
#             ;;
#         "--no-install")
#             _install=false
#             ;;
#         "--user-agent")
#             shift
#             _ua_extend=$1
#             ;;
#         "--help")
#             printHelp
#             ;;
#         esac
#         shift
#     done

#     # If the binary should only be downloaded but not installed, path must be set.
#     if [ "$_install" = false ] && [ "$_path_set" = false ]; then
#         err "Flag '--no-install' requires flag '-o | --output' to be set as well."
#     fi

#     # Under some circumstances we skip prompting,
#     # e.g. in CI systems or if there is no tty to read input from.
#     if [ "$CI" = "true" ] || ! sh -c ': >/dev/tty' >/dev/null 2>&1; then
#         _skip_prompt=true
#     fi

#     if [ "$_path_set" = false ] && check_cmd "atlas"; then
#         local _out="$(atlas version)"
#         # Ensure this binary is ours before attempting to override.
#         # Run 'atlas version' and ensure it contains the string 'ariga'.
#         # If so, proceed. If not, ask where to save (if possible).
#         if [ "${_out#*/ariga/atlas/}" != "$_out" ]; then
#             _path="$(which atlas)"
#         elif [ "$_skip_prompt" = false ]; then
#             echo "Found '$_path', but it is not Atlas CLI."
#             echo "To override '$_path' type 'yes'."
#             echo "To install to a different location, specify the path."
#             local _prompt="Type 'yes' or path: "
#             if [ -t 0 ]; then
#                 read -p "$_prompt" _path
#             else
#                 read -p "$_prompt" _path </dev/tty
#             fi
#             if [ "$_path" = "yes" ]; then
#                 _path=$C_DEFAULT_ATLAS_INSTALL_PATH
#             fi
#             if [ -z "$_path" ]; then
#                 err "Invalid path: '$_path'"
#             fi
#         else
#             # Either there is no tty or prompting was disabled by flag.
#             err "Found '$_path', but it is not Atlas CLI.\nSpecify installation location using the '-o PATH' flag!"
#         fi
#     fi

#     # Determine architecture and cpu type.
#     get_architecture || return 1
#     local _platform="${_user_platform:-$PLATFORM}"
#     local _os="$OS"
#     local _chipset="$CHIPSET"

#     # Create a temporary download folder.
#     local _dir
#     _dir="$(ensure mktemp -d)"
#     ensure mkdir -p "$_dir"

#     # Build filename and download path.
#     local _file="atlas"
#     if [ "$_community" = true ]; then
#         _file="$_file-$C_FLAVOR_COMMUNITY"
#     fi
#     _file="$_file-$_platform-$ATLAS_VERSION"
#     case "$_platform" in *windows*)
#         _file="$_file.exe"
#     esac
#     local _url="$ATLAS_UPDATE_SRV/$_file"
#     if [ "$ATLAS_DEBUG" = "true" ]; then
#         _url="$_url?test=1"
#     fi

#     # Since this script is most likely piped into sh, there is no stdin to prompt the user on.
#     # In that case explicitly connect to /dev/tty to read user input.
#     if [ "$_skip_prompt" = false ]; then
#         # We want to prompt the user. If there is a stdin, use it. If not, use /dev/tty.
#         local _yn _prompt
#         if [ "$_install" = true ]; then
#             _prompt="Install"
#         else
#             _prompt="Download"
#         fi
#         local _prompt="$_prompt '$_file' to '$_path'? [y/N] "
#         if [ -t 0 ]; then
#             read -p "$_prompt" _yn
#         else
#             read -p "$_prompt" _yn </dev/tty
#         fi
#         case "$_yn" in
#         "y" | "yes" | "Y" | "YES") ;;
#         *) exit ;;
#         esac
#     fi

#     echo "Downloading $_url"
#     local _curlVersion="$(curl --version | head -n 1 | awk '{ print $2 }')"
#     local _ua="Atlas Installer/$C_VERSION ($_os; $_chipset) cURL/$_curlVersion"
#     if [ -n "${_ua_extend-}" ]; then
#         _ua="$_ua $_ua_extend"
#     fi
#     cd "$_dir"
#     ensure_silent curl -L -o "$_file" -A "$_ua" --fail "-#" "$_url" || back
#     back

#     # If the user wanted us to install the binary for him do so.
#     if [ "$_install" = true ]; then
#         case "$_platform" in
#         *linux*)
#             # Install the binary in path
#             local _install="install -o root -g root -m 0755 $_dir/$_file $_path"
#             if ! [ "$(id -u)" = 0 ]; then
#                 _install="sudo $_install"
#             fi
#             ensure_silent eval "$_install"
#             ;;
#         *darwin*)
#             ensure chmod +x "$_dir/$_file"
#             # On Mac sometimes the default path does not exist.
#             local _mkdir="mkdir -p ${_path%/*}"
#             local _mv="mv $_dir/$_file $_path"
#             if ! [ "$(id -u)" = 0 ]; then
#                 _mkdir="sudo $_mkdir"
#                 _mv="sudo $_mv"
#             fi
#             ensure_silent eval "$_mkdir"
#             ensure_silent eval "$_mv"
#             if ! [ "$(id -u)" = 0 ]; then
#                 ensure_silent sudo chown root: "$_path"
#             fi
#             ;;
#         esac
#         # Run once to ensure atlas is installed correctly.
#         ensure "$_path" version
#         echo "Installation successful!"
#     else
#         mkdir -p ${_path%/*}
#         mv "$_dir/$_file" "$_path"
#         echo "Download successful!"
#     fi
# }

# need_cmd() {
#     if ! check_cmd "$1"; then
#         err "need '$1' (command not found)"
#     fi
# }

# check_cmd() {
#     command -v "$1" >/dev/null 2>&1
# }

# ensure() {
#     if ! "$@"; then err "command failed: $*"; fi
# }

# ensure_silent() {
#     if ! "$@"; then exit 1; fi
# }

# err() {
#     echo "$1" >&2
#     exit 1
# }

# version() {
#     echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
# }

# back() {
#     >/dev/null cd -
# }

# printHelp() {
#     echo "Atlas CLI Shell Installer.

# Usage:
#     curl -sSf https://atlasgo.sh | sh
#     curl -sSf https://atlasgo.sh | sh -s -- [options]

# Options:
#     -y, --yes     Skip interactive prompting defaulting to 'yes'
#     -o, --output  Path to save the binary to, attempting to create it, if it does not exist
#     --community   Install the community version
#     --no-install  Download only without adding to PATH
#     --platform    Specify platform to assume, e.g. 'darwin-arm64', 'linux-amd64', ...
#     --user-agent  Add comments to User Agent information sent by cURL request
#     --help        Print this help message

# Environment:
#     ATLAS_VERSION  Set the version to install (default: 'latest')
#     CI             Disables prompting for CI systems
# "
#     exit 0
# }

# # main "$@" || exit 1

# get_architecture
# echo $OS
# echo $PLATFORM
