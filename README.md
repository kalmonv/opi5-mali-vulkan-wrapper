# Orange Pi 5 Mali-G610 Vulkan Setup

Setup script to enable **Vulkan on the Mali-G610 GPU** used by the **Orange Pi 5 / RK3588S**, using the proprietary Rockchip/ARM Mali Vulkan driver together with a WSI wrapper that adds support for **X11, XCB, Xlib, and Wayland**.

This project was created after testing a real Orange Pi 5 setup where OpenGL acceleration worked through Panfrost/Panfork, but Vulkan either failed completely or worked only in headless/display mode without proper window surface support.

The final working setup uses:

```text
OpenGL  = Panfrost/Panfork
Vulkan  = ARM Mali proprietary driver through libmali + WSI wrapper
PanVK   = not used
```

## Purpose

The goal of this project is to automate the Vulkan setup on the Orange Pi 5 and fix the common situation where:

* `glxinfo -B` shows hardware-accelerated OpenGL through Panfrost;
* `vulkaninfo --summary` fails, falls back to `llvmpipe`, or detects Mali Vulkan without window surface support;
* `vkcube` fails because `VK_KHR_xcb_surface` is missing;
* the system has a Mali-G610 GPU, but Vulkan apps cannot open a window on X11 or Wayland.

After applying this setup, Vulkan should detect the GPU as:

```text
deviceName = Mali-LODX
driverID   = DRIVER_ID_ARM_PROPRIETARY
driverName = Mali-LODX
```

And the following Vulkan surface extensions should be available:

```text
VK_KHR_wayland_surface
VK_KHR_xcb_surface
VK_KHR_xlib_surface
```

## Tested Hardware

This project was tested on:

```text
Board: Orange Pi 5
SoC: Rockchip RK3588S
GPU: ARM Mali-G610
Architecture: ARM64 / aarch64
```

## Tested System

The working environment used during testing was:

```text
OS: Ubuntu 22.04 Jammy ARM64
Kernel: 5.10.0-1012-rockchip
Mesa/OpenGL: Panfrost/Panfork
Vulkan: ARM Mali proprietary driver through libmali + wrapper
```

Kernel check:

```bash
uname -a
```

Tested output:

```text
Linux orangepi5 5.10.0-1012-rockchip #12-Ubuntu SMP Wed Aug 14 22:22:22 UTC 2024 aarch64 aarch64 aarch64 GNU/Linux
```

## Image Used

The working setup was based on an Ubuntu/Rockchip image for the Orange Pi 5 using:

```text
Kernel: 5.10.0-1012-rockchip
Ubuntu: 22.04 Jammy ARM64
```

This project has not been validated as a universal solution for every Orange Pi 5 image.

Images using different kernels, such as `6.1.99-rockchip-rk3588`, may behave differently because the kernel-side Mali driver and userspace `libmali` version must be compatible.

## What This Script Does

The setup script performs the following tasks:

1. Installs build dependencies.
2. Installs the Rockchip Mali Vulkan userspace blob if missing.
3. Installs newer Vulkan headers from Khronos into `/usr/local`.
4. Builds `mali-vulkan-icd-wrapper`.
5. Installs the wrapper library:

```text
/usr/lib/aarch64-linux-gnu/libmali_wrapper.so
```

6. Installs the Vulkan ICD manifest:

```text
/usr/share/vulkan/icd.d/mali_icd.aarch64.json
```

7. Disables the old manually-created Mali ICD if present:

```text
/etc/vulkan/icd.d/mali.json
```

8. Configures `dma_heap` permissions.
9. Adds the current user to the required groups:

```text
video
render
```

## What This Project Is Not

This project does **not** install PanVK.

PanVK is the open-source Vulkan implementation for Mali GPUs in Mesa. In the tested environment, the available Panfork/Mesa packages provided working OpenGL acceleration but did not provide a working PanVK ICD for the Mali-G610.

This project uses the proprietary ARM Mali Vulkan driver because that was the working path for this setup.

