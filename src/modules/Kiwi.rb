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

# File:	modules/Kiwi.ycp
# Package:	Configuration of product-creator
# Summary:	Data for kiwi configuration, input and output functions.
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
require "yast"

module Yast
  class KiwiClass < Module
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "product-creator"

      Yast.import "Arch"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Label"
      Yast.import "Message"
      Yast.import "Package"
      Yast.import "Popup"
      Yast.import "ProductCreator"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Security"
      Yast.import "String"
      Yast.import "URL"

      # path to file with global repo aliases (fate#312133)
      @aliases_path = "/etc/kiwi/repoalias"

      # mapping of repository aliases to real URLs
      # nil means not activated
      @alias2url = nil

      # mapping of repo URLs to alias - only those used in last read
      # (so not the reverse of alias2url map)
      @url2alias = {}

      # argument for any_xml agent: key indicating content of element without
      # attributes
      @content_key = "__yast_content__"

      # default image size, if none was given (in MB)
      @default_size = "10"

      Yast.include self, "product-creator/routines.rb"

      @encryption_method = nil

      # temporary directory, where kiwi is working
      @tmp_dir = ""

      # directory for saving image configurations
      @images_dir = Ops.add(Directory.vardir, "/product-creator/images")

      # bug 331733
      @supported_boot_images = ""

      # target architecture of image (can be only i386 if different from current one)
      @image_architecture = ""

      # if target architecture should be i586 instead of i686
      @target_i586 = false

      # directories with user-made templated
      @templates_dirs = []

      @default_packagemanager = "zypper"

      @all_sources = []

      # repositories used for current configuration
      @current_repositories = {}

      # initial system repositories
      @initial_repositories = {}

      # where the kiwi configuration files are stored
      @config_dir = ""

      # chroot directory for creating the physical extend
      @chroot_dir = ""

      # What we want to create with kiwi
      @kiwi_task = "iso"

      # map with image templates (to base new projects on)
      @Templates = {}

      @stdout_file = "image_creator.stdout"
      @stderr_file = "image_creator.stderr"
      @logs_directory = "/tmp"

      # all available locales
      @all_locales = {}

      # all available time zones
      @all_timezones = []
    end

    # crypt given user password with current encryption algorithm
    def crypt_password(pw)
      return pw if pw == ""
      if @encryption_method == nil
        progress = Progress.set(false)
        Security.Read
        Progress.set(progress)
        security = Security.Export
        @encryption_method = Builtins.tolower(
          Ops.get_string(security, "PASSWD_ENCRYPTION", "des")
        )
      end
      return Builtins.cryptmd5(pw) if @encryption_method == "md5"
      return Builtins.cryptblowfish(pw) if @encryption_method == "blowfish"
      Builtins.crypt(pw)
    end

    # change the yast source path format to kiwi (smart?) one
    def adapt_source_path(source)
      if Builtins.substring(source, 0, 6) == "dir://"
        return Builtins.substring(source, 6)
      end
      source
    end

    # generate the 'repository' tag
    def get_source_value(source, config)
      config = deep_copy(config)
      ret = {}
      # first check if we weren't importing this source:
      Builtins.foreach(@current_repositories) do |url, repo|
        if url == source && Ops.get_map(repo, "org", {}) != {}
          ret = Ops.get_map(repo, "org", {})
        end
      end
      adapted = adapt_source_path(source)
      if Builtins.haskey(@url2alias, source) ||
          Builtins.haskey(@url2alias, adapted)
        Ops.set(
          ret,
          ["source", 0, "path"],
          Ops.get(@url2alias, source, Ops.get(@url2alias, adapted, ""))
        )
        Builtins.y2milestone(
          "alias for %1 is %2",
          source,
          Ops.get_string(ret, ["source", 0, "path"], "")
        )
        return deep_copy(ret)
      end

      if ret != {}
        Builtins.y2milestone("imported source: %1", source)
        return deep_copy(ret)
      end

      # ... otherwise, we must ask zypp:
      type = "yast2"

      Builtins.foreach(@all_sources) do |sourcemap|
        srcid = Ops.get_integer(sourcemap, "SrcId", -1)
        data = Pkg.SourceGeneralData(srcid)
        url = Ops.get_string(data, "url", "")
        if adapt_source_path(url) == adapted
          if Ops.get_string(data, "type", "") == "NONE"
            Ops.set(data, "type", Pkg.RepositoryProbe(url, ""))
          end
          type = "rpm-dir" if Ops.get_string(data, "type", "") == "Plaindir"
          type = "rpm-md" if Ops.get_string(data, "type", "") == "YUM"
          parsed = URL.Parse(url)
          if Ops.get_string(parsed, "scheme", "") == "https"
            # change source url to contain password
            source = Pkg.SourceURL(srcid)
          end
        end
      end
      { "source" => [{ "path" => adapt_source_path(source) }], "type" => type }
    end

    # generate the name of directory with kiwi configuration
    def get_config_dir(name, task)
      Builtins.deletechars(name, " \t")
    end



    # convert YCP map (of type read from any_xml agent) to XML
    def MapAny2XML(item_key, item_descr, level)
      item_descr = deep_copy(item_descr)
      tab = ""
      i = 0
      while Ops.less_than(i, level)
        i = Ops.add(i, 1)
        tab = Ops.add(tab, "  ")
      end
      ret = Ops.add(Ops.add(tab, "<"), item_key)
      attr = ""
      subret = ""
      content = ""
      Builtins.foreach(
        Convert.convert(item_descr, :from => "map", :to => "map <string, any>")
      ) do |key, value|
        if Ops.is_list?(value)
          Builtins.foreach(
            Convert.convert(value, :from => "any", :to => "list <map>")
          ) do |it_map|
            subret = Ops.add(
              Ops.add(subret, "\n"),
              MapAny2XML(key, it_map, Ops.add(level, 1))
            )
          end
        elsif Ops.is_string?(value) || Ops.is_integer?(value) ||
            Ops.is_boolean?(value)
          if key == @content_key
            content = String.EscapeTags(Builtins.tostring(value))
          else
            attr = Ops.add(
              attr,
              Builtins.sformat(
                " %1=\"%2\"",
                key,
                String.EscapeTags(Builtins.tostring(value))
              )
            )
          end
        end
      end
      ret = Ops.add(ret, attr)
      ret = Ops.add(ret, subret == "" && content == "" ? "/>" : ">")
      if content != ""
        ret = Ops.add(
          Ops.add(ret, content),
          Builtins.sformat("</%1>", item_key)
        )
      elsif subret != ""
        ret = Ops.add(
          Ops.add(Ops.add(Ops.add(ret, subret), "\n"), tab),
          Builtins.sformat("</%1>", item_key)
        )
      end
      ret
    end

    # Transform given XML file using given XSL transformation file
    # Return path to new file if transformation was done and was successful
    # @param [String] config_path path to XML file
    # @param [String] xsl_file path to XSL file
    def XSLTTransform(config_path, xsl_file)
      ret_path = config_path
      if Package.Installed("libxslt") && FileUtils.Exists(xsl_file)
        # new path identified by xsl file:
        # config-usr-share-kiwi-xsl-convertSleposSp1toSp2-xsl.xml
        ret_path = Builtins.sformat(
          "%1/config%2.xml",
          Directory.tmpdir,
          Builtins.mergestring(Builtins.splitstring(xsl_file, "/ ."), "-")
        )
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "/usr/bin/xsltproc '%1' '%2' > %3",
              String.Quote(xsl_file),
              String.Quote(config_path),
              ret_path
            )
          )
        )
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2error("xslt transformation failed: %1", out)
          ret_path = config_path
        end
      end
      ret_path
    end

    # Read global list of repository aliases
    def ReadAliases(force)
      return deep_copy(@alias2url) if @alias2url != nil && !force
      @alias2url = {}
      if FileUtils.Exists(@aliases_path)
        aliases = SCR.Dir(path(".etc.kiwi.repoalias.v"))
        if aliases == nil
          Builtins.y2warning("aliases file broken, empty or not for reading...")
        else
          Builtins.foreach(aliases) do |_alias|
            url = Convert.to_string(
              SCR.Read(Builtins.add(path(".etc.kiwi.repoalias.v"), _alias))
            )
            if url == nil || url == ""
              Builtins.y2warning(
                "alias '%1' incorrectly defined: '%2'",
                _alias,
                url
              )
            else
              Ops.set(@alias2url, _alias, url)
            end
          end
        end
      end
      deep_copy(@alias2url)
    end

    # import the data from given config.xml
    # @param directory where to look for config.xml
    # @ret map of imported data
    def ReadConfigXML(base_path)
      ret = {}
      if !FileUtils.Exists(Ops.add(base_path, "/config.xml"))
        Builtins.y2warning("no such file %1/config.xml", base_path)
        return deep_copy(ret)
      end
      @url2alias = {}
      file_path = Ops.add(base_path, "/config.xml")

      # transformation to latest kiwi version
      file_path = XSLTTransform(file_path, "/usr/share/kiwi/xsl/master.xsl")
      # transformation to latest SLEPOs version (bnc#723031)
      slepos_path = XSLTTransform(
        file_path,
        "/usr/share/kiwi/xsl/convertSleposSp1toSp2.xsl"
      )
      # make a backup when SLEPOS transformation changed anything
      if slepos_path != file_path
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("diff -1 '%1' '%2'", file_path, slepos_path)
          )
        )
        if Ops.get_integer(out, "exit", 0) != 0
          backup = Ops.add(base_path, "/config.xml.POSsave")
          Builtins.y2milestone("creating backup of config file: %1", backup)
          SCR.Execute(
            path(".target.bash"),
            Builtins.sformat(
              "cp -- '%1/config.xml' '%2'",
              String.Quote(base_path),
              String.Quote(backup)
            )
          )
        end
        file_path = slepos_path
      end

      # read rest of config.xml using more generic agent
      anyxml = Convert.to_map(
        SCR.Read(
          path(".anyxml"),
          {
            "file" => file_path,
            "args" => {
              "ForceArray"   => 1,
              "KeepRoot"     => 1,
              "KeyAttr"      => [],
              "ForceContent" => 1,
              "ContentKey"   => @content_key
            }
          }
        )
      )
      image = Ops.get_map(anyxml, ["image", 0], {})

      # attributes of 'image' tag:
      Ops.set(ret, "name", Ops.get_string(image, "name", ""))
      Ops.set(
        ret,
        "schemaversion",
        Ops.get_string(image, "schemaversion", "5.2")
      )
      if Builtins.haskey(image, "inherit")
        Ops.set(ret, "inherit", Ops.get_string(image, "inherit", ""))
      end

      Ops.set(ret, "preferences", Ops.get_list(image, "preferences", []))
      Ops.set(ret, "description", Ops.get_list(image, "description", []))
      Ops.set(ret, "users", Builtins.maplist(Ops.get_list(image, "users", [])) do |gmap|
        # convert integer values to strings
        Ops.set(gmap, "user", Builtins.maplist(Ops.get_list(gmap, "user", [])) do |umap|
          if Ops.get(umap, "id") != nil
            Ops.set(umap, "id", Builtins.sformat("%1", Ops.get(umap, "id")))
          end
          # add internal info if password was already crypted
          Ops.set(umap, "encrypted", Ops.get(umap, "pwd") != nil)
          deep_copy(umap)
        end)
        if Ops.get(gmap, "id") != nil
          Ops.set(gmap, "id", Builtins.sformat("%1", Ops.get(gmap, "id")))
        end
        deep_copy(gmap)
      end)
      Ops.set(ret, "packages", Ops.get_list(image, "packages", []))
      Ops.set(ret, "profiles", Ops.get_list(image, "profiles", []))
      Ops.set(ret, "split", Ops.get_list(image, "split", []))

      if Ops.get(image, "repository") != nil
        # check repo aliases and replace with real paths for YaST
        ReadAliases(false)
        image_repos = Ops.get_list(image, "repository", [])
        Ops.set(
          ret,
          "repository",
          Builtins.maplist(Ops.get_list(image, "repository", [])) do |repo|
            source = Ops.get_string(repo, ["source", 0, "path"], "")
            url = Ops.get(@alias2url, source, "")
            if url != ""
              Ops.set(repo, ["source", 0, "path"], url)
              # save alias for writing:
              Ops.set(@url2alias, url, source)
              Builtins.y2milestone("alias %1 replaced with %2", source, url)
            end
            deep_copy(repo)
          end
        )
      end

      # FIXME iso-directory should be used only when converting PC->IC
      if Builtins.haskey(
          Ops.get_map(ret, ["preferences", 0], {}),
          "defaultdestination"
        )
        Ops.set(
          ret,
          "iso-directory",
          Ops.get_string(
            ret,
            ["preferences", 0, "defaultdestination", 0, @content_key],
            ""
          )
        )
      end

      if Builtins.haskey(Ops.get_map(ret, ["preferences", 0], {}), "locale")
        # remove .UTF-8 endings from locale (bnc#675101)
        lang = get_preferences(ret, "locale", "")
        split = Builtins.splitstring(lang, ".")
        ret = save_preferences(ret, "locale", Ops.get(split, 0, lang))
      end
      deep_copy(ret)
    end

    # Write currect configuration to new config.xml
    def WriteConfigXML(_KiwiConfig, task)
      _KiwiConfig = deep_copy(_KiwiConfig)
      @all_sources = Pkg.SourceEditGet
      @tmp_dir = Directory.tmpdir
      @chroot_dir = Ops.add(@tmp_dir, "/myphysical")
      defaultroot = get_preferences(_KiwiConfig, "defaultroot", "")
      if defaultroot != ""
        @chroot_dir = defaultroot
        if Ops.get_boolean(_KiwiConfig, "new_configuration", false)
          @chroot_dir = Ops.add(
            Ops.add(@chroot_dir, "/"),
            Ops.get_string(_KiwiConfig, "name", "")
          )
        end
        _KiwiConfig = save_preferences(_KiwiConfig, "defaultroot", @chroot_dir)
      end

      image_tag = Builtins.sformat(
        "<image name=\"%1\" schemaversion=\"%2\"%3>",
        Ops.get_string(_KiwiConfig, "name", ""),
        Ops.get_string(_KiwiConfig, "schemaversion", "5.2"),
        Ops.get_string(_KiwiConfig, "inherit", "") == "" ?
          "" :
          Builtins.sformat(
            " inherit=\"%1\"",
            Ops.get_string(_KiwiConfig, "inherit", "")
          )
      )
      image_contents = Ops.add(
        Ops.add(
          Ops.add(
            MapAny2XML(
              "description",
              Ops.get_map(_KiwiConfig, ["description", 0], {}),
              1
            ),
            "\n"
          ),
          MapAny2XML(
            "preferences",
            Ops.get_map(_KiwiConfig, ["preferences", 0], {}),
            1
          )
        ),
        "\n"
      )

      if Builtins.haskey(_KiwiConfig, "users")
        Builtins.foreach(Ops.get_list(_KiwiConfig, "users", [])) do |gmap|
          Ops.set(
            gmap,
            "user",
            Builtins.maplist(Ops.get_list(gmap, "user", [])) do |umap|
              encrypted = Ops.get_boolean(umap, "encrypted", false)
              Ops.set(
                umap,
                "pwd",
                Ops.get_boolean(umap, "encrypted", false) ?
                  Ops.get_string(umap, "pwd", "") :
                  crypt_password(Ops.get_string(umap, "pwd", ""))
              )
              if Builtins.haskey(umap, "encrypted")
                umap = Builtins.remove(umap, "encrypted")
              end
              deep_copy(umap)
            end
          )
          image_contents = Ops.add(
            Ops.add(image_contents, MapAny2XML("users", gmap, 1)),
            "\n"
          )
        end
      end
      if Ops.greater_than(
          Builtins.size(Ops.get_list(_KiwiConfig, "profiles", [])),
          0
        )
        image_contents = Ops.add(
          Ops.add(
            image_contents,
            MapAny2XML(
              "profiles",
              Ops.get_map(_KiwiConfig, ["profiles", 0], {}),
              1
            )
          ),
          "\n"
        )
      end
      Builtins.foreach(Ops.get_list(_KiwiConfig, "sources", [])) do |source|
        sourcemap = get_source_value(source, _KiwiConfig)
        image_contents = Ops.add(
          Ops.add(image_contents, MapAny2XML("repository", sourcemap, 1)),
          "\n"
        )
      end
      Builtins.foreach(Ops.get_list(_KiwiConfig, "packages", [])) do |packagemap|
        if Builtins.size(Ops.get_list(packagemap, "opensusePattern", [])) == 0 &&
            Builtins.size(Ops.get_list(packagemap, "package", [])) == 0
          Builtins.y2milestone("no patterns/packages in %1", packagemap)
        end
        image_contents = Ops.add(
          Ops.add(image_contents, MapAny2XML("packages", packagemap, 1)),
          "\n"
        )
      end

      # now, add the rest, created using more generic MapAny2XML function
      if Builtins.haskey(_KiwiConfig, "split") &&
          Ops.greater_than(
            Builtins.size(Ops.get_list(_KiwiConfig, "split", [])),
            0
          )
        image_contents = Ops.add(
          Ops.add(
            image_contents,
            MapAny2XML("split", Ops.get_map(_KiwiConfig, ["split", 0], {}), 1)
          ),
          "\n"
        )
      end
      write_string = Builtins.sformat(
        "<?xml version=\"1.0\"?>\n%1\n%2</image>",
        image_tag,
        image_contents
      )


      @config_dir = Ops.add(
        Ops.add(@tmp_dir, "/"),
        Ops.get_string(
          _KiwiConfig,
          "original_directory",
          Ops.get_string(_KiwiConfig, "name", "")
        )
      )
      SCR.Execute(path(".target.mkdir"), @config_dir)
      SCR.Write(
        path(".target.string"),
        Ops.add(@config_dir, "/config.xml"),
        write_string
      )
      # config.xml may contain password, do not let other users read it
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("chmod 600 %1/config.xml", @config_dir)
      )

      Builtins.foreach(["root_dir", "config_dir"]) do |dir|
        Builtins.foreach(Ops.get_list(_KiwiConfig, dir, [])) do |val|
          realdir = Ops.add(
            Ops.add(@config_dir, "/"),
            Builtins.substring(dir, 0, Builtins.search(dir, "_"))
          )
          created = false
          if val != "" && FileUtils.Exists(val)
            if !created && !FileUtils.Exists(realdir)
              SCR.Execute(path(".target.mkdir"), realdir)
              created = true
            end
            SCR.Execute(
              path(".target.bash"),
              Builtins.sformat("cp -ar %1 %2/", val, realdir)
            )
          end
        end
      end
      Builtins.foreach(["images.sh", "config.sh", "root/build-custom"]) do |file|
        if Ops.get_string(_KiwiConfig, file, "") != ""
          SCR.Write(
            path(".target.string"),
            Ops.add(Ops.add(@config_dir, "/"), file),
            Ops.get_string(_KiwiConfig, file, "")
          )
          SCR.Execute(
            path(".target.bash"),
            Ops.add(Ops.add(Ops.add("chmod +x ", @config_dir), "/"), file)
          )
        end
      end
      Builtins.foreach(Ops.get_list(_KiwiConfig, "import_files", [])) do |file|
        Builtins.y2milestone("copying %1 to %2", file, @config_dir)
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("cp -ar %1 %2/", file, @config_dir)
        )
      end
      true
    end

    # for a given full path to directory, return the path one level up
    # (/a/b/c -> /a/b)
    def path_to_dir(full_path)
      # first, leave '/' from the end of string
      adapted = Ops.add(
        "/",
        Builtins.mergestring(
          Builtins.filter(Builtins.splitstring(full_path, "/")) { |p| p != "" },
          "/"
        )
      )
      Builtins.substring(full_path, 0, Builtins.findlastof(full_path, "/"))
    end

    # wait until process is really done or kill -9 it after minute
    def give_kiwi_time_to_finish(pid)
      count = 0
      while SCR.Read(path(".process.running"), pid) == true
        Builtins.sleep(100)
        count = Ops.add(count, 1)
        break if Ops.greater_than(count, 600)
      end
      if SCR.Read(path(".process.running"), pid) == true
        SCR.Execute(path(".process.kill"), pid)
      end

      nil
    end

    # ask user where to save kiwi log files
    def save_logs_popup
      dir = @logs_directory

      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(1.5),
          VBox(
            VSpacing(0.2),
            HBox(
              # text box label
              InputField(
                Id(:out_dir),
                Opt(:hstretch),
                _("Path to directory to store the log files"),
                dir
              ),
              VBox(Label(""), PushButton(Id(:browse), Label.BrowseButton))
            ),
            # text box label
            InputField(
              Id(:stdout_file),
              Opt(:hstretch),
              _("Standard output file name"),
              @stdout_file
            ),
            # text box label
            InputField(
              Id(:stderr_file),
              Opt(:hstretch),
              _("Error output file name"),
              @stderr_file
            ),
            VSpacing(0.2),
            ButtonBox(
              PushButton(Id(:ok), Label.SaveButton),
              PushButton(Id(:cancel), Label.CancelButton)
            ),
            VSpacing(0.2)
          ),
          HSpacing(1.5)
        )
      )

      ret = :cancel
      full_stdout = Ops.add(Ops.add(dir, "/"), @stdout_file)
      full_stderr = Ops.add(Ops.add(dir, "/"), @stderr_file)

      while true
        ret = UI.UserInput
        if ret == :cancel
          UI.CloseDialog
          break
        end
        if ret == :browse
          dir = Convert.to_string(UI.QueryWidget(Id(:out_dir), :Value))
          selected = UI.AskForExistingDirectory(dir, "")
          UI.ChangeWidget(Id(:out_dir), :Value, selected) if selected != nil
        end
        if ret == :ok
          dir = Convert.to_string(UI.QueryWidget(Id(:out_dir), :Value))
          full_stdout = Ops.add(
            Ops.add(dir, "/"),
            Convert.to_string(UI.QueryWidget(Id(:stdout_file), :Value))
          )
          full_stderr = Ops.add(
            Ops.add(dir, "/"),
            Convert.to_string(UI.QueryWidget(Id(:stderr_file), :Value))
          )
          if FileUtils.Exists(full_stdout) &&
              !Popup.YesNo(
                Builtins.sformat(
                  _("File %1 already exists.\nRewrite?"),
                  full_stdout
                )
              )
            next
          end
          if FileUtils.Exists(full_stderr) &&
              !Popup.YesNo(
                Builtins.sformat(
                  _("File %1 already exists.\nRewrite?"),
                  full_stderr
                )
              )
            next
          end
          break
        end
      end

      return false if ret == :cancel

      @stdout_file = Convert.to_string(UI.QueryWidget(Id(:stdout_file), :Value))
      @stderr_file = Convert.to_string(UI.QueryWidget(Id(:stderr_file), :Value))


      UI.CloseDialog

      if FileUtils.CheckAndCreatePath(dir)
        SCR.Write(
          path(".target.string"),
          full_stdout,
          Convert.to_string(UI.QueryWidget(Id(:log), :Value))
        )
      else
        return false
      end

      SCR.Write(
        path(".target.string"),
        full_stderr,
        Convert.to_string(UI.QueryWidget(Id(:errlog), :Value))
      )

      @logs_directory = dir

      true
    end

    # run kiwi to finally create the selected image
    # @param [String] out_dir output directory for the result
    # @param [String] selected_profiles which profiles should be build (prepared part
    # of command line option)
    def PrepareAndCreate(out_dir, selected_profiles)
      return false if @config_dir == "" || !FileUtils.Exists(@config_dir)
      if !Package.Install("kiwi")
        Report.Error(Message.CannotContinueWithoutPackagesInstalled)
        return false
      end

      if FileUtils.Exists(@chroot_dir)
        Builtins.y2milestone(
          "%1 directory is present, removing...",
          @chroot_dir
        )
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("rm -rf %1", @chroot_dir)
          )
        )
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2warning("cmd output: %1", out)
          Report.Error(
            Ops.add(
              _("Removing old chroot directory failed.") + "\n\n",
              Ops.get_string(out, "stderr", "")
            )
          )
          return false
        end
      end
      # create path to chroot_dir if it does not exist (#406731)
      FileUtils.CheckAndCreatePath(path_to_dir(@chroot_dir))
      # construct the dialog
      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(1.5),
          VBox(
            HSpacing(85),
            VWeight(
              2,
              VBox(
                VSpacing(0.5),
                ReplacePoint(
                  Id(:rpl),
                  # label
                  Left(Label(_("Preparing for Image Creation")))
                ),
                VSpacing(0.5),
                LogView(Id(:log), "", 8, 0)
              )
            ),
            VWeight(
              1,
              VBox(
                VSpacing(0.5),
                LogView(Id(:errlog), "", 8, 0),
                VSpacing(0.5),
                HBox(
                  ReplacePoint(
                    Id(:rp),
                    PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
                  ),
                  # button label
                  PushButton(Id(:save), _("Save logs"))
                ),
                VSpacing(0.5)
              )
            )
          ),
          HSpacing(1.5)
        )
      )

      UI.ChangeWidget(Id(:save), :Enabled, false)

      id = -1

      update_output = lambda do
        line = Convert.to_string(SCR.Read(path(".process.read_line"), id))
        if line != nil && line != ""
          UI.ChangeWidget(Id(:log), :LastLine, Ops.add(line, "\n"))
        end
        err = Convert.to_string(SCR.Read(path(".process.read_line_stderr"), id))
        if err != nil && err != ""
          UI.ChangeWidget(Id(:errlog), :LastLine, Ops.add(err, "\n"))
        end

        nil
      end

      linux32 = ""
      target_arch = "" # rather set target_arch only in one specific case
      if Arch.architecture == "x86_64" && ProductCreator.GetArch == "i386"
        linux32 = "linux32"
      end
      if ProductCreator.GetArch == "i386" && @target_i586
        target_arch = "--target-arch i586"
      end
      cmd = Builtins.sformat(
        "ZYPP_READONLY_HACK=1 %3 kiwi --nocolor --root %1 --prepare %2 --logfile terminal %4",
        @chroot_dir,
        @config_dir,
        linux32,
        target_arch
      )
      if selected_profiles != "" && selected_profiles != nil
        cmd = Ops.add(cmd, selected_profiles)
      end

      Builtins.y2milestone("calling '%1'", cmd)

      id = Convert.to_integer(SCR.Execute(path(".process.start_shell"), cmd))

      ret = nil
      creating = false
      begin
        ret = Convert.to_symbol(UI.PollInput)
        if SCR.Read(path(".process.running"), id) != true
          update_output.call
          # explicitely check the process buffer after exit (bnc#488799)
          buf = Convert.to_string(SCR.Read(path(".process.read"), id))
          err_buf = Convert.to_string(
            SCR.Read(path(".process.read_stderr"), id)
          )
          if buf != nil && buf != ""
            UI.ChangeWidget(Id(:log), :LastLine, Ops.add(buf, "\n"))
          end
          if err_buf != nil && err_buf != ""
            UI.ChangeWidget(Id(:errlog), :LastLine, Ops.add(err_buf, "\n"))
          end

          status = Convert.to_integer(SCR.Read(path(".process.status"), id))
          if status != 0
            UI.ReplaceWidget(
              Id(:rp),
              HBox(
                # label (command result)
                Label(Opt(:boldFont), _("Image creation failed.")),
                PushButton(Id(:close), Label.CloseButton)
              )
            )
            UI.ChangeWidget(Id(:save), :Enabled, true)
            begin
              ret = Convert.to_symbol(UI.UserInput)
              save_logs_popup if ret == :save
            end until ret == :close
            break
          elsif !creating
            creating = true
            SCR.Execute(path(".process.kill"), id) # just to be sure...

            # now continue with creating
            UI.ChangeWidget(Id(:log), :LastLine, "\n")
            cmd = Builtins.sformat(
              "ZYPP_READONLY_HACK=1 %3 kiwi --nocolor --create %1 -d %2 --logfile terminal %4",
              @chroot_dir,
              out_dir,
              linux32,
              target_arch
            )
            Builtins.y2milestone("calling '%1'", cmd)
            # label
            UI.ReplaceWidget(Id(:rpl), Left(Label(_("Creating Image"))))
            id = Convert.to_integer(
              SCR.Execute(path(".process.start_shell"), cmd)
            )
            ret = nil
            next
          else
            UI.ReplaceWidget(
              Id(:rp),
              HBox(
                # label (command result)
                Label(Opt(:boldFont), _("Image creation succeeded.")),
                PushButton(Id(:ok), Label.OKButton)
              )
            )
            UI.ChangeWidget(Id(:save), :Enabled, true)
            begin
              ret = Convert.to_symbol(UI.UserInput)
              save_logs_popup if ret == :save
            end until ret == :ok
            break
          end
        else
          update_output.call
        end
        if ret == :cancel
          UI.ReplaceWidget(
            Id(:rp),
            HBox(
              # label (command result)
              Label(Opt(:boldFont), _("Image creation canceled.")),
              PushButton(Id(:close), Label.CloseButton)
            )
          )
          SCR.Execute(path(".process.kill"), id, 15)
          give_kiwi_time_to_finish(id)
          UI.ChangeWidget(Id(:save), :Enabled, true)
          begin
            ret = Convert.to_symbol(UI.UserInput)
            save_logs_popup if ret == :save
          end until ret == :close
          break
        end
        Builtins.sleep(100)
      end while ret == nil

      give_kiwi_time_to_finish(id)

      UI.CloseDialog
      ret == :ok
    end

    # save the image configuration to the kiwi images directory
    def SaveConfiguration(_KiwiConfig, task)
      _KiwiConfig = deep_copy(_KiwiConfig)
      return nil if @config_dir == "" || !FileUtils.Exists(@config_dir)
      if !FileUtils.Exists(@images_dir)
        SCR.Execute(path(".target.mkdir"), @images_dir)
      end
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("cp -ar %1 %2/", @config_dir, @images_dir)
      )
      Ops.add(
        Ops.add(@images_dir, "/"),
        Ops.get_string(_KiwiConfig, "name", "")
      )
    end

    # Import repositories from given kiwi image configuration
    # @patam Config configuration map, as read from config.xml
    # @param [String] dir path to directory containing this config.xml
    def ImportImageRepositories(_Config, dir)
      _Config = deep_copy(_Config)
      @current_repositories = {}
      Builtins.foreach(Ops.get_list(_Config, "repository", [])) do |repo|
        source = Ops.get_string(repo, ["source", 0, "path"], "")
        if source != ""
          url = ""
          if Builtins.substring(source, 0, 7) == "this://"
            source_path = Builtins.substring(source, 7)
            source = Ops.add(Ops.add(dir, "/"), source_path)
          end
          url = "dir://" if Builtins.substring(source, 0, 1) == "/"
          url = Ops.add(url, source)
          parsed = URL.Parse(url)
          full_url = url
          if Ops.get_string(parsed, "pass", "") != ""
            parsed = Builtins.remove(parsed, "pass")
            url = URL.Build(parsed)
          end
          Ops.set(
            @current_repositories,
            url,
            {
              "url"      => url,
              "plaindir" => Ops.get_string(repo, "type", "") == "rpm-dir",
              "org"      => repo,
              "full_url" => full_url
            }
          )
        end
      end
      deep_copy(@current_repositories)
    end

    # Initialize the list of current repositories
    def InitCurrentRepositories
      @current_repositories = {}
      Pkg.SourceRestore
      Builtins.foreach(Pkg.SourceEditGet) do |source|
        srcid = Ops.get_integer(source, "SrcId", -1)
        data = Pkg.SourceGeneralData(srcid)
        url = Ops.get_string(data, "url", "")
        full_url = url
        parsed = URL.Parse(url)
        if Ops.get_string(parsed, "scheme", "") == "https"
          full_url = Pkg.SourceURL(srcid)
        end
        Ops.set(
          @current_repositories,
          url,
          {
            "url"      => url,
            "plaindir" => Ops.get_string(data, "type", "") == "Plaindir",
            "full_url" => full_url
          }
        )
      end
      deep_copy(@current_repositories)
    end

    # Read the templates on which the images can be based
    def ReadImageTemplates
      dirs = Convert.to_string(
        SCR.Read(path(".sysconfig.product-creator.IMAGE_TEMPLATES"))
      )
      name_version = {}
      Builtins.foreach(Builtins.splitstring(dirs, "\t ")) do |line|
        next if line == "" || Builtins.substring(line, 0, 1) == "#"
        @templates_dirs = Builtins.add(@templates_dirs, line)
        if !FileUtils.IsDirectory(line)
          Builtins.y2warning("%1 is not a directory", line)
          next
        end
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("ls -A1 %1", line)
          )
        )
        Builtins.foreach(
          Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
        ) do |d|
          next if d == ""
          config = ReadConfigXML(Ops.add(Ops.add(line, "/"), d))
          # index by full path, there may be same names
          # (templates could be provided by different vendors)
          if config != nil && config != {}
            name = Ops.get_string(config, "name", "")
            ver = get_preferences(config, "version", "")
            if Ops.get_string(config, ["description", 0, "type"], "") != "system"
              Builtins.y2warning("%1 not a 'system' image type, skipping", name)
            elsif Ops.get(name_version, name) == ver
              Builtins.y2warning("template %1,%2 already imported", name, ver)
            else
              Ops.set(name_version, name, ver)
              Ops.set(@Templates, Ops.add(Ops.add(line, "/"), d), config)
            end
          end
        end
      end
      true
    end

    # REad the confgiuration stuff for image creator
    def Read
      dir = Convert.to_string(
        SCR.Read(path(".sysconfig.product-creator.IMAGE_CONFIGURATIONS"))
      )
      @images_dir = dir if dir != nil && dir != ""
      @supported_boot_images = Convert.to_string(
        SCR.Read(path(".sysconfig.product-creator.SUPPORTED_BOOT_IMAGES"))
      )
      @supported_boot_images = "" if @supported_boot_images == nil
      architecture = Convert.to_string(
        SCR.Read(path(".sysconfig.product-creator.DEFAULT_IMAGE_ARCHITECTURE"))
      )
      if architecture == "" || architecture == nil
        architecture = ProductCreator.GetArch
      end
      if architecture != "x86_64" # all i[456]86 are i386...
        architecture = "i386"
      end
      @image_architecture = architecture
      ReadImageTemplates()
    end

    publish :variable => :content_key, :type => "string"
    publish :variable => :default_size, :type => "string"
    publish :variable => :tmp_dir, :type => "string"
    publish :variable => :images_dir, :type => "string"
    publish :variable => :supported_boot_images, :type => "string"
    publish :variable => :image_architecture, :type => "string"
    publish :variable => :target_i586, :type => "boolean"
    publish :variable => :templates_dirs, :type => "list <string>"
    publish :variable => :default_packagemanager, :type => "string"
    publish :variable => :current_repositories, :type => "map <string, map>"
    publish :variable => :initial_repositories, :type => "map <string, map>"
    publish :variable => :kiwi_task, :type => "string"
    publish :variable => :Templates, :type => "map <string, map>"
    publish :variable => :all_locales, :type => "map <string, integer>"
    publish :variable => :all_timezones, :type => "list <string>"
    publish :function => :ReadAliases, :type => "map <string, string> (boolean)"
    publish :function => :ReadConfigXML, :type => "map <string, any> (string)"
    publish :function => :WriteConfigXML, :type => "boolean (map <string, any>, string)"
    publish :function => :PrepareAndCreate, :type => "boolean (string, string)"
    publish :function => :SaveConfiguration, :type => "string (map, string)"
    publish :function => :ImportImageRepositories, :type => "map <string, map> (map, string)"
    publish :function => :InitCurrentRepositories, :type => "map <string, map> ()"
    publish :function => :ReadImageTemplates, :type => "boolean ()"
    publish :function => :Read, :type => "boolean ()"
  end

  Kiwi = KiwiClass.new
  Kiwi.main
end
