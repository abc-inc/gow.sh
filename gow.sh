#!/usr/bin/env bash

# Copyright 2021 The gow.sh authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http: //www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# A sentinel zero-byte file to indicate that the Go version was downloaded and
# unpacked successfully.
declare -r UNPACKED_OKAY=".unpacked-success"

# Runs the "go" tool of the provided Go version.
function main() {
  local version
  local root
  version="$(basename "${1:-gotip}")"
  root="$(goroot "${version}")"

  local err
  if [[ $# -eq 2 && "$2" == "download" ]]; then
    if ! err="$(install "${root}" "${version}")"; then
      fatal "${version}: download failed: ${err}"
    fi
    echo "${err}"
    exit 0
  fi

  if [[ ! -f "${root}/${UNPACKED_OKAY}" ]]; then
    fatal "${version}: not downloaded. Run '$(basename "$0") ${version} download' to install to ${root}"
  fi

  local gobin
  gobin="${root}/bin/go$(exe)"
  export GOROOT="${root}"

  shift
  exec "${gobin}" "$@"
}

# Installs a version of Go to the named target directory,
# creating the directory as needed.
function install() {
  local target_dir="$1"
  local version="$2"

  if [[ -f "${target_dir}/${UNPACKED_OKAY}" ]]; then
    echo "${version}: already downloaded in ${target_dir}"
    return
  fi

  local go_url
  local head
  go_url="$(version_archive_url "${version}")"
  if ! head="$(curl -fILsS -w "%{http_code}" "${go_url}")"; then
    echo "server returned ${head##*$'\n'}"
    return 1
  fi

  local code
  code="${head##*$'\n'}"
  if [[ "${code}" == "404" ]]; then
    echo "no binary release of ${version} for $(get_os)/$(get_arch) at ${go_url}"
    return 1
  elif [[ "${code}" != "200" ]]; then
    echo "server returned ${code} checking size of ${go_url}"
    #    return 1
  fi

  local base="${go_url##*/}"
  local archive_file="${target_dir}/${base}"
  local len="${head,,}"
  len="${len##*content-length: }"
  len="${len%%[[:space:]]*}"

  if [[ ! -f "${archive_file}" ||
    "$(wc -c <"${archive_file}")" -ne "${len}" ]]; then

    mkdir -p "${target_dir}" || return
    curl -fLsS -o "${archive_file}" "${go_url}" || return

    local size
    size="$(wc -c <"${archive_file}")"
    if [[ ! -f "${archive_file}" || "${size}" -ne "${len}" ]]; then
      echo "downloaded file ${archive_file} size ${size} doesn't match server size ${len}"
      return 1
    fi
  fi

  local want_sha
  if ! want_sha="$(curl -fLsS "${go_url}.sha256")"; then
    echo "error downloading SHA256 of ${archive_file}: ${want_sha}"
    return 1
  fi

  local err
  if ! err="$(verify_sha256 "${archive_file}" "${want_sha}")"; then
    echo "error verifying SHA256 of ${archive_file}: ${err}"
    return 1
  fi

  echo "Unpacking ${archive_file} ..."
  if ! err=$(unpack_archive "${target_dir}" "${archive_file}"); then
    echo "extracting archive ${archive_file}: ${err}"
    return 1
  fi

  touch "${target_dir}/${UNPACKED_OKAY}"
  echo "Success. You may now run '$(basename "$0") ${version}'"

  local gobin
  gobin="${root}/bin/go$(exe)"
  export GOROOT="${root}"
  exec "${gobin}" tool dist banner
}

# Unpacks the provided archive zip or tar.gz file to target_dir,
# removing the "go/" prefix from file entries.
function unpack_archive() {
  local target_dir="$1"
  local archive_file="$2"

  find "${target_dir}" -maxdepth 1 -mindepth 1 \
    -not -name "*.${archive_file##*.}" \
    -exec rm -r "{}" \;

  case "${archive_file}" in
    *.zip) unpack_zip "${target_dir}" "${archive_file}" ;;
    *.tar.gz) unpack_tar_gz "${target_dir}" "${archive_file}" ;;
    *)
      echo "unsupported archive file"
      return 1
      ;;
  esac
}

# Extracts a tar.gz into the given target directory.
function unpack_tar_gz() {
  local target_dir="$1"
  local archive_file="$2"
  tar -C "${target_dir}" -xzf "${archive_file}" --strip-components 1
}

# Extracts a zip into the given target directory.
function unpack_zip() {
  local target_dir="$1"
  local archive_file="$2"
  unzip -q "${archive_file}" go/* -d "${target_dir}"
  mv "${target_dir}/go/"* "${target_dir}"
  rmdir "${target_dir}/go"
}

# Reports whether the named file has contents with SHA-256 of the given value.
function verify_sha256() {
  local file="$1"
  local wantHex="$2"
  if [[ "$(shasum -a 256 -b "${file}" | cut -d " " -f 1)" != "${wantHex}" ]]; then
    echo "${file} corrupt? does not have expected SHA-256 of ${wantHex}"
    return 1
  fi
}

# Returns the machine type:
# one of 386, amd64, arm, and so on.
function get_arch() {
  if [[ -n "${GOARCH:-}" ]]; then
    echo "${GOARCH}"
    return
  fi

  local arch
  arch="$(uname -m)"
  case "${arch}" in
    i?86) echo "386" ;;
    amd64 | x86_64) echo "amd64" ;;
    aarch64 | arm64 | armv8*) echo "arm64" ;;
    arm | armv6l | armv7l) echo "armv6l" ;;
    ppc*) echo "ppc64le" ;;
    *) fatal "cannot determine architecture. Please set GOARCH and run again" ;;
  esac
}

# Returns the operating system name (lowercase):
# one of darwin, freebsd, linux, and so on.
function get_os() {
  if [[ -n "${GOOS:-}" ]]; then
    echo "${GOOS}"
    return
  fi

  local os
  os="$(uname -s)"
  if [[ "${os,,}" =~ cygwin*|mingw*|msys*|windows* ]]; then
    echo "windows"
  else
    echo "${os,,}"
  fi
}

# Returns the zip or tar.gz URL of the given Go version.
function version_archive_url() {
  local version="$1"
  local arch
  local goos
  arch="$(get_arch)"
  goos="$(get_os)"

  local ext=".tar.gz"
  [[ "${goos}" != "windows" ]] || ext=".zip"

  local base_url="${GOBASEURL:-https://storage.googleapis.com/golang}"
  echo "${base_url}/${version}.${goos}-${arch}${ext}"
}

# Returns the OS specific file extension for binary executables.
function exe() {
  [[ "$(get_os)" != "windows" ]] || echo ".exe"
}

# Returns the root directory of the Go installation.
function goroot() {
  echo "${GOROOT:-${HOME}/sdk/$1}"
}

# Prints the error to stderr and exits with status 1.
function fatal() {
  echo "$@" >&2
  exit 1
}

main "$@"
