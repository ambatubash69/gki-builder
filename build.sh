#!/usr/bin/env bash
set -e

# Check chat_id and token
if [ -z "$chat_id" ]; then
    echo "error: please fill your CHAT_ID secret!"
    exit 1
fi

if [ -z "$token" ]; then
    echo "error: please fill TOKEN secret!"
    exit 1
fi

mkdir -p android-kernel && cd android-kernel

## Variables

# DO NOT change
WORK_DIR=$(pwd)
BUILDER_DIR="$WORK_DIR/.."
RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)
LAST_COMMIT_BUILDER=$(git log --format="%s" -n 1)

# Common
GKI_VERSION="android12-5.10"
CUSTOM_MANIFEST_REPO="https://github.com/ambatubash69/gki_manifest"
CUSTOM_MANIFEST_BRANCH="$GKI_VERSION"
ANYKERNEL_REPO="https://github.com/ambatubash69/Anykernel3"
ANYKERNEL_BRANCH="gki"
ZIP_NAME="gki-KVER-OPTIONE-$RANDOM_HASH.zip"
AOSP_CLANG_VERSION="r536225"
KERNEL_IMAGE="$WORK_DIR/out/${GKI_VERSION}/dist/Image"

# Import telegram functions
. "$BUILDER_DIR/telegram_functions.sh"

# if ksu = yes
if [ "${USE_KSU}" == "yes" ]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
else
    # if ksu = no
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

## Install needed packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y automake flex lzop bison gperf build-essential zip curl zlib1g-dev g++-multilib libxml2-utils bzip2 libbz2-dev libbz2-1.0 libghc-bzlib-dev squashfs-tools pngcrush schedtool dpkg-dev liblz4-tool make optipng maven libssl-dev pwgen libswitch-perl policycoreutils minicom libxml-sax-base-perl libxml-simple-perl bc libc6-dev-i386 lib32ncurses5-dev libx11-dev lib32z-dev libgl1-mesa-dev xsltproc unzip device-tree-compiler python2 rename libelf-dev dwarves rsync

## Install Google's repo
curl -o repo https://storage.googleapis.com/git-repo-downloads/repo
sudo mv repo /usr/bin
sudo chmod +x /usr/bin/repo

## Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$WORK_DIR/anykernel"

# Set swappiness
sudo sysctl vm.swappiness=100
sudo sysctl -p

# Repo sync
repo init --depth 1 "$CUSTOM_MANIFEST_REPO" -b "$CUSTOM_MANIFEST_BRANCH"
repo sync -j$(nproc --all) --force-sync

## Extract kernel version, git commit string
cd "$WORK_DIR/common"
KERNEL_VERSION=$(make kernelversion)
LAST_COMMIT_KERNEL=$(git log --format="%s" -n 1)
cd "$WORK_DIR"

# Set aosp clang version
sed -i "s/DUMMY1/$AOSP_CLANG_VERSION/g" $WORK_DIR/common/build.config.common

## Set kernel version in ZIP_NAME
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

## KernelSU setup
if [ "${USE_KSU}" == "yes" ]; then
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    cd "$WORK_DIR/KernelSU"
    KSU_VERSION=$(git describe --abbrev=0 --tags)
    cd "$WORK_DIR"
fi

## Apply kernel patches
git config --global user.email "eraselk@proton.me"
git config --global user.name "eraselk"

## SUSFS4KSU
if [ "${USE_KSU}" == "yes" ] && [ "${USE_KSU_SUSFS}" == "yes" ]; then
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu" -b "gki-${GKI_VERSION}"
    SUSFS_PATCHES="$WORK_DIR/susfs4ksu/kernel_patches"
    SUSFS_MODULE="$WORK_DIR/susfs4ksu/ksu_module_susfs"
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')
    cd "$WORK_DIR/susfs4ksu"
    LAST_COMMIT_SUSFS=$(git log --format="%s" -n 1)

    cd "$WORK_DIR/common"
    cp "$SUSFS_PATCHES/50_add_susfs_in_gki-${GKI_VERSION}.patch" .
    cp "$SUSFS_PATCHES/fs/susfs.c" ./fs/
    cp "$SUSFS_PATCHES/include/linux/susfs.h" ./include/linux/
    cp "$SUSFS_PATCHES/fs/sus_su.c" ./fs/
    cp "$SUSFS_PATCHES/include/linux/sus_su.h" ./include/linux/
    cd "$WORK_DIR/KernelSU"
    cp "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" .
    patch -p1 <10_enable_susfs_for_ksu.patch || exit 1
    cd "$WORK_DIR/common"
    patch -p1 <50_add_susfs_in_gki-${GKI_VERSION}.patch || exit 1

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
    SUSFS_MODULE_ZIP="ksu_module_susfs_${SUSFS_VERSION}.zip"
elif [ "${USE_KSU_SUSFS}" == "yes" ]; then
    echo "[ERROR] You can't use SUSFS without KSU enabled!"
    exit 1
fi
