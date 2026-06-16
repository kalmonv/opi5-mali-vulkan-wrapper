#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " Orange Pi 5 - Mali-G610 Vulkan Wrapper Setup"
echo " Recommended kernel: 5.10.x rockchip"
echo " Tested base: Ubuntu 22.04 Jammy ARM64"
echo " Vulkan backend: ARM Mali g29p1 + WSI wrapper"
echo " OpenGL backend: Panfrost/Panfork"
echo "===================================================="

if [ "$(uname -m)" != "aarch64" ]; then
    echo "ERROR: this script is intended for ARM64/aarch64 systems."
    exit 1
fi

if [ "${EUID}" -eq 0 ]; then
    echo "ERROR: do not run this script as root."
    echo "Run it as your normal user. The script will use sudo when needed."
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"

WORKDIR="${HOME}/Downloads"
BACKUP_DIR="${HOME}/backup-mali-vulkan-$(date +%Y%m%d-%H%M%S)"

WRAPPER_REPO="https://github.com/zeyadadev/mali-vulkan-icd-wrapper.git"
VULKAN_HEADERS_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"

MALI_G29P1_DEB_URL="https://github.com/ginkage/libmali-rockchip/releases/download/v1.9-1-4b399ed/libmali-valhall-g610-g29p1-x11-wayland-gbm_1.9-1_arm64.deb"

MALI_OPT_DIR="/opt/mali-g29p1"
MALI_LIB_DIR="${MALI_OPT_DIR}/usr/lib/aarch64-linux-gnu"
MALI_LIB="${MALI_LIB_DIR}/libmali.so"

echo
echo "[1/11] System information"
uname -a

echo
echo "[2/11] Creating backup at: ${BACKUP_DIR}"

mkdir -p "${BACKUP_DIR}"

dpkg -l | grep -E "mali|mesa|vulkan|panfork|rockchip" \
    | tee "${BACKUP_DIR}/packages-before.txt" || true

sudo cp -a /etc/vulkan "${BACKUP_DIR}/etc-vulkan-backup" 2>/dev/null || true
sudo cp -a /usr/share/vulkan "${BACKUP_DIR}/usr-share-vulkan-backup" 2>/dev/null || true

echo
echo "[3/11] Installing build dependencies"

sudo apt update

sudo apt install -y \
    git \
    wget \
    curl \
    ca-certificates \
    cmake \
    build-essential \
    ninja-build \
    pkg-config \
    libvulkan-dev \
    vulkan-tools \
    mesa-utils \
    libx11-dev \
    libxcb1-dev \
    libx11-xcb-dev \
    libxext-dev \
    libxcb-dri3-dev \
    libxcb-present-dev \
    libxcb-sync-dev \
    libxcb-randr0-dev \
    libxcb-shm0-dev \
    libxshmfence-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    libxxf86vm-dev \
    libdrm-dev \
    libwayland-dev \
    wayland-protocols \
    libudev-dev

echo
echo "[4/11] Downloading Mali g29p1 and configuring paths"

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

MALI_DEB="${WORKDIR}/$(basename "${MALI_G29P1_DEB_URL}")"

if [ ! -f "${MALI_DEB}" ]; then
    wget -O "${MALI_DEB}" "${MALI_G29P1_DEB_URL}"
else
    echo "Package already downloaded:"
    echo "${MALI_DEB}"
fi

sudo mkdir -p "${MALI_OPT_DIR}"
sudo dpkg-deb -x "${MALI_DEB}" "${MALI_OPT_DIR}"

REAL_MALI_LIB="$(
find "${MALI_LIB_DIR}" \
    -maxdepth 1 \
    -type f \
    \( \
        -name "libmali-valhall-g610-g29p1*.so*" \
        -o \
        -name "libmali*.so*" \
    \) \
    | sort \
    | head -n 1
)"

if [ -z "${REAL_MALI_LIB}" ]; then
    echo "ERROR: Mali library not found."
    echo "Search manually:"
    echo "find ${MALI_OPT_DIR} -iname '*mali*.so*'"
    exit 1
fi

sudo ln -sf "${REAL_MALI_LIB}" "${MALI_LIB}"

