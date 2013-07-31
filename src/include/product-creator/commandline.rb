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

# File:	include/product-creator/commandline.ycp
# Package:	Configuration of product-creator
# Summary:	Dialogs definitions
# Authors:	Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
module Yast
  module ProductCreatorCommandlineInclude
    def initialize_product_creator_commandline(include_target)
      Yast.import "Pkg"
      Yast.import "UI"
      Yast.import "CommandLine"
      Yast.import "FileUtils"
      Yast.import "Progress"
      Yast.import "ProductCreator"
      Yast.import "RichText"
      Yast.import "SourceManager"
      Yast.import "Report"

      Yast.include include_target, "product-creator/complex.rb"

      textdomain "product-creator"
    end

    # dummy function to return true when callback is invoked (from AutoInstall.ycp)
    def callbackTrue_boolean_map_integer(dummy_map, dummy)
      dummy_map = deep_copy(dummy_map)
      true
    end

    def ProcessConfigFileOption(params)
      params = deep_copy(params)
      if Builtins.haskey(params, "configfile")
        new_config = Ops.get_string(params, "configfile", "")

        if new_config != nil && new_config != ""
          Builtins.y2milestone("Using config file: %1", new_config)

          # TODO FIXME: set the config file path in "initialize" handler,
          # don't read the default config file if the "configfile" option is used
          ProductCreator.ConfigFile = new_config
          ProductCreator.Read
        end
      end

      nil
    end

    # Go through the command line parameters map, verify the validity
    # and fill appropriate gloal values
    # @param [Hash] params map with command line parameters
    # @param [String] action for what action are the parameters intended (create/edit)
    def ProcessParameters(params, action)
      params = deep_copy(params)
      name = Ops.get_string(params, "name", "")
      if name == ""
        # command line error message
        Report.Error(_("Configuration name is missing."))
        return false
      end
      _Config = { "name" => name }

      if action != "create" && !Builtins.haskey(ProductCreator.Configs, name)
        # command line error message, %1 is a name
        Report.Error(Builtins.sformat(_("There is no configuration %1."), name))
        return false
      end
      if action == "edit" || action == "show"
        ProductCreator.LoadConfig(name)
        _Config = deep_copy(ProductCreator.Config)
      end
      return true if action == "show"

      # first, handle required parameters
      if Ops.get_string(params, "output_dir", "") != ""
        Ops.set(
          _Config,
          "iso-directory",
          Ops.get_string(params, "output_dir", "")
        )
      elsif action == "create"
        # command line error message
        Report.Error(_("Path to output directory is missing."))
        return false
      end

      repos = Builtins.splitstring(
        Ops.get_string(params, "repositories", ""),
        ","
      )
      if repos != []
        Ops.set(_Config, "sources", repos)
      elsif action == "create"
        # command line error message
        Report.Error(_("List of package repositories is empty."))
        return false
      end

      if Ops.get_string(params, "profile", "") != ""
        Ops.set(_Config, "profile", Ops.get_string(params, "profile", ""))
      elsif action == "create"
        # command line error message
        Report.Error(_("Path to AutoYaST profile is missing."))
        return false
      end
      if Builtins.haskey(params, "copy_profile")
        Ops.set(_Config, "copy_profile", true)
      end

      # there is no manual way for selecting packages:
      if action == "create" || Ops.get_string(params, "profile", "") != ""
        Ops.set(_Config, "pkgtype", "autoyast")
        ProductCreator.profile_parsed = false
      end

      if Ops.get_string(params, "iso_name", "") != ""
        Ops.set(_Config, "isofile", Ops.get_string(params, "iso_name", ""))
      elsif action == "create"
        Ops.set(_Config, "isofile", Ops.add(name, ".iso"))
      end

      if Builtins.haskey(params, "create_iso")
        Ops.set(_Config, "result", "iso")
      elsif action == "create"
        Ops.set(_Config, "result", "tree")
      end

      if Builtins.haskey(params, "savespace")
        Ops.set(_Config, "savespace", true)
      end

      if Ops.get_string(params, "gpg_key", "") != ""
        Ops.set(_Config, "gpg_key", Ops.get_string(params, "gpg_key", ""))
      end

      # no selections
      Ops.set(_Config, "type", :patterns) if action == "create"

      if Ops.get_string(params, "isolinux_path", "") != ""
        file = Ops.get_string(params, "isolinux_path", "")
        if !FileUtils.Exists(file)
          # command line error message
          Report.Error(Builtins.sformat(_("File %1 does not exist."), file))
          return false
        end
        if Ops.greater_than(SCR.Read(path(".target.size"), file), 0)
          cont = Convert.to_string(SCR.Read(path(".target.string"), file))
          Ops.set(_Config, "bootconfig", cont) if cont != nil
        end
      end

      ProductCreator.Config = deep_copy(_Config)

      # read default isolinux (Config needs to be saved already to
      # ProductCreator::Config, it is used by Readisolinux)
      if Ops.get_string(params, "isolinux_path", "") == "" && action == "create"
        Ops.set(
          ProductCreator.Config,
          "bootconfig",
          ProductCreator.Readisolinux
        )
      end

      if action != "show"
        # initialize the sources before commiting configuration

        ProductCreator.ResetArch
        # unload all active sources (reset the internal state, see bnc#469191)
        Pkg.SourceFinishAll

        SourceManager.ReadSources

        # automatically import GPG keys when adding repository
        Pkg.CallbackImportGpgKey(
          fun_ref(
            method(:callbackTrue_boolean_map_integer),
            "boolean (map <string, any>, integer)"
          )
        )
      end

      # save the new configuration into global map, parse autoyast profile
      ProductCreator.CommitConfig

      nil
    end

    # Command line handler for List action: list available configurations
    def ListHandler(params)
      params = deep_copy(params)
      ProcessConfigFileOption(params)

      Builtins.foreach(ProductCreator.Configs) do |name, conf|
        CommandLine.Print(name)
      end 


      false # = do not try to write
    end

    # Command line handler for Create ISO action
    def CreateIsoHandler(params)
      params = deep_copy(params)
      Builtins.y2milestone("CreateIsoHandler parameters: %1", params)

      ProcessConfigFileOption(params)

      name = Ops.get_string(params, "name", "")

      if name != ""
        CommandLine.PrintVerbose(
          Builtins.sformat(_("Loading configuration %1..."), name)
        )
        # load the requested configuration

        if !ProductCreator.LoadConfig(name)
          # command line error message
          CommandLine.Print(
            Builtins.sformat(_("Cannot load configuration %1."), name)
          )
          return false
        end

        file = Ops.get_string(params, "passphrase_file", "")
        if file != nil && file != ""
          Builtins.y2milestone("Reading passphrase from file %1...", file)
          ProductCreator.gpg_passphrase = Convert.to_string(
            SCR.Read(path(".target.string"), file)
          )
        end

        if Builtins.haskey(params, "passphrase")
          ProductCreator.gpg_passphrase = Ops.get_string(
            params,
            "passphrase",
            ""
          )
        end

        # disable the progress
        progress = Progress.set(false)

        # verify the destination
        if VerifyDialog() != :next
          # command line error message
          CommandLine.Print("Cannot verify the destination")
          return false
        end

        # copy packages, create ISO image
        TreeDialog()

        # reset the passphrase
        ProductCreator.gpg_passphrase = ""

        iso_name = Ops.add(
          Ops.add(
            Ops.get_string(ProductCreator.Config, "iso-directory", ""),
            "/"
          ),
          Ops.get_string(ProductCreator.Config, "isofile", "")
        )
        image_size = Convert.to_integer(
          SCR.Read(path(".target.size"), iso_name)
        )
        if Ops.less_than(SCR.Read(path(".target.size"), iso_name), 0)
          # command line error message (%1 is path)
          CommandLine.Print(
            Builtins.sformat(_("Cannot create ISO image %1."), iso_name)
          )
          return false
        else
          # command line info message
          CommandLine.Print(
            Builtins.sformat(_("ISO image %1 has been written."), iso_name)
          )
        end

        Progress.set(progress)
      else
        # command line error message
        Report.Error(_("Configuration name cannot be empty."))
        return false
      end

      true
    end

    # Command line handler for Create Config action: create new product
    # configuration
    def CreateConfigHandler(params)
      params = deep_copy(params)
      Builtins.y2milestone("CreateConfigHandler parameters: %1", params)
      ProcessConfigFileOption(params)

      ProcessParameters(params, "create")
    end

    # Command line handler for Delete Config action
    def DeleteConfigHandler(params)
      params = deep_copy(params)
      Builtins.y2milestone("DeleteConfigHandler parameters: %1", params)
      name = Ops.get_string(params, "name", "")

      if name == ""
        # command line error message
        Report.Error(_("Configuration name is missing."))
        return false
      end
      ProductCreator.Configs = Builtins.filter(ProductCreator.Configs) do |k, v|
        k != name
      end
      true
    end

    # Command line handler for Edit Config action
    def EditConfigHandler(params)
      params = deep_copy(params)
      Builtins.y2milestone("EditConfigHandler parameters: %1", params)
      ProcessConfigFileOption(params)

      ProcessParameters(params, "edit")
    end

    # Command line handler for Show Config action
    def ShowConfigHandler(params)
      params = deep_copy(params)
      Builtins.y2milestone("EditConfigHandler parameters: %1", params)
      ProcessConfigFileOption(params)
      return false if !ProcessParameters(params, "show")

      # summary caption
      CommandLine.Print(_("Package Source"))
      Builtins.foreach(Ops.get_list(ProductCreator.Config, "sources", [])) do |s|
        CommandLine.Print(Ops.add("* ", s))
      end


      #         // summary line (%1 is number)
      #         CommandLine::Print (sformat(_("Selected %1 packages"),
      #     size (ProductCreator::Config["packages"]:[])));
      # // currently does not have sense: packages from patterns would need
      # // to be counted as well
      if Ops.get_string(ProductCreator.Config, "profile", "") != ""
        # summary line (%1 is file path)
        CommandLine.Print(
          Builtins.sformat(
            _("Using AutoYaST profile %1"),
            Ops.get_string(ProductCreator.Config, "profile", "")
          )
        )
      end


      if Ops.get_string(ProductCreator.Config, "result", "tree") == "iso"
        # summary line (%1/%2 is file path)
        CommandLine.Print(
          Builtins.sformat(
            _("Creating ISO image %1/%2"),
            Ops.get_string(ProductCreator.Config, "iso-directory", ""),
            Ops.get_string(ProductCreator.Config, "isofile", "")
          )
        )
      else
        # summary line (%1/%2 is file path)
        CommandLine.Print(
          Builtins.sformat(
            _("Creating directory tree in %1/%2"),
            Ops.get_string(ProductCreator.Config, "iso-directory", ""),
            Ops.get_string(ProductCreator.Config, "name", "")
          )
        )
      end

      gpgkey = Ops.get_string(ProductCreator.Config, "gpg_key", "")

      if gpgkey != ""
        privatekeys = GPG.PrivateKeys
        uid = ""
        Builtins.foreach(privatekeys) do |key|
          if Ops.get_string(key, "id", "") == gpgkey
            uid = Builtins.mergestring(Ops.get_list(key, "uid", []), ", ")
          end
        end 

        uid = Builtins.sformat(" (%1)", uid) if uid != ""

        # summary text - %1 is GPG key ID (e.g. ABCDEF01), %2 is GPG key user ID (or empty if not defined)
        CommandLine.Print(
          Builtins.sformat(
            _("Digitally sign the medium with GPG key %1%2"),
            gpgkey,
            uid
          )
        )
      else
        # summary text
        CommandLine.Print(_("The medium will not be digitally signed"))
      end
      false
    end
  end
end
