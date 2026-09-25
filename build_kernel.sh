#!/bin/bash
#
# Advanced kernel build script with dynamic toolchain provisioning 
# and on-the-fly defconfig patching for ZharVe1L Kernel.
#

set -e

# Define primary directory structures
KERNEL_DIR="$(pwd)"
OUT_DIR="${KERNEL_DIR}/out"
TC_DIR="${KERNEL_DIR}/toolchain/clang"
GCC_DIR="${KERNEL_DIR}/toolchain/gcc"
DEFCONFIG="a23_eur_open_defconfig"

export ARCH=arm64
export SUBARCH=arm64

# 1. Dynamic Toolchain Provisioning
echo "Verifying toolchain integrity..."
mkdir -p "${TC_DIR}" "${GCC_DIR}/aarch64" "${GCC_DIR}/arm"

if [ ! -f "${TC_DIR}/bin/clang" ]; then
    echo "Clang not found. Initiating Neutron Clang download..."
    wget -q "https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst" -O clang.tar.zst
    tar -xf clang.tar.zst -C "${TC_DIR}"
    rm clang.tar.zst
fi

if [ ! -f "${GCC_DIR}/aarch64/bin/aarch64-linux-android-gcc" ]; then
    echo "GCC aarch64 not found. Cloning from repository..."
    git clone --depth=1 https://github.com/KudProject/aarch64-linux-android-4.9.git "${GCC_DIR}/aarch64"
fi

if [ ! -f "${GCC_DIR}/arm/bin/arm-linux-androideabi-gcc" ]; then
    echo "GCC arm not found. Cloning from repository..."
    git clone --depth=1 https://github.com/KudProject/arm-linux-androideabi-4.9.git "${GCC_DIR}/arm"
fi

# 2. Path Export and Variable Assignments
export PATH="${TC_DIR}/bin:${PATH}"
GCC_64="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
GCC_32="${GCC_DIR}/arm/bin/arm-linux-androideabi-"

# 3. Ccache Initialization
if command -v ccache &> /dev/null; then
    export CCACHE_DIR=~/.cache/ccache
    export CCACHE_EXEC=$(which ccache)
    export USE_CCACHE=1
    # Limit ccache to 10G to prevent runner out-of-disk errors
    ccache -M 10G
    CCACHE_BIN="ccache "
    echo "Ccache initialized successfully."
else
    CCACHE_BIN=""
    echo "Ccache initialization failed."
fi

MAKE_ARGS=(
    -j"$(nproc --all)"
    O="${OUT_DIR}"
    ARCH=arm64
    CROSS_COMPILE="${GCC_64}"
    CROSS_COMPILE_ARM32="${GCC_32}"
    CC="${CCACHE_BIN}clang"
    CLANG_TRIPLE=aarch64-linux-gnu-
    HOSTCFLAGS="-fcommon -Wno-deprecated-declarations"
    LLVM_IAS=1
    KCFLAGS="-Wno-format-overflow -Wno-single-bit-bitfield-constant-conversion -Wno-format-truncation-non-kprintf -Wno-format-truncation -Wno-void-pointer-to-enum-cast -Wno-strict-prototypes -Wno-void-pointer-to-enum-cast -Wno-pointer-to-int-cast -Wno-fortify-source -Wno-align-mismatch -Wno-default-const-init-var-unsafe -Wno-implicit-int -Wno-unused-but-set-variable -Wno-implicit-enum-enum-cast -Wno-default-const-init-field-unsafe -Wno-default-const-init-var-unsafe"
)

# Fix Samsung Kconfig syntax warnings on-the-fly
echo "Fixing Samsung Kconfig warnings..."
sed -i 's/bool "Samsung TN Ramdump Feature"/tristate "Samsung TN Ramdump Feature"/' drivers/samsung/debug/Kconfig
sed -i '/^choice$/,/^endchoice$/ s/default [yn]//g' drivers/samsung/debug/Kconfig

# Fix blank help text warning for SENSORS_A96T365IF
echo "Fixing sensors Kconfig help text..."
sed -i '/config SENSORS_A96T365IF/,/help/ s/^[[:space:]]*help[[:space:]]*$/\thelp\n\t  Enable A96T365IF sensor./' drivers/sensors/Kconfig

# Fix type redefinition warning for VBUS_NOTIFIER
echo "Fixing vbus_notifier Kconfig type redefinition..."
sed -i 's/tristate "VBUS notifier support"/bool "VBUS notifier support"/' drivers/usb/common/vbus_notifier/Kconfig

# 4. Defconfig Generation
echo "Generating base defconfig..."
make "${MAKE_ARGS[@]}" "${DEFCONFIG}"
echo "Disabling DEBUG_INFO..."
./scripts/config --file "${OUT_DIR}/.config" --disable DEBUG_INFO

# 5. On-the-fly LTO Patching
echo "Applying LTO configuration: ${LTO:-none}"
if [ "${LTO}" = "thin" ]; then
    ./scripts/config --file "${OUT_DIR}/.config" --enable LTO_CLANG --enable THINLTO
elif [ "${LTO}" = "full" ]; then
    ./scripts/config --file "${OUT_DIR}/.config" --enable LTO_CLANG --disable THINLTO
else
    ./scripts/config --file "${OUT_DIR}/.config" --disable LTO_CLANG --disable THINLTO
fi

# 6. Kernel Compilation
echo "Initiating primary compilation phase..."
make "${MAKE_ARGS[@]}" CONFIG_SECTION_MISMATCH_WARN_ONLY=y

echo "Transferring compiled artifacts..."
cp "${OUT_DIR}/arch/arm64/boot/Image.gz" "${KERNEL_DIR}/Image.gz"

echo "Build sequence executed successfully."