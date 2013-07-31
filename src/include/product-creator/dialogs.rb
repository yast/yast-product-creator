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

# File:	include/product-creator/dialogs.ycp
# Package:	Configuration of product-creator
# Summary:	Dialogs definitions
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
module Yast
  module ProductCreatorDialogsInclude
    def initialize_product_creator_dialogs(include_target)
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "product-creator"

      Yast.import "FileUtils"
      Yast.import "ProductCreator"
      Yast.import "Wizard"
      Yast.import "SourceManager"
      Yast.import "Report"
      Yast.import "URL"
      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "GPG"
      Yast.import "GPGWidgets"
      Yast.import "CWM"
      Yast.import "String"
      Yast.import "Package"
      Yast.import "Arch"
      Yast.import "PackagesUI"

      Yast.include include_target, "product-creator/routines.rb"
      Yast.include include_target, "product-creator/helps.rb"

      # remember the direction to correctly skip baseProductSelectionDialog()
      @going_back = false
    end

    #    Create a table item from a map as returned by the InstSrcManager agent.
    #    @param [Fixnum] source The map describing the source as returned form the agent.
    #    @return An item suitable for addition to a Table.
    def createTableItem(source, selectable, media_filter)
      # Source data
      sd = SourceManager.SourceData(source)
      Builtins.y2milestone("SourceManager:: sources: %1", sd)
      item = Item()

      url = URL.Parse(Ops.get_string(sd, "url", ""))
      if media_filter == "" || Ops.get_string(url, "scheme", "") == media_filter
        if selectable
          item = Item(
            Id(source),
            "",
            Ops.get_boolean(
              # corresponds to the "Enable/Disable" button
              sd,
              "enabled",
              true
            ) ?
              _("On") :
              _("Off"),
            Ops.get_string(sd, "alias", ""),
            Ops.get_string(sd, "url", "")
          )
        else
          item = Item(
            Id(source),
            Ops.get_boolean(
              # corresponds to the "Enable/Disable" button
              sd,
              "enabled",
              true
            ) ?
              _("On") :
              _("Off"),
            Ops.get_string(sd, "alias", ""),
            Ops.get_string(sd, "url", "")
          )
        end
      end

      Builtins.y2debug("Table item for source %1: %2", source, item)
      deep_copy(item)
    end

    # Fill sources table with entries from the InstSrcManager agent.
    # @return [Array] list of items
    def fillSourceTable(sources, selectable, media_filter)
      sources = deep_copy(sources)
      sources = Pkg.SourceGetCurrent(false) if Builtins.size(sources) == 0

      items = []

      items = Builtins.maplist(sources) do |source|
        Builtins.y2debug("working on source: %1", source)
        createTableItem(source, selectable, media_filter)
      end
      items = Builtins.filter(items) { |i| Ops.get_string(i, 3, "") != "" }

      deep_copy(items)
    end

    # Select package for installation. If package itself is not available, find package providing it
    # If version is not empty, select specific package version
    def InstallPackageOrProviderVersion(p, version)
      selected = version == "" ?
        Pkg.PkgInstall(p) :
        Pkg.ResolvableInstallArchVersion(
          p,
          :package,
          ProductCreator.GetArch,
          version
        )

      Builtins.y2milestone(
        "selecting package for installation: %1 -> %2",
        p,
        selected
      )
      if !selected
        provides = Pkg.PkgQueryProvides(p)
        provides = Builtins.filter(provides) do |l|
          Ops.get_symbol(l, 1, :NONE) != :NONE
        end
        pp = Ops.get_string(provides, [0, 0], "")
        if pp != ""
          Builtins.y2milestone(
            "selecting first package providing %1: %2 -> %3",
            p,
            pp,
            Pkg.PkgInstall(pp)
          )
        end
      end

      true
    end

    def InstallPackageOrProvider(p)
      InstallPackageOrProviderVersion(p, "")
    end


    # General configuration dialog
    # @return dialog result
    def Configure1Dialog
      # ProductCreator configure1 dialog caption
      caption = _("Product Creator Configuration")


      name = Ops.get_string(ProductCreator.Config, "name", "")
      pkgtype = Ops.get_string(
        ProductCreator.Config,
        "pkgtype",
        "package-manager"
      )

      # Autoyast
      profile = Ops.get_string(ProductCreator.Config, "profile", "")
      copy_profile = Ops.get_boolean(
        ProductCreator.Config,
        "copy_profile",
        false
      )


      # List
      plain_list = Ops.get_string(ProductCreator.Config, "package-list", "")


      c2 = HBox(
        HWeight(10, Empty()),
        HWeight(
          80,
          VBox(
            VSquash(
              HBox(
                InputField(
                  Id(:profile_loc),
                  Opt(:hstretch),
                  # text entry label
                  _("Profile Loca&tion:"),
                  profile
                ),
                VBox(
                  VSpacing(),
                  Bottom(
                    # push button label
                    PushButton(Id(:open_profile), _("Select Fi&le"))
                  )
                )
              )
            ),
            Left(
              CheckBox(
                Id(:copyprofile),
                # check box label
                _("Copy Profile to CD I&mage"),
                copy_profile
              )
            )
          )
        )
      )

      v = VBox(
        # radio button label
        Left(
          RadioButton(
            Id(:pkgmgr),
            Opt(:notify),
            _("Pac&kage Manager"),
            pkgtype == "package-manager"
          )
        ),
        # radio button label
        Left(
          RadioButton(
            Id(:autoyast),
            Opt(:notify),
            _("&AutoYaST Control File"),
            pkgtype == "autoyast"
          )
        ),
        c2
      )


      sources = [] # ProductCreator::GetDirSources(source);
      # ProductCreator configure1 dialog contents
      contents = HVSquash(
        VBox(
          InputField(
            Id(:name),
            Opt(:hstretch),
            # text entry label
            _("&Configuration Name:"),
            name
          ),
          # frame label
          Frame(_("Packages"), VBox(RadioButtonGroup(Id(:pkg), v)))
        )
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "initial", ""),
        Label.BackButton,
        Label.NextButton
      )



      ret = nil
      rb = :none
      while true
        rb = Convert.to_symbol(UI.QueryWidget(Id(:pkg), :CurrentButton))

        if rb == :autoyast
          UI.ChangeWidget(Id(:profile_loc), :Enabled, true)
          UI.ChangeWidget(Id(:open_profile), :Enabled, true)
          UI.ChangeWidget(Id(:copyprofile), :Enabled, true)
        elsif rb == :plain
          UI.ChangeWidget(Id(:profile_loc), :Enabled, false)
          UI.ChangeWidget(Id(:open_profile), :Enabled, false)
          UI.ChangeWidget(Id(:copyprofile), :Enabled, false)
        else
          UI.ChangeWidget(Id(:profile_loc), :Enabled, false)
          UI.ChangeWidget(Id(:open_profile), :Enabled, false)
          UI.ChangeWidget(Id(:copyprofile), :Enabled, false)
        end

        ret = UI.UserInput



        # abort?
        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == :next
          # set architecture if configured
          arch = Ops.get_string(ProductCreator.Config, "arch", "")
          ProductCreator.SetPackageArch(arch) if arch != nil && arch != ""

          name2 = Convert.to_string(UI.QueryWidget(Id(:name), :Value))

          if name2 == ""
            Report.Error(_("Enter the name of the configuration."))
            next
          end
          if Builtins.haskey(ProductCreator.Configs, name2) &&
              Ops.get_string(ProductCreator.Config, "name", "") != name2
            Report.Error(
              _(
                "A configuration with this name already exists.\n                                Select a new name.\n"
              )
            )
            next
          end


          Ops.set(
            ProductCreator.Config,
            "old_name",
            Ops.get_string(ProductCreator.Config, "name", "")
          )
          Ops.set(ProductCreator.Config, "name", name2)



          if rb == :autoyast
            profile_loc = Convert.to_string(
              UI.QueryWidget(Id(:profile_loc), :Value)
            )
            if !FileUtils.Exists(profile_loc)
              # error message
              Report.Error(
                Builtins.sformat(
                  _("The file '%1' does not exist. Choose a correct one."),
                  profile_loc
                )
              )
              next
            end
            Ops.set(ProductCreator.Config, "pkgtype", "autoyast")
            Ops.set(ProductCreator.Config, "profile", profile_loc)
            Ops.set(
              ProductCreator.Config,
              "copy_profile",
              Convert.to_boolean(UI.QueryWidget(Id(:copyprofile), :Value))
            )
          else
            Ops.set(ProductCreator.Config, "pkgtype", "package-manager")
          end
          ProductCreator.modified = true
          ProductCreator.profile_parsed = false
          break
        elsif ret == :back
          break
        elsif ret == :open_profile
          new_file = UI.AskForExistingFile(
            ProductCreator.AYRepository,
            "*",
            _("Select File")
          )
          if new_file != nil
            UI.ChangeWidget(
              Id(:profile_loc),
              :Value,
              Convert.to_string(new_file)
            )
          end
          next
        else
          if ret != :autoyast && ret != :pkgmgr
            Builtins.y2error("unexpected retcode: %1", ret)
          end
          next
        end
      end

      Convert.to_symbol(ret)
    end

    # Configure2 dialog
    # @return dialog result
    def Configure2Dialog
      # ProductCreator configure2 dialog caption
      caption = _("Product Creator Configuration")

      dirtree = Ops.get_string(ProductCreator.Config, "iso-directory", "")
      publisher = Ops.get_string(ProductCreator.Config, "publisher", "")
      preparer = Ops.get_string(ProductCreator.Config, "preparer", "")
      result = Ops.get_string(ProductCreator.Config, "result", "iso")
      isofile_path = Ops.get_string(ProductCreator.Config, "isofile", "")
      savespace = Ops.get_boolean(ProductCreator.Config, "savespace", false)

      if isofile_path == ""
        isofile_path = Ops.add(
          Ops.get_string(ProductCreator.Config, "name", ""),
          ".iso"
        )
      end

      # ProductCreator configure2 dialog contents
      contents = HVSquash(
        VBox(
          # frame label
          Frame(
            _("Output:"),
            VBox(
              VSquash(
                HBox(
                  InputField(
                    Id(:dirtree),
                    Opt(:hstretch),
                    # text entry label
                    _("&Path to Generated Directory Tree:"),
                    dirtree
                  ),
                  VBox(
                    VSpacing(),
                    Bottom(
                      # push button label
                      PushButton(Id(:open_dir), _("&Select Directory"))
                    )
                  )
                )
              ),
              RadioButtonGroup(
                Id(:result),
                VBox(
                  Left(
                    RadioButton(
                      Id(:isofile),
                      Opt(:notify),
                      # radio button label
                      _("&Generate ISO Image File"),
                      result == "iso"
                    )
                  ),
                  HBox(
                    HWeight(10, Empty()),
                    HWeight(
                      80,
                      VBox(
                        HBox(
                          HWeight(
                            2,
                            InputField(
                              Id(:isofile_path),
                              Opt(:hstretch),
                              # text entry label
                              _("&ISO Image File:"),
                              isofile_path
                            )
                          ),
                          HWeight(1, Empty())
                        )
                      )
                    )
                  ),
                  Left(
                    RadioButton(
                      Id(:directory),
                      Opt(:notify),
                      # radio button label
                      _("Create Directory &Tree Only"),
                      result == "tree"
                    )
                  )
                )
              )
            )
          ),
          VSpacing(1),
          # frame label
          Frame(
            _("Other Options"),
            VBox(
              Left(
                CheckBox(
                  Id(:savespace),
                  # check box label
                  _("Copy only needed files to save space."),
                  savespace
                )
              ),
              VSpacing(),
              Left(
                InputField(
                  Id(:pub),
                  Opt(:hstretch),
                  # text entry label
                  _("CD Publisher:"),
                  publisher
                )
              ),
              Left(
                InputField(
                  Id(:prep),
                  Opt(:hstretch),
                  # text entry label
                  _("CD Preparer:"),
                  preparer
                )
              )
            )
          )
        )
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "dest", ""),
        Label.BackButton,
        Label.NextButton
      )

      ret = nil
      while true
        rb = Convert.to_symbol(UI.QueryWidget(Id(:result), :CurrentButton))

        if rb == :isofile
          UI.ChangeWidget(Id(:isofile_path), :Enabled, true)
        else
          UI.ChangeWidget(Id(:isofile_path), :Enabled, false)
        end

        ret = UI.UserInput

        # abort?
        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == :open_dir
          new_dir = UI.AskForExistingDirectory(
            dirtree,
            # ask for directory widget label
            _("Select Directory")
          )
          if new_dir != nil
            UI.ChangeWidget(Id(:dirtree), :Value, Convert.to_string(new_dir))
          end
          next
        elsif ret == :back
          @going_back = true
          break
        elsif ret == :next
          isodir = Convert.to_string(UI.QueryWidget(Id(:dirtree), :Value))
          if isodir == ""
            # error popup
            Report.Error(_("Path to generated directory tree missing."))
            next
          else
            Ops.set(ProductCreator.Config, "iso-directory", isodir)
          end
          if rb == :isofile
            Ops.set(ProductCreator.Config, "result", "iso")
            Ops.set(
              ProductCreator.Config,
              "isofile",
              Convert.to_string(UI.QueryWidget(Id(:isofile_path), :Value))
            )
          else
            Ops.set(ProductCreator.Config, "result", "tree")
          end
          Ops.set(
            ProductCreator.Config,
            "savespace",
            Convert.to_boolean(UI.QueryWidget(Id(:savespace), :Value))
          )
          Ops.set(
            ProductCreator.Config,
            "publisher",
            Convert.to_string(UI.QueryWidget(Id(:pub), :Value))
          )
          Ops.set(
            ProductCreator.Config,
            "preparer",
            Convert.to_string(UI.QueryWidget(Id(:prep), :Value))
          )
          break
        elsif ret != :directory && ret != :isofile
          Builtins.y2error("unexpected retcode: %1", ret)
          next
        end
      end
      Convert.to_symbol(ret)
    end

    def AskArch(label, archs, preselected)
      archs = deep_copy(archs)
      widget1 = VBox()
      widget2 = VBox()

      max_lines = 6

      if !Builtins.contains(archs, preselected)
        Builtins.y2warning(
          "The preselected architecture is missing in the list!"
        )
        # add the missing preselected arch
        archs = Builtins.prepend(archs, preselected)
      end

      archsz = Builtins.size(archs)
      col1num = Ops.greater_than(archsz, max_lines) ?
        Ops.divide(Ops.add(archsz, 1), 2) :
        archsz
      Builtins.y2milestone("Number of archs in the first column: %1", col1num)

      # preselect the first item
      Builtins.foreach(archs) do |a|
        if Ops.greater_than(col1num, 0)
          widget1 = Builtins.add(
            widget1,
            MinWidth(10, Left(RadioButton(Id(a), a, a == preselected)))
          )
        else
          widget2 = Builtins.add(
            widget2,
            MinWidth(10, Left(RadioButton(Id(a), a, a == preselected)))
          )
        end
        col1num = Ops.subtract(col1num, 1)
      end 


      content = MarginBox(
        1,
        0.5,
        VBox(
          Label(label),
          VSpacing(1),
          Frame(
            _("Target Architecture"),
            RadioButtonGroup(
              Id(:rb),
              HBox(Top(widget1), HStretch(), Top(widget2), HStretch())
            )
          ),
          VSpacing(1),
          HBox(
            HSpacing(Opt(:hstretch), 2),
            HWeight(1, PushButton(Id(:ok), Label.OKButton)),
            HSpacing(2),
            HWeight(1, PushButton(Id(:cancel), Label.CancelButton)),
            HSpacing(Opt(:hstretch), 2)
          )
        )
      )

      UI.OpenDialog(content)

      ui = UI.UserInput
      ret = Convert.to_string(UI.QueryWidget(Id(:rb), :CurrentButton))

      UI.CloseDialog

      if ui == :cancel || ui == :close
        # canceled
        return nil
      elsif ui == :ok
        Builtins.y2milestone("Selected architecture: %1", ret)
        return ret
      else
        Builtins.y2error("Unhandled user input %1", ui)
        return nil
      end
    end


    def CheckArchitecture(_SrcID)
      general_info = Pkg.SourceGeneralData(_SrcID)
      Builtins.y2milestone(
        "Checking architecture of repository %1",
        general_info
      )
      found_architecture = false
      found_archs = []

      arch = ProductCreator.GetPackageArch

      arch = ProductCreator.GetArch if arch == nil

      arch = "s390x" if arch == "s390_64"

      type = Ops.get_string(general_info, "type", "")

      # if the type is missing then probe it now
      if type == "NONE"
        type = Pkg.RepositoryProbe(
          Ops.get_string(general_info, "url", ""),
          Ops.get_string(general_info, "product_dir", "/")
        )
        Builtins.y2milestone("Probed repository type: %1", type)
      end

      # architecture check is possible only for YaST sources
      if type == "YaST"
        # Check architecture
        read_content = ProductCreator.ReadContentFile(_SrcID)
        Builtins.y2milestone("content file: %1", read_content)

        Builtins.foreach(read_content) do |key, value|
          if key == Ops.add("ARCH.", arch)
            found_architecture = true
            raise Break
          end
          if key == "BASEARCHS"
            Builtins.y2milestone("BASEARCHS: %1", value)
            arch_list = Builtins.splitstring(value, " ")
            arch_list = Builtins.filter(arch_list) { |a| a != nil && a != "" }
            Builtins.y2milestone("Found architectures: %1", arch_list)

            if Builtins.contains(arch_list, arch)
              found_architecture = true
              raise Break
            else
              found_archs = Convert.convert(
                Builtins.union(found_archs, arch_list),
                :from => "list",
                :to   => "list <string>"
              )
            end
          else
            found_arch = Builtins.regexpsub(key, "ARCH\\.(.*)", "\\1")

            if found_arch != nil
              found_archs = Builtins.add(found_archs, found_arch)
            end
          end
        end
      else
        Builtins.y2milestone(
          "Not a YaST source, cannot verify the architecture"
        )
        found_architecture = true
      end

      Builtins.y2milestone(
        "Architecture %1 is supported: %2",
        arch,
        found_architecture
      )

      if found_architecture
        return true
      else
        Builtins.y2milestone("Supported architectures: %1", found_archs)

        if Builtins.size(found_archs) == 0
          Builtins.y2milestone(
            "The repository does not provide architecture data, assuming it is compatible"
          )
          return true
        end

        # the architecture is different, ask to switch it
        # %1 is URL of the repository
        # %2 is name of the architecture (like i386, x86_64, ppc...)
        new_arch = AskArch(
          Builtins.sformat(
            _(
              "Source %1\n" +
                "does not support the current target architecture (%2).\n" +
                "Change the target architecture?\n"
            ),
            Ops.get_string(general_info, "url", ""),
            ProductCreator.GetArch
          ),
          found_archs,
          Ops.get(found_archs, 0, "")
        )

        # nil == switch has been canceled
        if new_arch != nil
          # change the architecture
          ProductCreator.SetPackageArch(new_arch)
          return true
        end
      end

      false
    end


    # Dialog for selecting the sources
    # @return [Symbol]
    def sourceDialog
      # dialog caption
      caption = _("Source Selection")

      SourceManager.ReadSources
      sources = fillSourceTable([], true, "")
      Builtins.y2debug("sources: %1", sources)

      table = Table(
        Id(:table),
        Opt(:keepSorting, :notify),
        Header(_("Selected"), _("Status"), _("Name"), _("URL")),
        sources
      )


      buttons = VBox(
        HBox(
          ReplacePoint(
            Id(:rp),
            Label(
              Builtins.sformat(
                _("Target architecture: %1"),
                ProductCreator.GetArch
              )
            )
          ),
          HSpacing(2),
          PushButton(Id(:arch), Label.EditButton)
        ),
        VSpacing(0.3),
        HBox(
          PushButton(Id(:select), Label.SelectButton),
          PushButton(Id(:remove), Label.RemoveButton),
          # push button label
          PushButton(Id(:create), _("Cr&eate New..."))
        )
      )


      contents = VBox(table, VSpacing(0.5), buttons)

      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "sourceDialog", ""),
        Label.BackButton,
        Label.NextButton
      )


      selected_items = ProductCreator.UrlToId(
        Ops.get_list(ProductCreator.Config, "sources", [])
      )

      # remove not found sources (with id = -1)
      selected_items = Builtins.filter(selected_items) do |source_id|
        Ops.greater_or_equal(source_id, 0)
      end

      Builtins.foreach(selected_items) do |i|
        UI.ChangeWidget(Id(:table), term(:Item, i, 0), _("X"))
      end

      # report unavailbale sources if any
      ProductCreator.CheckUnavailableSources

      ret = nil


      while true
        ret = UI.UserInput
        if ret == :table
          _ID = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
          ret = Builtins.contains(selected_items, _ID) ? :remove : :select
        end
        # abort?
        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == :select
          _SrcID = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))

          repo_ok = CheckArchitecture(_SrcID)

          if repo_ok
            if !Builtins.contains(selected_items, _SrcID)
              selected_items = Builtins.add(selected_items, _SrcID)

              general_info = Pkg.SourceGeneralData(_SrcID)

              # enable the source
              if Ops.get_boolean(general_info, "enabled", false)
                Pkg.SourceSetEnabled(_SrcID, true)
              end
            end

            UI.ChangeWidget(Id(:table), term(:Item, _SrcID, 0), _("X"))

            # refresh the target architecture if it has been changed
            if ProductCreator.GetPackageArch != nil
              UI.ReplaceWidget(
                :rp,
                Label(
                  Builtins.sformat(
                    _("Target Architecture: %1"),
                    ProductCreator.GetPackageArch
                  )
                )
              )
            end
          end
        elsif ret == :remove
          _SrcID = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
          general_info = Pkg.SourceGeneralData(_SrcID)

          # disable the source
          if Ops.get_boolean(general_info, "enabled", false)
            Pkg.SourceSetEnabled(_SrcID, false)
          end

          selected_items = Builtins.filter(selected_items) { |i| _SrcID != i }
          UI.ChangeWidget(Id(:table), term(:Item, _SrcID, 0), "")
        elsif ret == :create
          if Package.Install("yast2-add-on-creator")
            createret = Convert.to_symbol(
              WFM.CallFunction("add-on-creator", [])
            )
            if createret == :next
              ex = Convert.to_map(
                WFM.CallFunction("add-on-creator_auto", ["Export"])
              )
              product_path = Ops.get_string(ex, "product_path", "")
              if product_path != ""
                url = Ops.get_boolean(ex, "iso", false) ? "file://" : "dir://"
                if Pkg.SourceCreate(Ops.add(url, product_path), "") != -1
                  SourceManager.ReadSources
                  sources2 = fillSourceTable([], true, "")
                  UI.ChangeWidget(Id(:table), :Items, sources2)
                  Builtins.foreach(sources2) do |source|
                    _SrcID = Ops.get_integer(source, [0, 0], -1)
                    if _SrcID != -1 && Builtins.contains(selected_items, _SrcID)
                      UI.ChangeWidget(
                        Id(:table),
                        term(:Item, _SrcID, 0),
                        _("X")
                      )
                    end
                  end
                  Pkg.SourceSaveAll
                end
              end
            end
          end
        elsif ret == :next
          Builtins.y2milestone("selected items: %1", selected_items)
          Ops.set(
            ProductCreator.Config,
            "sources",
            ProductCreator.getSourceURLs(selected_items)
          )
          Builtins.y2milestone(
            "sources: %1",
            Ops.get_list(ProductCreator.Config, "sources", [])
          )
          if Builtins.size(Ops.get_list(ProductCreator.Config, "sources", [])) == 0
            Report.Error(_("Select at least one source."))
            next
          end

          arch = ProductCreator.GetPackageArch

          if arch != nil
            Builtins.y2milestone(
              "Target architecture has been changed to %1",
              arch
            )
            Ops.set(ProductCreator.Config, "arch", arch)

            check_ok = true
            arch_changed = false
            begin
              ar = ProductCreator.GetPackageArch
              check_ok = true
              arch_changed = false

              # all selected sources should be refreshed
              # check archs onece again (needed after switching architecture multiple times)
              Builtins.foreach(selected_items) do |src|
                if !CheckArchitecture(src)
                  check_ok = false
                  raise Break
                end
                arch_changed = arch_changed ||
                  ar != ProductCreator.GetPackageArch
              end
            end while arch_changed

            if !check_ok
              # error message
              Report.Error(
                _(
                  "There is a mismatch between the selected\n" +
                    "repositories and the machine architecture.\n" +
                    "\n" +
                    "Either select a different repository or\n" +
                    "change the target architecture.\n"
                )
              )

              # don't leave the dialog
              next
            end

            # temporarily initialize the target, read trusted GPG keys (needed for refresh)
            Pkg.TargetInit("/", false)

            Builtins.foreach(selected_items) do |src|
              Pkg.SourceForceRefreshNow(src)
            end 


            # reload repositories
            Pkg.SourceFinishAll
            Pkg.SourceStartManager(false)

            # finish the target
            Pkg.TargetFinish
          end

          @going_back = false

          break
        elsif ret == :back
          break
        elsif ret == :arch
          # ask for the target architecture
          pkg_arch = ProductCreator.GetPackageArch

          pkg_arch = Pkg.SystemArchitecture if pkg_arch == nil

          new_arch = AskArch(
            _("Select the new target architecture."),
            # sort the list according to the current locale
            Builtins.lsort(
              [
                "i386",
                "i486",
                "i586",
                "i686",
                "sparc",
                "sparc64",
                "mips",
                "mips64",
                "ppc",
                "ppc64",
                "alpha",
                "s390",
                "s390x",
                "ia64",
                "x86_64"
              ]
            ),
            pkg_arch
          )

          # nil == switch has been canceled
          if new_arch != nil && new_arch != "" && new_arch != pkg_arch
            # change the architecture
            ProductCreator.SetPackageArch(new_arch)

            UI.ReplaceWidget(
              :rp,
              Label(
                Builtins.sformat(
                  _("Target Architecture: %1"),
                  ProductCreator.GetPackageArch
                )
              )
            )
          end
        else
          Builtins.y2error("unexpected retcode: %1", ret)
          next
        end
      end

      Convert.to_symbol(ret)
    end

    def ProductFromRepo(repo_id)
      read_content = ProductCreator.ReadContentFile(repo_id)
      prod_name = Ops.get(read_content, "LABEL", "")

      Builtins.y2milestone("Product name: %1", prod_name)
      prod_name
    end

    def ProductFromURL(url)
      src_id = Ops.get(ProductCreator.UrlToId([url]), 0, -1)
      Builtins.y2milestone("Reading product name from src %1", src_id)
      prod_name = ProductFromRepo(src_id)

      prod_name
    end

    def baseProductSelectionDialog
      if Builtins.size(Ops.get_list(ProductCreator.Config, "sources", [])) == 1
        # there is just one repository, we can skip this dialog
        Builtins.y2milestone(
          "Only one repository selected, skipping base repository selection"
        )

        # remove the option if it exists
        if Builtins.haskey(ProductCreator.Config, "base_repo")
          ProductCreator.Config = Builtins.remove(
            ProductCreator.Config,
            "base_repo"
          )
        end
        ret2 = @going_back ? :back : :next

        if ret2 == :next
          Ops.set(
            ProductCreator.Config,
            "product",
            ProductFromURL(
              Ops.get(Ops.get_list(ProductCreator.Config, "sources", []), 0, "")
            )
          )
        end

        return ret2
      end

      # dialog caption
      caption = _("Base Source Selection")

      base_url = Ops.get_string(ProductCreator.Config, "base_repo", "")
      Builtins.y2milestone("Base product: %1", base_url)

      # convert the URL to Id
      default_base = Ops.get(ProductCreator.UrlToId([base_url]), 0, -1)

      if Ops.less_than(default_base, 0)
        Builtins.y2milestone("The base repository is unknown, proposing...")
        default_base = ProductCreator.checkProductDependency
      end

      default_url = Ops.get_string(
        Pkg.SourceGeneralData(default_base),
        "url",
        ""
      )

      items = []

      Builtins.foreach(Ops.get_list(ProductCreator.Config, "sources", [])) do |srcurl|
        items = Builtins.add(items, Item(srcurl, srcurl == default_url))
      end 


      contents = SelectionBox(
        Id(:base_selection),
        _("Selected Base Source"),
        items
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "baseSelection", ""),
        Label.BackButton,
        Label.NextButton
      )

      ret = :again
      base = ""

      while !Builtins.contains([:next, :back, :abort], ret)
        ret = Convert.to_symbol(UI.UserInput)

        if ret == :next
          # get the selected source
          base = Convert.to_string(
            UI.QueryWidget(Id(:base_selection), :CurrentItem)
          )
          Builtins.y2internal("Selected base product: %1", base)

          base_src_id = Ops.get(ProductCreator.UrlToId([base]), 0, -1)
          boot_info = ProductCreator.GetBootInfoRepo(base_src_id)
          bootable = Ops.get_boolean(boot_info, "bootable", false)

          # is the base source bootable?
          if !bootable
            Builtins.y2warning("Selected base product is not bootable")

            if !Popup.ContinueCancel(
                "The selected base repository doesn't contain /boot directory.\nThe created medium will not be bootable.\n"
              )
              ret = :again
            end
          end
        end

        ret = :abort if ret == :close
      end

      if ret == :next
        Ops.set(ProductCreator.Config, "base_repo", base)
        Ops.set(ProductCreator.Config, "product", ProductFromURL(base))
      end

      ret
    end

    # Configure3 dialog
    # @return dialog result
    def isolinuxDialog
      # dialog caption
      caption = _("Product Creator Configuration")


      isolinux = ProductCreator.Readisolinux

      # FIXME: Manage files for other archs
      bootconfig = "isolinux.cfg"

      contents = VBox(
        MultiLineEdit(
          Id(:isolinux),
          Builtins.sformat(_("File Contents: %1"), bootconfig),
          isolinux
        ),
        PushButton(Id(:loadfile), _("Load File"))
      )


      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "bootconfig", ""),
        Label.BackButton,
        Label.NextButton
      )

      ret = nil
      while true
        ret = UI.UserInput
        # abort?
        if ret == :abort || ret == :cancel
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == :loadfile
          new_file = UI.AskForExistingFile("", "*", _("Select File"))
          if new_file != nil
            if Ops.greater_than(SCR.Read(path(".target.size"), new_file), 0)
              file = Convert.to_string(
                SCR.Read(path(".target.string"), new_file)
              )
              UI.ChangeWidget(Id(:isolinux), :Value, file)
            end
          end
          next
        elsif ret == :next
          isolinux_new = Convert.to_string(
            UI.QueryWidget(Id(:isolinux), :Value)
          )
          Ops.set(ProductCreator.Config, "bootconfig", isolinux_new)
          Builtins.y2milestone("Isolinux config: %1", isolinux_new)

          break
        elsif ret == :back
          break
        else
          Builtins.y2error("unexpected retcode: %1", ret)
          next
        end
      end

      if Ops.get_string(ProductCreator.Config, "profile", "") != "" &&
          ret == :next
        return :autoyast
      end
      Convert.to_symbol(ret)
    end

    def autoyastPackages
      base_selection = ""
      #Pkg::TargetFinish ();
      Popup.ShowFeedback(
        _("Reading data from Package Database..."),
        _("Please wait...")
      )

      Pkg.TargetFinish
      tmp = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      SCR.Execute(path(".target.mkdir"), Ops.add(tmp, "/tmproot"))
      Pkg.TargetInit(Ops.add(tmp, "/tmproot"), true)

      success = ProductCreator.EnableSource

      # Pkg::SourceStartManager(true);

      if Ops.get_string(ProductCreator.Config, "profile", "") != "" &&
          !ProductCreator.profile_parsed
        if !ProductCreator.readControlFile(
            Ops.get_string(ProductCreator.Config, "profile", "")
          )
          return :overview
        end
        # set the new selection
        Builtins.y2debug("Config: %1", ProductCreator.Config)

        if Ops.get_symbol(ProductCreator.Config, "type", :unknown) == :patterns
          base_pat = Ops.get_string(ProductCreator.Config, "base", "")

          if Ops.greater_than(Builtins.size(base_pat), 0)
            Pkg.ResolvableInstall(base_pat, :pattern)
            Builtins.y2milestone("Selecting pattern: %1", base_pat)
          end

          if Ops.greater_than(
              Builtins.size(Ops.get_list(ProductCreator.Config, "addons", [])),
              0
            )
            Builtins.foreach(Ops.get_list(ProductCreator.Config, "addons", [])) do |addon|
              Pkg.ResolvableInstall(addon, :pattern)
              Builtins.y2milestone("Selecting pattern: %1", addon)
            end
          end
        else
          Builtins.y2warning(
            "Unsupported software selection type: %1",
            Ops.get_symbol(ProductCreator.Config, "type", :unknown)
          )
        end

        if Ops.greater_than(
            Builtins.size(Ops.get_list(ProductCreator.Config, "packages", [])),
            0
          )
          versions = Builtins.listmap(
            Ops.get_list(ProductCreator.Config, "package_versions", [])
          ) do |p|
            {
              Ops.get_string(p, "name", "") => Ops.get_string(p, "version", "")
            }
          end

          Builtins.foreach(Ops.get_list(ProductCreator.Config, "packages", [])) do |p|
            version = Ops.get(versions, p, "")
            if version != ""
              Builtins.y2milestone(
                "selecting package for installation: %1 (%2) -> %3",
                p,
                version,
                InstallPackageOrProviderVersion(p, version)
              )
            else
              Builtins.y2milestone(
                "selecting package for installation: %1 -> %2",
                p,
                Pkg.PkgInstall(p)
              )
            end
          end
        end

        # mark taboo packages
        ProductCreator.MarkTaboo(
          Ops.get_list(ProductCreator.Config, "taboo", [])
        )

        Pkg.PkgSolve(true)

        allpacs = Pkg.GetPackages(:selected, true)
        Builtins.y2milestone(
          "All packages: %1 ( %2 )",
          allpacs,
          Builtins.size(allpacs)
        )
      end
      Popup.ClearFeedback
      :next
    end

    # Start the detailed package selection. If 'mode' is non-nil, it will be
    # passed as an option to the PackageSelector widget.
    #
    # Returns `accept or `cancel .
    #
    def detailedSelection(mode)
      # Open empty dialog for instant feedback

      UI.OpenDialog(
        Opt(:defaultsize),
        ReplacePoint(Id(:rep), Label(_("Reading package database...")))
      )

      # This will take a while: Detailed package data are retrieved
      # while the package manager is initialized
      UI.ReplaceWidget(
        :rep,
        mode == nil ?
          PackageSelector(Id(:packages)) :
          PackageSelector(Id(:packages), Opt(mode))
      )

      result = Convert.to_symbol(UI.RunPkgSelection(Id(:packages)))
      UI.CloseDialog
      Builtins.y2milestone("Package selector returned  %1", result)

      result
    end

    # Start the pattern selection dialog. If the UI does not support the
    # PatternSelector, start the detailed selection with "selections" as the
    # initial view.
    #
    def patternSelection
      if !UI.HasSpecialWidget(:PatternSelector) ||
          UI.WizardCommand(term(:Ping)) != true
        return detailedSelection(nil) # Fallback: detailed selection
      end

      # switch to packager textdomain, reuse the translations

      # Help text for software patterns / selections dialog
      helptext = _(
        "<p>\n" +
          "Select one of the following <b>base</b> selections and click <i>Detailed<i> to add\n" +
          "more <b>add-on</b> selections and packages.\n" +
          "</p>"
      )

      Wizard.SetContents(
        # dialog caption
        _("Software Selection"),
        PatternSelector(Id(:patterns)),
        helptext,
        true, # has_back
        true
      ) # has_next

      Wizard.SetDesktopIcon("sw_single")

      result = nil
      begin
        result = Convert.to_symbol(UI.RunPkgSelection(Id(:patterns)))
        Builtins.y2milestone("Pattern selector returned %1", result)

        if result == :details
          result = detailedSelection(nil)

          if result == :cancel
            # don't get all the way out - the user might just have
            # been scared of the gory details.
            result = nil
          end
        end
      end until result == :cancel || result == :accept

      result = :next if result == :accept

      result
    end

    # Display package selection dialog with preselected packages.
    # See runPackageSelector
    # @param [Hash{String => String}] versions map of specific package versions that need to be selected
    def runPackageSelectorVersions(base_pattern, patterns, packages, versions, taboo, mode)
      patterns = deep_copy(patterns)
      packages = deep_copy(packages)
      versions = deep_copy(versions)
      taboo = deep_copy(taboo)
      Builtins.y2milestone(
        "running package selector: base_pattern: %1, patterns: %2, packages: %3, versions: %4 taboo: %5, mode: %6",
        base_pattern,
        patterns,
        packages,
        versions,
        taboo,
        mode
      )

      ret = nil

      Pkg.ResolvableNeutral("", :package, true)
      Pkg.ResolvableNeutral("", :pattern, true)

      # set a mount point - there is no use to display DU of the current system
      Pkg.TargetInitDU(
        [
          {
            "name"     => "/",
            "free"     => Ops.multiply(ProductCreator.max_size_mb, 1024),
            "used"     => 0,
            "readonly" => false
          }
        ]
      )

      # dialog caption
      caption = _("Software Selection")

      helptext = _(
        "<p>\n" +
          "Select one of the following <b>base</b> selections and click <i>Detailed<i> to add\n" +
          "more <b>add-on</b> selections and packages.\n" +
          "</p>"
      )
      Pkg.TargetFinish


      Popup.ShowFeedback(
        _("Reading data from Package Database..."),
        _("Please wait...")
      )
      ProductCreator.enableSources

      Popup.ClearFeedback


      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("product-creator")

      base_selection = ""

      Wizard.SetContents(
        caption,
        HVCenter(Label(_("Reading package database..."))),
        helptext,
        false,
        true
      )

      addons = deep_copy(patterns)

      # ensure that a langugage is selected
      ProductCreator.CheckLanguage

      if Ops.greater_than(Builtins.size(addons), 0) ||
          Ops.get_string(ProductCreator.Config, "base", "") != ""
        Builtins.y2milestone(
          "base pattern: %1, addons: %2",
          base_pattern,
          addons
        )

        # select the base pattern
        Pkg.ResolvableInstall(base_pattern, :pattern) if base_pattern != ""

        # select the addons
        Builtins.foreach(addons) do |addon|
          Pkg.ResolvableInstall(addon, :pattern)
        end

        # mark taboo packages
        ProductCreator.MarkTaboo(taboo)

        Pkg.PkgSolve(true)
      end

      # add extra packages
      Builtins.foreach(packages) do |p|
        InstallPackageOrProviderVersion(p, Ops.get(versions, p, ""))
      end if Ops.greater_than(
        Builtins.size(packages),
        0
      )

      Builtins.y2milestone("package selection mode: %1", mode)

      if mode == :packages
        ret = detailedSelection(nil)
      elsif mode == :patterns
        ret = patternSelection
      else
        Builtins.y2error("Unknown mode parameter: %1", mode)
      end

      Builtins.y2milestone(
        "Selected packages: %1 ",
        Builtins.size(Pkg.GetPackages(:selected, true))
      )

      # activate the selections
      solved = ret == :cancel || Pkg.PkgSolve(true)

      if !solved
        details = Convert.to_string(
          SCR.Read(path(".target.string"), "/var/log/YaST2/badlist")
        )
        # error message, %1 = details
        Report.LongError(
          Builtins.sformat(
            _("Dependencies cannot be resolved.\n\n%1\n"),
            details
          )
        )
        Wizard.CloseDialog
        return { "ui" => :failed }
      end

      allpacs = Pkg.GetPackages(:selected, true)
      Builtins.y2milestone(
        "All packages: %1 ( %2 )",
        allpacs,
        Builtins.size(allpacs)
      )

      seladd = []
      selbase = []
      if ret != :back && ret != :cancel
        # do not return patterns selected by dependencies
        Builtins.foreach(Pkg.ResolvableProperties("", :pattern, "")) do |pat|
          Builtins.y2debug("Processing pattern: %1", pat)
          if Ops.get_symbol(pat, "status", :none) == :selected
            pat_name = Ops.get_string(pat, "name", "")
            Builtins.y2milestone(
              "pat %1 selected by %2",
              pat_name,
              Ops.get(pat, "transact_by")
            )

            if Ops.get(pat, "transact_by") != :solver
              seladd = Builtins.add(seladd, pat_name)
            end

            if Ops.get_string(pat, "category", "") == "base"
              selbase = Builtins.add(selbase, pat_name)
            end
          end
        end
      else
        seladd = deep_copy(patterns)
        selbase = [base_pattern]
      end

      ret_map = {}

      Ops.set(ret_map, "packages", Pkg.FilterPackages(false, true, true, true))
      Builtins.y2milestone(
        "User selected packages: %1",
        Ops.get_list(ret_map, "packages", [])
      )

      Ops.set(ret_map, "base", Ops.get_string(selbase, 0, ""))
      Builtins.y2milestone("selected base: %1", Ops.get_string(selbase, 0, ""))

      if Ops.greater_than(Builtins.size(selbase), 1)
        # add the other base patterns to addons
        other_base = Builtins.remove(selbase, 0)

        seladd = Builtins.merge(other_base, seladd)
      end

      Ops.set(ret_map, "addons", seladd)
      Builtins.y2milestone("selected addons: %1", seladd)

      # remember taboo packages
      Ops.set(ret_map, "taboo", Pkg.GetPackages(:taboo, true))
      Builtins.y2milestone(
        "taboo packages: %1",
        Ops.get_list(ret_map, "taboo", [])
      )

      # patterns are used in the product
      Ops.set(ret_map, "type", :patterns)

      Ops.set(ret_map, "ui", ret)

      Wizard.CloseDialog
      deep_copy(ret_map)
    end

    # Display package selection dialog with preselected packages.
    # @param [String] base_pattern base pattern to install, can be empty ("") if there is no base pattern
    # @param [Array<String>] patterns list of patterns to install
    # @param [Array<String>] packages list of packages to install
    # @param [Array<String>] taboo list of packages marked as taboo
    # @param [Symbol] mode UI mode selection, use `packages for detailed package selection or `patterns for pattern selection.
    # @return [Hash{String => Object}]
    def runPackageSelector(base_pattern, patterns, packages, taboo, mode)
      patterns = deep_copy(patterns)
      packages = deep_copy(packages)
      taboo = deep_copy(taboo)
      runPackageSelectorVersions(
        base_pattern,
        patterns,
        packages,
        {},
        taboo,
        mode
      )
    end

    # Select packages
    # @return [Symbol]
    def packageSelector
      result = {}
      begin
        base_pattern = Ops.get_string(ProductCreator.Config, "base", "")
        patterns = Ops.get_list(ProductCreator.Config, "addons", [])
        packages = Ops.get_list(ProductCreator.Config, "packages", [])
        taboo = Ops.get_list(ProductCreator.Config, "taboo", [])

        versions = Builtins.listmap(
          Ops.get_list(ProductCreator.Config, "package_versions", [])
        ) do |p|
          { Ops.get_string(p, "name", "") => Ops.get_string(p, "version", "") }
        end

        result = runPackageSelectorVersions(
          base_pattern,
          patterns,
          packages,
          versions,
          taboo,
          :patterns
        )

        Builtins.y2debug("Package selector result: %1", result)

        Ops.set(
          ProductCreator.Config,
          "base",
          Ops.get_string(result, "base", "")
        )
        Ops.set(
          ProductCreator.Config,
          "addons",
          Ops.get_list(result, "addons", [])
        )
        Ops.set(
          ProductCreator.Config,
          "packages",
          Ops.get_list(result, "packages", [])
        )
        Ops.set(
          ProductCreator.Config,
          "taboo",
          Ops.get_list(result, "taboo", [])
        )
        Ops.set(
          ProductCreator.Config,
          "type",
          Ops.get_symbol(result, "type", :patterns)
        )
      end while Ops.get_symbol(result, "ui", :next) == :cancel &&
        !ProductCreator.ReallyAbort

      # the package selector returns `cancel when pressing [Abort]
      return :abort if Ops.get_symbol(result, "ui", :next) == :cancel

      Ops.get_symbol(result, "ui", :next)
    end


    def GpgDialogContent
      MarginBox(
        2,
        1,
        VBox(
          Left("sign_checkbox"),
          VSpacing(0.5),
          "select_private_key",
          VSpacing(1),
          "create_new_key"
        )
      )
    end

    def refreshSigningDialog(sign)
      UI.ChangeWidget(Id("create_new_key"), :Enabled, sign)
      UI.ChangeWidget(Id(:gpg_priv_table), :Enabled, sign)
      UI.ChangeWidget(Id(:gpg_priv_label), :Enabled, sign)

      nil
    end

    def SignContent(key, event)
      event = deep_copy(event)
      Builtins.y2debug("SignContent: %1, %2", key, event)

      if key == "sign_checkbox"
        # refresh table and pushbutton state
        sign = Convert.to_boolean(UI.QueryWidget(Id("sign_checkbox"), :Value))
        refreshSigningDialog(sign)
      end

      nil
    end

    def signCheckboxInit(key)
      if key == "sign_checkbox"
        sign = false

        if Ops.get_string(ProductCreator.Config, "gpg_key", "") != ""
          sign = true
        end

        UI.ChangeWidget(Id("sign_checkbox"), :Value, sign)
        refreshSigningDialog(sign)
      end

      nil
    end

    def sign_checkbox_widget
      {
        "sign_checkbox" => {
          "widget"        => :checkbox,
          "opt"           => [:notify],
          "init"          => fun_ref(method(:signCheckboxInit), "void (string)"),
          "label"         => _("&Digitally Sign the Product on the Medium"),
          "handle_events" => ["sign_checkbox"],
          "handle"        => fun_ref(
            method(:SignContent),
            "symbol (string, map)"
          ),
          # TODO: validate the dialog (is a key selected if the checkbox is selected?
          # "validate_help" : _("Select a gpg key in the table. Create...")
          "help"          => _(
            "<p><big><b>Sign</b></big><br>\n" +
              "To make it possible for users to verify your product, sign it with a GPG key. \n" +
              "This key is checked when the product is added as a repository.</p>"
          ) +
            # part of the help text (signing dialog), the URL can be modified to the translated language
            # (if the page exists in that language, you have to check that!)
            _(
              "<P>If the product is not signed, Yast automatically adds the option 'Insecure:\n1' to the linuxrc configuration file, otherwise linuxrc would deny loading an unsigned installation system at boot. See http://en.opensuse.org/Linuxrc for more information.</P>"
            )
        }
      }
    end


    def gpgKeyDialog
      caption = _("Signing the Product on the Medium")

      if Ops.get_string(ProductCreator.Config, "gpg_key", "") != ""
        # preselect the key
        GPGWidgets.SetSelectedPrivateKey(
          Ops.get_string(ProductCreator.Config, "gpg_key", "")
        )
      end

      ret = nil
      begin
        ret = CWM.ShowAndRun(
          {
            "widget_names"       => [
              "sign_checkbox",
              "select_private_key",
              "create_new_key"
            ],
            "widget_descr"       => Builtins.union(
              GPGWidgets.Widgets,
              sign_checkbox_widget
            ),
            "contents"           => GpgDialogContent(),
            "caption"            => caption,
            "back_button"        => Label.BackButton,
            "next_button"        => Label.NextButton,
            "fallback_functions" => {}
          }
        )
      end while ret == :abort && !ProductCreator.ReallyAbort

      sign = Convert.to_boolean(UI.QueryWidget(Id("sign_checkbox"), :Value))
      Builtins.y2milestone("Sign the medium: %1", sign)

      gpg_key = sign ? GPGWidgets.SelectedPrivateKey : ""
      Builtins.y2milestone("GPG signing key: %1", gpg_key)

      # remember the key
      Ops.set(ProductCreator.Config, "gpg_key", gpg_key)

      ret
    end

    # Configuration Summary
    # @return [void]
    def ConfigSummary
      Yast.import "Summary"

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("product-creator")
      caption = _("Configuration Summary")
      Wizard.SetContents(caption, Empty(), "", false, false)

      ProductCreator.CommitConfig


      summary = ""
      # summary caption
      summary = Summary.AddHeader(summary, _("Package Source"))
      summary = Summary.OpenList(summary)
      Builtins.foreach(Ops.get_list(ProductCreator.Config, "sources", [])) do |s|
        summary = Summary.AddListItem(summary, s)
      end
      summary = Summary.CloseList(summary)
      # summary caption
      summary = Summary.AddHeader(summary, _("Packages"))

      # summary line
      summary = Summary.AddLine(
        summary,
        Builtins.sformat(
          _("Selected %1 packages"),
          Builtins.size(Pkg.GetPackages(:selected, true))
        )
      )

      arch = Ops.get_string(ProductCreator.Config, "arch", "")
      # display the architecture in the summary if it has been changed
      if arch != nil && arch != "" && arch != Arch.architecture
        summary = Summary.AddHeader(summary, _("Architecture"))

        # summary line, %1 is e.g. i386, x86_64, ppc...
        summary = Summary.AddLine(
          summary,
          Builtins.sformat(_("Target architecture: %1"), arch)
        )
      end

      # summary caption
      summary = Summary.AddHeader(summary, _("Output Directory"))

      if Ops.get_string(ProductCreator.Config, "result", "tree") == "iso"
        summary = Summary.AddLine(
          summary,
          # summary line (%1/%2 is file path)
          Builtins.sformat(
            _("Creating ISO image %1/%2"),
            Ops.get_string(ProductCreator.Config, "iso-directory", ""),
            Ops.get_string(ProductCreator.Config, "isofile", "")
          )
        )
      else
        summary = Summary.AddLine(
          summary,
          # summary line (%1/%2 is file path)
          Builtins.sformat(
            _("Creating directory tree in <b> %1/%2 </b>"),
            Ops.get_string(ProductCreator.Config, "iso-directory", ""),
            Ops.get_string(ProductCreator.Config, "name", "")
          )
        )
      end


      # header in the summary dialog
      summary = Summary.AddHeader(summary, _("Signing"))
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
        summary = Summary.AddLine(
          summary,
          Builtins.sformat(
            _("Digitally sign the medium with GPG key <b>%1</b>%2"),
            gpgkey,
            String.EscapeTags(uid)
          )
        )
      else
        # summary text
        summary = Summary.AddLine(
          summary,
          _("The medium will not be digitally signed")
        )
      end

      contents = RichText(summary)

      help_text = _(
        "<p>Verify the data in the summary then press Next to continue.\n</p>\n"
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        help_text,
        Label.BackButton,
        Label.FinishButton
      )
      ret = nil
      begin
        ret = UI.UserInput

        if ret == :abort && !ProductCreator.ReallyAbort
          # abort canceled
          ret = :dummy
        end
      end until ret == :next || ret == :back || ret == :abort
      Wizard.CloseDialog

      Convert.to_symbol(ret)
    end
  end
end