# --- INÍCIO DA CORREÇÃO DO DLOPEN ---
echo "Configuring ldconfig and symlinks for /opt isolation..."
sudo ln -sf libmali.so "${MALI_LIB_DIR}/libmali.so.0"
sudo ln -sf libmali.so "${MALI_LIB_DIR}/libmali.so.1"
echo "${MALI_LIB_DIR}" | sudo tee /etc/ld.so.conf.d/00-mali-g29p1.conf >/dev/null
sudo ldconfig
# --- FIM DA CORREÇÃO ---

echo
echo "Real Mali library:"
echo "${REAL_MALI_LIB}"

echo
echo "Wrapper target:"
readlink -f "${MALI_LIB}"

echo
echo "[5/11] Vulkan-Headers"

cd "${WORKDIR}"

if [ ! -d Vulkan-Headers ]; then
    git clone --depth 1 "${VULKAN_HEADERS_REPO}"
else
    cd Vulkan-Headers
    git pull --ff-only || true
    cd "${WORKDIR}"
fi

cd Vulkan-Headers

rm -rf build

cmake \
    -S . \
    -B build \
    -DCMAKE_INSTALL_PREFIX=/usr/local

sudo cmake --build build -j"$(nproc)"
sudo cmake --install build

echo
echo "[6/11] Verifying Vulkan headers"

grep -R "VkSurfacePresentModeEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null
grep -R "PFN_vkReleaseSwapchainImagesEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null
grep -R "VkFrameBoundaryEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null

echo "Vulkan headers OK"

echo
echo "[7/11] Downloading wrapper"

cd "${WORKDIR}"

if [ ! -d mali-vulkan-icd-wrapper ]; then
    git clone "${WRAPPER_REPO}"
else
    cd mali-vulkan-icd-wrapper
    git pull --ff-only || true
    cd "${WORKDIR}"
fi

echo
echo "[8/11] Building wrapper"

cd "${WORKDIR}/mali-vulkan-icd-wrapper"

rm -rf build64

export C_INCLUDE_PATH="/usr/local/include:${C_INCLUDE_PATH:-}"
export CPLUS_INCLUDE_PATH="/usr/local/include:${CPLUS_INCLUDE_PATH:-}"

export WRAPPER_INTERACTIVE=0
export WRAPPER_INSTALL_BUILD_DEPS=0
export WRAPPER_BUILD_64BIT=1
export WRAPPER_BUILD_32BIT=0
export WRAPPER_PRUNE_UNSELECTED_ARCH=1
export WRAPPER_MALI_DRIVER_PATH_64="${MALI_LIB}"

./scripts/wrapper/build_wrapper.sh \
    2>&1 | tee "${BACKUP_DIR}/build-wrapper.log"

echo
echo "[9/11] Disabling old ICD files"

sudo mkdir -p "${BACKUP_DIR}/old-icd"
sudo mkdir -p /etc/vulkan/icd.d

[ -f /etc/vulkan/icd.d/mali.json ] && \
sudo mv /etc/vulkan/icd.d/mali.json "${BACKUP_DIR}/old-icd/"

[ -f /etc/vulkan/icd.d/arm_mali.json ] && \
sudo mv /etc/vulkan/icd.d/arm_mali.json "${BACKUP_DIR}/old-icd/"

sudo ldconfig

echo
echo "[10/11] User permissions"

sudo usermod -aG video,render "${TARGET_USER}" || true

sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

echo
echo "[11/11] Validation"

echo
echo "Installed ICD files:"
ls -la /usr/share/vulkan/icd.d/ || true

echo
echo "ICD JSON:"
cat /usr/share/vulkan/icd.d/mali_icd.aarch64.json || true

echo
echo "Wrapper library:"
ls -la /usr/lib/aarch64-linux-gnu/libmali_wrapper.so* || true

echo
echo "Mali libraries:"
ls -la "${MALI_LIB_DIR}"/libmali* || true

echo
echo "Checking embedded paths:"
strings /usr/lib/aarch64-linux-gnu/libmali_wrapper.so \
    | grep -iE "/opt|g29|libmali" || true

echo
echo "===================================================="
echo " Installation completed"
echo "===================================================="

echo
echo "Backup:"
echo "${BACKUP_DIR}"

echo
echo "REBOOT REQUIRED:"
echo "sudo reboot"

echo
echo "After reboot run:"
echo "vulkaninfo --summary"
echo 'vulkaninfo | grep -E "deviceName|driverName|driverID|driverInfo|apiVersion"'
echo "glxinfo -B"
echo "vkcube"
