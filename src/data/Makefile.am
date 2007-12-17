#
# Makefile.am for devtools/devtools/skeletons/config/agents
#
SUBDIRS	= kiwi_templates

ydatadir = @ydatadir@/product-creator

ydata_DATA = \
	isolinux.cfg \
	HFS_mapping \
	message \
	options.msg

fillup_DATA = sysconfig.product-creator

fillupdir = /var/adm/fillup-templates

EXTRA_DIST = $(ydata_DATA) $(fillup_DATA)
