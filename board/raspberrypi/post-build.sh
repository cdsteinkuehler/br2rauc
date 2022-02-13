#!/bin/sh

set -u
set -e

# Add a console on tty1
if [ -e ${TARGET_DIR}/etc/inittab ]; then
    grep -qE '^tty1::' ${TARGET_DIR}/etc/inittab || \
	sed -i '/GENERIC_SERIAL/a\
tty1::respawn:/sbin/getty -L  tty1 0 vt100 # HDMI console' ${TARGET_DIR}/etc/inittab
fi

# Mount persistent data partition
if [ -e ${TARGET_DIR}/etc/fstab ]; then
	grep -qE 'LABEL=Data' ${TARGET_DIR}/etc/fstab || \
	echo "LABEL=Data /data ext4 defaults,data=journal,noatime 0 0" >> ${TARGET_DIR}/etc/fstab
fi

# Copy custom cmdline.txt file
install -D -m 0644 $BR2_EXTERNAL_BR2RAUC_PATH/board/raspberrypi/cmdline.txt ${BINARIES_DIR}/custom/cmdline.txt

# Copy RAUC certificate
install -D -m 0644 $BR2_EXTERNAL_BR2RAUC_PATH/board/raspberrypi/cert/cert.pem ${TARGET_DIR}/etc/rauc/keyring.pem

# 
cat <<- EOF >> ${TARGET_DIR}/etc/issue

	Default username:password is [user:<empty>]
	Root login disabled, use sudo su -
	eth0: \4{eth0}

EOF
