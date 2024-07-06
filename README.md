# Buildroot + RAUC

## Overview

This project attempts to provide a working example system combining Buildroot,
U-Boot, and RAUC in a "works out of the box" example for the Raspberry Pi
Compute Module 4 (CM4).  The intent is for this to be usable as a base system
for some classes of IoT projects, and a hopefully easy to modify starting point
if you need something more customized to your needs.

#### Current features:

* U-Boot bootloader with redundant environment storage
* Symmetric Root-FS Slots with fallback on failed updates
* Rescue slot for recovery mode (eg: hold button when booting)
* Atomic updates of bootloader vfat partition (no fallback)
* Boot-time watchdog support (via recent RPi Firmware)
* Run-time watchdog timeouts (via systemd)
* Persistent data partition
* Temporary data partition for updates
* Partition layout (fits on a 4G uSD card with room to spare):
  * DOS MBR partition table
  * 4 MB "empty" (matches RPi images, used for U-Boot environment)
  * 256/512 MB vfat boot partition (uses boot-mbr-switch)
  * 256 MB squashfs rescue partition
  * 2x 900 MB A & B rootfs partitions
  * 128 MB Persistent data partition
  * 900 MB Upload partition (eg: storage for firmware updates)

## Getting Started

This project is a Buildroot external directory and can **not** be used alone.
You also need to have a local copy of the Buildroot project and a properly
configured build.  One simple way to do this would be:

### Building a bootable uSD image from scratch

```bash
# Create a working directory
mkdir ~/MyWorkDir
cd ~/MyWorkDir

# Pull in the required projects
git clone --depth 1 --branch 2022.02.x --no-single-branch https://git.busybox.net/buildroot/
git clone https://github.com/cdsteinkuehler/br2rauc

# Create the certficate and keyring files needed for signing RAUC bundles
# Optional: Pass CA and ORG as arguments: openssl-ca.sh [ ORG [ CA ]]
# Optional: Create a symlink to your CA directory located elsewhere
( cd br2rauc/ ; ./openssl-ca.sh )

# Setup buildroot, keeping build artifacts outside the buildroot tree
# Note paths are relative to the buildroot directory
make -C buildroot/ BR2_EXTERNAL=../br2rauc O=../output raspberrypicm4io-64-rauc_defconfig

# ...or for the Raspberry Pi 4B:
make -C buildroot/ BR2_EXTERNAL=../br2rauc O=../output raspberrypi4-64-rauc_defconfig

# You can now run standard buildroot make commands with no options
# directly from the output directory
cd output

# You may want to run "make menuconfig" to enable ccache or review/tweak the
# default config selections
# Some suggested changes:
# Rename defconfig file to save customizations:
#   Build options -> Location to save buildroot config
# Enable ccache:
#   Build options -> Enable compiler cache
#   Build options -> Compiler cache location
# Download a bootlin toolchain instead of building one from scratch:
#   Toolchain -> Toolchain type -> External toolchain
#   Toolchain -> Toolchain -> Bootlin toolchains
#   Toolchain -> Bootlin toolchain variant -> aarch64 glibc stable 2021.11-1

# Build everything and generate the uSD image file:
make

# The bootable uSD is xz compressed with a bmap file in the images directory
# Write the image file to a uSD card with something like the following (or use
# your favorite imaging utility):
sudo bmaptool copy images/sdcard.img.xz /dev/sdX
```
### Custom Rescue Filesystem
```bash
# Currently, the rescue partition simply uses a squashfs version of the
# generated root filesystem.  If you add a lot of packages to your target
# filesystem, you may wish to use a simpler rescue filesystem with just enough
# to run RAUC and perform updates.
#
# WARNING:
# You will have to update the genimage.cfg config file and point it to the new
# rescue squashfs filesystem for this to work properly!
#
# To create another Buildroot working directory to use for the rescue partition:
cd ~/MyWorkDir
make -C buildroot/ BR2_EXTERNAL=../br2rauc O=../rescue raspberrypicm4io-64-rauc_defconfig

# You can now run standard buildroot make commands with no options
# directly from the output directory
cd rescue

# As above, you can run make menuconfig, or just run make...
# make menuconfig
make

# ...then rebuild the uSD image from your primary output directory
```

While the provided default configuration attempts to limit the changes made to
the Buildroot default configuration, I highly recommend you enable ccache and
switch to an external Bootlin toolchain unless you enjoy wasting time and CPU
cycles building gcc and recompiling identical code multiple times.  See the
comments above for details.

