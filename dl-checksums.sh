#!/usr/bin/env sh
set -e
DIR=~/Downloads
MIRROR=https://github.com/rumstead/gitops-toolkit/releases/download
APP=gitops-toolkit

dl() {
    local ver=$1
    local lchecksums=$2
    local os=$3
    local arch=$4
    local platform="${os}_${arch}"
    # parse out based on matching arch/checksum - this is because version includeds v0.0.0 whilst the file is 0.0.0
    local file=$(grep ${arch} ${lchecksums} | grep ${os} | awk '{print $2}')
    local url=$MIRROR/$ver/$file
    printf "    # %s\n" $url
    printf "    %s: sha256:%s\n" $platform $(grep $file $lchecksums | awk '{print $1}')
}

dl_ver() {
    local ver=$1
    local checksums="checksums.txt"
    local url=$MIRROR/$ver/$checksums
    local lchecksums="$DIR/${APP}-${ver}-${checksums}"
    if [ ! -e $lchecksums ];
    then
        wget -q -O $lchecksums $url
    fi

    printf "  # %s\n" $url
    printf "  %s:\n" $ver

    dl $ver $lchecksums Darwin arm64
    dl $ver $lchecksums Darwin x86_64
    dl $ver $lchecksums Linux arm64
    dl $ver $lchecksums Linux x86_64
    dl $ver $lchecksums Windows x86_64
}

dl_ver ${1:-v0.0.6}

