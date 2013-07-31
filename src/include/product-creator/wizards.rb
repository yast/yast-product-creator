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

# File:	include/product-creator/wizards.ycp
# Package:	Configuration of product-creator
# Summary:	Wizards definitions
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
module Yast
  module ProductCreatorWizardsInclude
    def initialize_product_creator_wizards(include_target)
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "product-creator"

      Yast.import "Kiwi"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "Package"
      Yast.import "PackageCallbacks"
      Yast.import "Sequencer"

      Yast.include include_target, "product-creator/complex.rb"
      Yast.include include_target, "product-creator/dialogs.rb"
      Yast.include include_target, "product-creator/kiwi_dialogs.rb"
    end

    # Add a configuration of product-creator
    # @return sequence result
    def AddSequence
      aliases = {
        "source"         => lambda { sourceDialog },
        "base"           => lambda { baseProductSelectionDialog },
        "config1"        => lambda { Configure1Dialog() },
        "config2"        => lambda { Configure2Dialog() },
        "isolinuxcheck"  => [lambda { CheckBootableSrc() }, true],
        "isolinux"       => lambda { isolinuxDialog },
        "packagemanager" => lambda { packageSelector },
        "gpgkey"         => lambda { gpgKeyDialog },
        "write"          => lambda { WriteDialog() },
        "summary"        => lambda { ConfigSummary() }
      }


      sequence = {
        "ws_start"       => "config1",
        "source"         => { :abort => :abort, :next => "base" },
        "base"           => { :abort => :abort, :next => "config2" },
        "config1"        => { :abort => :abort, :next => "source" },
        "config2"        => { :abort => :abort, :next => "isolinuxcheck" },
        "isolinuxcheck"  => {
          :next          => "isolinux",
          :skip_isolinux => "packagemanager"
        },
        "isolinux"       => {
          :abort    => :abort,
          :next     => "packagemanager",
          :autoyast => "gpgkey"
        },
        "packagemanager" => {
          :abort  => :abort,
          :next   => "gpgkey",
          :accept => "gpgkey",
          :failed => "summary",
          :cancel => "isolinuxcheck"
        },
        "gpgkey"         => { :abort => :abort, :next => "summary" },
        "summary"        => { :abort => :abort, :next => "write" },
        "write"          => { :abort => :abort, :next => :next }
      }

      Sequencer.Run(aliases, sequence)
    end
    # Create a CD image tree and ISO image
    # @return sequence result
    def CreateSequence
      aliases = { "verify" => lambda { VerifyDialog() }, "create" => lambda do
        TreeDialog()
      end }


      sequence = {
        "ws_start" => "verify",
        "verify"   => {
          :abort    => :abort,
          :next     => "create",
          :overview => :next
        },
        "create"   => { :abort => :abort, :next => :next, :overview => :next }
      }

      Sequencer.Run(aliases, sequence)
    end

    # save current configuration into global map
    def CommitConfig
      ProductCreator.CommitConfig
      :next
    end

    # Initialize the sources of selected configuration
    def InitSources
      ProductCreator.EnableSource
      :next
    end

    # Initialize the list of current repositories (before any other handling):
    # we need to know their id's so it is possible to delete them when new
    # kiwi config is imported (and its repos should be added)
    def InitRepositories
      # finish sources before next start, so 32bit and 64bit don't get mangled (bnc#510971)
      Pkg.SourceFinishAll
      Pkg.SourceStartManager(false)

      Kiwi.initial_repositories = Kiwi.InitCurrentRepositories
      Kiwi.Read
      :next
    end


    def KiwiSequence
      aliases = {
        "init_sources" => [lambda { InitSources() }, true],
        "kiwi"         => lambda { KiwiDialog() },
        "summary"      => lambda { CommitConfig() },
        # FIXME check if it was only kiwi config...
        "write"        => lambda do
          WriteDialog()
        end
      }

      sequence = {
        "ws_start"     => "init_sources",
        "init_sources" => { :next => "kiwi" },
        "kiwi"         => { :abort => :abort, :next => "summary" },
        "summary"      => { :next => "write" },
        "write"        => { :abort => :abort, :next => :next }
      }
      Sequencer.Run(aliases, sequence)
    end

    def ImageCreatorSequence
      aliases = {
        "init_repositories" => [lambda { InitRepositories() }, true],
        "images_overview"   => lambda { ImagesOverviewDialog() },
        "kiwi_prepare"      => lambda { PrepareDialog() },
        "kiwi"              => lambda { KiwiDialog() }
      }
      sequence = {
        "ws_start"          => "init_repositories",
        "init_repositories" => { :next => "images_overview" },
        "images_overview"   => {
          :abort => :abort,
          :kiwi  => "kiwi_prepare",
          :next  => :next
        },
        "kiwi_prepare"      => { :abort => :abort, :next => "kiwi" },
        "kiwi"              => {
          :abort => :abort,
          :next  => "init_repositories"
        }
      }

      PackageCallbacks.InitPackageCallbacks

      ret = Sequencer.Run(aliases, sequence)
      ret
    end

    # Main workflow of the product-creator configuration
    # @return sequence result
    def MainSequence
      aliases = {
        "overview"  => lambda { OverviewDialog() },
        "configure" => [lambda { AddSequence() }, true],
        "add"       => [lambda { AddSequence() }, true],
        "edit"      => [lambda { AddSequence() }, true],
        "create"    => [lambda { CreateSequence() }, true],
        "kiwi"      => [lambda { KiwiSequence() }, true]
      }

      sequence = {
        "ws_start"  => "overview",
        "overview"  => {
          :abort  => :abort,
          :add    => "add",
          :edit   => "edit",
          :create => "create",
          :kiwi   => "kiwi",
          :next   => :next
        },
        "configure" => { :abort => :abort, :next => "overview" },
        "add"       => { :abort => :abort, :next => "overview" },
        "edit"      => { :abort => :abort, :next => "overview" },
        "create"    => { :abort => :abort, :next => "overview" },
        "kiwi"      => { :abort => :abort, :next => "overview" }
      }

      ret = Sequencer.Run(aliases, sequence)

      ret
    end



    # Whole configuration of product-creator
    # @return sequence result
    def ProductCreatorSequence
      aliases = { "main" => lambda { MainSequence() }, "read" => [lambda do
        ReadDialog()
      end, true] }

      sequence = {
        "ws_start" => "read",
        "read"     => { :abort => :abort, :next => "main" },
        "main"     => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("product-creator")
      required_packages = ["inst-source-utils", "mkisofs", "createrepo"]

      # add PPC specific packages
      if ProductCreator.GetArch == "ppc" || ProductCreator.GetArch == "ppc64"
        # /bin/objcopy - binutils
        # /bin/mkzimage - lilo
        required_packages = Convert.convert(
          Builtins.union(required_packages, ["binutils", "lilo"]),
          :from => "list",
          :to   => "list <string>"
        )
      end

      if !Package.InstallAll(required_packages)
        Popup.Error(_("Installation of required packages\nfailed."))
        return false
      end

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret == :next
    end
  end
end
