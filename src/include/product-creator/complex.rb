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

# File:	include/product-creator/complex.ycp
# Package:	Configuration of product-creator
# Summary:	Dialogs definitions
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
module Yast
  module ProductCreatorComplexInclude
    def initialize_product_creator_complex(include_target)
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "product-creator"

      Yast.import "CommandLine"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Kiwi"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "ProductCreator"
      Yast.import "Report"
      Yast.import "String"
      Yast.import "Wizard"
      Yast.import "UIHelper"

      Yast.include include_target, "product-creator/helps.rb"
      Yast.include include_target, "product-creator/dialogs.rb"
      Yast.include include_target, "product-creator/routines.rb"

      @first_start = true
    end

    # Return a modification status
    # @return true if data was modified
    def Modified
      ProductCreator.Modified
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))
      ProductCreator.AbortFunction = lambda { ProductCreator.PollAbort }
      ret = ProductCreator.Read
      ret ? :next : :abort
    end

    # Write settings dialog
    # @return `abort if aborted and `next otherwise
    def WriteDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "write", ""))
      ProductCreator.AbortFunction = lambda { ProductCreator.PollAbort }
      ret = ProductCreator.Write
      ret ? :next : :abort
    end

    # check if the selected configuration has the same target architecture as the machine architecture
    # needed for creating kiwi images because kiwi cannot create cross-architecture images
    def SameArchitecture
      # current config's arch
      arch = Ops.get_string(ProductCreator.Config, "arch", "")
      arch = "i386" if Builtins.contains(["i486", "i586", "i686"], arch)
      # system's arch
      sysarch = ProductCreator.GetArch

      # possible combination
      if arch == "i386" && sysarch == "x86_64"
        # Kiwi.ycp asks if GetArch is i386
        ProductCreator.SetPackageArch("i686")
        return true
      end
      # is the target architecture different than the machine architecture?
      if arch != nil && arch != "" && arch != sysarch
        # error message: %1 and %2 are architecture names like i386, x86_64, ppc...
        Report.Error(
          Builtins.sformat(
            _(
              "Target architecture of the current configuration (%1)\n" +
                "does not match the system architecture (%2).\n" +
                "\n" +
                "Kiwi cannot create images for different architectures."
            ),
            arch,
            sysarch
          )
        )
        return false
      end

      true
    end

    def checkNeededPackages
      # if the target is a PPC product and the system arch is not PPC we need to install
      # cross-ppc-binutils package to update the initrd
      if (Ops.get_string(ProductCreator.Config, "arch", "") == "ppc" ||
          Ops.get_string(ProductCreator.Config, "arch", "") == "ppc64") &&
          !Arch.ppc
        Builtins.y2milestone("cross-ppc-binutils is needed")
        return Package.InstallAll(["cross-ppc-binutils"])
      end

      true
    end

    # Overview dialog
    # @return dialog result
    def OverviewDialog
      # ProductCreator overview dialog caption
      caption = _("Product Creator Configuration Overview")

      overview = ProductCreator.Overview

      # start "add" workflow if there is no configuration
      if @first_start
        @first_start = false

        return :add if Builtins.size(overview) == 0
      end

      contents = UIHelper.EditTable(
        # Table header
        Header(_("Name"), _("Product"), _("Image"), _("GPG Key")),
        overview,
        nil,
        nil,
        nil,
        nil
      )

      menubutton_items = [
        # push button label
        Item(Id(:xen_button), _("Xen Image")),
        # push button label
        Item(Id(:vmx_button), _("Virtual Disk Image"))
      ]
      # build Live iso only for x86_64 and i386 (bnc#675101)
      if Arch.architecture == "x86_64" || ProductCreator.GetArch == "i386"
        menubutton_items = Builtins.prepend(
          menubutton_items,
          # push box item
          Item(Id(:iso_button), _("Live ISO Image"))
        )
      end

      contents2 = VBox(
        contents,
        HBox(
          # menu button label
          MenuButton(
            Id(:create_button),
            _("&Create Product..."),
            [
              # button label
              Item(Id(:create_iso_button), _("ISO Image")),
              # button label
              Item(Id(:create_tree_button), _("Directory Tree"))
            ]
          ),
          # menu button label
          MenuButton(
            Id(:kiwi),
            _("Cre&ate Image with KIWI..."),
            menubutton_items
          )
        )
      )

      contents = UIHelper.SpacingAround(contents2, 1.5, 1.5, 1.0, 1.0)

      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "overview", ""),
        Label.BackButton,
        Label.CloseButton
      )

      if Builtins.size(overview) == 0
        UI.ChangeWidget(Id(:edit_button), :Enabled, false)
        UI.ChangeWidget(Id(:delete_button), :Enabled, false)
        UI.ChangeWidget(Id(:create_button), :Enabled, false)
        UI.ChangeWidget(Id(:kiwi), :Enabled, false)
      end

      ret = nil
      while true
        # reset the current architecture (needed when going back)
        ProductCreator.ResetArch
        # unload all active sources (reset the internal state, see bnc#469191)
        Pkg.SourceFinishAll

        ret = UI.UserInput

        current = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
        # abort?
        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        # add
        elsif ret == :add_button
          ProductCreator.Config = {}
          ret = :add
          break
        # edit
        elsif ret == :edit_button || ret == :table
          ProductCreator.LoadConfig(current)
          ret = :edit
          break
        # delete
        elsif ret == :delete_button
          Builtins.y2debug("Deleting: %1", current)
          ProductCreator.Configs = Builtins.filter(ProductCreator.Configs) do |k, v|
            k != current
          end
          overview = ProductCreator.Overview
          UI.ChangeWidget(Id(:table), :Items, overview)
          if Builtins.size(overview) == 0
            UI.ChangeWidget(Id(:edit_button), :Enabled, false)
            UI.ChangeWidget(Id(:delete_button), :Enabled, false)
            UI.ChangeWidget(Id(:create_button), :Enabled, false)
            UI.ChangeWidget(Id(:kiwi), :Enabled, false)
          end
          Yast.import "Progress"
          Progress.set(false)
          ProductCreator.Write
          Progress.set(true)
          next
        # create
        elsif ret == :create_iso_button || ret == :create_tree_button
          current2 = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          ProductCreator.Config = Ops.get(ProductCreator.Configs, current2, {})
          # check the needed packages
          next if !checkNeededPackages

          if ret == :create_iso_button
            Ops.set(ProductCreator.Config, "result", "iso")
            isofile_path = Ops.get_string(ProductCreator.Config, "isofile", "")
            if isofile_path == ""
              Ops.set(
                ProductCreator.Config,
                "isofile",
                Ops.add(
                  Ops.get_string(ProductCreator.Config, "name", ""),
                  ".iso"
                )
              )
            end
          else
            Ops.set(ProductCreator.Config, "result", "tree")
          end
          ret = :create
          break
        elsif ret == :iso_button &&
            Package.InstallAll(["kiwi", "squashfs", "kiwi-desc-isoboot"])
          current2 = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          ProductCreator.Config = Ops.get(ProductCreator.Configs, current2, {})
          # check the architecture
          next if !SameArchitecture()
          Kiwi.kiwi_task = "iso"
          ret = :kiwi
          break
        elsif ret == :xen_button &&
            Package.InstallAll(["kiwi", "squashfs", "kiwi-desc-xenboot"])
          current2 = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          ProductCreator.Config = Ops.get(ProductCreator.Configs, current2, {})
          # check the architecture
          next if !SameArchitecture()
          Kiwi.kiwi_task = "xen"
          ret = :kiwi
          break
        elsif ret == :vmx_button &&
            Package.InstallAll(["kiwi", "squashfs", "kiwi-desc-vmxboot"])
          current2 = Convert.to_string(UI.QueryWidget(Id(:table), :CurrentItem))
          ProductCreator.Config = Ops.get(ProductCreator.Configs, current2, {})
          # check the architecture
          next if !SameArchitecture()
          Kiwi.kiwi_task = "vmx"
          ret = :kiwi
          break
        elsif ret == :next || ret == :back
          break
        else
          Builtins.y2error("unexpected retcode: %1", ret)
          next
        end
      end

      Convert.to_symbol(ret)
    end



    # TreeDialog
    # Dialog for creating the skeleton and copying common data.
    # @return [Symbol]
    def TreeDialog
      Yast.import "Progress"


      help = _(
        "<P>Creating the directory structure for the new ISO image.</P>\n                \n"
      )
      help = Ops.add(
        help,
        _("<p>Press <b>Next</b> to start creating the ISO file.</p>")
      )



      progress_stages = [
        _("Create skeleton with common files"),
        _("Copy additional and customized files"),
        _("Copy selected packages")
      ]

      progress_descriptions = [
        _("Creating skeleton with essential files"),
        _("Copying additional and customized files to directory tree..."),
        _("Copying selected packages")
      ]

      gpg_key = Ops.get_string(ProductCreator.Config, "gpg_key", "")
      if gpg_key != ""
        # label
        progress_stages = Builtins.add(
          progress_stages,
          _("Sign the source with a GPG key")
        )
        # progressbar label
        progress_descriptions = Builtins.add(
          progress_descriptions,
          _("Signing the source with a GPG key...")
        )
      else
        # label
        progress_stages = Builtins.add(
          progress_stages,
          _("Disable signature checks in linuxrc")
        )
        # progressbar label
        progress_descriptions = Builtins.add(
          progress_descriptions,
          _("Disabling signature checks in linuxrc...")
        )
      end

      Progress.New(
        _("Creating ISO image directory..."),
        "",
        Ops.add(
          Ops.add(Builtins.size(progress_stages), ProductCreator.PackageCount), # progress_title
          1
        ),
        progress_stages,
        progress_descriptions,
        help
      )


      if ProductCreator.Abort
        ProductCreator.ResetCallbacks
        return :abort
      end
      Progress.NextStage

      # redirect the download callbacks
      ProductCreator.RedirectCallbacks

      boot_info = ProductCreator.GetBootInfo
      Builtins.y2milestone("Boot info: %1", boot_info)

      bootable = Ops.get_boolean(boot_info, "bootable", false)
      boot_arch = Ops.get_string(boot_info, "boot_architecture", "")
      base_source = Ops.get_integer(boot_info, "base_source", -1)

      if !ProductCreator.CreateSkeleton(base_source, bootable, boot_arch)
        Report.Error(_("Error while creating skeleton."))
        ProductCreator.ResetCallbacks
        return :overview
      end


      if ProductCreator.Abort
        ProductCreator.ResetCallbacks
        return :abort
      end
      Progress.NextStage
      if Ops.get_string(ProductCreator.Config, "pkgtype", "") == "autoyast"
        ProductCreator.CopyMiscFiles(boot_arch)
      else
        if Ops.get_string(ProductCreator.Config, "bootconfig", "") != ""
          Builtins.y2debug("bootconfig available")
          fname = Builtins.sformat(
            "%1/boot/%2/loader/isolinux.cfg",
            ProductCreator.skel_root,
            boot_arch
          )
          Builtins.y2milestone("Writing bootconfig to %1", fname)

          SCR.Write(
            path(".target.string"),
            fname,
            Ops.get_string(ProductCreator.Config, "bootconfig", "")
          )
        end
      end

      Progress.NextStage
      if !ProductCreator.CopyPackages
        ProductCreator.ResetCallbacks
        return :overview
      end

      Progress.NextStage
      if !ProductCreator.SignSourceStep
        ProductCreator.ResetCallbacks
        return :overview
      end

      i = 0

      Progress.Title(_("ISO image directory ready"))
      Progress.Finish

      # if (!Mode::commandline())
      # {
      #     Wizard::EnableNextButton();
      #     Wizard::RestoreNextButton();
      # }


      ret = nil
      begin
        ret = :next
        if ret == :next
          if Ops.get_string(ProductCreator.Config, "result", "") == "iso"
            isodir = Ops.add(
              Ops.add(
                Ops.get_string(ProductCreator.Config, "iso-directory", "/tmp"),
                "/"
              ),
              Ops.get_string(ProductCreator.Config, "name", "tmp")
            )
            isofile = Ops.add(
              Ops.add(
                Ops.get_string(ProductCreator.Config, "iso-directory", ""),
                "/"
              ),
              Ops.get_string(ProductCreator.Config, "isofile", "")
            )
            pub = Ops.get_string(ProductCreator.Config, "publisher", "anon")
            prep = Ops.get_string(ProductCreator.Config, "preparer", "anon")

            output = Convert.to_map(
              SCR.Execute(
                path(".target.bash_output"),
                Builtins.sformat(
                  "du -s -b '%1' | awk -F' ' ' { printf $1 }'",
                  String.Quote(isodir)
                )
              )
            )
            du = Ops.get_string(output, "stdout", "")
            Builtins.y2milestone("Expected size: %1", du)

            if !Mode.commandline
              Popup.ShowFeedback(
                _("Creating CD Image..."),
                _("This may take a while.")
              )
            end

            command = Builtins.sformat(
              "/usr/lib/YaST2/bin/y2mkiso '%1' '%2' '%3'",
              String.Quote(isodir),
              String.Quote(isofile),
              String.Quote(boot_arch)
            )
            Builtins.y2milestone("command: %1", command)

            SCR.Execute(
              path(".target.bash"),
              command,
              { "CD_PUBLISHER" => pub, "CD_PREPARER" => prep }
            )

            Popup.ClearFeedback if !Mode.commandline
          end
        end
      end until ret == :next || ret == :back || ret == :abort

      ProductCreator.ResetCallbacks

      Convert.to_symbol(ret)
    end

    # ISO Summary
    # @return [Symbol]
    def isoSummary
      Yast.import "HTML"

      # caption
      caption = _("ISO Summary")
      html = HTML.Heading(_("Package Source"))
      html = Ops.add(
        html,
        HTML.Para(Ops.get_string(ProductCreator.Config, "source", ""))
      )

      html = Ops.add(html, HTML.Heading(_("Packages")))
      html = Ops.add(
        html,
        HTML.Para(
          Builtins.sformat(
            "%1",
            Builtins.size(Pkg.GetPackages(:selected, true))
          )
        )
      )

      html = Ops.add(html, HTML.Heading(_("Missing Packages")))
      if Ops.greater_than(Builtins.size(ProductCreator.missing_packages), 0)
        html = Ops.add(html, HTML.List(ProductCreator.missing_packages))
      else
        html = Ops.add(html, HTML.Para(_("None")))
      end

      contents = RichText(html)

      help_text = _(
        "<p>Verify the data in the summary box then\npress Finish to return to main dialog.</p>\n"
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        help_text,
        Label.BackButton,
        Label.NextButton
      )
      ret = nil
      begin
        ret = UI.UserInput
      end until ret == :next || ret == :back || ret == :abort
      Convert.to_symbol(ret)
    end

    # VerifyDialog()
    # Verify Dialog
    #
    def VerifyDialog
      Yast.import "Progress"


      # caption
      caption = _("Custom CDs")

      help = _(
        "<p>Verifying data and packages...\n" +
          "                    </p>\n" +
          "                    \n"
      )
      help = Ops.add(
        help,
        _(
          "<p>If there is something missing, the process will be aborted.\n" +
            "Fix the problem and try again.</p>\n" +
            "                    "
        )
      )

      progress_stages = [
        _("Set up Package Source"),
        _("Create Package List"),
        _("Verify Package Availability"),
        _("Check Destination")
      ]

      progress_descriptions = [
        _("Configuring package source..."),
        _("Creating package list..."),
        _("Verifying package availability..."),
        _("Checking destination...")
      ]

      Progress.New(
        _("Verification of Data for ISO Image"),
        "", # progress_title
        Builtins.size(progress_stages),
        progress_stages,
        progress_descriptions,
        help
      )


      success = true

      arch = Ops.get_string(ProductCreator.Config, "arch", "")
      ProductCreator.SetPackageArch(arch) if arch != nil && arch != ""


      Progress.NextStage
      Pkg.TargetFinish

      tmp = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      #            SCR::Execute(.target.mkdir, tmp + "/tmproot");
      #            Pkg::TargetInit( tmp + "/tmproot" , true);

      CommandLine.PrintVerbose(_("Enabling sources..."))
      success = ProductCreator.EnableSource

      if !success
        ProductCreator.CheckUnavailableSources
        return :overview
      end

      Progress.NextStage
      CommandLine.PrintVerbose(_("Selecting packages..."))
      success = ProductCreator.setPackages

      if !success
        # set a fake root mount point - there is no use to display DU of the current system
        Pkg.TargetInitDU(
          [
            {
              "name"     => "/",
              "free"     => 999 * 1024 * 1024, # 999GB
              "used"     => 0,
              "readonly" => false
            }
          ]
        )

        # the solver has failed, let the user resolve the dependencies
        detailedSelection(nil)
      end


      Progress.NextStage
      CommandLine.PrintVerbose(_("Checking packages..."))
      error_msg = ProductCreator.checkPackageAvail
      if error_msg != ""
        Popup.Error(error_msg)
        return :back
      end

      Progress.NextStage
      CommandLine.PrintVerbose(_("Verifying the destination directory..."))
      return :overview if !ProductCreator.verifyDestination

      Progress.Finish

      return :next if Mode.commandline

      #             Wizard::EnableNextButton();
      #             Wizard::RestoreNextButton();
      #             Wizard::EnableBackButton();
      :next
    end

    def CheckBootableSrc
      boot_info = ProductCreator.GetBootInfo
      bootable = Ops.get_boolean(boot_info, "bootable", false)

      if !bootable
        Builtins.y2milestone(
          "Base source %1 is not bootable, skipping isolinux.cfg configuration",
          Ops.get_integer(boot_info, "base_source", -1)
        )
        return :skip_isolinux
      end

      # skip isolinux configuration if the architecture
      # is not i386 or x86_64 - there is no isolinux
      if ProductCreator.GetArch != "i386" && ProductCreator.GetArch != "x86_64"
        return :skip_isolinux
      end

      :next
    end

    # overview dialog with image configurations
    def ImagesOverviewDialog
      overview = []
      _Configurations = {}

      images_dir = Kiwi.images_dir
      if !FileUtils.Exists(images_dir)
        SCR.Execute(path(".target.mkdir"), images_dir)
      end

      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("ls -A1 %1", images_dir)
        )
      )
      if out != {}
        i = 0
        Builtins.foreach(
          Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
        ) do |d|
          next if d == ""
          if FileUtils.Exists(
              Ops.add(Ops.add(Ops.add(images_dir, "/"), d), "/config.xml")
            )
            # FIXME now, we should read only type, name, version, size to
            # make initial start faster
            config = Kiwi.ReadConfigXML(Ops.add(Ops.add(images_dir, "/"), d))
            if Ops.get_string(config, ["description", 0, "type"], "") != "system"
              Builtins.y2warning("%1 not a 'system' image type, skipping", d)
              next
            end
            task = get_current_task(config)

            Ops.set(config, "original_directory", d)
            Ops.set(
              config,
              Ops.add("kiwi_configuration_", task),
              Ops.add(Ops.add(images_dir, "/"), d)
            )
            Ops.set(config, "current_task", task)

            name = Ops.get_string(config, "name", d)
            # index by order, so we can handle more configs with same name
            Ops.set(_Configurations, i, config)
            size_map = get_current_size_map(config, task)
            unit = Ops.get_string(size_map, "unit", "M")
            i_size = Ops.get_string(size_map, Kiwi.content_key, "")
            # fallback values when size is not given
            if i_size == ""
              i_size = Kiwi.default_size
              if Ops.get_string(size_map, "additive", "") == ""
                Ops.set(size_map, "additive", "true")
              end
            end
            i_size = Ops.add(i_size, unit)
            # with "additive", "size" has a different meaning
            if Ops.get_string(size_map, "additive", "") == "true"
              i_size = Ops.add("+", i_size)
            end
            overview = Builtins.add(
              overview,
              Item(
                Id(i),
                name,
                get_preferences(config, "version", "1.0.0"),
                i_size
              )
            )
            i = Ops.add(i, 1)
          end
        end
      end

      # help text
      help_text = Ops.add(
        _("<p>Start creating a new image configuration with <b>Add</b>.</p>") +
          # help text
          _(
            "<p>Use <b>Edit</b> to change selected image configuration or create the image.</p>"
          ) +
          # help text
          _(
            "<p>Delete the directory with the selected configuration by selecting <b>Delete</b>.</p>"
          ),
        # help text, %1 is directory
        Builtins.sformat(
          _(
            "<p>All image configurations are saved in <tt>%1</tt> directory.</p>"
          ),
          images_dir
        )
      )

      # main dialog caption
      caption = _("Image Creator Configuration Overview")

      contents = VBox(
        VWeight(
          3,
          Table(
            Id(:table),
            Opt(:notify, :immediate),
            Header(_("Name"), _("Version"), _("Size")),
            overview
          )
        ),
        VWeight(1, RichText(Id(:descr), "")),
        HBox(
          PushButton(Id(:add), Opt(:key_F3), Label.AddButton),
          PushButton(Id(:edit), Opt(:key_F4), Label.EditButton),
          PushButton(Id(:delete), Opt(:key_F5), Label.DeleteButton),
          HStretch()
        )
      )

      contents = UIHelper.SpacingAround(contents, 1.5, 1.5, 1.0, 1.0)

      Wizard.SetContentsButtons(
        caption,
        contents,
        help_text,
        Label.BackButton,
        Label.CloseButton
      )
      Wizard.HideBackButton
      Wizard.HideAbortButton

      UI.ChangeWidget(
        Id(:edit),
        :Enabled,
        Ops.greater_than(Builtins.size(overview), 0)
      )
      if Ops.greater_than(Builtins.size(overview), 0)
        current = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
        val = get_description(
          Ops.get_map(_Configurations, current, {}),
          "specification"
        )
        UI.ChangeWidget(
          Id(:descr),
          :Value,
          Builtins.mergestring(
            Builtins.splitstring(String.EscapeTags(val), "\n"),
            "<br>"
          )
        )
      end

      ret = nil
      while true
        event = UI.WaitForEvent
        ret = Ops.get(event, "ID")

        current = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))

        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == :add
          ProductCreator.Config = {}
          ret = :kiwi
          break
        elsif ret == :delete
          config = Ops.get_map(_Configurations, current, {})
          version = get_preferences(config, "version", "")
          if Popup.YesNo(
              # yes/no popup
              Builtins.sformat(
                _("Delete configuration %1 (%2) now?"),
                Ops.get_string(config, "name", ""),
                version
              )
            )
            dir = Ops.get_string(
              config,
              Ops.add(
                "kiwi_configuration_",
                Ops.get_string(config, "current_task", "")
              ),
              ""
            )
            if dir != "" && Builtins.issubstring(dir, Kiwi.images_dir)
              SCR.Execute(path(".target.bash"), Ops.add("rm -rf ", dir))
            end
            _Configurations = Builtins.remove(_Configurations, current)
            overview = Builtins.filter(
              Convert.convert(overview, :from => "list", :to => "list <term>")
            ) do |it|
              Ops.get_integer(it, [0, 0], -1) != current ||
                Ops.get_string(it, 2, "") != version
            end
            UI.ChangeWidget(Id(:table), :Items, overview)
            current = Convert.to_integer(
              UI.QueryWidget(Id(:table), :CurrentItem)
            )
            UI.ChangeWidget(
              Id(:descr),
              :Value,
              get_description(
                Ops.get_map(_Configurations, current, {}),
                "specification"
              )
            )
          end
        elsif ret == :table
          UI.ChangeWidget(
            Id(:descr),
            :Value,
            get_description(
              Ops.get_map(_Configurations, current, {}),
              "specification"
            )
          )
          ret = :edit if Ops.get_string(event, "EventReason", "") == "Activated"
        end
        if ret == :edit
          ProductCreator.Config = Ops.get_map(_Configurations, current, {})
          task = Ops.get_string(ProductCreator.Config, "current_task", "")
          to_install = ["kiwi"]
          if Package.InstallAll(to_install)
            dir = Ops.get_string(
              ProductCreator.Config,
              Ops.add("kiwi_configuration_", task),
              ""
            )
            Kiwi.ImportImageRepositories(ProductCreator.Config, dir)
            Kiwi.kiwi_task = task
            ret = :kiwi
            break
          end
          next
        end
        break if ret == :next || ret == :back
      end
      if ret == :kiwi
        # we do import own sources...
        ProductCreator.enable_sources = false
        # ask on abort...
        ProductCreator.modified = true
      end
      Convert.to_symbol(ret)
    end
  end
end
