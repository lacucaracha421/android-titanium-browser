#!/bin/bash
set -euo pipefail

source common.sh
set_keys
export VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git # https://github.com/chromium/chromium.git
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow imagemagick librsvg2-bin
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libgcc-s1:i386

# Chromium and gclient hooks apply patches in multiple independent Git repos
# (src, v8, search_engines_data, etc.), so the identity must be global in CI.
git config --global user.name "Titanium CI"
git config --global user.email "titanium-ci@users.noreply.github.com"

git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"
mkdir -p chromium/src/out/Default
cd chromium/src
git init
git remote add origin "$CHROMIUM_SOURCE"
git fetch --depth 1 "$CHROMIUM_SOURCE" +refs/tags/$VERSION:chromium_$VERSION
git checkout "$VERSION"

cp "$SCRIPT_DIR/.gclient" ../.gclient

# https://grapheneos.org/build#browser-and-webview
rm -rf $SCRIPT_DIR/vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{detailed,supported}-language*.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*component-updates.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,new-tab-card,predictive-back*}*.patch
# rm -rf $SCRIPT_DIR/vanadium/patches/*crashpad*.patch
replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"
git am --whitespace=nowarn --keep-non-patch $SCRIPT_DIR/vanadium/patches/*.patch

gclient sync -D --no-history --nohooks
gclient runhooks
./build/install-build-deps.sh --no-prompt

# Fail early with a useful error if hooks did not prepare Chromium metadata.
test -f build/util/LASTCHANGE.committime
# Vanadium/Titanium patch application must create this tree before local patches run.
test -d titanium

source "$SCRIPT_DIR/patch.sh"
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
if [ "${TITANIUM_ARM64_ONLY:-0}" = "1" ]; then
    sed -i 's/target_cpu = "arm"/target_cpu = "arm64"/' out/Default/args.gn
fi
gn gen out/Default
mkdir -p out/tmp out/release

if [ "${TITANIUM_ARM64_ONLY:-0}" = "1" ]; then
    autoninja -C out/Default chrome_public_apk
    apk_path=$(find out/Default/apks -name 'Chrome*.apk' -print -quit)
    test -n "$apk_path"
    mv "$apk_path" "out/tmp/$VERSION-arm64-v8a.apk"
    export PATH="$PWD/third_party/jdk/current/bin/:$PATH"
    export ANDROID_HOME="$PWD/third_party/android_sdk/public"
    sign_apk "out/tmp/$VERSION-arm64-v8a.apk" "out/release/$VERSION-arm64-v8a.apk"
    rm -rf "$SCRIPT_DIR/keys"
    exit 0
fi

autoninja -C out/Default chrome_public_apk
apk_path=$(find out/Default/apks -name 'Chrome*.apk' -print -quit)
test -n "$apk_path"
mv "$apk_path" "out/tmp/$VERSION-armeabi-v7a.apk"
sed -i 's/target_cpu = "arm"/target_cpu = "arm64"/' out/Default/args.gn
autoninja -C out/Default chrome_public_apk chrome_public_bundle
apk_path=$(find out/Default/apks -name 'Chrome*.apk' -print -quit)
aab_path=$(find out/Default/apks -name 'Chrome*.aab' -print -quit)
test -n "$apk_path"
test -n "$aab_path"
mv "$apk_path" "out/tmp/$VERSION-arm64-v8a.apk"
mv "$aab_path" "out/tmp/$VERSION-arm64-v8a.aab"

export PATH="$PWD/third_party/jdk/current/bin/:$PATH"
export ANDROID_HOME="$PWD/third_party/android_sdk/public"
sign_apk "out/tmp/$VERSION-armeabi-v7a.apk" "out/release/$VERSION-armeabi-v7a.apk"
sign_apk "out/tmp/$VERSION-arm64-v8a.apk" "out/release/$VERSION-arm64-v8a.apk"
sign_aab "out/tmp/$VERSION-arm64-v8a.aab" "out/release/$VERSION-arm64-v8a.aab"
rm -rf "$SCRIPT_DIR/keys"
