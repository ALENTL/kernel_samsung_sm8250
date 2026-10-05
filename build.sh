#!/usr/bin/env bash

set -e

SECONDS=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==========================================================
# Configuration
# ==========================================================

KERNEL_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$KERNEL_DIR/out"

# Device
DEVICE="r8q"

# Defconfig
DEFCONFIG="vendor/kona-perf_defconfig"
SEC_CONFIG="vendor/samsung/kona-sec-common.config"
DEVICE_CONFIG="vendor/samsung/r8q.config"

# Neutron Clang
TOOLCHAIN_DIR="${NEUTRON_CLANG_DIR:-$KERNEL_DIR/toolchains/neutron-clang}"

# AnyKernel3
AK3_DIR="$KERNEL_DIR/AnyKernel3"

# Output
ZIPNAME="tl_kernel-${DEVICE}-$(date '+%Y%m%d-%H%M').zip"

BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTS_DIR="$BOOT_DIR/dts/vendor/qcom"

# Common Make Flags
MAKE_ARGS=(
  O="$OUT_DIR"
  ARCH=arm64
  CC=clang
  LD=ld.lld
  AS=llvm-as
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  STRIP=llvm-strip
  LLVM=1
  LLVM_IAS=1
)

# ==========================================================
# Neutron Clang
# ==========================================================

setup_toolchain() {
  echo -e "${YELLOW}[*] Setting up Neutron Clang...${NC}"

  if [ ! -x "$TOOLCHAIN_DIR/bin/clang" ]; then
    echo -e "${YELLOW}[!] Neutron Clang not found.${NC}"
    echo -e "${YELLOW}[*] Downloading latest Neutron Clang...${NC}"

    mkdir -p "$TOOLCHAIN_DIR"

    ASSET_URL=$(
      curl -fsSL \
        https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest |
        jq -r '
                .assets[]
                | select(.name | endswith(".tar.zst"))
                | .browser_download_url
              ' |
        head -n1
    )

    if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
      echo -e "${RED}[!] Failed to find Neutron Clang release.${NC}"
      exit 1
    fi

    curl -L "$ASSET_URL" |
      tar --zstd -x -C "$TOOLCHAIN_DIR" --strip-components=1
  fi

  export PATH="$TOOLCHAIN_DIR/bin:$PATH"

  echo -e "${GREEN}[+] Neutron Clang ready${NC}"
  clang --version | head -n1
}

# ==========================================================
# Kernel configuration
# ==========================================================

configure_kernel() {
  echo -e "${YELLOW}[*] Configuring kernel...${NC}"

  mkdir -p "$OUT_DIR"

  make "${MAKE_ARGS[@]}" \
    "$DEFCONFIG" \
    "$SEC_CONFIG" \
    "$DEVICE_CONFIG"
}

# ==========================================================
# Kernel compilation
# ==========================================================

build_kernel() {
  echo
  echo -e "${YELLOW}[*] Starting kernel compilation...${NC}"
  echo

  make -j"$(nproc --all)" "${MAKE_ARGS[@]}" \
    Image dtbo.img
}

# ==========================================================
# DTB generation
# ==========================================================

build_dtb() {
  echo -e "${YELLOW}[*] Generating combined DTB...${NC}"

  if [ ! -d "$DTS_DIR" ]; then
    echo -e "${RED}[!] DTS directory not found: $DTS_DIR${NC}"
    exit 1
  fi

  DTB_COUNT=$(find "$DTS_DIR" -type f -name "*.dtb" | wc -l)

  if [ "$DTB_COUNT" -eq 0 ]; then
    echo -e "${RED}[!] No DTB files found.${NC}"
    exit 1
  fi

  find "$DTS_DIR" -type f -name "*.dtb" -print0 |
    sort -z |
    xargs -0 cat >"$BOOT_DIR/dtb"

  echo -e "${GREEN}[+] Generated combined DTB${NC}"
  echo -e "${BLUE}    DTBs: $DTB_COUNT${NC}"
}

# ==========================================================
# Verify build output
# ==========================================================

verify_output() {
  echo -e "${YELLOW}[*] Checking build output...${NC}"

  for file in \
    "$BOOT_DIR/Image" \
    "$BOOT_DIR/dtbo.img" \
    "$BOOT_DIR/dtb"; do
    if [ ! -f "$file" ]; then
      echo -e "${RED}[!] Missing: $file${NC}"
      exit 1
    fi

    echo -e "${GREEN}[+] $(basename "$file")${NC}"
  done
}

# ==========================================================
# AnyKernel3
# ==========================================================

prepare_anykernel() {
  echo -e "${YELLOW}[*] Preparing AnyKernel3...${NC}"

  if [ ! -f "$AK3_DIR/anykernel.sh" ]; then
    echo -e "${RED}[!] AnyKernel3 not found: $AK3_DIR${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] Using repository AnyKernel3${NC}"

  cp "$BOOT_DIR/Image" \
    "$AK3_DIR/Image"

  cp "$BOOT_DIR/dtbo.img" \
    "$AK3_DIR/dtbo.img"

  cp "$BOOT_DIR/dtb" \
    "$AK3_DIR/dtb"

  echo -e "${GREEN}[+] Kernel files copied to AnyKernel3${NC}"
}

# ==========================================================
# Create ZIP
# ==========================================================

create_zip() {
  echo
  echo -e "${YELLOW}[*] Creating AnyKernel3 ZIP...${NC}"

  cd "$AK3_DIR"

  rm -f "../$ZIPNAME"

  zip -r9 \
    "../$ZIPNAME" \
    * \
    -x ".git/*" \
    -x "README.md" \
    -x "*placeholder"

  cd "$KERNEL_DIR"

  if [ ! -f "$ZIPNAME" ]; then
    echo -e "${RED}[!] Failed to create ZIP.${NC}"
    exit 1
  fi

  echo
  echo -e "${GREEN}===============================================${NC}"
  echo -e "${GREEN} Build completed successfully!${NC}"
  echo -e "${GREEN}===============================================${NC}"
  echo
  echo -e "Kernel:  $BOOT_DIR/Image"
  echo -e "DTBO:    $BOOT_DIR/dtbo.img"
  echo -e "DTB:     $BOOT_DIR/dtb"
  echo -e "ZIP:     $KERNEL_DIR/$ZIPNAME"
  echo

  ls -lh "$ZIPNAME"

  echo
  echo -e "${BLUE}SHA256:${NC}"
  sha256sum "$ZIPNAME"

  echo
  echo -e "${GREEN}Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s).${NC}"
}

# ==========================================================
# Main
# ==========================================================

cd "$KERNEL_DIR"

setup_toolchain
configure_kernel
build_kernel
build_dtb
verify_output
prepare_anykernel
create_zip
