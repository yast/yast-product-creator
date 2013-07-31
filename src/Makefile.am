# Sources for product-creator

module_DATA = \
  modules/Kiwi.rb \
  modules/ProductCreator.rb

client_DATA = \
  clients/product-creator.rb \
  clients/image-creator.rb \
  clients/kiwi.rb

yncludedir = @yncludedir@/product-creator
ynclude_DATA = \
  include/product-creator/kiwi_dialogs.rb \
  include/product-creator/wizards.rb \
  include/product-creator/commandline.rb \
  include/product-creator/dialogs.rb \
  include/product-creator/complex.rb \
  include/product-creator/routines.rb \
  include/product-creator/helps.rb

scrconf_DATA = \
  scrconf/cfg_product-creator.scr \
  scrconf/etc_kiwi_repoalias.scr

ybin_SCRIPTS = \
  bin/y2mkiso

desktop_DATA = \
  desktop/image-creator.desktop \
  desktop/product-creator.desktop

fillup_DATA = \
  fillup/sysconfig.product-creator

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(ybin_SCRIPTS) $(desktop_DATA) $(fillup_DATA)

include $(top_srcdir)/Makefile.am.common