Final result:

```text
OpenGL  = Panfrost/Panfork
Vulkan  = ARM Mali proprietary driver through libmali + wrapper
PanVK   = no
```

## Before the Fix

OpenGL was already working:

```text
OpenGL vendor string: Panfrost
OpenGL renderer string: Mali-G610 (Panfrost)
Accelerated: yes
```

But Vulkan had no usable X11/Wayland surface support.

Without the wrapper, `vulkaninfo` only showed extensions such as:

```text
VK_KHR_surface
VK_KHR_display
VK_EXT_headless_surface
```

The important window-system extensions were missing:

```text
VK_KHR_xcb_surface
VK_KHR_xlib_surface
VK_KHR_wayland_surface
```

Because of that, Vulkan applications that needed to open a graphical window could fail.

## After the Fix

After installing the wrapper, `vulkaninfo --summary` showed:

```text
deviceType = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
deviceName = Mali-LODX
driverID   = DRIVER_ID_ARM_PROPRIETARY
driverName = Mali-LODX
```

And the following surface extensions became available:

```text
VK_KHR_wayland_surface
VK_KHR_xcb_surface
VK_KHR_xlib_surface
```

This allows Vulkan applications to use X11, XCB, Xlib, or Wayland surfaces.

## Main Dependencies

The script installs packages such as:

```text
git
wget
cmake
build-essential
ninja-build
pkg-config
libvulkan-dev
vulkan-tools
libx11-dev
libxcb1-dev
libxrandr-dev
libdrm-dev
libwayland-dev
wayland-protocols
libudev-dev
```

It also installs newer Vulkan headers from:

```text
KhronosGroup/Vulkan-Headers
```

This is required because the default Vulkan headers from Ubuntu 22.04 are too old to build the wrapper successfully.

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR-USERNAME/orange-pi-5-mali-g610-vulkan-setup.git
cd orange-pi-5-mali-g610-vulkan-setup
```

Make the script executable:

```bash
chmod +x setup-mali-vulkan-wrapper.sh
```

Run the setup:

```bash
./setup-mali-vulkan-wrapper.sh
```

Reboot after installation:

```bash
sudo reboot
```

## Testing Vulkan

After rebooting, run:

```bash
vulkaninfo --summary
```

Expected result:

```text
deviceName = Mali-LODX
driverID   = DRIVER_ID_ARM_PROPRIETARY
driverName = Mali-LODX
```

Check for X11 and Wayland surface support:

```bash
vulkaninfo | grep -E "VK_KHR_xcb_surface|VK_KHR_xlib_surface|VK_KHR_wayland_surface|deviceName|driverName|driverID"
```

Expected result:

```text
VK_KHR_wayland_surface
VK_KHR_xcb_surface
VK_KHR_xlib_surface
deviceName = Mali-LODX
driverID = DRIVER_ID_ARM_PROPRIETARY
driverName = Mali-LODX
```

Run a practical Vulkan test:

```bash
vkcube
```

If you are using Wayland and `vkcube-wayland` is available:

```bash
vkcube-wayland
```

## Testing OpenGL

To confirm OpenGL still uses Panfrost/Panfork:

```bash
glxinfo -B
```

Expected result:

```text
OpenGL vendor string: Panfrost
OpenGL renderer string: Mali-G610 (Panfrost)
Accelerated: yes
```

## Checking the Installed ICD

The wrapper installs this ICD file:

```text
/usr/share/vulkan/icd.d/mali_icd.aarch64.json
```

Expected content:

```json
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/aarch64-linux-gnu/libmali_wrapper.so",
        "api_version": "1.3.276"
    }
}
```

Check it with:

```bash
cat /usr/share/vulkan/icd.d/mali_icd.aarch64.json
```

## Forcing the Wrapper ICD

To force Vulkan to use only the wrapper ICD:

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/mali_icd.aarch64.json vulkaninfo --summary
```

