### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=tl_kernel by alentl @ xda-developers
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=r8q
supported.versions=11 - 17
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*
  set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin
} # end attributes

# boot shell variables
BLOCK=/dev/block/platform/soc/1d84000.ufshc/by-name/boot
IS_SLOT_DEVICE=0
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# init boot install & cmdline patching
split_boot
[ -z "$(file_getprop /system/build.prop ro.build.version.oneui)" ] && patch_cmdline "android.is_aosp" "android.is_aosp=1"

flash_generic dtbo
flash_boot ## end boot install
