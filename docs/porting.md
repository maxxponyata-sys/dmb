# Porting dmb to a new phone

A port is a folder in `devices/`. If the SoC has a mainline tree that dmb
doesn't know yet, add a folder in `kernels/` too.

## 1. Kernel

Look for the SoC in this order:

1. Upstream Linux (`arch/arm64/boot/dts/qcom/` and friends).
2. A SoC mainlining tree (for example sm7150-mainline, sm7125-mainline, msm8953-mainline) or the kernel postmarketOS ships for it: its `APKBUILD` names the tree and tag, and its `config-*.aarch64` is a good base config.
3. If there is none, the port is a mainlining project for the SoC first; dmb doesn't do downstream (vendor 3.x/4.x) kernels.

`kernels/<name>/kernel.conf`:

```sh
KERNEL_NAME="sm7150-mainline"
KERNEL_TAG="v7.1_rc3"                 # git tag or branch
KERNEL_GIT="https://github.com/…/linux.git"
KERNEL_COMMIT="<full sha of the tag>"  # checked after the clone
KERNEL_CONFIG="config"                 # base config in the same folder
KERNEL_DTS_SUBDIR="qcom"
```

`kernels/dmb.fragment` is added to every config (devtmpfs, USB gadget,
simpledrm, pstore). Device-specific options go to
`devices/<dev>/kernel.fragment`. Whatever the initramfs needs to reach the
root partition (storage, its PHY, clocks, regulators, pinctrl) and the USB
gadget must be built in (`=y`), because the dmb initramfs loads no modules.

## 2. Device

```bash
./dmb new-device vendor-codename
```

Then fill in `devices/vendor-codename/device.conf`.

**Boot image values.** Copy them from a boot.img that boots on the phone
(stock, LineageOS, TWRP):

```bash
unpack_bootimg --boot_img boot.img     # from the mkbootimg package
```

Some bootloaders also check `--board`, `--os_version` and
`--os_patch_level`; use the same values as that image.

**Device tree.** Start from a mainline DTS of a phone with the same SoC
and, if possible, the same PMICs. From the vendor's DTB/DTBO take:

- `qcom,msm-id` and `qcom,board-id` (Qualcomm bootloaders pick the DTB by them),
- `reserved-memory` — vendors move firmware carveouts; a wrong map means
  random crashes or a reset as soon as a remote processor starts,
- the framebuffer the bootloader leaves on (`cont_splash`) for a first
  `simple-framebuffer`,
- regulators and reset GPIO of the storage (UFS/eMMC), USB, buttons.

`tools/dtbo-dump.py dtbo.img outdir/` splits and decompiles a dtbo.img
or a kernel with appended DTBs. Overlays reference their targets through
`__fixups__`, which tells you which node each `fragment@N` changes.

Keep the first DTS small: framebuffer, storage, USB, buttons. Display
panels, touch, Wi-Fi, audio and modem come later, one at a time.

**Variants.** A DTS that includes the base one (`#include
"socname-vendor-codename.dts"`) and adds hardware still being tested can
be listed in `DEVICE_DTB_VARIANTS`: `DEVICE_DTB_VARIANTS="dsi"` builds
`boot-dsi.img` from `<DEVICE_DTB>-dsi.dtb` next to `boot.img`, so the
known-good image stays one flash away.

**Drivers that aren't upstream.** New files go under
`devices/<dev>/kernel/` with the kernel tree's layout (for example
`kernel/drivers/gpu/drm/panel/panel-vendor-model.c`); changes to existing
files (Kconfig, Makefile, other drivers) go to `devices/<dev>/patches/`
as `-p1` patches, applied once each. Turn them on in
`devices/<dev>/kernel.fragment`.

**DSI panels.** A command or video mode panel's init sequence is in the
vendor DTB as `qcom,mdss-dsi-on-command`: a list of `dtype last vc ack
wait dlen payload` records; `tools/dsi-cmds.py panel.dts` prints them
readably. Base a driver on an upstream panel of the same vendor and the
same mode.

## 3. Flashing

`DEVICE_FLASH_METHOD` is `fastboot` (most phones: `fastboot flash boot
boot.img`) or `odin` (Samsung: `./dmb pack` makes `*.tar.md5` for Odin's AP
slot). `devices/<dev>/dtbo.py`, if present, makes an empty dtbo image for
bootloaders that apply overlays to the DTB they boot.

Write the device's own guide as `docs/<device>.md`: unlock steps, button
combinations, risks, what works.
