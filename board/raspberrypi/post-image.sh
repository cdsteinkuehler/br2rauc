#!/bin/bash

set -e

BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Pass an empty rootpath. genimage makes a full copy of the given rootpath to
# ${GENIMAGE_TMP}/root so passing TARGET_DIR would be a waste of time and disk
# space. We don't rely on genimage to build the rootfs image, just to insert a
# pre-built one in the disk image.

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

rm -rf "${GENIMAGE_TMP}"

genimage \
	--rootpath "${ROOTPATH_TMP}"   \
	--tmppath "${GENIMAGE_TMP}"    \
	--inputpath "${BINARIES_DIR}"  \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"

# Generate a RAUC update bundle for the root filesystem
[ -e ${BINARIES_DIR}/rootfs.raucb ] && rm -rf ${BINARIES_DIR}/rootfs.raucb
[ -e ${BINARIES_DIR}/temp-rootfs ] && rm -rf ${BINARIES_DIR}/temp-rootfs
mkdir -p ${BINARIES_DIR}/temp-rootfs

cat >> ${BINARIES_DIR}/temp-rootfs/manifest.raucm << EOF
[update]
compatible=br2rauc-rpi4-64
version=${VERSION}
[bundle]
format=verity
[image.rootfs]
filename=rootfs.ext4
EOF

ln -L ${BINARIES_DIR}/rootfs.ext4 ${BINARIES_DIR}/temp-rootfs/

${HOST_DIR}/bin/rauc bundle \
	--cert ${BOARD_DIR}/cert/cert.pem \
	--key ${BOARD_DIR}/cert/key.pem \
	${BINARIES_DIR}/temp-rootfs/ \
	${BINARIES_DIR}/rootfs.raucb

# Generate a RAUC update bundle for the boot filesystem
[ -e ${BINARIES_DIR}/bootfs.raucb ] && rm -rf ${BINARIES_DIR}/bootfs.raucb
[ -e ${BINARIES_DIR}/temp-bootfs ] && rm -rf ${BINARIES_DIR}/temp-bootfs
mkdir -p ${BINARIES_DIR}/temp-bootfs

cat >> ${BINARIES_DIR}/temp-bootfs/manifest.raucm << EOF
[update]
compatible=br2rauc-rpi4-64
version=${VERSION}
[bundle]
format=verity
[image.bootloader]
filename=boot.vfat
EOF

ln -L ${BINARIES_DIR}/boot.vfat ${BINARIES_DIR}/temp-bootfs/

${HOST_DIR}/bin/rauc bundle \
	--cert ${BOARD_DIR}/cert/cert.pem \
	--key ${BOARD_DIR}/cert/key.pem \
	${BINARIES_DIR}/temp-bootfs/ \
	${BINARIES_DIR}/bootfs.raucb

