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

# File:	clients/product-creator.ycp
# Package:	Configuration of product-creator
# Summary:	Main file
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
#
# Main file for product-creator configuration. Uses all other files.
module Yast
  class ProductCreatorClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"

      #**
      # <h3>Configuration of the product-creator</h3>

      textdomain "product-creator"

      Yast.include self, "product-creator/wizards.rb"
      Yast.include self, "product-creator/commandline.rb"

      Yast.import "CommandLine"
      Yast.import "ProductCreator"

      Yast.import "PackageCallbacks"

      PackageCallbacks.InitPackageCallbacks

      @cmdline_description = {
        "id"         => "product-creator",
        # transltors: command line help text for the product-creator module
        "help"       => _(
          "Configuration of Product Creator"
        ),
        "guihandler" => fun_ref(method(:ProductCreatorSequence), "boolean ()"),
        "initialize" => fun_ref(ProductCreator.method(:Read), "boolean ()"),
        "finish"     => fun_ref(ProductCreator.method(:Write), "boolean ()"),
        "actions"    => {
          "list"       => {
            "handler" => fun_ref(method(:ListHandler), "boolean (map)"),
            # translators: command line help text for list action
            "help"    => _(
              "Print existing configurations"
            )
          },
          "create-iso" => {
            "handler" => fun_ref(method(:CreateIsoHandler), "boolean (map)"),
            # translators: command line help text for create-iso action
            "help"    => _(
              "Create installation ISO image"
            )
          },
          "create"     => {
            "handler" => fun_ref(method(:CreateConfigHandler), "boolean (map)"),
            # translators: command line help text for create-config action
            "help"    => _(
              "Create new product configuration"
            )
          },
          "delete"     => {
            "handler" => fun_ref(method(:DeleteConfigHandler), "boolean (map)"),
            # translators: command line help text for delete-config action
            "help"    => _(
              "Delete existing configuration"
            )
          },
          "edit"       => {
            "handler" => fun_ref(method(:EditConfigHandler), "boolean (map)"),
            # translators: command line help text for delete-config action
            "help"    => _(
              "Edit existing configuration"
            )
          },
          "show"       => {
            "handler" => fun_ref(method(:ShowConfigHandler), "boolean (map)"),
            # translators: command line help text for show action
            "help"    => _(
              "Show the summary of selected configuration"
            )
          }
        },
        "options"    => {
          "name"            => {
            # translators: command line help text for the 'name' option
            "help" => _(
              "Name of the configuration"
            ),
            "type" => "string"
          },
          "passphrase"      => {
            # translators: command line help text for the 'passphrase' option
            "help" => _(
              "GPG passphrase required for signing the source."
            ),
            "type" => "string"
          },
          "passphrase_file" => {
            # command line help text for the 'passhrase_file' option
            "help" => _(
              "File with GPG passphrase required for signing the source"
            ),
            "type" => "string"
          },
          "configfile"      => {
            # cmd line help text for the 'configfile' option, %1 is a file name
            "help" => Builtins.sformat(
              _("Path to the configuration file (default is %1)"),
              ProductCreator.ConfigFile
            ),
            "type" => "string"
          },
          "output_dir"      => {
            # command line help text for 'output_dir' option
            "help" => _(
              "Path to the output directory"
            ),
            "type" => "string"
          },
          # TODO provide also for create-iso...?
          "create_iso"      => {
            # command line help text for 'create_iso' option
            "help" => _(
              "Output should be an ISO image instead of directory tree"
            )
          },
          "iso_name"        => {
            # command line help text for 'iso_name' option
            "help" => _(
              "Name of the output ISO image"
            ),
            "type" => "string"
          },
          "savespace"       => {
            # command line help text for 'savespace' option
            "help" => _(
              "Copy only needed files to save space"
            )
          },
          "profile"         => {
            # command line help text for 'profile' option
            "help" => _(
              "Path to AutoYaST profile"
            ),
            "type" => "string"
          },
          "copy_profile"    => {
            # command line help text for 'copy_profile' option
            "help" => _(
              "Copy AutoYaST profile to CD image"
            )
          },
          "isolinux_path"   => {
            # command line help text for 'isolinux_path' option
            "help" => _(
              "Path to isolinux.cfg file"
            ),
            "type" => "string"
          },
          "gpg_key"         => {
            # command line help text for 'gpg_key' option
            "help" => _(
              "GPG key ID used to sign a product"
            ),
            "type" => "string"
          },
          "repositories"    => {
            # command line help text for 'repositories' option
            "help" => _(
              "List of package repositories (separated by commas)"
            ),
            "type" => "string"
          }
        },
        "mappings"   => {
          "list"       => ["configfile"],
          "create-iso" => [
            "name",
            "passphrase",
            "passphrase_file",
            "configfile"
          ],
          "create"     => [
            "name",
            "configfile",
            "output_dir",
            "create_iso",
            "iso_name",
            "savespace",
            "profile",
            "copy_profile",
            "isolinux_path",
            "gpg_key",
            "repositories"
          ],
          "edit"       => [
            "name",
            "configfile",
            "output_dir",
            "create_iso",
            "iso_name",
            "savespace",
            "profile",
            "copy_profile",
            "isolinux_path",
            "gpg_key",
            "repositories"
          ],
          "delete"     => ["name"],
          "show"       => ["name"]
        }
      }

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("ProductCreator module started")


      # start the module
      @ret = CommandLine.Run(@cmdline_description)
      Builtins.y2debug("ret=%1", @ret)

      # Finish
      Builtins.y2milestone("ProductCreator module finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::ProductCreatorClient.new.main
