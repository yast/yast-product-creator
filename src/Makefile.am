# Makefile.am for product-creator/src
#
#
SUBDIRS = data

yncludedir = @yncludedir@/product-creator

YCPCFLAGS = -I ./include

client_DATA =			\
	product-creator.ycp		

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp		\
	routines.ycp		\
	commandline.ycp		\
	kiwi.ycp


desktop_DATA =			\
	product-creator.desktop

module_DATA =			\
	ProductCreator.ycp	\
	Kiwi.ycp

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(module_DATA) $(desktop_DATA)

include:
	mkdir include && ln -sf ../ include/product-creator

ycpchook = include

include $(top_srcdir)/Makefile.am.common



