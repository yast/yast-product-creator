#!/bin/bash
#================
# FILE          : config.sh
#----------------
# PROJECT       : OpenSuSE KIWI Image System
# COPYRIGHT     : (c) 2006,2007,2008 SUSE LINUX Products GmbH. All rights reserved
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>, Stephan Kulow <coolo@suse.de>
#               :
# LICENSE       : BSD
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

exec > /var/log/config.log
exec 2>&1

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$name]..."

#======================================
# Load sound drivers by default
#--------------------------------------
perl -ni -e 'm,^blacklist snd-, || print;' \
	/etc/modprobe.d/blacklist

# and unmute their mixers.
perl -pi -e 's,/sbin/alsactl -F restore,/bin/set_default_volume -f,;' \
	/etc/udev/rules.d/40-alsa.rules

# Deactivate services
#--------------------------------------
suseRemoveService boot.device-mapper
suseRemoveService mdadmd
suseRemoveService rpasswdd
suseRemoveService boot.scsidev
suseRemoveService boot.md

# these two we want to disable for policy reasons
chkconfig sshd off
chkconfig cron off

# enable create_xconf
chkconfig create_xconf on

cd /
patch -p0 < /tmp/config.patch
rm /tmp/config.patch

insserv 

rm -rf /var/cache/zypp/raw/*

zypper addrepo -d http://download.opensuse.org/distribution/SL-OSS-factory/inst-source/ factory-oss
zypper addrepo -d http://download.opensuse.org/distribution/SL-Factory-non-oss/inst-source-extra/ factory-non-oss
zypper addrepo -d http://download.opensuse.org/update/11.0/ updates

#======================================
# /etc/sudoers hack to fix #297695 
# (Installation Live CD: no need to ask for password of root)
#--------------------------------------
sed -e "s/ALL ALL=(ALL) ALL/ALL ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers > /tmp/sudoers && mv /tmp/sudoers /etc/sudoers
chmod 0440 /etc/sudoers

# empty password is ok
pam-config -a --nullok

: > /var/log/zypper.log

#======================================
# SuSEconfig
#--------------------------------------
mount -o bind /lib/udev/devices /dev
suseConfig
umount /dev

test -x /usr/bin/kbuildsycoca4 && su - linux -c /usr/bin/kbuildsycoca4

#======================================
# Umount kernel filesystems
#--------------------------------------
baseCleanMount

rm -rf /var/lib/smart

exit 0