For quick experiments, you may wish to modify the br2rauc tree directly, or a
more sophisticated process might use a top-level project that includes several
exteranl trees and multiple BR2_EXTERNAL entries, eg:

```bash
  -- MyCoolProject
     |-- buildroot (git external)
     |-- br2rauc (git external)
     |-- MyApp1 (external or part of MyCoolProject)
     |-- MyApp2 (external or part of MyCoolProject)
     |-- output (generated by Buildroot, can be renamed or moved elsewhere)
     |-- rescue (optional, generated by Buildroot if you use an alternate rescue config)

cd MyCoolProject

# Generate output directory with BR2 Externals configured
# NOTE: There are additional parameters you may wish to pass to Buildroot, see
# the Buildroot documentation for details
make -C buildroot/ BR2_EXTERNAL=../br2rauc:../MyApp1:../MyApp2 O=../output my_defconfig

# Configure the system as desired...
cd output
make menuconfig

# ...and build an image
make
```

## Usage

After completing a build, your Buildroot output directory should contain an
image file (output/images/sdcard.img) that can be written to a uSD card for use
with the Raspberry Pi Compute Module 4 IO Board.  In addition to the uSD you
will need a 3.3V serial cable connected to the standard serial console pins on
the cm4io (gpio 14 & 15, pins 8 & 10 on the 40-pin connector).

Once the system boots, you can use the rauc command to examine the current
status:

```rauc status```

...or to mark the current partition as good:

```rauc status mark-good```

Note that if you do not mark the status as good the boot count in the bootload
will count down and eventually switch to the other partition.  You can use the
fw_printenv command to examine the current bootloader status:

```
$ sudo fw_printenv | grep BOOT_
BOOT_A_LEFT=2
BOOT_B_LEFT=3
BOOT_ORDER=A B
```

...and see what happens after marking the current boot as 'good':

```
$ rauc status mark-good
rauc-Message: 17:34:00.021: rauc status: marked slot rootfs.0 as good
$ sudo fw_printenv | grep BOOT_
BOOT_B_LEFT=3
BOOT_ORDER=A B
BOOT_A_LEFT=3
```

For full details, read through the RAUC manual.

## Buildroot Changes

This project is based on the Buildroot provided 64-bit default configuration
for the Raspberry Pi CM4 I/O board, with the following major changes:

* Switch to glibc, systemd, and udev : The RPi is not particularly resouce
  constrained, and using glibc, systemd, and udev provides the fewest surprises
  when migrating from a Raspberry Pi OS based system.  In particular, if you
  are not using udev many device nodes will not get properly generated,
  particularly the video devices
* Switch to the U-Boot boot loader : U-Boot is required to allow intelligent
    switching between redundant filesystem images and handling failed updates.
* Add RAUC : This builds the required host and target tools needed to use RAUC.
* Undefine BR2_ARM_FPU_VFPV4 : 64-bit ARM cores are required to support ARMv8.
* Add a non-root user (user) and enable sudo without password
* Implement device tree customizations necessary for the cm4io
* Modify post-*.sh scripts as needed for RAUC
* Generate RAUC update bundles for boot and root filesystems
* Enable hardware watchdog support in systemd

## Busybox

A configuration fragment file is used to slightly modify the default Busybox
config supplied with Buildroot:

* Add blkdiscard (so you can easily wipe your uSD card while experimenting)
* Remove watchdog utility from busybox (handled by systemd)
* Remove klogd/syslogd (logging handled by systemd journald)

## U-Boot

The U-Boot configuration leverages the default rpi_arm64 configuation provided
by upstream.  A configuration fragment file is used to override a few options:

* Store environment on the mmc device
* Enable redundant copies of the environment
* Increase environment size to 32K
* Enable squashfs support needed for rescue partition

### Notes

The RPi firmware loads and modifies the device tree based on the contents of the
config.txt file.  The original device-tree file may not boot without some of
these changes (eg: the dma-ranges property for the emmc controller is different
between the BCM2711 C0T stepping revisions).

The RPi firmware uses more than just cmdline.txt to construct the kernel command
line.  If you do not duplicate these entries, your system may not boot (eg: the
rootwait parameter is required when booting from emmc).  To make it easy to
modify the kernel command line without having to update the boot loader, the
U-Boot script looks for a /boot/uEnv.txt file on the rootfs partition selected
by the RAUC logic (either A, B, or Rescue) and supports the following two
environment variables to control the kernel command line:

