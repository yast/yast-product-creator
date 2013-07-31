# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:	clients/kiwi.ycp
# Package:	Configuration of product-creator
# Summary:	Client to start the kiwi UI
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
#
module Yast
  class KiwiClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "product-creator"

      Yast.include self, "product-creator/kiwi_dialogs.rb"
      Yast.include self, "product-creator/wizards.rb"

      Yast.import "CommandLine"
      Yast.import "Confirm"
      Yast.import "PackageCallbacks"
      Yast.import "Sequencer"

      @cmdline_description = {
        "id"         => "kiwi",
        # command line help text for the kiwi module
        "help"       => _(
          "Configuration of Kiwi"
        ),
        "guihandler" => fun_ref(method(:ShortKiwiSequence), "boolean ()"),
        "actions"    => {}
      }

      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("ProductCreator-kiwi module started")


      @ret = CommandLine.Run(@cmdline_description)

      Builtins.y2milestone("ProductCreator-kiwi module finished with %1", @ret)
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret)
    end

    # configuration workflow for kiwi
    # @return sequence result
    def ShortKiwiSequence
      aliases = { "prepare" => lambda { PrepareDialog() }, "kiwi" => lambda do
        KiwiDialog()
      end }
      sequence = {
        "ws_start" => "prepare",
        "prepare"  => { :abort => :abort, :next => "kiwi" },
        "kiwi"     => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("kiwi")

      if !Confirm.MustBeRoot
        UI.CloseDialog
        return false
      end

      # not necessary to install all kiwi-descs, but now we don't know
      # which will be needed...
      if !Package.InstallAll(
          [
            "kiwi",
            "kiwi-desc-isoboot",
            "kiwi-desc-xenboot",
            "kiwi-desc-usbboot",
            "kiwi-desc-vmxboot",
            "squashfs"
          ]
        )
        # error popup
        Popup.Error(_("Installation of required packages\nfailed."))
        return false
      end

      InitRepositories()
      PackageCallbacks.InitPackageCallbacks

      ret = Sequencer.Run(aliases, sequence)
      UI.CloseDialog
      ret == :next
    end
  end
end

Yast::KiwiClient.new.main
