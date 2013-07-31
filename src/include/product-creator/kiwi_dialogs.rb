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

# File:	include/product-creator/kiwi.ycp
# Package:	Configuration of product-creator
# Summary:	Dialogs for kiwi configuration
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
module Yast
  module ProductCreatorKiwiDialogsInclude
    def initialize_product_creator_kiwi_dialogs(include_target)
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "product-creator"

      Yast.import "Arch"
      Yast.import "CWM"
      Yast.import "CWMTab"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Keyboard"
      Yast.import "Kiwi"
      Yast.import "Label"
      Yast.import "Message"
      Yast.import "Package"
      Yast.import "PackageLock"
      Yast.import "PackageSystem"
      Yast.import "Popup"
      Yast.import "ProductCreator"
      Yast.import "SourceDialogs"
      Yast.import "SourceManager"
      Yast.import "String"
      Yast.import "Summary"
      Yast.import "URL"
      Yast.import "Wizard"

      Yast.include include_target, "product-creator/dialogs.rb"
      Yast.include include_target, "product-creator/routines.rb"

      # map of current image configuration
      @KiwiConfig = {}

      # what are we configuring now ("iso"/"xen"/...)
      @kiwi_task = ""

      @content_key = Kiwi.content_key

      @section_type_label = {
        "image"     => _("Packages for Image"),
        "bootstrap" => _("Bootstrap"),
        "xen"       => _("Xen Specific Packages")
      }

      # map indexes of packages sets to their names
      # (package set is indexed in the sets list)
      @index2package_set = {}

      @package_set2index = {}
    end

    # read available the images under /usr/share/kiwi/image/ directory
    def GetAvailableImages(subdir)
      ret = []
      dir = "/usr/share/kiwi/image/"
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("ls %1/%2", dir, subdir)
        )
      )
      return deep_copy(ret) if Ops.get_integer(out, "exit", 0) != 0
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
      ) do |file|
        if file != "" &&
            FileUtils.IsDirectory(
              Builtins.sformat("%1/%2/%3", dir, subdir, file)
            )
          ret = Builtins.add(
            ret,
            Item(
              Id(file),
              file,
              file == Ops.get_string(@KiwiConfig, subdir, "")
            )
          )
        end
      end
      deep_copy(ret)
    end

    #****************************************************************************
    # widget handlers
    #**************************************************************************

    def InitCompressionCombo(id)
      current_method = "none"
      Builtins.foreach(
        Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
      ) do |typemap|
        if Ops.get_string(typemap, "image", "") == @kiwi_task
          current_method = Ops.get_string(typemap, "flags", current_method)
        end
      end
      methods = {
        "unified"    => "unified",
        "compressed" => "compressed",
        "clic"       => "clic",
        # combo box label
        "none"       => _("None")
      }
      items = Builtins.maplist(methods) do |method, label|
        Item(Id(method), label, method == current_method)
      end
      UI.ChangeWidget(Id(id), :Items, items)

      nil
    end

    def StoreCompressionCombo(key, event)
      event = deep_copy(event)
      selected = Convert.to_string(UI.QueryWidget(Id(key), :Value))
      Ops.set(
        @KiwiConfig,
        ["preferences", 0, "type"],
        Builtins.maplist(
          Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
        ) do |typemap|
          if Ops.get_string(typemap, "image", "") == @kiwi_task
            if selected == "none"
              if Builtins.haskey(typemap, "flags")
                typemap = Builtins.remove(typemap, "flags")
              end
            else
              Ops.set(typemap, "flags", selected)
            end
          end
          deep_copy(typemap)
        end
      )

      nil
    end

    def HandleCompressionCombo(key, event)
      event = deep_copy(event)
      StoreCompressionCombo(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    def InitDiskPassword(id)
      disk_password = ""
      Builtins.foreach(
        Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
      ) do |typemap|
        if Ops.get_string(typemap, "image", "") == @kiwi_task
          disk_password = Ops.get_string(typemap, "luks", disk_password)
        end
      end
      UI.ChangeWidget(Id(id), :Value, disk_password)
      UI.ChangeWidget(Id(id), :Enabled, disk_password != "")
      UI.ChangeWidget(Id("encrypt_disk"), :Value, disk_password != "")

      nil
    end

    def StoreDiskPassword(key, event)
      event = deep_copy(event)
      disk_password = Convert.to_string(UI.QueryWidget(Id(key), :Value))
      disk_password = "" if UI.QueryWidget(Id("encrypt_disk"), :Value) == false

      Ops.set(
        @KiwiConfig,
        ["preferences", 0, "type"],
        Builtins.maplist(
          Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
        ) do |typemap|
          if Ops.get_string(typemap, "image", "") == @kiwi_task
            if disk_password == ""
              if Builtins.haskey(typemap, "luks")
                typemap = Builtins.remove(typemap, "luks")
              end
            else
              Ops.set(typemap, "luks", disk_password)
            end
          end
          deep_copy(typemap)
        end
      )

      nil
    end

    def HandleDiskPassword(key, event)
      event = deep_copy(event)
      StoreDiskPassword(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    def HandleEncryptDisk(key, event)
      event = deep_copy(event)
      value = Convert.to_boolean(UI.QueryWidget(Id(key), :Value))
      UI.ChangeWidget(Id("disk_password"), :Enabled, value)
      nil
    end

    # Initialize the widget with ignored packages
    def InitSWIgnore(id)
      sw_selection = Ops.get_string(@KiwiConfig, "sw_selection", "image")
      ignore_key = sw_selection == "image" ?
        "ignore" :
        Ops.add(sw_selection, "_ignore")
      UI.ChangeWidget(
        Id(id),
        :Value,
        Builtins.mergestring(Ops.get_list(@KiwiConfig, ignore_key, []), "\n")
      )

      nil
    end

    def StoreSWIgnore(key, event)
      event = deep_copy(event)
      sw_selection = Ops.get_string(@KiwiConfig, "sw_selection", "image")
      ignore_key = sw_selection == "image" ?
        "ignore" :
        Ops.add(sw_selection, "_ignore")
      Ops.set(
        @KiwiConfig,
        ignore_key,
        Builtins.filter(
          Builtins.splitstring(
            Convert.to_string(UI.QueryWidget(Id(key), :Value)),
            "\n"
          )
        ) { |p| p != "" }
      )

      nil
    end

    def HandleSWIgnore(key, event)
      event = deep_copy(event)
      StoreSWIgnore(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # Initialize the widget with packages intended for deletion
    def InitSWDelete(id)
      to_delete = []
      Builtins.foreach(Ops.get_list(@KiwiConfig, "packages", [])) do |pmap|
        type = Ops.get_string(pmap, "type", "")
        if type == "delete"
          to_delete = Builtins.maplist(Ops.get_list(pmap, "package", [])) do |pacmap|
            Ops.get_string(pacmap, "name", "")
          end
        end
      end
      UI.ChangeWidget(Id(id), :Value, Builtins.mergestring(to_delete, "\n"))

      nil
    end

    def StoreSWDelete(key, event)
      event = deep_copy(event)
      to_delete = Builtins.filter(
        Builtins.splitstring(
          Convert.to_string(UI.QueryWidget(Id(key), :Value)),
          "\n"
        )
      ) { |p| p != "" }
      index = 0
      del_index = -1
      Builtins.foreach(Ops.get_list(@KiwiConfig, "packages", [])) do |pmap|
        if Ops.get_string(pmap, "type", "") == "delete"
          del_index = index
          raise Break
        end
        index = Ops.add(index, 1)
      end

      sw_contents = Ops.get_map(@KiwiConfig, ["packages", del_index], {})
      if del_index == -1
        sw_contents = { "type" => "delete" }
        del_index = Builtins.size(Ops.get_list(@KiwiConfig, "packages", []))
        Ops.set(
          @KiwiConfig,
          "packages",
          Builtins.add(Ops.get_list(@KiwiConfig, "packages", []), {})
        )
      end
      Ops.set(sw_contents, "package", Builtins.maplist(to_delete) do |name|
        { "name" => name }
      end)
      Ops.set(@KiwiConfig, ["packages", del_index], sw_contents)

      nil
    end

    def HandleSWDelete(key, event)
      event = deep_copy(event)
      StoreSWDelete(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # Initialize the contents of richtext with selected software
    def InitSWRichText(id)
      package_set = Ops.get_integer(@KiwiConfig, "package_set", 0)
      rt = ""

      packages = Ops.get_list(@KiwiConfig, "packages", [])
      pat = ""
      pac = ""
      ign = ""

      if Ops.get(@index2package_set, package_set, "") == "bootinclude"
        package_set = Ops.get(@package_set2index, "image", 0)

        if Ops.greater_than(
            Builtins.size(Ops.get_list(packages, [package_set, "package"], [])),
            0
          )
          # richtext header
          pac = Summary.AddHeader("", _("Packages"))
        end
        Builtins.foreach(Ops.get_list(packages, [package_set, "package"], [])) do |pacmap|
          if Ops.get_string(pacmap, "bootinclude", "") == "true"
            pac = Summary.AddListItem(pac, Ops.get_string(pacmap, "name", ""))
          end
        end
        UI.ChangeWidget(Id(id), :Value, Ops.add(Ops.add(pat, pac), ign))
        return
      end

      if Ops.greater_than(
          Builtins.size(
            Ops.get_list(packages, [package_set, "opensusePattern"], [])
          ),
          0
        )
        # richtext header
        pat = Summary.AddHeader("", _("Patterns"))
      end
      Builtins.foreach(
        Ops.get_list(packages, [package_set, "opensusePattern"], [])
      ) do |patmap|
        pat = Summary.AddListItem(pat, Ops.get_string(patmap, "name", ""))
      end
      if Ops.greater_than(
          Builtins.size(Ops.get_list(packages, [package_set, "package"], [])),
          0
        )
        # richtext header
        pac = Summary.AddHeader("", _("Packages"))
      end
      Builtins.foreach(Ops.get_list(packages, [package_set, "package"], [])) do |pacmap|
        if Ops.get_string(pacmap, "bootinclude", "") != "true"
          pac = Summary.AddListItem(pac, Ops.get_string(pacmap, "name", ""))
        end
      end
      if Ops.greater_than(
          Builtins.size(Ops.get_list(packages, [package_set, "ignore"], [])),
          0
        )
        ign = Summary.AddHeader(
          "",
          Builtins.deletechars(_("&Ignored Software"), "&")
        )
      end
      Builtins.foreach(Ops.get_list(packages, [package_set, "ignore"], [])) do |pacmap|
        ign = Summary.AddListItem(ign, Ops.get_string(pacmap, "name", ""))
      end
      UI.ChangeWidget(Id(id), :Value, Ops.add(Ops.add(pat, pac), ign))

      nil
    end


    # open package selector with given set of packages, return modified set
    # or nil on cancel
    def modifyPackageSelection(sw_contents)
      sw_contents = deep_copy(sw_contents)
      mbytes = Convert.to_integer(UI.QueryWidget(Id("size"), :Value))
      if UI.QueryWidget(Id("sizeunit"), :Value) == "G"
        mbytes = Ops.multiply(mbytes, 1024)
      end
      ProductCreator.max_size_mb = mbytes
      # no size check for "additive" (bnc#512358)
      if UI.QueryWidget(Id("additive"), :Value) == true
        ProductCreator.max_size_mb = 999 * 1024 * 1024
      end

      ret_map = runPackageSelector(
        "",
        Builtins.maplist(Ops.get_list(sw_contents, "opensusePattern", [])) do |pat|
          Ops.get_string(pat, "name", "")
        end,
        Builtins.maplist(Ops.get_list(sw_contents, "package", [])) do |pat|
          Ops.get_string(pat, "name", "")
        end,
        Builtins.maplist(Ops.get_list(sw_contents, "ignore", [])) do |pat|
          Ops.get_string(pat, "name", "")
        end,
        :packages
      )
      if Ops.get(ret_map, "ui") == :cancel || Ops.get(ret_map, "ui") == :failed
        return nil
      end
      Ops.set(
        sw_contents,
        "opensusePattern",
        Builtins.maplist(Ops.get_list(ret_map, "addons", [])) do |name|
          { "name" => name }
        end
      )
      Ops.set(
        sw_contents,
        "package",
        Builtins.maplist(Ops.get_list(ret_map, "packages", [])) do |name|
          { "name" => name }
        end
      )
      Ops.set(
        sw_contents,
        "ignore",
        Builtins.maplist(Ops.get_list(ret_map, "taboo", [])) do |name|
          { "name" => name }
        end
      )

      deep_copy(sw_contents)
    end

    # Popup for modifying the list of 'bootinclude' packages
    def modifyBootIncludePackages(packages)
      packages = deep_copy(packages)
      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(0.5),
          VSpacing(20),
          VBox(
            HSpacing(70),
            VSpacing(0.5),
            MultiLineEdit(
              Id(:bootinclude),
              _("Packages to be included in Boot Image"),
              Builtins.mergestring(
                Builtins.maplist(
                  Convert.convert(
                    packages,
                    :from => "list",
                    :to   => "list <map>"
                  )
                ) { |p| Ops.get_string(p, "name", "") },
                "\n"
              )
            ),
            ButtonBox(
              PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
              PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
            )
          ),
          HSpacing(0.5)
        )
      )
      ret = UI.UserInput
      value = Convert.to_string(UI.QueryWidget(Id(:bootinclude), :Value))
      retlist = Builtins.maplist(
        Builtins.filter(Builtins.splitstring(value, "\n")) { |p| p != "" }
      ) { |name| { "name" => name, "bootinclude" => "true" } }

      UI.CloseDialog
      return nil if ret == :cancel
      deep_copy(retlist)
    end

    # check the conflicts between packages selected and marked for deletion (fate#305254)
    # @param [Hash] packages_before map of packages already selected before entering package selector
    def CheckForDeletedPackages(packages_before)
      packages_before = deep_copy(packages_before)
      Builtins.y2milestone("checking list of selected packages...")
      StoreSWDelete("delete_sw", {})
      to_delete = {}
      Builtins.foreach(Ops.get_list(@KiwiConfig, "packages", [])) do |pmap|
        type = Ops.get_string(pmap, "type", "")
        if type == "delete"
          to_delete = Builtins.listmap(Ops.get_list(pmap, "package", [])) do |pacmap|
            { Ops.get_string(pacmap, "name", "") => true }
          end
        end
      end
      conflicting = false
      if Ops.greater_than(Builtins.size(to_delete), 0)
        Builtins.foreach(Pkg.ResolvableProperties("", :package, "")) do |package|
          raise Break if conflicting
          name = Ops.get_string(package, "name", "")
          # only look at packages selected in last package selector run
          if Ops.get(package, "status") == :selected &&
              !Builtins.haskey(packages_before, name)
            transact_by = Ops.get_symbol(package, "transact_by", :none)
            if transact_by == :solver || transact_by == :user ||
                transact_by == :app_high
              if Builtins.haskey(to_delete, name)
                Builtins.y2milestone(
                  "packege %1 selected by %2 is present in the delete list",
                  name,
                  transact_by
                )
                conflicting = true
              end
            end
          end
        end
      end
      conflicting
    end

    # Handler for software selection
    def HandleSWSelection(key, event)
      event = deep_copy(event)
      if Ops.get(event, "ID") == key
        package_set = Ops.get_integer(@KiwiConfig, "package_set", 0)
        bootinclude = false
        if Ops.get(@index2package_set, package_set, "") == "bootinclude"
          package_set = Ops.get(@package_set2index, "image", 0)
          bootinclude = true
        end

        sw_contents = Ops.get_map(@KiwiConfig, ["packages", package_set], {})
        packages_before = {}

        # separate bootinclude packages from normal ones
        bi_packages = []
        Ops.set(
          sw_contents,
          "package",
          Builtins.filter(Ops.get_list(sw_contents, "package", [])) do |p|
            Ops.set(packages_before, Ops.get_string(p, "name", ""), true)
            if Ops.get_string(p, "bootinclude", "") == "true"
              bi_packages = Builtins.add(bi_packages, p)
            end
            Ops.get_string(p, "bootinclude", "") != "true"
          end
        )

        if bootinclude
          bi_packages = modifyBootIncludePackages(bi_packages)
        else
          again = true
          while again
            sw_contents = modifyPackageSelection(sw_contents)
            again = CheckForDeletedPackages(packages_before)
            if again &&
                Popup.YesNo(
                  _(
                    "Some of the packages that are selected for installation\n" +
                      "are also included in the list for deletion.\n" +
                      "Continue anyway?"
                  )
                )
              again = false
            end
          end
        end

        if sw_contents != nil && bi_packages != nil
          Ops.set(
            sw_contents,
            "package",
            Builtins.union(
              Ops.get_list(sw_contents, "package", []),
              bi_packages
            )
          )
          Ops.set(@KiwiConfig, ["packages", package_set], sw_contents)
        end
        InitSWRichText("rt_sw")
      end
      nil
    end

    # initialize the combo box with package selection groups
    def InitSWSelectionCombo(id)
      package_set = Ops.get_integer(@KiwiConfig, "package_set", 0)
      items = []
      i = 0
      Builtins.foreach(Ops.get_list(@KiwiConfig, "packages", [])) do |pmap|
        type = Ops.get_string(pmap, "type", "")
        # combo box label
        label = _("Packages for Image")
        if type == "delete"
          # combo box label
          label = _("Packages to Delete")
          i = Ops.add(i, 1) # index to list must be increased
          next # delete is handled by different widgets
        end
        Ops.set(@index2package_set, i, type)
        Ops.set(@package_set2index, type, i)
        if type == "bootstrap"
          # combo box label
          label = _("Bootstrap")
        elsif type == "xen"
          # combo box label
          label = _("Xen Specific Packages")
        elsif type == "testsuite"
          # combo box label
          label = _("Testing")
        elsif type != "image"
          label = type
        end
        if Ops.get_string(pmap, "profiles", "") != ""
          # combo box label, %1 is profile name
          label = Builtins.sformat(
            _("Image, Profile %1"),
            Ops.get_string(pmap, "profiles", "")
          )
        end
        items = Builtins.add(items, Item(Id(i), label, package_set == i))
        i = Ops.add(i, 1)
      end
      # combo box label
      items = Builtins.add(
        items,
        Item(Id(i), _("Include in Boot Image"), package_set == i)
      )
      Ops.set(@index2package_set, i, "bootinclude")
      UI.ChangeWidget(Id(id), :Items, items)

      nil
    end

    def StoreSWSelectionCombo(key, event)
      event = deep_copy(event)
      Ops.set(
        @KiwiConfig,
        "package_set",
        Convert.to_integer(UI.QueryWidget(Id(key), :Value))
      )

      nil
    end

    # handler for combo box with package sets items
    def HandleSWSelectionCombo(key, event)
      event = deep_copy(event)
      id = Ops.get(event, "ID")
      # store the value on exiting
      if id == :next
        StoreSWSelectionCombo(key, event)
      elsif Ops.get(event, "ID") == key
        selected = Convert.to_integer(UI.QueryWidget(Id(key), :Value))
        if selected != Ops.get_integer(@KiwiConfig, "package_set", -1)
          Ops.set(@KiwiConfig, "package_set", selected)
          StoreSWSelectionCombo(key, event)
          InitSWRichText("rt_sw")
        end
      end
      nil
    end


    # initialize the value of combo box with boot items
    def InitBootCombo(id)
      UI.ChangeWidget(Id(id), :Items, GetAvailableImages(id))

      nil
    end

    # store the value of current boot image
    def StoreBootCombo(key, event)
      event = deep_copy(event)
      Ops.set(
        @KiwiConfig,
        key,
        Convert.to_string(UI.QueryWidget(Id(key), :Value))
      )

      nil
    end
    # handler for combo box with boot items
    def HandleBootCombo(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StoreBootCombo(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the value of version
    def InitVersion(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        get_preferences(@KiwiConfig, "version", "1.0.0")
      )

      nil
    end

    # store the value of current version
    def StoreVersion(key, event)
      event = deep_copy(event)
      Ops.set(
        @KiwiConfig,
        ["preferences", 0, "version"],
        [
          {
            @content_key => Builtins.sformat(
              "%1",
              UI.QueryWidget(Id(key), :Value)
            )
          }
        ]
      )

      nil
    end

    # handler for version
    def HandleVersion(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StoreVersion(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the values of "size", "sizeunit" and "additive" widgets
    def InitSize(id)
      size_map = get_current_size_map(@KiwiConfig, @kiwi_task)
      siz = 0
      if Builtins.haskey(size_map, Kiwi.content_key)
        siz = Builtins.tointeger(
          Ops.get_string(size_map, Kiwi.content_key, "0")
        )
      else
        siz = Builtins.tointeger(Kiwi.default_size)
        if Ops.get_string(size_map, "additive", "") == ""
          Ops.set(size_map, "additive", "true")
        end
      end
      UI.ChangeWidget(Id("size"), :Value, siz)
      UI.ChangeWidget(
        Id("additive"),
        :Value,
        Ops.get_string(size_map, "additive", "") == "true"
      )
      UI.ChangeWidget(Id("sizeunit"), :Items, Builtins.maplist(["M", "G"]) do |u|
        Item(Id(u), Ops.add(u, "B"), Ops.get_string(size_map, "unit", "M") == u)
      end)

      nil
    end

    # store the values of "size", "sizeunit" and "additive" widgets
    def StoreSize(key, event)
      event = deep_copy(event)
      Ops.set(
        @KiwiConfig,
        ["preferences", 0, "type"],
        Builtins.maplist(
          Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
        ) do |typemap|
          if Ops.get_string(typemap, "image", "") == @kiwi_task
            Ops.set(
              typemap,
              "size",
              [
                {
                  @content_key => Builtins.sformat(
                    "%1",
                    UI.QueryWidget(Id(key), :Value)
                  ),
                  "unit"       => UI.QueryWidget(Id("sizeunit"), :Value),
                  "additive"   => Convert.to_boolean(
                    UI.QueryWidget(Id("additive"), :Value)
                  ) ? "true" : "false"
                }
              ]
            )
          end
          deep_copy(typemap)
        end
      )

      nil
    end

    # handler for size widget: store value on exit/save
    def HandleSize(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StoreSize(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the product label
    def InitLabel(id)
      UI.ChangeWidget(
        Id("name"),
        :Value,
        Ops.get_string(@KiwiConfig, "name", "")
      )

      nil
    end


    # universal widget: initialize the string value of widget @param
    def InitGeneric(id)
      UI.ChangeWidget(Id(id), :Value, Ops.get_string(@KiwiConfig, id, ""))
      if (id == "config.sh" || id == "images.sh") &&
          Builtins.haskey(@KiwiConfig, "root/build-custom")
        UI.ChangeWidget(Id(id), :Enabled, false)
      end

      nil
    end

    # store the string value of given widget
    def StoreGeneric(key, event)
      event = deep_copy(event)
      Ops.set(@KiwiConfig, key, UI.QueryWidget(Id(key), :Value))

      nil
    end

    # handler for general string-value widgets: store their value on exit/save
    def HandleGeneric(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StoreGeneric(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the string value of "description" related widget
    def InitDescription(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        Ops.get_string(@KiwiConfig, ["description", 0, id, 0, @content_key], "")
      )

      nil
    end

    # store the string value of "description" related given widget
    def StoreDescription(key, event)
      event = deep_copy(event)
      Ops.set(
        @KiwiConfig,
        ["description", 0, key],
        [{ @content_key => UI.QueryWidget(Id(key), :Value) }]
      )

      nil
    end

    # handler for string-value "description" related widgets: store on exit/save
    def HandleDescription(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StoreDescription(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the list value of "locale" combo box
    def InitLocaleCombo(id)
      lang = Ops.get_string(
        @KiwiConfig,
        ["preferences", 0, id, 0, @content_key],
        ""
      )
      items = [Item(Id("none"), "---", false)]
      if Kiwi.all_locales == {}
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "/usr/bin/locale -a")
        )
        Builtins.foreach(
          Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
        ) do |line|
          code = Ops.get(Builtins.splitstring(line, ".@"), 0, line)
          if code != "" && code != "C" && code != "POSIX"
            Ops.set(Kiwi.all_locales, code, 1)
          end
        end
      end
      Builtins.foreach(Kiwi.all_locales) do |code, i|
        items = Builtins.add(items, Item(Id(code), code, lang == code))
      end

      UI.ChangeWidget(Id(id), :Items, items)

      nil
    end

    # initialize the list value of "keytable" combo box
    def InitKeytableCombo(id)
      kb = Ops.get_string(
        @KiwiConfig,
        ["preferences", 0, id, 0, @content_key],
        ""
      )

      items = []
      kb_present = false

      Builtins.foreach(Keyboard.keymap2yast) do |name, yast|
        items = Builtins.add(items, Item(Id(name), name, kb == name))
        kb_present = true if kb == name
      end
      items = Builtins.add(items, Item(Id(kb), kb, true)) if !kb_present
      UI.ChangeWidget(Id(id), :Items, items)

      nil
    end

    # initialize the list value of "timezone" combo box
    def InitTimezoneCombo(id)
      tz = Ops.get_string(
        @KiwiConfig,
        ["preferences", 0, id, 0, @content_key],
        ""
      )

      if Kiwi.all_timezones == []
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            "grep -v '#' /usr/share/zoneinfo/zone.tab | cut -f 3 | sort",
            { "LANG" => "C" }
          )
        )
        Kiwi.all_timezones = Builtins.filter(
          Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
        ) { |t| t != "" }
      end

      items = Builtins.maplist(Kiwi.all_timezones) do |zone|
        Item(Id(zone), zone, tz == zone)
      end
      items = Builtins.prepend(items, Item(Id("none"), "---"))

      UI.ChangeWidget(Id(id), :Items, items)

      nil
    end

    # initialize the string value of "preferences" related widget
    def InitPreferences(id)
      UI.ChangeWidget(
        Id(id),
        :Value,
        Ops.get_string(@KiwiConfig, ["preferences", 0, id, 0, @content_key], "")
      )

      nil
    end

    # store the string value of "preferences" related given widget
    def StorePreferences(key, event)
      event = deep_copy(event)
      val = Convert.to_string(UI.QueryWidget(Id(key), :Value))

      # split .UTF-8 endings from locale (bnc#675101)
      if key == "locale"
        split = Builtins.splitstring(val, ".")
        val = Ops.get(split, 0, val)
        UI.ChangeWidget(Id(key), :Value, val)
      end
      if (val == "" || val == "none") &&
          Builtins.haskey(Ops.get_map(@KiwiConfig, ["preferences", 0], {}), key)
        Ops.set(
          @KiwiConfig,
          ["preferences", 0],
          Builtins.remove(Ops.get_map(@KiwiConfig, ["preferences", 0], {}), key)
        )
      elsif val != "" && val != "none"
        Ops.set(
          @KiwiConfig,
          ["preferences", 0, key],
          [{ @content_key => UI.QueryWidget(Id(key), :Value) }]
        )
      end

      nil
    end

    # handler for string-value "preferences" related widgets: store on exit/save
    def HandlePreferences(key, event)
      event = deep_copy(event)
      # store the value on exiting
      StorePreferences(key, event) if Ops.get(event, "ID") == :next
      nil
    end

    # initialize the table with users
    def InitUsersTable(id)
      items = []
      Builtins.foreach(Ops.get_list(@KiwiConfig, "users", [])) do |groupmap|
        group = Ops.get_string(groupmap, "group", "")
        gid = Ops.get_string(groupmap, "id", "")
        Builtins.foreach(Ops.get_list(groupmap, "user", [])) do |usermap|
          items = Builtins.add(
            items,
            Item(
              Id(Ops.get_string(usermap, "name", "")),
              Ops.get_string(usermap, "name", ""),
              Ops.get_string(usermap, "realname", ""),
              Ops.get_string(usermap, "id", ""),
              Ops.get_string(usermap, "home", ""),
              group,
              gid
            )
          )
        end
      end
      UI.ChangeWidget(Id("table"), :Items, items)
      UI.ChangeWidget(
        Id("edituser"),
        :Enabled,
        Ops.greater_than(Builtins.size(items), 0)
      )
      UI.ChangeWidget(
        Id("deleteuser"),
        :Enabled,
        Ops.greater_than(Builtins.size(items), 0)
      )

      nil
    end

    # Handle changes in users table
    def HandleAddEditUser(key, event)
      event = deep_copy(event)
      if Ops.get(event, "ID") != key &&
          (key != "userstable" || Ops.get(event, "ID") != "table")
        return nil
      end

      key = "edituser" if key == "userstable"
      current_user = Convert.to_string(
        UI.QueryWidget(Id("table"), :CurrentItem)
      )
      user_map = {}
      group_map = {}
      if key == "edituser"
        Builtins.foreach(Ops.get_list(@KiwiConfig, "users", [])) do |gmap|
          user_map = Builtins.find(Ops.get_list(gmap, "user", [])) do |umap|
            current_user == Ops.get_string(umap, "name", "")
          end
          if user_map != {} && user_map != nil
            group_map = deep_copy(gmap)
            raise Break
          end
        end
      end
      # store original names
      user = Ops.get_string(user_map, "name", "")
      group = Ops.get_string(group_map, "group", "")
      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(0.5),
          VBox(
            VSpacing(0.5),
            # popup label
            Label(Id(:label), _("Add New User")),
            # text entry label
            InputField(Id(:username), Opt(:hstretch), _("Login &Name")),
            # text entry label
            InputField(Id("realname"), Opt(:hstretch), _("&Full Name")),
            Password(Id(:pw1), Opt(:hstretch), Label.Password, ""),
            Password(Id(:pw2), Opt(:hstretch), Label.ConfirmPassword, ""),
            # text entry label
            InputField(Id("home"), Opt(:hstretch), _("&Home Directory")),
            # text entry label
            InputField(Id("id"), Opt(:hstretch), _("&UID")),
            HBox(
              # text entry label
              InputField(Id(:group), Opt(:hstretch), _("G&roup Name")),
              # text entry label
              InputField(Id(:gid), Opt(:hstretch), _("&GID"))
            ),
            HBox(
              PushButton(Id(:ok), Opt(:key_F10), Label.OKButton),
              PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
            ),
            VSpacing(0.5)
          ),
          HSpacing(0.5)
        )
      )
      UI.ChangeWidget(Id("id"), :ValidChars, String.CDigit)
      UI.ChangeWidget(Id(:gid), :ValidChars, String.CDigit)
      if key == "edituser"
        UI.ChangeWidget(Id(:username), :Value, current_user)
        UI.ChangeWidget(
          Id("realname"),
          :Value,
          Ops.get_string(user_map, "realname", "")
        )
        UI.ChangeWidget(
          Id("home"),
          :Value,
          Ops.get_string(user_map, "home", "")
        )
        UI.ChangeWidget(Id("id"), :Value, Ops.get_string(user_map, "id", ""))
        UI.ChangeWidget(Id(:gid), :Value, Ops.get_string(group_map, "id", ""))
        UI.ChangeWidget(
          Id(:group),
          :Value,
          Ops.get_string(group_map, "group", "")
        )
        if Ops.get_string(user_map, "pwd", "") != ""
          UI.ChangeWidget(Id(:pw1), :Value, Ops.get_string(user_map, "pwd", ""))
          UI.ChangeWidget(Id(:pw2), :Value, Ops.get_string(user_map, "pwd", ""))
        end
        # popup label
        UI.ChangeWidget(Id(:label), :Value, _("Edit User"))
      end
      ret = nil
      begin
        ret = UI.UserInput
        if ret == :ok
          username = Convert.to_string(UI.QueryWidget(Id(:username), :Value))
          pwd = Convert.to_string(UI.QueryWidget(Id(:pw1), :Value))
          new_group = Convert.to_string(UI.QueryWidget(Id(:group), :Value))
          gid = Convert.to_string(UI.QueryWidget(Id(:gid), :Value))
          if username == ""
            # popup message
            Report.Error(_("Enter the user name."))
            ret = :notnext
            next
          end
          if pwd != UI.QueryWidget(Id(:pw2), :Value)
            # popup message
            Report.Error(_("The passwords do not match.\nTry again."))
            ret = :notnext
            next
          end
          # ok, now update the structures
          user_map = {
            "pwd"       => pwd,
            "encrypted" => Ops.get_boolean(user_map, "encrypted", false) &&
              pwd == Ops.get_string(user_map, "pwd", ""),
            "name"      => username
          }
          Builtins.foreach(["home", "realname", "id"]) do |key2|
            if UI.QueryWidget(Id(key2), :Value) != ""
              Ops.set(user_map, key2, UI.QueryWidget(Id(key2), :Value))
            end
          end

          new_group = username == "root" ? "root" : "users" if new_group == ""

          group_modified = false
          Ops.set(
            @KiwiConfig,
            "users",
            Builtins.maplist(Ops.get_list(@KiwiConfig, "users", [])) do |gmap|
              # the group is already defined
              if Ops.get_string(gmap, "group", "") == new_group
                Ops.set(gmap, "id", gid) if gid != ""
                user_modified = false
                Ops.set(
                  gmap,
                  "user",
                  Builtins.maplist(Ops.get_list(gmap, "user", [])) do |umap|
                    if Ops.get(umap, "name") == user ||
                        Ops.get(umap, "name") == username
                      umap = deep_copy(user_map)
                      user_modified = true
                    end
                    deep_copy(umap)
                  end
                )
                if !user_modified
                  Ops.set(
                    gmap,
                    "user",
                    Builtins.add(Ops.get_list(gmap, "user", []), user_map)
                  )
                end
                group_modified = true
              # remove user from original group (= group was 'renamed')
              elsif Ops.get_string(gmap, "group", "") == group
                Ops.set(
                  gmap,
                  "user",
                  Builtins.filter(Ops.get_list(gmap, "user", [])) do |umap|
                    Ops.get(umap, "name") != user
                  end
                )
              end
              deep_copy(gmap)
            end
          )
          if !group_modified
            if Ops.get_list(@KiwiConfig, "users", []) == []
              Ops.set(@KiwiConfig, "users", [])
            end
            group_map = { "group" => new_group, "user" => [user_map] }
            Ops.set(group_map, "id", gid) if gid != ""
            Ops.set(
              @KiwiConfig,
              "users",
              Builtins.add(Ops.get_list(@KiwiConfig, "users", []), group_map)
            )
          end
          # remove empty groups
          Ops.set(
            @KiwiConfig,
            "users",
            Builtins.filter(Ops.get_list(@KiwiConfig, "users", [])) do |gmap|
              Ops.get_list(gmap, "user", []) != []
            end
          )
        end
      end until ret == :ok || ret == :cancel

      UI.CloseDialog
      InitUsersTable("table") if ret == :ok
      nil
    end

    # handle delete user button
    def HandleDeleteUser(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key

      current_user = Convert.to_string(
        UI.QueryWidget(Id("table"), :CurrentItem)
      )
      is_empty = false
      Ops.set(
        @KiwiConfig,
        "users",
        Builtins.maplist(Ops.get_list(@KiwiConfig, "users", [])) do |gmap|
          Ops.set(gmap, "user", Builtins.filter(Ops.get_list(gmap, "user", [])) do |umap|
            Ops.get_string(umap, "name", "") != current_user
          end)
          is_empty = true if Builtins.size(Ops.get_list(gmap, "user", [])) == 0
          deep_copy(gmap)
        end
      )
      if is_empty
        # remove empty groups
        Ops.set(
          @KiwiConfig,
          "users",
          Builtins.filter(Ops.get_list(@KiwiConfig, "users", [])) do |gmap|
            Ops.get_list(gmap, "user", []) != []
          end
        )
      end
      InitUsersTable("table")
      nil
    end

    # initialize the table with root dir contents
    def InitRootDirTable(id)
      items = Builtins.maplist(Ops.get_list(@KiwiConfig, "root_dir", [])) do |file|
        Item(Id(file), file)
      end
      UI.ChangeWidget(Id("roottable"), :Items, items)
      UI.ChangeWidget(
        Id("root_dir_delete"),
        :Enabled,
        Ops.greater_than(Builtins.size(items), 0)
      )

      nil
    end

    # add new subdir to the 'root' directory
    def HandleAddToRootDir(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      # popup for file selection dialog
      dir = UI.AskForExistingDirectory("", _("Directory to Import"))
      if dir != nil
        Ops.set(
          @KiwiConfig,
          "root_dir",
          Builtins.union(Ops.get_list(@KiwiConfig, "root_dir", []), [dir])
        )
        InitRootDirTable("roottable")
      end
      nil
    end

    # delete subdir from the 'root' directory
    def HandleDeleteFromRootDir(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      current = Convert.to_string(UI.QueryWidget(Id("roottable"), :Value))
      Ops.set(
        @KiwiConfig,
        "root_dir",
        Builtins.filter(Ops.get_list(@KiwiConfig, "root_dir", [])) do |f|
          f != current
        end
      )
      InitRootDirTable("roottable")
      nil
    end

    # initialize the table with config dir contents
    def InitConfigDirTable(id)
      items = Builtins.maplist(Ops.get_list(@KiwiConfig, "config_dir", [])) do |file|
        Item(Id(file), file)
      end
      UI.ChangeWidget(Id("configtable"), :Items, items)
      UI.ChangeWidget(
        Id("config_dir_delete"),
        :Enabled,
        Ops.greater_than(Builtins.size(items), 0)
      )

      nil
    end

    # add new subdir to the 'config' directory
    def HandleAddToConfigDir(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      # popup for file selection dialog
      dir = UI.AskForExistingFile("", "", _("Script to Import"))
      if dir != nil
        Ops.set(
          @KiwiConfig,
          "config_dir",
          Builtins.union(Ops.get_list(@KiwiConfig, "config_dir", []), [dir])
        )
        InitConfigDirTable("configtable")
      end
      nil
    end

    # delete subdir from the 'config' directory
    def HandleDeleteFromConfigDir(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      current = Convert.to_string(UI.QueryWidget(Id("configtable"), :Value))
      Ops.set(
        @KiwiConfig,
        "config_dir",
        Builtins.filter(Ops.get_list(@KiwiConfig, "config_dir", [])) do |f|
          f != current
        end
      )
      InitConfigDirTable("configtable")
      nil
    end

    # universal handler for directory browsing
    def BrowseDirectoryHandler(key, label)
      current = Convert.to_string(UI.QueryWidget(Id(key), :Value))
      current = "" if current == nil
      dir = UI.AskForExistingDirectory(current, label)
      if dir != nil
        UI.ChangeWidget(Id(key), :Value, dir)
        StoreGeneric(key, {})
      end
      dir
    end

    # handler for 'root' directory browse
    def HandleBrowseRootDirectory(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      # popup for file selection dialog ('root' is a name, do not translate)
      BrowseDirectoryHandler("root_dir", _("Path to root Directory"))
      nil
    end

    # handler for 'config' directory browse
    def HandleBrowseConfigDirectory(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      # popup for file selection dialog ('config' is a name, do not translate)
      BrowseDirectoryHandler("config_dir", _("Path to config Directory"))
      nil
    end

    # universal handler for file browsing
    def BrowseFileHandler(key, label)
      file = UI.AskForExistingFile(key, "", label)
      if file != nil && key != "config.sh" && key != "root/build-custom"
        UI.ChangeWidget(Id(key), :Value, file)
        StoreGeneric(key, {})
      end
      file
    end

    # Handler for importing config.sh file
    def HandleImportConfigFile(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      name = Builtins.substring(key, 7) # removing 'import_' button id prefix
      # popup for file selection dialog
      file = BrowseFileHandler(
        name,
        Builtins.sformat(_("Path to %1 File"), name)
      )
      if file != nil
        if FileUtils.Exists(file)
          cont = Convert.to_string(SCR.Read(path(".target.string"), file))
          if cont != nil
            UI.ChangeWidget(Id(name), :Value, cont)
            StoreGeneric(name, event)
          end
        end
      end
      nil
    end

    # Handler for importing images.sh file
    # TODO same function as HandleImportConfigFile
    def HandleImportImagesFile(key, event)
      event = deep_copy(event)
      return nil if Ops.get(event, "ID") != key
      # popup for file selection dialog
      file = BrowseFileHandler("images.sh", _("Path to images.sh File"))
      if file != nil
        if FileUtils.Exists(file)
          imagessh = Convert.to_string(SCR.Read(path(".target.string"), file))
          if imagessh != nil
            UI.ChangeWidget(Id("images.sh"), :Value, imagessh)
            StoreGeneric("images.sh", event)
          end
        end
      end
      nil
    end

    # generic popup
    def NotImplementedHandler(key, event)
      event = deep_copy(event)
      if Ops.get(event, "ID") == key
        Popup.Message(_("Feature not implemented yet."))
      end
      nil
    end

    # Check if selected packages are available (some of them may not after
    # deleting some repository)
    # return true if there was no conflict
    def CheckForAvailablePackages(ignore_allowed)
      packages_section = Ops.get_list(@KiwiConfig, "packages", [])
      index = 0
      ret = :ok
      Builtins.foreach(packages_section) do |pmap|
        type = Ops.get_string(pmap, "type", "")
        if type != "delete"
          Popup.ShowFeedback(
            _("Checking packages availability..."),
            _("Please wait...")
          )
          n_a = []

          bi_packages = []
          original_pmap = deep_copy(pmap)
          Ops.set(
            pmap,
            "package",
            Builtins.filter(Ops.get_list(pmap, "package", [])) do |p|
              if Ops.get_string(p, "bootinclude", "") == "true"
                bi_packages = Builtins.add(bi_packages, p)
              # do not check bootinclude packages
              elsif Ops.get_string(p, "name", "") != "" &&
                  !Pkg.IsAvailable(Ops.get_string(p, "name", ""))
                n_a = Builtins.add(n_a, Ops.get_string(p, "name", ""))
              end
              Ops.get_string(p, "bootinclude", "") != "true"
            end
          )
          Popup.ClearFeedback
          if Ops.greater_than(Builtins.size(n_a), 0)
            ret = :missing
            type_label = Ops.get_string(@section_type_label, type, type)

            UI.OpenDialog(
              Opt(:decorated),
              HBox(
                VSpacing(25),
                VBox(
                  HSpacing(70),
                  Left(Heading(_("Missing packages"))),
                  VSpacing(0.2),
                  # popup text
                  RichText(
                    Builtins.sformat(
                      _(
                        "<p>Packages from section '%1' are not available with selected repositories:</p>\n" +
                          "<p>%2.</p>\n" +
                          "<p>\n" +
                          "Either remove the packages from the section, check the detailed package selection or ignore the situation.</p>\n" +
                          "<p>\n" +
                          "Going to detailed package selection and accepting the view without any further changes results in removal of problematic packages from the section.\n" +
                          "</p>\n"
                      ),
                      type_label,
                      Builtins.mergestring(Builtins.sort(n_a), "<br>")
                    )
                  ),
                  HBox(
                    # button label
                    PushButton(Id(:remove), Opt(:default), _("Remove Packages")),
                    # button label
                    PushButton(Id(:selection), _("Check Package Selection")),
                    # button label
                    PushButton(
                      Id(:ignore),
                      ignore_allowed ? _("Ignore") : _("Cancel")
                    )
                  )
                )
              )
            )
            r = UI.UserInput
            UI.CloseDialog
            if r == :remove
              Ops.set(
                @KiwiConfig,
                ["packages", index, "package"],
                Builtins.filter(Ops.get_list(original_pmap, "package", [])) do |p|
                  !Builtins.contains(n_a, Ops.get_string(p, "name", ""))
                end
              )
              ret = :removed
            end
            if r == :selection
              sw_contents = modifyPackageSelection(pmap)
              if sw_contents != nil
                Ops.set(
                  sw_contents,
                  "package",
                  Builtins.union(
                    Ops.get_list(sw_contents, "package", []),
                    bi_packages
                  )
                )
                Ops.set(@KiwiConfig, ["packages", index], sw_contents)
                ret = :selection
              end
            end
          end
        end
        index = Ops.add(index, 1)
      end

      ret
    end

    # Check if all selected packages and patterns can be installed
    # If dependency problem was found, open package selector.
    # Return false if package selector was canceled
    def CheckPackageDependencies
      ret = true

      packages_section = Ops.get_list(@KiwiConfig, "packages", [])
      index = 0
      Builtins.foreach(packages_section) do |pmap|
        type = Ops.get_string(pmap, "type", "")
        if type != "delete"
          Pkg.ResolvableNeutral("", :package, true)
          Pkg.ResolvableNeutral("", :pattern, true)

          Builtins.foreach(Ops.get_list(pmap, "opensusePattern", [])) do |pat|
            Pkg.ResolvableInstall(Ops.get_string(pat, "name", ""), :pattern)
          end

          ProductCreator.MarkTaboo(
            Builtins.maplist(Ops.get_list(pmap, "ignore", [])) do |i|
              Ops.get_string(i, "name", "")
            end
          )

          # remember bootinclude packages: in Package selector we will lose this information (bnc#750739)
          bi_packages = {}
          Builtins.foreach(
            Ops.get_list(@KiwiConfig, ["packages", index, "package"], [])
          ) do |p|
            if Ops.get_string(p, "bootinclude", "") == "true"
              Ops.set(bi_packages, Ops.get_string(p, "name", ""), true)
            end
            InstallPackageOrProvider(Ops.get_string(p, "name", ""))
          end
          solved = Pkg.PkgSolve(true)
          if !solved
            sw_contents = modifyPackageSelection(
              Ops.get_map(@KiwiConfig, ["packages", index], {})
            )
            if sw_contents != nil
              Ops.set(
                sw_contents,
                "package",
                Builtins.maplist(Ops.get_list(sw_contents, "package", [])) do |p|
                  name = Ops.get_string(p, "name", "")
                  if Ops.get_boolean(bi_packages, name, false)
                    Builtins.y2milestone(
                      "package %1 was marked as bootinclude",
                      name
                    )
                    Ops.set(p, "bootinclude", "true")
                  end
                  deep_copy(p)
                end
              )
              Ops.set(@KiwiConfig, ["packages", index], sw_contents)
            else
              ret = false
            end
          end
        end
        index = Ops.add(index, 1)
      end
      ret
    end


    # handler for main action: create the iso image with kiwi
    def CreateImage(key, event)
      event = deep_copy(event)
      return true if Ops.get(event, "ID") != :next


      ret = true
      question = {
        # popup question
        "iso" => _("Create ISO image now?"),
        # popup question
        "xen" => _("Create Xen image now?"),
        # popup question
        "usb" => _("Create USB stick image now?"),
        # popup question
        "vmx" => _("Create virtual disk image now?")
      }

      success = {
        # popup message, %1 is a dir
        "iso" => _(
          "ISO image successfully created in\n" +
            "%1\n" +
            "directory."
        ),
        # popup message, %1 is a dir
        "xen" => _(
          "Xen image files successfully created in\n" +
            "%1\n" +
            "directory.\n"
        ),
        # popup message, %1 is a dir
        "usb" => _(
          "USB stick image successfully created in\n" +
            "%1\n" +
            "directory."
        ),
        # popup message, %1 is a dir
        "vmx" => _(
          "Virtual disk image successfully created in\n" +
            "%1\n" +
            "directory."
        )
      }

      create_image_now = false
      selected_profiles = ""
      if Ops.greater_than(
          Builtins.size(Ops.get_list(@KiwiConfig, "profiles", [])),
          0
        )
        items = VBox(VSpacing(0.5))
        profiles = Builtins.maplist(
          Ops.get_list(@KiwiConfig, ["profiles", 0, "profile"], [])
        ) do |prof|
          name = Ops.get_string(prof, "name", "")
          desc = Ops.get_string(prof, "description", "")
          items = Builtins.add(
            items,
            Left(
              CheckBox(
                Id(name),
                desc == "" ? name : Builtins.sformat("%1 (%2)", name, desc)
              )
            )
          )
          name
        end
        UI.OpenDialog(
          Opt(:decorated),
          HBox(
            HSpacing(0.5),
            VBox(
              VSpacing(0.5),
              # popup label
              Label(
                Ops.get_locale(question, @kiwi_task, _("Create image now?"))
              ),
              items,
              HBox(
                PushButton(Id(:yes), Opt(:key_F10), Label.YesButton),
                PushButton(Id(:no), Opt(:key_F9), Label.NoButton)
              ),
              VSpacing(0.5)
            ),
            HSpacing(0.5)
          )
        )
        while true
          ret2 = UI.UserInput
          if ret2 == :no
            create_image_now = false
            break
          end
          if ret2 == :yes
            create_image_now = true
            Builtins.foreach(
              Convert.convert(profiles, :from => "list", :to => "list <string>")
            ) do |name|
              if UI.QueryWidget(Id(name), :Value) == true
                selected_profiles = Ops.add(
                  Ops.add(selected_profiles, " --add-profile "),
                  name
                )
              end
            end
            break
          end
        end
        UI.CloseDialog
      else
        create_image_now =
          # default question
          Popup.YesNo(
            Ops.get_locale(question, @kiwi_task, _("Create image now?"))
          )
      end
      if create_image_now
        if CheckForAvailablePackages(false) == :missing
          Builtins.y2milestone(
            "there were missing packages, not going to build"
          )
          InitSWRichText("rt_sw")
          return false
        end
        if !CheckPackageDependencies()
          Builtins.y2milestone(
            "there was unresolved dependency problem, not going to build"
          )
          InitSWRichText("rt_sw")
          return false
        end
        # write XML now, after possible modification of the package list
        Kiwi.WriteConfigXML(@KiwiConfig, @kiwi_task)

        out_dir = Ops.get_string(@KiwiConfig, "iso-directory", "")
        if FileUtils.CheckAndCreatePath(out_dir) &&
            Kiwi.PrepareAndCreate(out_dir, selected_profiles)
          # default popup message, %1 is a dir
          Popup.Message(
            Builtins.sformat(
              Ops.get_locale(
                success,
                @kiwi_task,
                _(
                  "Image successfully created in\n" +
                    "%1\n" +
                    "directory."
                )
              ),
              out_dir
            )
          )
        else
          ret = false
        end
      else
        Kiwi.WriteConfigXML(@KiwiConfig, @kiwi_task)
      end

      dir = Kiwi.SaveConfiguration(@KiwiConfig, @kiwi_task)
      if dir != nil && dir != ""
        Ops.set(
          ProductCreator.Config,
          Ops.add("kiwi_configuration_", @kiwi_task),
          dir
        )
      end
      ret
    end

    # Global init function for Kiwi image dialog
    # - read saved settings and fill in defaults
    def InitImageConfiguration
      @kiwi_task = Kiwi.kiwi_task


      # path to definition of openSUSE live CD (used if kiwi-config-openSUSE is installed)
      kiwi_dir = "/usr/share/openSUSE-kiwi/livecd-x11"

      # read the information from the base product
      src_id = ProductCreator.checkProductDependency
      content = ProductCreator.ReadContentFile(src_id)

      @KiwiConfig = deep_copy(ProductCreator.Config)
      # busy popup
      Popup.ShowFeedback(
        _("Reading current image configuration..."),
        _("Please wait...")
      )

      # path to current config directory
      default_dir = @kiwi_task == "iso" ? kiwi_dir : ""
      kiwi_configuration = Ops.get_string(
        @KiwiConfig,
        Ops.add("kiwi_configuration_", @kiwi_task),
        default_dir
      )
      if kiwi_configuration == "" || !FileUtils.Exists(kiwi_configuration)
        # use local template if default dir does not exist (bug #289552)
        if !FileUtils.Exists(default_dir)
          default_dir = Ops.add(
            Directory.datadir,
            "/product-creator/kiwi_templates/"
          )
          default_dir = Ops.add(
            default_dir,
            @kiwi_task == "xen" ? "xen" : "iso"
          )
        end
        Builtins.y2warning(
          "directory %1 is not available, using %2",
          kiwi_configuration,
          default_dir
        )
        kiwi_configuration = default_dir
      end

      if FileUtils.Exists(Ops.add(kiwi_configuration, "/root"))
        # read all entries from root_dir and save to list
        out2 = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "ls -A1 -d %1/root/* 2>/dev/null",
              kiwi_configuration
            )
          )
        )
        Ops.set(
          @KiwiConfig,
          "root_dir",
          Builtins.filter(
            Builtins.splitstring(Ops.get_string(out2, "stdout", ""), "\n")
          ) do |f|
            f != "" && f != Ops.add(kiwi_configuration, "/root/build-custom")
          end
        )
      end
      if FileUtils.Exists(Ops.add(kiwi_configuration, "/config"))
        out2 = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "ls -A1 -d %1/config/* 2>/dev/null",
              kiwi_configuration
            )
          )
        )
        Ops.set(
          @KiwiConfig,
          "config_dir",
          Builtins.filter(
            Builtins.splitstring(Ops.get_string(out2, "stdout", ""), "\n")
          ) { |f| f != "" }
        )
      end

      # existence of manifesto.xml means studio-generated configuration
      if FileUtils.Exists(
          Ops.add(kiwi_configuration, "/root/studio/manifesto.xml")
        )
        Ops.set(@KiwiConfig, "root/build-custom", "")
      end

      Builtins.foreach(["images.sh", "config.sh", "root/build-custom"]) do |file|
        file_path = Ops.add(Ops.add(kiwi_configuration, "/"), file)
        if FileUtils.Exists(file_path)
          contents = Convert.to_string(
            SCR.Read(path(".target.string"), file_path)
          )
          Ops.set(@KiwiConfig, file, contents) if contents != nil
        end
      end
      # take care of the rest in the input directory (#330052)
      import_files = []
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("ls -A1 -d %1/* 2>/dev/null", kiwi_configuration)
        )
      )
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
      ) do |line|
        next if line == ""
        last = Builtins.substring(
          line,
          Ops.add(Builtins.findlastof(line, "/"), 1)
        )
        if Builtins.contains(
            ["images.sh", "config.sh", "config.xml", "root", "config"],
            last
          )
          next
        end
        import_files = Builtins.add(import_files, line)
      end
      Ops.set(@KiwiConfig, "import_files", import_files)

      read_config = Kiwi.ReadConfigXML(kiwi_configuration)

      if !Ops.get_boolean(@KiwiConfig, "_imported", false)
        # "type" had different meaning in ProductCreator::Config...
        if Builtins.haskey(@KiwiConfig, "type")
          @KiwiConfig = Builtins.remove(@KiwiConfig, "type")
        end
        @KiwiConfig = Convert.convert(
          Builtins.union(@KiwiConfig, read_config),
          :from => "map",
          :to   => "map <string, any>"
        )
        # do not read everything from the template, use the data defined in
        # Product Creator
        Builtins.y2milestone("product-creator based configuration...")

        Ops.set(
          @KiwiConfig,
          "sources",
          Ops.get_list(ProductCreator.Config, "sources", [])
        )

        # find the set with 'image' packages
        index = 0
        i = -1
        Builtins.foreach(Ops.get_list(@KiwiConfig, "packages", [])) do |set|
          i = Ops.add(i, 1)
          if Ops.get_string(set, "type", "") == "image"
            index = i
            raise Break
          end
        end
        sw_contents = Ops.get_map(@KiwiConfig, ["packages", index], {})
        Ops.set(
          sw_contents,
          "opensusePattern",
          Builtins.maplist(Ops.get_list(ProductCreator.Config, "addons", [])) do |name2|
            { "name" => name2 }
          end
        )
        Ops.set(
          sw_contents,
          "package",
          Builtins.maplist(Ops.get_list(ProductCreator.Config, "packages", [])) do |name2|
            { "name" => name2 }
          end
        )
        Ops.set(
          sw_contents,
          "ignore",
          Builtins.maplist(Ops.get_list(ProductCreator.Config, "taboo", [])) do |name2|
            { "name" => name2 }
          end
        )

        Ops.set(@KiwiConfig, ["packages", index], sw_contents)

        Ops.set(
          @KiwiConfig,
          "name",
          Ops.get_string(ProductCreator.Config, "name", "")
        )
      else
        Builtins.y2milestone("imported configuration...")
        # ignore options already set earlier...
        Builtins.foreach(read_config) do |key, val|
          if !Builtins.contains(
              ["name", "sources", "version", "preferences"],
              key
            )
            Ops.set(@KiwiConfig, key, val)
          end
        end
        pref = Ops.get_list(@KiwiConfig, "preferences", [])
        # new configuration doesn't get preferences at all...
        if pref == []
          pref = Ops.get_list(read_config, "preferences", [])
          Ops.set(pref, [0, "version"], [{ @content_key => "1.0.0" }])
          Ops.set(@KiwiConfig, "preferences", pref) 
          # FIXME check if boot directories match current product (-> enable building
          # for product different from installed one)
        else
          # existing defaultdestination needs to be used as iso-dirctory as well
          # (correct iso-directory was replaced on import (bnc#499489)
          dest = get_preferences(@KiwiConfig, "defaultdestination", "")
          Ops.set(@KiwiConfig, "iso-directory", dest) if dest != ""
        end
        primary_included = false
        boot_dir = ""
        # set the primary building target according to kiwi_task
        Ops.set(
          @KiwiConfig,
          ["preferences", 0, "type"],
          Builtins.maplist(Ops.get_list(pref, [0, "type"], [])) do |typemap|
            type = Ops.get_string(typemap, "image", "")
            if Builtins.tolower(Ops.get_string(typemap, "primary", "false")) == "true" &&
                type != @kiwi_task
              typemap = Builtins.remove(typemap, "primary")
            elsif type == @kiwi_task
              Ops.set(typemap, "primary", "true")
              primary_included = true
            end
            boot_dir = Ops.get_string(typemap, "boot", "") if boot_dir == ""
            deep_copy(typemap)
          end
        )
        # add the new type, that was not previously defined in config.xml
        # read the default values for this type from the template
        if !primary_included
          if default_dir == ""
            default_dir = Ops.add(
              Directory.datadir,
              "/product-creator/kiwi_templates/"
            )
            default_dir = Ops.add(
              default_dir,
              @kiwi_task == "xen" ? "xen" : "iso"
            )
          end
          def_map = Kiwi.ReadConfigXML(default_dir)
          Builtins.foreach(
            Ops.get_list(def_map, ["preferences", 0, "type"], [])
          ) do |typemap|
            if Ops.get_string(typemap, "image", "") == @kiwi_task
              Ops.set(
                @KiwiConfig,
                ["preferences", 0, "type"],
                Builtins.add(
                  Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], []),
                  typemap
                )
              )
              raise Break
            end
          end
        end
        # save the info about packages and patterns into ProductCreator::Config
        # ("sources" are already there...)
        sw_contents = Ops.get_map(@KiwiConfig, ["packages", 0], {})
        Ops.set(
          ProductCreator.Config,
          "addons",
          Builtins.maplist(Ops.get_list(sw_contents, "opensusePattern", [])) do |pat|
            Ops.get_string(pat, "name", "")
          end
        )
        Ops.set(
          ProductCreator.Config,
          "packages",
          Builtins.maplist(Ops.get_list(sw_contents, "package", [])) do |pat|
            Ops.get_string(pat, "name", "")
          end
        )
        Ops.set(
          ProductCreator.Config,
          "taboo",
          Builtins.maplist(Ops.get_list(sw_contents, "ignore", [])) do |pat|
            Ops.get_string(pat, "name", "")
          end
        )
      end
      label2boot = {
        "openSUSE 11.0"                        => "suse-11.0",
        "openSUSE 11.1"                        => "suse-11.1",
        "SUSE Linux Enterprise Server 10"      => "suse-SLES10",
        "SUSE Linux Enterprise Desktop 10"     => "suse-SLED10",
        "SUSE Linux Enterprise Desktop 10 SP2" => "suse-SLED10-SP2",
        "SUSE Linux Enterprise Server 10 SP2"  => "suse-SLES10-SP2",
        "SUSE Linux Enterprise Server 11"      => "suse-SLES11",
        "SUSE Linux Enterprise Desktop 11"     => "suse-SLED11"
      }
      contentlabel = String.CutBlanks(Ops.get(content, "LABEL", ""))
      boot_image = Ops.get_string(label2boot, contentlabel, "")

      # guess some default boot image value
      if @kiwi_task == "iso" && !Builtins.haskey(@KiwiConfig, "isoboot") &&
          boot_image != ""
        Ops.set(@KiwiConfig, "isoboot", boot_image)
      elsif @kiwi_task == "usb"
        if !Builtins.haskey(@KiwiConfig, "usbboot") && boot_image != ""
          Ops.set(@KiwiConfig, "usbboot", boot_image)
        end
      elsif @kiwi_task == "vmx"
        if !Builtins.haskey(@KiwiConfig, "vmxboot") && boot_image != ""
          Ops.set(@KiwiConfig, "vmxboot", boot_image)
        end
      elsif @kiwi_task == "xen"
        if !Builtins.haskey(@KiwiConfig, "xenboot")
          Ops.set(@KiwiConfig, "xenboot", boot_image)
        end
      end
      name = Ops.get_string(@KiwiConfig, "name", "")
      Popup.ClearFeedback

      nil
    end


    #***************************************************************************
    # widget descriptions
    #**************************************************************************

    # return map with description of tabs
    # it is a function, to be able to adapt to actual state)
    def tabs_descr
      show_compression = true

      # compression not allowed in most cases (bnc#510833)
      Builtins.foreach(
        Ops.get_list(@KiwiConfig, ["preferences", 0, "type"], [])
      ) do |typemap|
        if Ops.get_string(typemap, "image", "") == @kiwi_task
          if Ops.get_string(typemap, "filesystem", "") == "ext3"
            show_compression = false
          end
        end
      end

      # if root/build-custom file is present, offer its editing instead of
      # config.sh & images.sh (fate#310978)
      show_buildcustom = Builtins.haskey(@KiwiConfig, "root/build-custom")

      ret = {
        "config.xml"  => {
          # tab header
          "header"       => _("Image Configuration"),
          "contents"     => HBox(
            HSpacing(1),
            VBox(
              VSpacing(0.2),
              HBox(
                HWeight(
                  2,
                  HBox(
                    "version",
                    "size",
                    "sizeunit",
                    VBox(Label(""), "additive")
                  )
                ),
                show_compression ? HWeight(1, "compression") : HBox()
              ),
              HBox(VBox(Label(""), "encrypt_disk"), "disk_password"),
              HBox(
                HWeight(
                  2,
                  VBox(
                    "sw_selection",
                    Left(Label(_("Installed Software"))),
                    "rt_sw",
                    Right("configure_sw")
                  )
                ),
                HWeight(1, "delete_sw")
              ),
              VSpacing(0.2)
            ),
            HSpacing(1)
          ),
          "widget_names" => [
            "version",
            "size",
            "sizeunit",
            "additive",
            "encrypt_disk",
            "disk_password",
            "sw_selection",
            "rt_sw",
            "configure_sw",
            "delete_sw"
          ]
        },
        "description" => {
          # tab header
          "header"       => _("Description"),
          "contents"     => HBox(
            HSpacing(1),
            VBox(
              VSpacing(0.2),
              "author",
              VSpacing(0.2),
              "contact",
              VSpacing(0.2),
              "specification",
              VSpacing(0.6),
              # frame label
              Frame(
                _("Locale settings"),
                HBox("locale", "keytable", "timezone")
              ),
              VStretch()
            ),
            HSpacing(1)
          ),
          "widget_names" => [
            "author",
            "contact",
            "specification",
            "locale",
            "keytable",
            "timezone"
          ]
        },
        "users"       => {
          # tab header
          "header"       => _("Users"),
          "contents"     => HBox(
            HSpacing(1),
            VBox(
              "general_users",
              VSpacing(0.2),
              "userstable",
              VSpacing(0.2),
              HBox("adduser", "edituser", "deleteuser", HStretch()),
              VSpacing(0.2)
            ),
            HSpacing(1)
          ),
          "widget_names" => [
            "general_users",
            "group",
            "userstable",
            "adduser",
            "edituser",
            "deleteuser"
          ]
        },
        "scripts"     => {
          # tab header
          "header"       => _("Scripts"),
          "contents"     => HBox(
            HSpacing(1),
            VBox(
              "general_scripts",
              VSpacing(0.2),
              show_buildcustom ?
                VBox(
                  VWeight(
                    3,
                    HBox(
                      "root/build-custom",
                      Bottom("import_root/build-custom")
                    )
                  ),
                  Left(
                    # informative label
                    Label(
                      _(
                        "Editing of following files is disabled for configurations imported from Studio."
                      )
                    )
                  ),
                  VWeight(1, "config.sh"),
                  VWeight(1, "images.sh")
                ) :
                VBox(
                  HBox("config.sh", Bottom("import_config.sh")),
                  HBox("images.sh", Bottom("import_images.sh"))
                ),
              VSpacing(0.2)
            ),
            HSpacing(1)
          ),
          "widget_names" => [
            "general_scripts",
            "config.sh",
            "import_config.sh",
            "images.sh",
            "import_images.sh",
            "root/build-custom",
            "import_root/build-custom"
          ]
        },
        "directories" => {
          # tab header
          "header"       => _("Directories"),
          "contents"     => HBox(
            HSpacing(1),
            VBox(
              "general_directories",
              VSpacing(0.2),
              "root_dir_table",
              VSpacing(0.2),
              HBox("root_dir_add", Left("root_dir_delete")),
              VSpacing(0.2),
              "config_dir_table",
              VSpacing(0.2),
              HBox("config_dir_add", Left("config_dir_delete")),
              VSpacing(0.2),
              VSpacing(0.2)
            ),
            HSpacing(1)
          ),
          "widget_names" => [
            "general_directories",
            "root_dir_table",
            "root_dir_add",
            "root_dir_delete",
            "config_dir_table",
            "config_dir_add",
            "config_dir_delete"
          ]
        }
      }
      if show_compression
        Ops.set(
          ret,
          ["config.xml", "widget_names"],
          Builtins.add(
            Ops.get_list(ret, ["config.xml", "widget_names"], []),
            "compression"
          )
        )
      end
      deep_copy(ret)
    end

    def get_widget_description
      # ------------------
      {
        # global widgets
        "global"                   => {
          "widget"            => :empty,
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:CreateImage),
            "boolean (string, map)"
          ),
          "no_help"           => true
        },
        "compression"              => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify],
          "items"  => [],
          # textentry label
          "label"  => _("Co&mpression"),
          # help text
          "help"   => _(
            "<p>Select the value for image <b>Compression</b>. This will modify the\n<i>flags</i> value of the image type. Check the kiwi manual for an explanation of available values.</p>"
          ),
          "init"   => fun_ref(method(:InitCompressionCombo), "void (string)"),
          "store"  => fun_ref(
            method(:StoreCompressionCombo),
            "void (string, map)"
          ),
          "handle" => fun_ref(
            method(:HandleCompressionCombo),
            "symbol (string, map)"
          )
        },
        "sw_selection"             => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify],
          # combo box label
          "label"  => _("So&ftware Selection"),
          # help text for "So&ftware selection"
          "help"   => "",
          "items"  => [],
          "init"   => fun_ref(method(:InitSWSelectionCombo), "void (string)"),
          "store"  => fun_ref(
            method(:StoreSWSelectionCombo),
            "void (string, map)"
          ),
          "handle" => fun_ref(
            method(:HandleSWSelectionCombo),
            "symbol (string, map)"
          )
        },
        "rt_sw"                    => {
          "widget" => :richtext,
          "init"   => fun_ref(method(:InitSWRichText), "void (string)"),
          "help"   => "",
          "label"  => "&L"
        },
        "configure_sw"             => {
          "widget" => :push_button,
          # pusbutton label
          "label"  => _("Ch&ange..."),
          "help"   => _(
            "<p>Adapt the software selection with <b>Change</b>.</p>"
          ),
          "handle" => fun_ref(
            method(:HandleSWSelection),
            "symbol (string, map)"
          )
        },
        "ignore"                   => {
          "widget" => :multi_line_edit,
          # label
          "label"  => _("&Ignored Software"),
          "init"   => fun_ref(method(:InitSWIgnore), "void (string)"),
          "store"  => fun_ref(method(:StoreSWIgnore), "void (string, map)"),
          "handle" => fun_ref(method(:HandleSWIgnore), "symbol (string, map)"),
          # help text for "&Ignored software"
          "help"   => _(
            "<p>For <b>ignored software</b>, enter each entry (like 'smtp_daemon') on a new line.</p>"
          )
        },
        "delete_sw"                => {
          "widget" => :multi_line_edit,
          # label
          "label"  => _("Packages to &Delete"),
          "init"   => fun_ref(method(:InitSWDelete), "void (string)"),
          "store"  => fun_ref(method(:StoreSWDelete), "void (string, map)"),
          "handle" => fun_ref(method(:HandleSWDelete), "symbol (string, map)"),
          # help text for "&Ignored software"
          "help"   => _(
            "<p>Each entry of <b>Packages to Delete</b> is one package name to be uninstalled from the target image.</p>"
          )
        },
        "version"                  => {
          "widget"      => :textentry,
          # textentry label
          "label"       => _("&Version"),
          "help"        => _(
            "<p>Enter the <b>Version</b> of your image configuration.</p>"
          ),
          "valid_chars" => Ops.add(String.CDigit, "."),
          "init"        => fun_ref(method(:InitVersion), "void (string)"),
          "store"       => fun_ref(method(:StoreVersion), "void (string, map)"),
          "handle"      => fun_ref(
            method(:HandleVersion),
            "symbol (string, map)"
          )
        },
        "size"                     => {
          "widget" => :intfield,
          "opt"    => [:hstretch],
          # textentry label
          "label"  => _("&Size"),
          # help text for "Size" field and "Additive" checkbox
          "help"   => _(
            "<p>Set the image <b>Size</b> in the specified <b>Unit</b>.\nIf <b>Additive</b> is checked, the meaning of <b>Size</b> is different: it is the minimal free space available on the image.</p>"
          ),
          "init"   => fun_ref(method(:InitSize), "void (string)"),
          "store"  => fun_ref(method(:StoreSize), "void (string, map)"),
          "handle" => fun_ref(method(:HandleSize), "symbol (string, map)")
        },
        "sizeunit" =>
          # stored and handled by "size"
          {
            "widget"  => :combobox,
            # combo box label (MB/GB values)
            "label"   => _("&Unit"),
            "no_help" => true,
            "items"   => []
          },
        "additive"                 => {
          "widget"  => :checkbox,
          # check box label
          "label"   => _("Additive"),
          "no_help" => true
        },
        "encrypt_disk"             => {
          "widget" => :checkbox,
          "opt"    => [:notify],
          # check box label
          "label"  => _("Encrypt Image with LUKS"),
          # help text
          "help"   => _(
            "<p>To create an encrypted file system, check <b>Encrypt Image with LUKS</b> and enter the password.</p>"
          ),
          "handle" => fun_ref(
            method(:HandleEncryptDisk),
            "symbol (string, map)"
          )
        },
        "disk_password"            => {
          "widget"  => :textentry,
          # textentry label
          "label"   => _("Encrypted Image LUKS Password"),
          "init"    => fun_ref(method(:InitDiskPassword), "void (string)"),
          "store"   => fun_ref(method(:StoreDiskPassword), "void (string, map)"),
          "handle"  => fun_ref(
            method(:HandleDiskPassword),
            "symbol (string, map)"
          ),
          "no_help" => true
        },
        # ---------------- widgtes for directory structure
        "general_scripts"          => {
          "widget" => :empty,
          # general help for directory structure tab
          "help"   => _(
            "<p>Edit the configuration scripts used to build your image.</p>"
          )
        },
        "general_directories"      => {
          "widget" => :empty,
          # general help for directory structure tab
          "help"   => _(
            "<p>Point to the configuration directories for building your image.</p>"
          )
        },
        "root_dir"                 => {
          "widget" => :textentry,
          # textentry label
          "label"  => _(
            "Directory with System Configur&ation"
          ),
          # help text
          "help"   => _(
            "<p>Define the path to the <b>Directory with System Configuration</b> (the <tt>root</tt> directory). The entire directory is copied into the root of the image tree using <tt>cp -a</tt>.</p>"
          ),
          "init"   => fun_ref(method(:InitGeneric), "void (string)"),
          "store"  => fun_ref(method(:StoreGeneric), "void (string, map)"),
          "handle" => fun_ref(method(:HandleGeneric), "symbol (string, map)")
        },
        "browse_root_dir"          => {
          "widget" => :push_button,
          "label"  => Label.BrowseButton,
          "help"   => "",
          "handle" => fun_ref(
            method(:HandleBrowseRootDirectory),
            "symbol (string, map)"
          )
        },
        "root_dir_table"           => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            # label (above table)
            Left(Label(_("Directory with System Configuration"))),
            Table(
              Id("roottable"),
              Header(
                # table header
                _("Path to Directory")
              )
            )
          ),
          # help for table with users
          "help"          => _(
            "<p>Configure the <b>Directory with System Configuration</b> (the <tt>root</tt> directory). The entire directory is copied into the root of the image tree using <tt>cp -a</tt>.</p>"
          ),
          "init"          => fun_ref(method(:InitRootDirTable), "void (string)")
        },
        "root_dir_add"             => {
          "widget"  => :push_button,
          "label"   => Label.AddButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleAddToRootDir),
            "symbol (string, map)"
          )
        },
        "root_dir_delete"          => {
          "widget"  => :push_button,
          "label"   => Label.DeleteButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleDeleteFromRootDir),
            "symbol (string, map)"
          )
        },
        "config_dir_table"         => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            # label (above table)
            Left(Label(_("Directory with Scripts"))),
            Table(
              Id("configtable"),
              Header(
                # table header
                _("Path to File")
              )
            )
          ),
          # help for table with users
          "help"          => _(
            "<p>Configure the <b>Directory with Scripts</b> (the <tt>config</tt> directory). It contains scripts that are run after the installation of all the image packages.</p>"
          ),
          "init"          => fun_ref(
            method(:InitConfigDirTable),
            "void (string)"
          )
        },
        "config_dir_add"           => {
          "widget"  => :push_button,
          "label"   => Label.AddButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleAddToConfigDir),
            "symbol (string, map)"
          )
        },
        "config_dir_delete"        => {
          "widget"  => :push_button,
          "label"   => Label.DeleteButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleDeleteFromConfigDir),
            "symbol (string, map)"
          )
        },
        "root/build-custom"        => {
          "widget" => :multi_line_edit,
          # textentry label
          "label"  => _("Studio Custom Build Script"),
          "init"   => fun_ref(method(:InitGeneric), "void (string)"),
          "store"  => fun_ref(method(:StoreGeneric), "void (string, map)"),
          "handle" => fun_ref(method(:HandleGeneric), "symbol (string, map)")
        },
        "import_root/build-custom" => {
          "widget" => :push_button,
          # textentry label
          "label"  => _("&Import..."),
          "help"   => "",
          "handle" => fun_ref(
            method(:HandleImportConfigFile),
            "symbol (string, map)"
          )
        },
        "config.sh"                => {
          "widget" => :multi_line_edit,
          # textentry label
          "label"  => _("I&mage Configuration Script"),
          "help"   => _(
            "<p>Edit your <b>Image Configuration Script</b>, called <tt>config.sh</tt>. This script is run at the end of the installation but before the package scripts have run.</p>"
          ),
          "init"   => fun_ref(method(:InitGeneric), "void (string)"),
          "store"  => fun_ref(method(:StoreGeneric), "void (string, map)"),
          "handle" => fun_ref(method(:HandleGeneric), "symbol (string, map)")
        },
        "import_config.sh"         => {
          "widget" => :push_button,
          # textentry label
          "label"  => _("&Import..."),
          "help"   => "",
          "handle" => fun_ref(
            method(:HandleImportConfigFile),
            "symbol (string, map)"
          )
        },
        "config_dir"               => {
          "widget" => :textentry,
          # textentry label
          "label"  => _("Pa&th to Directory with Scripts"),
          "help"   => _(
            "<p>The optional <b>Directory with Scripts</b> (<tt>config</tt> directory) contains scripts that are run after the installation of all the image packages.</p>"
          ),
          "init"   => fun_ref(method(:InitGeneric), "void (string)"),
          "store"  => fun_ref(method(:StoreGeneric), "void (string, map)"),
          "handle" => fun_ref(method(:HandleGeneric), "symbol (string, map)")
        },
        "browse_config_dir"        => {
          "widget" => :push_button,
          # push button label
          "label"  => _("Br&owse..."),
          "help"   => "",
          "handle" => fun_ref(
            method(:HandleBrowseConfigDirectory),
            "symbol (string, map)"
          )
        },
        "images.sh"                => {
          "widget" => :multi_line_edit,
          # textentry label
          "label"  => _("C&leanup Script"),
          "help"   => _(
            "<p>Edit your <b>Cleanup Script</b> (<tt>images.sh</tt>). This script is run at the beginning of the image creation process.</p>"
          ),
          "init"   => fun_ref(method(:InitGeneric), "void (string)"),
          "store"  => fun_ref(method(:StoreGeneric), "void (string, map)"),
          "handle" => fun_ref(method(:HandleGeneric), "symbol (string, map)")
        },
        "import_images.sh"         => {
          "widget" => :push_button,
          # textentry label
          "label"  => _("Im&port..."),
          "help"   => "",
          "handle" => fun_ref(
            method(:HandleImportImagesFile),
            "symbol (string, map)"
          )
        },
        # ---------------- widgtes for description tab
        "author"                   => {
          "widget" => :textentry,
          # textentry label
          "label"  => _("&Author"),
          # help text for Author, Contact and Specification widgets
          "help"   => _(
            "<p>Set the values for <b>Author</b> of the image, <b>Contact Information</b>, and the image <b>Specification</b>.</p>"
          ),
          "init"   => fun_ref(method(:InitDescription), "void (string)"),
          "store"  => fun_ref(method(:StoreDescription), "void (string, map)"),
          "handle" => fun_ref(
            method(:HandleDescription),
            "symbol (string, map)"
          )
        },
        "contact"                  => {
          "widget"  => :textentry,
          # textentry label
          "label"   => _("C&ontact"),
          "init"    => fun_ref(method(:InitDescription), "void (string)"),
          "store"   => fun_ref(method(:StoreDescription), "void (string, map)"),
          "handle"  => fun_ref(
            method(:HandleDescription),
            "symbol (string, map)"
          ),
          "no_help" => true
        },
        "specification"            => {
          "widget"  => :multi_line_edit,
          # textentry label
          "label"   => _("&Specification"),
          "init"    => fun_ref(method(:InitDescription), "void (string)"),
          "store"   => fun_ref(method(:StoreDescription), "void (string, map)"),
          "handle"  => fun_ref(
            method(:HandleDescription),
            "symbol (string, map)"
          ),
          "no_help" => true
        },
        "locale"                   => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify],
          "items"  => [],
          # textentry label
          "label"  => _("&Locale"),
          "init"   => fun_ref(method(:InitLocaleCombo), "void (string)"),
          "store"  => fun_ref(method(:StorePreferences), "void (string, map)"),
          "handle" => fun_ref(
            method(:HandlePreferences),
            "symbol (string, map)"
          ),
          # help text for locale (heading)
          "help"   => _(
            "<p><b>Locale Settings</b></p>"
          ) +
            # help text for locale
            _(
              "<p>The value of <b>Locale</b> (e.g. <tt>en_US</tt>) defines the contents of the RC_LANG variable in <t>/etc/sysconfig/language</tt>.</p>"
            )
        },
        "keytable"                 => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify, :editable],
          # textentry label
          "label"  => _("&Keyboard Layout"),
          "init"   => fun_ref(method(:InitKeytableCombo), "void (string)"),
          "store"  => fun_ref(method(:StorePreferences), "void (string, map)"),
          "handle" => fun_ref(
            method(:HandlePreferences),
            "symbol (string, map)"
          ),
          # help text for keytable
          "help"   => _(
            "<p><b>Keyboard Layout</b> specifies the name of the console keymap to use. The value corresponds to a map file in <tt>/usr/share/kbd/keymaps</tt>.</p>"
          )
        },
        "timezone"                 => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify],
          "items"  => [],
          # textentry label
          "label"  => _("&Time Zone"),
          "init"   => fun_ref(method(:InitTimezoneCombo), "void (string)"),
          "store"  => fun_ref(method(:StorePreferences), "void (string, map)"),
          "handle" => fun_ref(
            method(:HandlePreferences),
            "symbol (string, map)"
          ),
          # help text for timezone
          "help"   => _(
            "<p>It is possible to set a specific <b>Time zone</b>. Available time zones are located in the <tt>/usr/share/zoneinfo</tt> directory.</p>"
          )
        },
        # ---------------- widgtes for users tab
        "general_users"            => {
          "widget" => :empty,
          # general help for users tab
          "help"   => _(
            "<p>Create users that should be available on the target system.</p>"
          )
        },
        "userstable"               => {
          "widget"        => :custom,
          "custom_widget" => Table(
            Id("table"),
            Opt(:notify),
            Header(
              # table header
              _("Login Name"),
              # table header
              _("Full Name"),
              # table header
              _("UID"),
              # table header
              _("Home Directory"),
              # table header
              _("Group"),
              # table header
              _("GID")
            )
          ),
          # help for table with users
          "help"          => _(
            "<p>For each user, specify the <b>Name</b>, <b>Password</b>, <b>Home Directory</b> and group\nto which the users belongs.</p>\n"
          ),
          "init"          => fun_ref(method(:InitUsersTable), "void (string)"),
          "handle"        => fun_ref(
            method(:HandleAddEditUser),
            "symbol (string, map)"
          )
        },
        "adduser"                  => {
          "widget"  => :push_button,
          "label"   => Label.AddButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleAddEditUser),
            "symbol (string, map)"
          )
        },
        "edituser"                 => {
          "widget"  => :push_button,
          "label"   => Label.EditButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleAddEditUser),
            "symbol (string, map)"
          )
        },
        "deleteuser"               => {
          "widget"  => :push_button,
          "label"   => Label.DeleteButton,
          "no_help" => true,
          "handle"  => fun_ref(
            method(:HandleDeleteUser),
            "symbol (string, map)"
          )
        }
      }
    end


    # Main dialog for Kiwi image configuration
    def KiwiDialog
      InitImageConfiguration()

      if CheckForAvailablePackages(true) != :selection
        CheckPackageDependencies()
      end

      widget_descr = get_widget_description
      Ops.set(
        widget_descr,
        "tab",
        CWMTab.CreateWidget(
          {
            "tab_order"    => [
              "config.xml",
              "description",
              "users",
              "scripts",
              "directories"
            ],
            "tabs"         => tabs_descr,
            "widget_descr" => widget_descr,
            "initial_tab"  => "config.xml"
          }
        )
      )
      Wizard.SetContentsButtons(
        "",
        VBox(),
        "",
        Label.BackButton,
        Label.NextButton
      )
      contents = VBox(
        Left(Label(Ops.get_string(@KiwiConfig, "name", ""))),
        "tab",
        VSpacing(0.3),
        "global"
      )

      caption = {
        # dialog caption
        "iso" => _("Live CD Configuration"),
        # dialog caption
        "xen" => _("Xen Image Configuration"),
        # dialog caption
        "usb" => _("USB Stick Image Configuration"),
        # button label
        "vmx" => _("Virtual Disk Image")
      }
      next_button = {
        # button label
        "iso" => _("&Create ISO"),
        # button label
        "xen" => _("&Create Xen Image"),
        # button label
        "usb" => _("&Create USB Stick Image"),
        # button label
        "vmx" => _("&Create Virtual Disk Image")
      }
      ret = CWM.ShowAndRun(
        {
          "widget_names"       => ["global", "tab"],
          "widget_descr"       => widget_descr,
          "contents"           => contents,
          # default dialog caption
          "caption"            => Ops.get_locale(
            caption,
            @kiwi_task,
            _("Image Configuration")
          ),
          "back_button"        => Label.BackButton,
          #	"next_button"		: next_button[kiwi_task]:Label::NextButton (),
          "next_button"        => Label.FinishButton(
          ),
          "fallback_functions" => {
            :abort => fun_ref(ProductCreator.method(:ReallyAbort), "boolean ()")
          }
        }
      )
      Builtins.y2milestone("Returning %1", ret)
      ret
    end

    # Prepare dialog: define kiwi data without product-creator
    def PrepareDialog
      @kiwi_task = Kiwi.kiwi_task
      @kiwi_task = "iso" if @kiwi_task == ""

      _Config = deep_copy(ProductCreator.Config)
      kiwi_configuration = Ops.get_string(
        _Config,
        Ops.add("kiwi_configuration_", @kiwi_task),
        ""
      )
      name = Ops.get_string(_Config, "name", "")
      out_dir = Ops.get_string(_Config, "iso-directory", "/tmp")
      repositories = deep_copy(Kiwi.current_repositories)
      new_configuration = _Config == {}
      append_name = false

      help = Ops.add(
        Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                new_configuration ?
                  # help text for kiwi UI preparation
                  _(
                    "<p>Enter the name of your image configuration. Base new configuration on template from the list or on the directory with the existing configuration.</p>"
                  ) :
                  "",
                # help text for kiwi UI preparation
                new_configuration ?
                  Builtins.sformat(
                    _(
                      "<p>Place custom configuration templates under <tt>%1</tt> directory.</p>"
                    ),
                    Ops.get(Kiwi.templates_dirs, 0, "")
                  ) :
                  ""
              ),
              # help text for kiwi UI preparation, cont.
              _("<p>Choose the <b>Image Type</b> which should be created.</p>")
            ),
            # help text for kiwi UI preparation, cont.
            _("<p>Select <b>Output Directory</b> for the created image.</p>")
          ),
          # help text for kiwi UI preparation, cont.
          _(
            "<p>Modify the list of <b>Package Repositories</b> that will be used for creating the image. Use <b>Add From System</b> to add one of the current system repositories.</p>"
          )
        ),
        # help text for kiwi UI preparation, cont.
        _("<p>Click <b>Next</b> to continue with the configuration.</p>")
      )

      basic_type_items = [
        # combo box item
        Item(Id("xen"), _("Xen Image"), @kiwi_task == "xen"),
        # combo box item
        Item(Id("usb"), _("USB Stick Image"), @kiwi_task == "usb"),
        # combo box item
        Item(Id("vmx"), _("Virtual Disk Image"), @kiwi_task == "vmx")
      ]

      # build Live iso only for x86_64 and i386 (bnc#675101)
      if Arch.architecture == "x86_64" || ProductCreator.GetArch == "i386"
        basic_type_items = Builtins.prepend(
          basic_type_items,
          # combo box item
          Item(Id("iso"), _("Live ISO Image"), @kiwi_task == "iso")
        )
      end

      task2label = {
        # combo box item
        "pxe" => _("Network Boot Image"),
        # combo box item
        "iso" => _("Live ISO Image"),
        # combo box item
        "xen" => _("Xen Image"),
        # combo box item
        "usb" => _("USB Stick Image"),
        # combo box item
        "vmx" => _("Virtual Disk Image"),
        # combo box item
        "oem" => _("OEM Image")
      }

      type_items = deep_copy(basic_type_items)
      default_type_items = deep_copy(basic_type_items)

      supported_images = Kiwi.supported_boot_images
      if supported_images != "" && supported_images != "template"
        type_items = [] # will be read from template..., or:
        Builtins.foreach(Builtins.splitstring(supported_images, ",")) do |type|
          if Builtins.haskey(task2label, type)
            type_items = Builtins.add(
              type_items,
              Item(
                Id(type),
                Ops.get_string(task2label, type, type),
                type == @kiwi_task
              )
            )
          end
        end
        default_type_items = deep_copy(type_items)
      elsif supported_images == "template" && !new_configuration
        type_its = []
        #solve `back here (=no import)
        Builtins.foreach(Ops.get_list(_Config, ["preferences", 0, "type"], [])) do |typemap|
          type = Ops.get_string(typemap, "image", "")
          type_its = Builtins.add(
            type_its,
            Item(
              Id(type),
              Ops.get_string(task2label, type, type),
              type == @kiwi_task
            )
          )
        end
        type_items = deep_copy(type_its) if type_its != []
      end
      present_types = Builtins.maplist(
        Convert.convert(type_items, :from => "list", :to => "list <term>")
      ) { |it| Ops.get_string(it, [0, 0], "") }
      if !Builtins.contains(["iso", "xen", "usb", "vmx"], @kiwi_task) &&
          !Builtins.contains(present_types, @kiwi_task)
        type_items = Builtins.add(
          type_items,
          Item(
            Id(@kiwi_task),
            Ops.get_string(task2label, @kiwi_task, @kiwi_task),
            true
          )
        )
        present_types = Builtins.add(present_types, @kiwi_task)
      end

      # on start, show the default YaST sources
      if Ops.get_list(_Config, "sources", []) != [] && repositories == {}
        Builtins.foreach(Ops.get_list(_Config, "sources", [])) do |src|
          Ops.set(repositories, src, { "url" => src })
        end
      end
      system_repo_items = Builtins.maplist(Kiwi.initial_repositories) do |url, repo|
        Item(Id(url), url)
      end

      update_repo_table = lambda do
        UI.ChangeWidget(
          Id(:repositories),
          :Items,
          Builtins.maplist(repositories) { |url, repo| Item(Id(url), url) }
        )
        UI.ChangeWidget(
          Id(:delete),
          :Enabled,
          Ops.greater_than(Builtins.size(repositories), 0)
        )

        nil
      end

      # read the new configuration and update UI accordingly
      # (no need to read config if it is provided as argument)
      update_config = lambda do |dir, config|
        config = deep_copy(config)
        kiwi_configuration = dir
        _Config = config == {} ? Kiwi.ReadConfigXML(kiwi_configuration) : config

        if Ops.get_string(_Config, ["description", 0, "type"], "") != "system"
          Builtins.y2warning(
            "%1 does not have 'system' image type, skipping",
            dir
          )
          # error popup
          Popup.Error(
            _(
              "Selected directory does not contain valid description of system configuration."
            )
          )
          return false
        end

        # busy popup
        Popup.ShowFeedback(_("Importing repositories..."), _("Please wait..."))
        repositories = Kiwi.ImportImageRepositories(_Config, dir)
        Popup.ClearFeedback
        if !new_configuration
          name = Ops.get_string(_Config, "name", "")
          UI.ChangeWidget(Id(:config), :Value, name)
        else
          _Config = save_preferences(_Config, "version", "1.0.0")
        end
        if Ops.get_string(_Config, "iso-directory", "") != ""
          UI.ChangeWidget(
            Id(:out_dir),
            :Value,
            Ops.get_string(_Config, "iso-directory", "")
          )
        end
        update_repo_table.call
        type_its = supported_images != "template" ? default_type_items : []

        @kiwi_task = ""
        Builtins.foreach(Ops.get_list(_Config, ["preferences", 0, "type"], [])) do |typemap|
          type = Ops.get_string(typemap, "image", "")
          if Builtins.tolower(Ops.get_string(typemap, "primary", "false")) == "true" ||
              @kiwi_task == ""
            @kiwi_task = type
          end
          if supported_images == "" && !Builtins.contains(present_types, type) ||
              supported_images == "template"
            type_its = Builtins.add(
              type_its,
              Item(Id(type), Ops.get_string(task2label, type, type))
            )
            present_types = Builtins.union(present_types, [type])
          end
        end
        if @kiwi_task == ""
          @kiwi_task = "iso"
          Builtins.y2warning("no task found, setting to 'iso'")
        end
        UI.ChangeWidget(Id(:type), :Items, type_its)
        UI.ChangeWidget(Id(:type), :Value, @kiwi_task)
        true
      end

      template_items = Builtins.maplist(Kiwi.Templates) do |dir, template|
        Item(
          Id(dir),
          Builtins.sformat(
            # combo box item, %1 is name, %2 version
            _("%1, version %2"),
            Ops.get_string(template, "name", ""),
            get_preferences(template, "version", "")
          )
        )
      end

      arch_term = VBox()

      if Arch.architecture == "x86_64"
        arch_term = VBox(
          # checkbox label
          CheckBox(
            Id(:i386),
            Opt(:notify, :hstretch),
            _("&32bit Architecture Image"),
            Kiwi.image_architecture == "i386"
          ),
          VSpacing(0.2)
        )
      end
      arch_term = Builtins.add(
        arch_term,
        # checkbox label
        CheckBox(
          Id(:i586),
          Opt(:hstretch),
          _("Target is i586 only"),
          Kiwi.target_i586
        )
      )
      arch_term = Builtins.add(arch_term, VSpacing(0.2))

      contents = VBox(
        new_configuration ?
          VBox(
            InputField(
              Id(:config),
              Opt(:hstretch),
              # text entry label
              _("&Kiwi Configuration"),
              name
            ),
            RadioButtonGroup(
              Id(:imp),
              HBox(
                HSpacing(),
                VBox(
                  VSpacing(0.2),
                  Left(
                    RadioButton(
                      Id("rb_new"),
                      Opt(:notify),
                      # radio button label
                      _("Create from Scratch"),
                      true
                    )
                  ),
                  template_items == [] ?
                    VSpacing(0) :
                    Left(
                      RadioButton(
                        Id("rb_template"),
                        Opt(:notify),
                        # radio button label
                        _("Base on Template")
                      )
                    ),
                  template_items == [] ?
                    VSpacing(0) :
                    HBox(
                      HSpacing(2.5),
                      ComboBox(
                        Id(:template),
                        Opt(:notify, :hstretch),
                        "",
                        template_items
                      )
                    ),
                  Left(
                    RadioButton(
                      Id("rb_dir"),
                      Opt(:notify),
                      # radio button label
                      _("Base on Existing Configuration")
                    )
                  ),
                  HBox(
                    HSpacing(2.5),
                    Label(Id(:import_dir), Opt(:outputField, :hstretch), ""),
                    # push button label
                    PushButton(Id(:import), _("&Choose..."))
                  )
                )
              )
            )
          ) :
          Left(Label(Id(:config), name)),
        # combo box label
        ComboBox(
          Id(:type),
          Opt(:notify, :hstretch),
          _("I&mage Type"),
          type_items
        ),
        HBox(
          InputField(
            Id(:out_dir),
            Opt(:hstretch),
            # text entry label
            _("&Output Directory"),
            out_dir
          ),
          VBox(Label(""), PushButton(Id(:browse), Label.BrowseButton))
        ),
        VSpacing(0.2),
        arch_term,
        Table(
          Id(:repositories),
          Opt(:notify),
          Header(
            # table header
            _("Package Repository")
          )
        ),
        HBox(
          PushButton(Id(:add), Label.AddButton),
          # menu butto label
          MenuButton(Id(:addsystem), _("A&dd from System"), system_repo_items),
          PushButton(Id(:edit), Label.EditButton),
          PushButton(Id(:delete), Label.DeleteButton),
          HStretch()
        )
      )
      # dialog caption
      Wizard.SetContentsButtons(
        _("Image preparation"),
        contents,
        help,
        Label.BackButton,
        Label.NextButton
      )
      Wizard.RestoreBackButton
      Wizard.RestoreAbortButton

      if new_configuration && kiwi_configuration != ""
        update_config.call(kiwi_configuration, {})
      else
        update_repo_table.call
      end

      if new_configuration
        UI.SetFocus(Id(:config))
        UI.ChangeWidget(Id(:template), :Enabled, false) if template_items != []
        UI.ChangeWidget(Id(:import), :Enabled, false)
        UI.ChangeWidget(Id(:config), :ValidChars, Ops.add(String.CAlnum, ".-_"))
      end
      if Arch.architecture == "x86_64"
        UI.ChangeWidget(Id(:i586), :Enabled, Kiwi.image_architecture == "i386")
      end
      ret = nil
      while true
        ret = UI.UserInput
        if ret == :abort || ret == :cancel || ret == :back
          if ProductCreator.ReallyAbort
            break
          else
            next
          end
        elsif ret == "rb_dir"
          if template_items != []
            UI.ChangeWidget(Id(:template), :Enabled, false)
          end
          UI.ChangeWidget(Id(:import), :Enabled, true)
          ret = :import if kiwi_configuration == ""
        elsif ret == "rb_template"
          UI.ChangeWidget(Id(:template), :Enabled, true)
          UI.ChangeWidget(Id(:import), :Enabled, false)
          ret = :template
        elsif ret == "rb_new"
          UI.ChangeWidget(Id(:template), :Enabled, false)
          UI.ChangeWidget(Id(:import), :Enabled, false)
        end
        if ret == :i386
          UI.ChangeWidget(
            Id(:i586),
            :Enabled,
            UI.QueryWidget(Id(:i386), :Value)
          )
        end
        if ret == :import
          dir = UI.AskForExistingDirectory(
            kiwi_configuration == "" ? Kiwi.images_dir : kiwi_configuration,
            # popup for file selection dialog
            _("Directory to Import")
          )
          if dir != nil && update_config.call(dir, {})
            UI.ChangeWidget(Id(:import_dir), :Value, dir)
          end
        elsif ret == :template
          dir = Convert.to_string(UI.QueryWidget(Id(:template), :Value))
          update_config.call(dir, Ops.get(Kiwi.Templates, dir, {}))
        elsif Ops.is_string?(ret) &&
            ret != "rb_dir" && # system repository selected
            ret != "rb_new"
          system_repo = Ops.get(
            Kiwi.initial_repositories,
            Convert.to_string(ret),
            {}
          )
          if !Builtins.haskey(repositories, Convert.to_string(ret))
            Ops.set(repositories, Convert.to_string(ret), system_repo)
          end

          update_repo_table.call
        elsif ret == :add
          Wizard.CreateDialog
          url = ""
          type_ret = SourceDialogs.TypeDialog

          if type_ret == :next || type_ret == :finish
            if type_ret == :finish && SourceDialogs.GetURL == "slp://"
              required_package = "yast2-slp"
              installed_before = PackageSystem.Installed(required_package)
              if !installed_before
                if !PackageSystem.CheckAndInstallPackagesInteractive(
                    [required_package]
                  )
                  Report.Error(
                    Builtins.sformat(
                      # popup error message, %1 is the package name
                      _(
                        "Cannot search for SLP repositories\nwithout having %1 package installed.\n"
                      ),
                      required_package
                    )
                  )
                  Builtins.y2warning("Not searching for SLP repositories")
                else
                  SCR.RegisterAgent(
                    path(".slp"),
                    term(:ag_slp, term(:SlpAgent))
                  )
                end
              end
              service = Convert.to_string(WFM.call("select_slp_source"))
              url = service if service != nil
            else
              url = SourceDialogs.GetURL if SourceDialogs.EditDialog == :next
            end
          end
          Wizard.CloseDialog
          if url != ""
            next if Builtins.haskey(repositories, url)

            parsed = URL.Parse(url)
            if Ops.get_string(parsed, "scheme", "") == "dir"
              url = Ops.get_string(parsed, "path", url)
              Builtins.y2milestone("un-escaping local directory path: %1", url)
            end
            plaindir = SourceDialogs.IsPlainDir

            Ops.set(
              repositories,
              url,
              {
                "url"      => url,
                "plaindir" => plaindir,
                "name"     => SourceDialogs.GetRepoName
              }
            )
            update_repo_table.call
          end
        elsif ret == :edit || ret == :repositories
          url = Convert.to_string(
            UI.QueryWidget(Id(:repositories), :CurrentItem)
          )
          selected_url = url
          plaindir = Ops.get_boolean(repositories, [url, "plaindir"], false)
          # change schema if the source type is plaindir
          # to show the right popup dialog
          if plaindir
            parsed2 = URL.Parse(url)
            url = URL.Build(parsed2)
            url = SourceDialogs.EditPopupType(url, true)
          else
            url = SourceDialogs.EditPopup(url)
          end
          next if url == "" || url == nil || url == selected_url
          # remove current url + add new one
          repositories = Builtins.remove(repositories, selected_url)
          parsed = URL.Parse(url)
          plaindir = SourceDialogs.IsPlainDir
          Ops.set(
            repositories,
            url,
            {
              "url"      => url,
              "plaindir" => plaindir,
              "name"     => SourceDialogs.GetRepoName
            }
          )
          update_repo_table.call
        elsif ret == :delete
          selected = Convert.to_string(
            UI.QueryWidget(Id(:repositories), :CurrentItem)
          )
          next if selected == nil
          repositories = Builtins.remove(repositories, selected)
          update_repo_table.call
          if Ops.greater_than(Builtins.size(repositories), 0)
            UI.SetFocus(Id(:repositories))
          end
        elsif ret == :browse
          dir = UI.AskForExistingDirectory(
            "",
            # popup for file selection dialog
            _("Path to the Output Directory")
          )
          UI.ChangeWidget(Id(:out_dir), :Value, dir) if dir != nil
        elsif ret == :next
          Builtins.y2internal(
            "package lock check returned %1",
            PackageLock.Check
          )

          name = Convert.to_string(UI.QueryWidget(Id(:config), :Value))
          if name == ""
            # error popup
            Report.Error(_("Enter the name of the configuration."))
            UI.SetFocus(Id(:config))
            next
          end
          if new_configuration &&
              FileUtils.Exists(Ops.add(Ops.add(Kiwi.images_dir, "/"), name))
            # error popup
            Popup.Error(
              Builtins.sformat(
                _(
                  "Configuration with name \"%1\" already exists.\nChoose a different one."
                ),
                name
              )
            )
            UI.SetFocus(Id(:config))
            next
          end
          out_dir = Convert.to_string(UI.QueryWidget(Id(:out_dir), :Value))
          if out_dir == ""
            # error popup
            Popup.Error(_("Enter the path to the output directory."))
            UI.SetFocus(Id(:out_dir))
            next
          end
          if repositories == {}
            # error popup
            Popup.Error(_("Specify at least one package repository."))
            UI.SetFocus(Id(:repositories))
            next
          end

          @kiwi_task = Convert.to_string(UI.QueryWidget(Id(:type), :Value))

          failed_repositories = []
          new_repositories = {}

          ProductCreator.ResetArch

          if Arch.architecture == "x86_64"
            Kiwi.image_architecture = "x86_64"
            if UI.QueryWidget(Id(:i386), :Value) == true
              Kiwi.image_architecture = "i386"
            end
            # closing sources, so they are created again with correct arch (bnc#510971, bnc#794583)
            Pkg.SourceFinishAll
            Pkg.SourceStartManager(false)
            ProductCreator.SetPackageArch(
              Kiwi.image_architecture == "i386" ? "i686" : "x86_64"
            )
          end

          Kiwi.target_i586 = Kiwi.image_architecture == "i386" &&
            Convert.to_boolean(UI.QueryWidget(Id(:i586), :Value))

          if Ops.greater_than(Builtins.size(repositories), 0)
            current_sources = {}
            # delete current repos, that won't be used in config
            Builtins.foreach(Pkg.SourceEditGet) do |source|
              srcid = Ops.get_integer(source, "SrcId", -1)
              data = Pkg.SourceGeneralData(srcid)
              url = Ops.get_string(data, "url", "")
              # there can be more sources with same url, leave there only one
              if Ops.get(current_sources, url, srcid) != srcid
                Builtins.y2milestone(
                  "deleting extra source %1 for %2",
                  Ops.get(current_sources, url, srcid),
                  url
                )
                Pkg.SourceDelete(Ops.get(current_sources, url, srcid))
              end
              Ops.set(current_sources, url, srcid)
            end
            # map of new repo aliases
            aliases = {}
            # initialize new repos now
            new_repositories = Builtins.filter(repositories) do |url, repo|
              if Builtins.substring(url, 0, 1) == "/"
                url = Ops.add("dir://", url)
              end
              if Builtins.haskey(current_sources, url)
                current_sources = Builtins.remove(current_sources, url)
                next true
              end
              source_ret = -1
              full_url = url
              if Ops.get_string(repo, "full_url", "") != "" &&
                  Ops.get_string(repo, "full_url", "") != url
                full_url = Ops.get_string(repo, "full_url", "")
              end
              _alias = Builtins.mergestring(
                Builtins.splitstring(
                  Ops.get_string(repo, "name", full_url),
                  " "
                ),
                "_"
              )
              if Ops.greater_than(Ops.get(aliases, _alias, 0), 0)
                _alias = Builtins.sformat(
                  "%1%2",
                  _alias,
                  Ops.get(aliases, _alias, 0)
                )
              end
              Ops.set(aliases, _alias, Ops.add(Ops.get(aliases, _alias, 0), 1))
              repo_map = {
                "name"      => Ops.get_string(repo, "name", _alias),
                "alias"     => _alias,
                "base_urls" => [full_url]
              }
              if Ops.get_boolean(repo, "plaindir", false)
                Ops.set(repo_map, "type", "Plaindir")
              end
              source_ret = Pkg.RepositoryAdd(repo_map)
              if source_ret == -1
                failed_repositories = Builtins.add(failed_repositories, url)
                next false
              end
              true
            end
            Builtins.foreach(current_sources) do |url, srcid|
              Pkg.SourceDelete(srcid)
            end
          end
          if failed_repositories != []
            # continue/cancel popup %1 is a \n separated list
            if !Popup.ContinueCancel(
                Builtins.sformat(
                  _(
                    "Failed to add these repositories:\n" +
                      "\n" +
                      "%1.\n" +
                      "\n" +
                      "Continue anyway?"
                  ),
                  Builtins.mergestring(failed_repositories, "\n")
                )
              )
              next
            else
              repositories = deep_copy(new_repositories)
            end
          end
          to_install = ""
          if Builtins.contains(["iso", "xen", "vmx", "usb"], @kiwi_task)
            bootdir = get_bootdir(_Config, @kiwi_task)
            if bootdir == "" ||
                !FileUtils.Exists(Ops.add("/usr/share/kiwi/image/", bootdir)) &&
                  !FileUtils.Exists(bootdir)
              to_install = Builtins.sformat("kiwi-desc-%1boot", @kiwi_task)
            end
            if to_install != "" && !Package.Install(to_install)
              Popup.Error(Message.FailedToInstallPackages)
              next
            end
          end
          break
        end
      end
      boot = get_bootdir(_Config, @kiwi_task)
      if boot != "" && Builtins.issubstring(boot, "/")
        prefix = @kiwi_task == "pxe" ? "net" : @kiwi_task
        Ops.set(
          _Config,
          Ops.add(prefix, "boot"),
          Builtins.substring(boot, Ops.add(Builtins.search(boot, "/"), 1))
        ) #FIXME this should not be needed...
      end
      if ret == :next
        if Ops.greater_than(Builtins.size(repositories), 0)
          ProductCreator.enable_sources = false
          Pkg.SourceLoad
        end
        Ops.set(
          _Config,
          Ops.add("kiwi_configuration_", @kiwi_task),
          kiwi_configuration
        )
        Ops.set(_Config, "_imported", true)
        Ops.set(
          _Config,
          "iso-directory",
          Ops.add(out_dir, new_configuration ? Ops.add("/", name) : "")
        )
        _Config = save_preferences(
          _Config,
          "defaultdestination",
          Ops.get_string(_Config, "iso-directory", "")
        )
        Ops.set(_Config, "name", name)
        Ops.set(_Config, "new_configuration", new_configuration)
        Ops.set(_Config, "sources", Builtins.maplist(repositories) do |url, repo|
          url
        end)
        ProductCreator.Config = deep_copy(_Config)
        Kiwi.current_repositories = deep_copy(repositories)
        Kiwi.kiwi_task = @kiwi_task
      end
      Builtins.y2milestone("Returning %1", ret)
      Convert.to_symbol(ret)
    end
  end
end
