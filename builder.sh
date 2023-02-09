#! /bin/sh

sudo mkdir -p ~/bin && sudo curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && sudo chmod a+x ~/bin/repo && echo 'export PATH=~/bin:$PATH' >> ~/.bashrc && source ~/.bashrc

# Check https://source.android.com/docs/setup/start/initializing
sudo apt-get update -y && sudo apt-get install git -y && sudo apt-get install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig -y

git config --global user.email "rabil@techie.com"
git config --global user.name "Mohammed Rabil"

# DEVICE TREE
git clone https://github.com/anandhan07/android_device_xiaomi_vince -b ricedroid-13.0 device/xiaomi/vince

# VENDOR TREE
git clone https://github.com/anandhan07/android_vendor_xiaomi_vince -b 13.0 vendor/xiaomi/vince

# KERNEL TREE
git clone https://github.com/GhostMaster69-dev/android_kernel_xiaomi_vince -b master kernel/xiaomi/vince

# CLANG
git clone --depth=1 https://gitlab.com/anandhan07/aosp-clang.git -b clang-15.0.3 prebuilts/clang/host/linux-x86/clang-r468909b

# Viper4Android FX
# git clone --depth=1 https://gitlab.com/anandhan07/packages_apps_ViPER4AndroidFX.git -b master packages/apps/ViPER4AndroidFX

# Setup source
repo init --depth=1 --no-repo-verify -u https://github.com/ricedroidOSS/android -b thirteen -g default,-mips,-darwin,-notdefault

# Fetch source
repo sync -c --no-clone-bundle --force-remove-dirty --optimized-fetch --prune --force-sync -j8

## BUILDING RICEDROID
# For vanilla
. build/envsetup.sh && lunch lineage_vince-user && mka bacon | tee log.txt

# For GApps
. build/envsetup.sh && lunch lineage_vince-user && export WITH_GAPPS=true && mka bacon | tee log.txt
