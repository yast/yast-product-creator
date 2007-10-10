#!/bin/bash
#================
# FILE          : config.sh
#----------------
# PROJECT       : OpenSuSE KIWI Image System
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH. All rights reserved
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : configuration script for SUSE based
#               : operating systems
#               :
#               :
# STATUS        : BETA
#----------------
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Sound?
#--------------------------------------

# Load sound drivers by default
perl -ni -e 'm,^blacklist snd-, || print;' \
	/etc/modprobe.d/blacklist

# and unmute their mixers.
perl -pi -e 's,/sbin/alsactl -F restore,/bin/set_default_volume -f,;' \
	/etc/udev/rules.d/40-alsa.rules

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$name]..."

#======================================
# Activate services
#--------------------------------------
suseActivateServices

#======================================
# Deactivate services
#--------------------------------------
suseRemoveService boot.multipath
suseRemoveService boot.device-mapper
suseRemoveService mdadmd
suseRemoveService multipathd
suseRemoveService rpmconfigcheck
suseRemoveService waitfornm
suseRemoveService smb
suseRemoveService xfs
suseRemoveService nmb
suseRemoveService autofs
suseRemoveService rpasswdd
suseRemoveService boot.scsidev
suseRemoveService boot.md
suseInsertService create_xconf
suseService boot.rootfsck off
# these two we want to disable for policy reasons
chkconfig sshd off
chkconfig cron off

# these are disabled because kiwi enables them without being default
chkconfig aaeventd off
chkconfig autoyast off
chkconfig boot.sched off
chkconfig create_xconf off
chkconfig dvb off
chkconfig esound off
chkconfig fam off
chkconfig festival off
chkconfig hotkey-setup off
chkconfig ipxmount off
chkconfig irda off
chkconfig java.binfmt_misc off
chkconfig joystick off
chkconfig lirc off
chkconfig lm_sensors off
chkconfig nfs off
chkconfig ntp off
chkconfig openct off
chkconfig pcscd off
chkconfig powerd off
chkconfig raw off
chkconfig saslauthd off
chkconfig spamd off
chkconfig xinetd off
chkconfig ypbind off

cd /
patch -p0 < /tmp/config.patch
rm /tmp/config.patch

insserv 

rpm -e smart
rpm -e rpm-python
rpm -e python

: > /var/log/zypper.log
rm -rf /var/cache/zypp/raw/*

zypper addrepo http://download.opensuse.org/distribution/10.3/repo/oss/ 10.3
zypper addrepo http://download.opensuse.org/update/10.3/ 10.3-update

#======================================
# SuSEconfig
#--------------------------------------
suseConfig

#======================================
# Umount kernel filesystems
#--------------------------------------
baseCleanMount

exit 0
