#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " Orange Pi 5 - Mali-G610 Vulkan Wrapper Setup"
echo " Kernel recomendado: 5.10.x rockchip"
echo " Ubuntu base: 22.04 Jammy ARM64"
echo "===================================================="

MALI_LIB="/usr/lib/aarch64-linux-gnu/libmali-valhall-g610-g6p0-wayland-gbm-vulkan.so"
MALI_DEB_URL="https://repo.rock-chips.com/edge/debian-release-v2.0.0/pool/main/r/rockchip-mali/rockchip-mali_1.9-12_arm64.deb"
WRAPPER_REPO="https://github.com/zeyadadev/mali-vulkan-icd-wrapper.git"
VULKAN_HEADERS_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"
WORKDIR="$HOME/Downloads"
BACKUP_DIR="$HOME/backup-mali-vulkan-$(date +%Y%m%d-%H%M%S)"

echo
echo "[1/10] Informações do sistema"
uname -a
echo

if [ "$(uname -m)" != "aarch64" ]; then
  echo "ERRO: este script é para ARM64/aarch64."
  exit 1
fi

echo "[2/10] Criando backup em: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

dpkg -l | grep -E "mali|mesa|vulkan|panfork|rockchip" | tee "$BACKUP_DIR/pacotes-antes.txt" || true

sudo cp -a /etc/vulkan "$BACKUP_DIR/etc-vulkan-backup" 2>/dev/null || true
sudo cp -a /usr/share/vulkan "$BACKUP_DIR/usr-share-vulkan-backup" 2>/dev/null || true

echo
echo "[3/10] Instalando dependências"
sudo apt update

sudo apt install -y \
  git wget curl ca-certificates \
  cmake build-essential ninja-build pkg-config \
  libvulkan-dev vulkan-tools \
  libx11-dev libxcb1-dev libx11-xcb-dev libxext-dev \
  libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev \
  libxcb-randr0-dev libxcb-shm0-dev libxshmfence-dev \
  libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxxf86vm-dev \
  libdrm-dev libwayland-dev wayland-protocols libudev-dev

echo
echo "[4/10] Instalando blob Rockchip Mali Vulkan, se necessário"

if [ ! -f "$MALI_LIB" ]; then
  cd "$WORKDIR"
  wget -O rockchip-mali_1.9-12_arm64.deb "$MALI_DEB_URL"
  sudo dpkg -i rockchip-mali_1.9-12_arm64.deb || sudo apt -f install -y
  sudo ldconfig
else
  echo "Lib Mali Vulkan já existe: $MALI_LIB"
fi

if [ ! -f "$MALI_LIB" ]; then
  echo "ERRO: lib Mali Vulkan não encontrada:"
  echo "$MALI_LIB"
  echo
  echo "Procure manualmente com:"
  echo 'find /usr/lib/aarch64-linux-gnu -iname "*mali*vulkan*.so*" -o -iname "*g610*vulkan*.so*" | sort'
  exit 1
fi

echo
echo "[5/10] Instalando Vulkan-Headers novos em /usr/local"

cd "$WORKDIR"

if [ ! -d Vulkan-Headers ]; then
  git clone --depth 1 "$VULKAN_HEADERS_REPO"
else
  cd Vulkan-Headers
  git pull --ff-only || true
  cd "$WORKDIR"
fi

cd "$WORKDIR/Vulkan-Headers"
rm -rf build
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr/local
sudo cmake --install build

echo
echo "[6/10] Verificando headers Vulkan novos"

grep -R "VkSurfacePresentModeEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null
grep -R "PFN_vkReleaseSwapchainImagesEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null
grep -R "VkFrameBoundaryEXT" /usr/local/include/vulkan/vulkan_core.h >/dev/null

echo "Headers Vulkan OK."

echo
echo "[7/10] Baixando/atualizando mali-vulkan-icd-wrapper"

cd "$WORKDIR"

if [ ! -d mali-vulkan-icd-wrapper ]; then
  git clone "$WRAPPER_REPO"
else
  cd mali-vulkan-icd-wrapper
  git pull --ff-only || true
  cd "$WORKDIR"
fi

echo
echo "[8/10] Compilando e instalando wrapper 64-bit"

cd "$WORKDIR/mali-vulkan-icd-wrapper"

rm -rf build64

export C_INCLUDE_PATH="/usr/local/include:${C_INCLUDE_PATH:-}"
export CPLUS_INCLUDE_PATH="/usr/local/include:${CPLUS_INCLUDE_PATH:-}"

WRAPPER_INTERACTIVE=0 \
WRAPPER_INSTALL_BUILD_DEPS=0 \
WRAPPER_BUILD_64BIT=1 \
WRAPPER_BUILD_32BIT=0 \
WRAPPER_PRUNE_UNSELECTED_ARCH=1 \
WRAPPER_MALI_DRIVER_PATH_64="$MALI_LIB" \
./scripts/wrapper/build_wrapper.sh 2>&1 | tee "$BACKUP_DIR/build-wrapper.log"

echo
echo "[9/10] Desativando ICD Mali antigo e mantendo só o wrapper"

sudo mkdir -p "$BACKUP_DIR/icd-antigo"

if [ -f /etc/vulkan/icd.d/mali.json ]; then
  sudo mv /etc/vulkan/icd.d/mali.json "$BACKUP_DIR/icd-antigo/"
fi

sudo mkdir -p /etc/vulkan/icd.d
sudo ldconfig

echo
echo "[10/10] Ajustando permissões"

sudo usermod -aG video,render "$USER" || true

sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

echo
echo "===================================================="
echo " Instalação concluída."
echo "===================================================="
echo
echo "ICD ativo:"
ls -la /usr/share/vulkan/icd.d/ || true
echo
cat /usr/share/vulkan/icd.d/mali_icd.aarch64.json || true
echo
echo "Agora REINICIE para aplicar grupos/permissões:"
echo
echo "sudo reboot"
echo
echo "Depois do reboot, teste:"
echo
echo "vulkaninfo --summary"
echo "vulkaninfo | grep -E \"VK_KHR_xcb_surface|VK_KHR_xlib_surface|VK_KHR_wayland_surface|deviceName|driverName|driverID\""
echo "vkcube"
echo
echo "Backup salvo em:"
echo "$BACKUP_DIR"
