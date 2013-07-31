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

# $Id$
#
module Yast
  class ImageCreatorClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "product-creator"

      Yast.import "CommandLine"
      Yast.import "Confirm"
      Yast.import "FileUtils"
      Yast.import "Kiwi"
      Yast.import "Label"
      Yast.import "ProductCreator"
      Yast.import "Sequencer"
      Yast.import "Wizard"
      Yast.include self, "product-creator/wizards.rb"

      @cmdline_description = {
        "id"         => "image-creator",
        # transltors: command line help text for the Xproduct-creator module
        "help"       => _(
          "Configuration of Image Creator"
        ),
        "guihandler" => fun_ref(method(:ICSequence), "boolean ()")
      }


      # start the module
      @ret = CommandLine.Run(@cmdline_description)
      Builtins.y2debug("ret=%1", @ret)

      deep_copy(@ret) 

      # EOF
    end

    # TODO merge with main product-creator sequence?
    def ICSequence
      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("product-creator")

      if !Confirm.MustBeRoot
        UI.CloseDialog
        return false
      end

      if !Package.InstallAll(["kiwi", "squashfs"])
        # error popup
        Popup.Error(_("Installation of required packages\nfailed."))
        UI.CloseDialog
        return false
      end

      ret = ImageCreatorSequence()

      UI.CloseDialog
      ret == :next
    end
  end
end

Yast::ImageCreatorClient.new.main
