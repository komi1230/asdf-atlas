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
	git ls-remote --tags --refs "$GH_REPO" |
		grep -o 'refs/tags/.*' |
		cut -d/ -f3-
}

list_all_versions() {
	list_github_tags |
		grep -e '^v' |
		sed -e 's/^v//'
}

download_release() {
	local version filename url
	version="v$1"
	filename="$2"

	get_architecture "$version"
	url="https://release.ariga.io/atlas/atlas-community-$PLATFORM-$version"
	if [[ "$OS" == *"windows"* ]]; then
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
		chmod +x "$install_path/atlas"

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
	local _version _ostype _cputype _os
	_version="$1"
	_ostype="$(uname -s)"
	_cputype="$(uname -m)"

	if [ "$_ostype" = Darwin ] && [ "$_cputype" = i386 ]; then
		# Darwin `uname -m` lies
		if sysctl hw.optional.x86_64 | grep -q ': 1'; then
			_cputype=x86_64
		fi
	fi

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
		if [ "$_version" != "latest" ] &&
			[ "$(printf '%s\n' "v0.12.1" "$_version" | sort -V | head -n1)" = "$_version" ]; then
			_tmp_version="$(ldd --version | awk '/ldd/{print $NF}')"
			if ldd --version 2>&1 | grep -q 'musl' ||
				[ "$(version \"$_tmp_version\")" -lt "$(version '2.31')" ]; then
				_cputype="$_cputype-musl"
			fi
		fi
		;;
	Darwin)
		_ostype=darwin
		_os=MacOS
		# We only provide arm64 builds for Mac starting with v0.12.1. If the requested version below
		# v0.12.1, fallback to amd64 builds, since M1 chips are capable of running amd64 binaries.
		if [ "$_version" != "latest" ] &&
			[ "$(printf '%s\n' "v0.12.1" "$_version" | sort -V | head -n1)" = "$_version" ]; then
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
