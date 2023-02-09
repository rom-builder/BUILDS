# DEVICE TREE
git clone https://github.com/anandhan07/android_device_xiaomi_vince -b ricedroid-13.0 device/xiaomi/vince

# VENDOR TREE
git clone https://github.com/anandhan07/android_vendor_xiaomi_vince -b 13.0 vendor/xiaomi/vince

# KERNEL TREE
git clone https://github.com/GhostMaster69-dev/android_kernel_xiaomi_vince -b master kernel/xiaomi/vince

# CLANG
git clone --depth=1 https://gitlab.com/anandhan07/aosp-clang.git -b clang-15.0.3 prebuilts/clang/host/linux-x86/clang-r468909b

# Viper4Android FX
git clone --depth=1 https://gitlab.com/anandhan07/packages_apps_ViPER4AndroidFX.git -b master packages/apps/ViPER4AndroidFX

## BUILDING RICEDROID
# For vanilla
. build/envsetup.sh && lunch lineage_vince-user && mka bacon | tee log.txt