To force `vkcube` to use the wrapper:

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/mali_icd.aarch64.json vkcube
```

## Debugging

If something fails, run:

```bash
VK_LOADER_DEBUG=all \
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/mali_icd.aarch64.json \
vkcube 2>&1 | tee ~/vkcube-wrapper-debug.log
```

Filter the important lines:

```bash
grep -iE "error|failed|xcb|xlib|wayland|surface|dma|heap|mali|wrapper" ~/vkcube-wrapper-debug.log | head -200
```

## Permissions

The wrapper creates a udev rule for `dma_heap`:

```text
/etc/udev/rules.d/99-mali-wrapper-dma-heap.rules
```

Expected rule:

```text
SUBSYSTEM=="dma_heap", OWNER="root", GROUP="video", MODE="0660"
```

The user should be in the following groups:

```text
video
render
```

Check with:

```bash
id
```

If needed, add the user to the required groups:

```bash
sudo usermod -aG video,render $USER
sudo reboot
```

## Installed Files

Main files installed by the setup:

```text
/usr/lib/aarch64-linux-gnu/libmali_wrapper.so
/usr/lib/aarch64-linux-gnu/libmali_wrapper.so.1
/usr/lib/aarch64-linux-gnu/libmali_wrapper.so.1.0.0
/usr/share/vulkan/icd.d/mali_icd.aarch64.json
/etc/udev/rules.d/99-mali-wrapper-dma-heap.rules
```

The Mali Vulkan library used during testing was:

```text
/usr/lib/aarch64-linux-gnu/libmali-valhall-g610-g6p0-wayland-gbm-vulkan.so
```

## Compatibility

Tested with:

```text
Orange Pi 5
Rockchip RK3588S
Mali-G610
Ubuntu 22.04 Jammy ARM64
Kernel 5.10.0-1012-rockchip
```

It may also work on other RK3588/RK3588S boards with Mali-G610, such as:

```text
Orange Pi 5B
Orange Pi 5 Plus
Radxa Rock 5B
Radxa Rock 5C
Other RK3588/RK3588S boards
```

These boards have not been validated by this project yet.

## Limitations

* This is not PanVK.
* It uses the proprietary ARM Mali Vulkan driver.
* It may depend on the Rockchip kernel version.
* It may not work with every Orange Pi 5 image.
* It may not work with every `libmali` version.
* The script targets ARM64/aarch64.
* 32-bit/armhf wrapper build is disabled by default.

## Manual Uninstall

To remove the wrapper:

```bash
sudo rm -f /usr/lib/aarch64-linux-gnu/libmali_wrapper.so
sudo rm -f /usr/lib/aarch64-linux-gnu/libmali_wrapper.so.1
sudo rm -f /usr/lib/aarch64-linux-gnu/libmali_wrapper.so.1.0.0
sudo rm -f /usr/share/vulkan/icd.d/mali_icd.aarch64.json
sudo rm -f /etc/udev/rules.d/99-mali-wrapper-dma-heap.rules
sudo ldconfig
sudo udevadm control --reload-rules
sudo udevadm trigger
```

If you backed up an older ICD file, you can restore it manually:

```bash
sudo mkdir -p /etc/vulkan/icd.d
sudo cp ~/backup-vulkan-icd-antigo/mali.json /etc/vulkan/icd.d/
```

## Credits

This project uses or relies on:

```text
zeyadadev/mali-vulkan-icd-wrapper
KhronosGroup/Vulkan-Headers
Rockchip Mali userspace blob
Mesa / Panfrost / Panfork
```

## Expected Final Result

After setup, the Orange Pi 5 should report:

```text
OpenGL:
  Vendor: Panfrost
  Renderer: Mali-G610 (Panfrost)
  Accelerated: yes

Vulkan:
  Device: Mali-LODX
  Driver: ARM proprietary
  X11/XCB surface: yes
  Xlib surface: yes
  Wayland surface: yes
```

## Warning

Use this project at your own risk. This script modifies graphics libraries, Vulkan ICD files, and udev rules.

Make backups before running it on important systems.