* bootargs_force: If set, this overrides the bootargs_default value set in the
  U-Boot environment.  The RAUC arguments (root and rauc.slot) are appended to
  generate the final kernel command line.
* bootargs_extra: If set, the contents are appended to bootargs_default before
  the RAUC arguments.  Ignored if bootargs_force is set.

The easiest way to determine exactly what the firmware is doing is to boot using
the firmware provided settings (fdt blob at ${fdt_addr} with no bootargs
specified by U-Boot), examine the run-time system that results, and compare with
the original source files.

The provided U-Boot script will use the firmware provided device tree if the
kernel command line includes the text "fw_dtb", otherwise the device tree is
loaded from the appropriate rootfs partition and the emmc dma-ranges property is
copied from the fixed-up fdt provided by the firmware.  This makes it fairly
easy to switch between using the RPi firmware to generate a device tree (so you
have support for dtoverlay= in config.txt) and a (likely flattened) device tree
built along with the kernel.  For more details, see the Device Tree section,
below.

If you are booting with the firmware loaded device-tree (cmdline.txt contains
"fw_dtb"), the RAUC Kernel arguments are appended to the kernel command line
provided by the firmware and the bootargs_default, bootargs_force, and
bootargs_extra variables are ignored.  Edit cmdline.txt on the vfat boot
partition to make any changes.  NOTE: Setting "fw_dtb" in cmdline.txt is intended
for experimetal purposes only  and is not recommended for production settings.

U-Boot does not currently support the watchdog timer for the Raspberry Pi family
so with the default configuration with the RPi firmware enabling the watchdog,
U-Boot and Linux must boot to the point where systemd is communicating with the
watchdog in less than apx. 16 seconds (the maximum RPi watchdog timeout).  In my
tests it takes just over 4 seconds for the Linux kernel to have booted enough
that systemd has started "petting" the watchdog.  With the 2 second U-Boot
autoboot delay, there should be plenty of margin unless your kernel is very
large or you drop into the U-Boot prompt.

## Linux Kernel

The Linux kernel configuration leverages the same bcm2711 configuration as the
Buildroot default Raspberry Pi examples.  A configuration fragment is used to
enable `verity` and `squashfs`, required to work with the new format RAUC
bundles.

### Warning

Since a Raspberry Pi kernel is used, the Linux Kernel version is stored as part
of the default config file and will not be updated if you switch to a newer
version of Buildroot and rebuild from scratch.  Make sure to update the
BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION setting in your configuration when
updating Buildroot!

## Device Tree

Managing the device tree can be one of the more complicated aspects of working
with embedded ARM based systems.  A full discussion of all available options for
managing device trees is well beyond the scope of this project, but a brief list
of some possible options includes:

* Let the RPi firmware load your device tree: This creates a dependency between
  your rootfs image containing the kernel and the FAT partition with the device
  tree file and overlays.  This is a Very Bad way to handle your device tree for
  an actual product, but can be useful for development, especially as you
  transition from a full Raspberry Pi OS development environment to the more
  streamlined Buildroot environment.  To use the device tree loaded by the RPi
  firmware, pass the "fw_dtb" argument on the kernel command line.  This is
  currently the default for the generated sdcard.img system.

* Migrate device tree overlay processing to U-Boot: This is non-trivial, but
  certainly possible (see the BeagleBone, for example).

* Manually generate a flattened device tree: This may be a decent intermediate
  option if you are willing to do some manual work when updating kernel
  versions. For example, you could boot using the RPi firmware and config.txt
  file then copy the run-time device tree to a flattened dts file:
  `dtc -I fs -O dts -s /proc/device-tree -o flattened.dts`

