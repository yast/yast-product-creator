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

# File:	include/product-creator/helps.ycp
# Package:	Configuration of product-creator
# Summary:	Help texts of all the dialogs
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
module Yast
  module ProductCreatorHelpsInclude
    def initialize_product_creator_helps(include_target)
      textdomain "product-creator"

      # All helps are here
      @HELPS = {
        "bootconfig"    => _(
          "<p><b><big>Boot Options</big></b><br>\n" +
            "Add additional boot menu entries with boot options.\n" +
            "</p>\n"
        ) +
          _(
            "<p>For example, \n" +
              "configure the CD for automatic installations and specify the installation\n" +
              "source location. If you are not sure, leave the file untouched and the original is used.</p>\n"
          ),
        # Read dialog help 1/2
        "read"          => _(
          "<p><b><big>Initializing Configuration</big></b></p>\n"
        ) +
          # Read dialog help 2/2
          _(
            "<p><b><big>Aborting Initialization:</big></b><br>\nSafely abort the configuration utility by pressing <b>Abort</b> now.</p>\n"
          ),
        # Write dialog help 1/2
        "write"         => _(
          "<p><b><big>Saving Configuration</big></b></p>\n"
        ) +
          # Write dialog help 2/2
          _(
            "<p><b><big>Aborting Saving:</big></b><br>\n" +
              "Abort the save procedure by pressing <b>Abort</b>.\n" +
              "An additional dialog will inform you whether it is safe to do so.\n" +
              "</p>\n"
          ),
        # Ovreview dialog help 1/3
        "overview"      => _(
          "<p><b><big>Product Creator Configuration Overview</big></b><br>\n" +
            "Obtain an overview of available configurations. Additionally\n" +
            "edit those configurations.<br></p>\n"
        ) +
          # Ovreview dialog help 2/3
          _(
            "<p><b><big>Adding a Configuration:</big></b><br>\nPress <b>Add</b> to create a new configuration.</p>"
          ) +
          # Ovreview dialog help 3/3
          _(
            "<p><b><big>Editing or Deleting:</big></b><br>\n" +
              "Choose a configuration to change or remove.\n" +
              "Then press <b>Edit</b> or <b>Delete</b> respectively.</p>\n"
          ) +
          # overview dialog help part 4
          _(
            "<p>Use <b>Create Product</b> to create the ISO image or installation\nrepository directory with the selected product.</p>"
          ) +
          # overview dialog help part 5
          _(
            "<p>Press <b>Create Image with KIWI</b> for additional configuration of various\ntypes of images, such as Live media or Xen images, with the KIWI image system.</p>"
          ),
        # Configure1 dialog help 1/4
        "initial"       => _(
          "<p><b><big>Configuration Name and Packages</big></b><br>\n" +
            "Choose a configuration name and the method with which to select \n" +
            "the packages to add to the ISO image.<br></p>\n"
        ) +
          # Configure1 dialog help 3/4
          _(
            "<b>AutoYaST Profile</b><p>\n" +
              "Select an AutoYaST profile with the software configuration.\n" +
              "</p>\n"
          ) +
          # Configure1 dialog help 3/4
          _(
            "<b>Software Manager</b><p>\n" +
              "Use the software manager without any preselected packages. All\n" +
              "packages that would be automatically selected during installation must be\n" +
              "selected manually based on the hardware and architecture for which you are\n" +
              "creating this CD.\n" +
              "</p>\n"
          ),
        # Source selection help 1/2
        "sourceDialog"  => _(
          "<p><b><big>Select Package Sources</big></b><br>\nSelect at least one package source.<br></p>\n"
        ) +
          # Source selection help 2/2
          _(
            "<p><b><big>Target Architecture</big></b><br>\n" +
              "It is possible to create a product for a different architecture than that of\n" +
              "the machine you are currently working on.\n" +
              "All selected repositories must support the target architecture.<br>\n" +
              "<b>Note:</b> KIWI does not support different architectures yet, do not change\n" +
              "the architecture if you intend to create a KIWI image from the current configuration.</p>\n"
          ),
        # Configure2 dialog help 1/2
        "dest"          => _(
          "<p><b><big>ISO Directory and Image</big></b><br>\n" +
            "Enter the location in which to create the skeleton directory. All needed\n" +
            "files will be copied to this directory. Select a location with enough disk\n" +
            "space.\n" +
            "<br></p>\n"
        ) +
          # Configure2 dialog help 2/3
          _(
            "<p>Create an ISO image or a directory that is suitable for \n" +
              "creating an ISO image at a later time.\n" +
              "</p>\n"
          ) +
          # Configure2 dialog help 2/3
          _(
            "<p>To save space, select the check box to copy only needed files \n" +
              "to the skeleton. \n" +
              "</p>\n"
          ),
        # help text - the base selection dialog 1/4
        "baseSelection" => _(
          "<p><b>The Base Product</b></p>"
        ) +
          # help text - the base selection dialog 2/4
          _(
            "<p>One of the used repositories must be marked as the base product. The base\n" +
              "product repository should be bootable to ensure the newly created product is also\n" +
              "bootable.</p>\n"
          ) +
          # help text - the base selection dialog 3/4
          _(
            "<p>The other repositories will be used as add-ons for the base repository.</p>"
          ) +
          # help text - the base selection dialog 4/4
          _(
            "<p>The product creator solves dependencies of the selected products and proposes\n" +
              "the base product. If the proposed value is wrong, select the right base\n" +
              "repository from the list.</p>\n"
          )
      } 

      # EOF
    end
  end
end
