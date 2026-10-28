# dmb: Debian Mobile Bootstrap

> **Всё создано Богом.** Я поддерживаю Терри Дэвиса и Ричарда Столлмана.
>
> *Everything is created by God. I support Terry A. Davis and Richard Stallman.*

dmb builds a standalone Debian for Android phones: a mainline Linux kernel,
a small busybox initramfs, an Android `boot.img` and a Debian root
filesystem. It does the same job as postmarketOS' `pmbootstrap`, but the
result is plain Debian with Debian's own packages and Mesa (freedreno for
Qualcomm Adreno GPUs).

Each phone is a folder under `devices/`, and each kernel tree is a folder
under `kernels/`, so one kernel can serve many phones. Adding a phone is
covered in [docs/porting.md](docs/porting.md).

## Devices

| Device | Folder | SoC | Kernel | Status |
|---|---|---|---|---|
| Samsung Galaxy A80 (SM-A805F) | `samsung-r1q` | SM7150 (Snapdragon 730G) | Linux 7.1 (sm7150-mainline) | Works on hardware: Debian 13 with XFCE boots from UFS; DSI panel (new AMS628RF05 driver), Adreno 618 with freedreno (OpenGL 4.6/ES 3.2, kmscube at 60 fps) and turnip (Vulkan); USB serial console and USB networking. In progress: touchscreen (IST4050; its power is switched by a PCAL6524 GPIO expander). Built, not tested: modem DSP, Wi-Fi, Bluetooth (`boot-wifi`). See [docs/samsung-r1q.md](docs/samsung-r1q.md) (in Russian) |

## Requirements

A Linux host or WSL2 (tested on Ubuntu 26.04 in WSL2 on Windows 10):

```bash
sudo apt install build-essential bc bison flex libssl-dev gcc-aarch64-linux-gnu \
    device-tree-compiler mkbootimg cpio xz-utils lz4 e2fsprogs curl git patch perl \
    uidmap qemu-user-binfmt
```

`./dmb check` lists anything missing. e2fsprogs must be 1.47.1 or newer
(`mke2fs -d` reads the rootfs tarball directly). The root filesystem is built without
root through user namespaces (`uidmap` provides `newuidmap`); ARM64
packages are configured through qemu binfmt.

## Usage

```bash
./dmb list                 # devices
./dmb init samsung-r1q     # pick one (saved in ~/.config/dmb.conf)
./dmb build                # kernel, initramfs, boot.img, Debian rootfs, flash files
```

Or one step at a time: `./dmb kernel`, `./dmb initramfs`, `./dmb bootimg`,
`./dmb rootfs`, `./dmb pack`. Everything goes to `work/out/<device>/`.

Settings in `~/.config/dmb.conf`:

| Setting | Default | |
|---|---|---|
| `DEBIAN_SUITE` | `trixie` | Debian release |
| `UI` | `console` | `console`, `weston` or `phosh` |
| `USERNAME` / `PASSWORD` | `user` / `147147` | the login on the phone |

## How it boots

1. The phone's bootloader loads `boot.img`: the kernel with the device's DTB appended, and the dmb initramfs.
2. The initramfs finds the root partition by its GPT name (`userdata` on most phones) and checks it holds a dmb rootfs. It first looks with a read-only mount, so a partition that still holds Android's data is left alone.
3. It switches to Debian (systemd).

If anything goes wrong, or with `dmb.debug` on the kernel command line, the
initramfs starts a debug console over USB instead and prints why on the screen:

- a serial port (it shows up as a COM port on Windows, `/dev/ttyACM0` on Linux), with a shell at 115200 baud
- RNDIS networking: the phone is `172.16.42.1` and gives the PC `172.16.42.2`; `telnet 172.16.42.1`

The booted Debian keeps the same USB gadget: SSH to `172.16.42.1`, or log in
on the serial port.

## Layout

```
dmb                  the command
lib/                 build steps (kernel, initramfs, bootimg, rootfs, pack)
kernels/<name>/      kernel source (git tag + commit) and base config
kernels/dmb.fragment options every dmb kernel needs
devices/<name>/      device.conf, DTS, kernel.fragment, extra rootfs files,
                     kernel/ (new driver files) and patches/ for the kernel
initramfs/init       the initramfs script
rootfs/              files added to every Debian rootfs
tools/               helpers: dtbo-dump.py splits and decompiles dtbo/DTB images,
                     dsi-cmds.py decodes vendor panel init sequences,
                     sparse.py packs Android sparse images
```

## License

GPL-2.0, see `LICENSE`. Device trees keep their own license (BSD-3-Clause
for the SM7150 ones, like the upstream files they are based on). dmb
downloads the kernel and Debian packages at build time and commits no
binaries. Firmware that can't be redistributed is copied from the phone
itself after the first boot.