* Generate a custom device-tree: You can configure Buildroot to compile custom
  device tree files (see BR2_LINUX_KERNEL_CUSTOM_DTS_PATH).  This mechanism is
  used in this example to generate a functional device tree for the CM4 (the
  default bcm2711-rpi-cm4.dts results in an unusable system as the serial
  console UART is non-functional (conflicts with bluetooth) and USB is disabled.
  To use this method, you will likely need to migrate the various overlay files
  you need for your system into dtsi files you can use when building a flattened
  device tree.  Refer to the included custom.dtsi (and the original source for
  the overlay files) for hints, read thorugh the Raspberry Pi Device Tree
  Overview, and diff your flattened tree with a known working run-time device
  tree loaded by the RPi firmware (see the dtc command above to get a dts file
  from your running system).  To enable loading the device tree from your rootfs
  partition, edit cmdline.txt on the vfat partition and delete the "fw_dtb"
  argument.

* Load device tree overlays at run-time: You can use the kernel's configfs
  interface to load and unload device-tree overlays once the system is up and
  running by creating and removing directories and dtbo files in:
  `/sys/kernel/config/device-tree/overlays/`

### Warning

The default configuration ignores the devcie tree files on your rootfs partition
and instead uses the device tree passed in by the RPi firmware.  To use the
flattened device tree file from your rootfs, edit cmdline.txt on the vfat
partition and delete the "fw_dtb" argument.  This was done as it is expected more
people would be confused by changes to config.txt having no effect vs. edits to
custom.dtsi being ignored.  I trust if you can edit dtsi files you can read
instructions and/or trace the boot process and figure out what's going on. :-)

The Raspberry Pi boot process is managed by closed source firmware, and you may
not be able to generate a working system without replicating some of the
functionaltiy provided by these closed source applications.  To debug use dtc to
generate sorted dts files from your flattened dtb and the firmware generated
run-time device tree which you can then compare using standard file diff tools.

Prior to migrating to Buildroot 2024.02 the U-Boot bootloader was modified to
have the  ft_board_setup() function copy some firmware created and modified
nodes from the firmware loaded device-tree to the U-Boot loaded device-tree.
Recent versions of U-Boot now include  support for this functionality which is
typically required to boot successfully.  Note that you may still need to use
the U-Boot patch or otherwise modify the U-Boot code if you need to add or
change which device-tree nodes get copied.  In particular, some hardware
libraries are sensitive to exactly which devic-tree nodes are present (eg:
rpi_ws281x_drv).

## System Image

The bootable sdcard.img image file is created by the genimage utility.  Three
filesystem images are created in addition to the rootfs images created by
Buildroot:

* rootfs.ext4: Root filesystem image generated by Buildroot
* rootfs.squashfs: Root filesystem image generated by Buildroot (used for the
  rescue partition)
* boot.vfat: 256M FAT filesystem with required RPi boot files and U-Boot
* data.ext4: 128M empty ext4 partition to use for persistent data (rauc.status)
* upload.ext4: 900M empty ext4 partition to use for temporary data (updates)

The genimage.cfg file writes two copies of the boot filesystem to the disk
image. The first is offset by 4M from the start of the device (to leave room
for the U-Boot environment) and appears in the partition table.  The second copy
is offet 260M from the first and is not listed in the partition table (this is
the "hidden" space used by RAUC with the boot-mbr-switch slot type).

The second partition (p2) is the squashfs rescue rootfs.

The third partition (p3) is the 128M persisitent data partition (p3). This
partition is mounted with the flag "data=journal" to insure maximum safety.
This partition is useful for storing occasionally modified data that must be
retained across updates (eg: rauc.status file, static IP address, etc.).  If you
need to consistently write large amounts of data, you will likely want to change
how persistent data is handled.  See:
"[Data Storage and Migration](https://rauc.readthedocs.io/en/latest/advanced.html#data-storage-and-migration)"
in the RAUC manual.

Partition 4 holds an extended partition table.

Two copies of the root filesystem are then written to the disk, both with enries
in the partition table (p5 and p6).  These are the "A" and "B" slots used by
RAUC as the symmetric rootfs Slots.

Finally, the upload partition is created (p7) to use as temporary storage when
performing RAUC updates.

## Rescue Image

The squashfs rescue image is generated by Buildroot by simply enabling a
squashfs version of the existing br2rauc ext4 rootfs.  For production usage, you
would typically enable a minimal system containing just enough to be able to
install updates using RAUC for the rescue filesystem and use a separate full
featured configuration for the normal rootfs partitions and RAUC update bundles.
For this example, the defult configuration is fairly minimal and makes a decent
rescue filesystem.  See the Buildroot documentation and the comments in `Getting
Started` above for details on maintining multiple configurations built from the
same Buildroot and External trees.  You will likely also want to enable ccache.

To boot into recovery mode using the rescue partition, tie GPIO pin 4 low while
booting.  This is pin 7 on the 40-pin header, conveniently setup with a weak
pull-up resistor at reset and located next to GND pin 9.  Place a shorting
jumper across pins 7 and 9 to boot into recovery mode.

## RAUC

### Important

RAUC *requires* updates to be cryptographically signed.  This example includes a
script (openssl-ca.sh, taken from the meta-rauc project) to generate a
certificate and key that can be used for testing.  You *must* run this script
(or otherwise supply proper keyring, key, and certificate files) before
attempting to build the br2rauc Buildroot project.

### RAUC configuration

The RAUC configuration includes three slots that can be targeted for updates.
Two rootfs slots are used in an "A B" redudnant setup (see
"[Symmetric Root-FS Slots](https://rauc.readthedocs.io/en/latest/scenarios.html#symmetric-root-fs-slots)"
in the RAUC manual).  The third slot is for the bootloader with a type of
boot-mbr-switch, used for
[atomic bootloader updates](https://rauc.readthedocs.io/en/latest/advanced.html#update-boot-partition-in-mbr).
See the /etc/rauc/system.conf file for full details.

### RAUC Update Bundles

The RAUC update bundles are made by the post-image.sh script by creating a
simple manifest file in a temporary directory along with the file system images
created by the genimage tool.  Since the bootloader is typically updated much
less frequently than the root filesystem, two separate bundles are created.  See
the post-image.sh script for details.

## ToDo

* Web portal for updates using RAUC example cgi program
* Example application to interact with RAUC and systemd watchdog:
  * Mark status good once booted and running
  * Interact with systemd watchdog
  * Use jumpers to trigger failed behavior for testing
* Use genimage to generate RAUC bundle?


## Credits

As with almost all open source projects, this project would not be possible
without the work of many others.  I would like to extend my thanks and gratitude
to:

* [Buildroot](https://buildroot.org/), [RAUC](https://rauc.io/),
  and [Das U-Boot](https://www.denx.de/wiki/U-Boot)
  communities: Obviously my work here would be impossible without the
  foundation proivded by these excellent projects.  My contributions are a
  small addition to the great strides made by these folks.
* [Bootlin](https://bootlin.com/):
  Other than the official documentation, the folks at Bootlin were probably my
  greatest resource.  Their blog posts and online training materials were
  invaluable as I was trying to learn how all the pieces fit together.
* [Home Assistant Operating System](https://github.com/home-assistant/operating-system):
  This platform runs on a RPi4 (among others) and provided an example of a
  working Buildroot, U-Boot, and RAUC system and was very helpful as a
  reference.
* [Raspberry Pi Foundation](https://www.raspberrypi.com/documentation/computers/):
  In addition to making excellent, powerful, and affordable hardware, they
  provide excellent documentation for their systems.

## License

As a Buildroot external directory tree which has borrowed heavily from the stock
configurations and scripts proivded with Buildroot, this project is
[licensed under the same terms as the Buildroot project](https://buildroot.org/downloads/manual/manual.html#legal-info):
[GNU General Public License, version 2](http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
or (at your option) any later version, with the exception that any package
patches are covered by the the license of the software to which the patches are
applied.

## References

* [Buildroot Manual](https://buildroot.org/downloads/manual/manual.html)
* [RAUC Manual](https://rauc.readthedocs.io/en/latest/index.html)
* [Das U-Boot Manual](https://u-boot.readthedocs.io/en/latest/index.html)
* [genimage README](https://github.com/pengutronix/genimage/blob/master/README.rst)
* [Bootlin Buildroot Training & Materials](https://bootlin.com/training/buildroot/)
* [Getting Started With RAUC](https://bootlin.com/pub/conferences/2021/lee/bouhara-rauc/bouhara-rauc.pdf)
* [Behind the Scenes of an Update Framework: RAUC](https://www.youtube.com/watch?v=ZkumnNsWczM)
* [Raspberry Pi Device Tree Overview](https://www.raspberrypi.com/documentation/computers/configuration.html#device-trees-overlays-and-parameters)
* [Raspberry Pi config.txt](https://www.raspberrypi.com/documentation/computers/config_txt.html)
* [Raspberry Pi CM4 Boot Details](https://www.raspberrypi.com/documentation/computers/compute-module.html#cm4bootloader)
* [Raspberry Pi 4 Boot Details](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-boot-eeprom)
* [meta-rauc yocto layer](https://github.com/rauc/meta-rauc)
