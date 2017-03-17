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

# File:	modules/ProductCreator.ycp
# Package:	Configuration of product-creator
# Summary:	Data for configuration of product-creator, input and output functions.
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
#
# Representation of the configuration of product-creator.
# Input and output routines.
require "yast"

module Yast
  class ProductCreatorClass < Module
    include Yast::Logger

    # @return [Array<Integer>] Temporarily enabled repositories
    attr_accessor :tmp_enabled

    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "product-creator"

      Yast.import "AddOnCreator"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "XML"
      Yast.import "URL"
      Yast.import "Profile"
      Yast.import "Misc"
      Yast.import "Directory"
      Yast.import "AutoinstSoftware"
      # NOTE: do not use Arch:: directly in this module, use GetArch() function instead!
      Yast.import "Arch"
      Yast.import "Package"
      Yast.import "PackageAI"
      Yast.import "Popup"
      Yast.import "String"
      Yast.import "SourceManager"
      Yast.import "GPG"
      Yast.import "GPGWidgets"
      Yast.import "Mode"
      Yast.import "CommandLine"
      Yast.import "FileUtils"
      Yast.import "PackageCallbacks"

      @old_enabled = []

      # content file cache - avoid multiple content file downloading
      @content_cache = {}

      @AYRepository = ""

      @meta = {}
      @meta_local = {}

      @missing_packages = []

      # packages to copy
      # $[ source_id : $[ media_id : list<packages> ] ]
      @toCopy = {}

      # Local variables

      @skel_root = ""


      @profile_parsed = false

      @max_size_mb = 999 * 1024

      # Configuration Map
      @Config = {}

      # All Configurations
      @Configs = {}

      # Configuration Repository
      @Rep = "/var/lib/YaST2/cd-creator"

      # Configuration file
      @ConfigFile = Ops.add(@Rep, "/cdcreator.xml")

      @gpg_passphrase = ""

      @pattern_descr = nil


      # Abort function
      # return boolean return true if abort
      @AbortFunction = nil

      # default is the system architecture
      @_arch = nil


      # Data was modified?
      @modified = false

      @proposal_valid = false

      # if the YaST sources should be enabled when opening package selector
      @enable_sources = true

      # original source configuration, needed to reset the package manager
      @original_config = nil

      @gzip_is_installed = nil

      # map additional products to "Addon" directory
      @product_map = {}

      # temporarily enabled repositories
      @tmp_enabled = []

      ProductCreator()
    end

    def ToPackageArch(arch)
      arch = "s390x" if arch == "s390_64"
      arch = "s390" if arch == "s390_32"

      if !Builtins.contains(
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
          ],
          arch
        )
        Builtins.y2error("Unknown architecture '%1'!", arch)
        return nil
      end

      arch
    end

    #   Set the target package architecture
    #   @param [String] new_arch new architecture (i386, i486, i586, i686, sparc, sparc64, mips, mips64, ppc, ppc64, alpha, s390, s390x, ia64, x86_64)
    #   @return true on success
    def SetPackageArch(new_arch)
      pkgarch = ToPackageArch(new_arch)

      return false if pkgarch == nil

      @_arch = pkgarch
      Builtins.y2milestone("Target architecture set to '%1'", new_arch)

      # set the architecture in the package manager
      Pkg.SetArchitecture(@_arch)

      true
    end

    # convert package (like i686) arch to system arch (i386)
    def GetArch
      ret = @_arch

      # not set, use the current arch
      ret = Arch.architecture if ret == nil

      # convert x86 package archs to i386 system arch
      if Builtins.contains(["i486", "i586", "i686"], ret)
        ret = "i386"
      elsif ret == "s390_64"
        ret = "s390x"
      elsif ret == "s390_32"
        ret = "s390"
      end

      ret
    end

    # nil means not set
    def GetPackageArch
      @_arch
    end

    def ResetArch
      @_arch = nil

      if Pkg.GetArchitecture != Pkg.SystemArchitecture
        # set the system architecture in the package manager
        Builtins.y2milestone(
          "Resetting the target architecture to '%1'",
          Pkg.SystemArchitecture
        )
        Pkg.SetArchitecture(Pkg.SystemArchitecture)
      end

      nil
    end

    def gzip_installed
      if @gzip_is_installed == nil
        @gzip_is_installed = Package.Installed("gzip")
      end
      @gzip_is_installed
    end

    # Data was modified?
    # @return true if modified
    def Modified
      Builtins.y2debug("modified=%1", @modified)
      @modified
    end

    # Abort function
    # @return blah blah lahjk
    def Abort
      return Builtins.eval(@AbortFunction) == true if @AbortFunction != nil
      false
    end

    # Check for pending Abort press
    # @return true if pending abort
    def PollAbort
      UI.PollInput == :abort
    end

    # If modified, ask for confirmation
    # @return true if abort is confirmed
    def ReallyAbort
      !Modified() || Popup.ReallyAbort(true)
    end

    # Progress::NextStage and Progress::Title combined into one function
    # @param [String] title progressbar title
    def ProgressNextStage(title)
      Progress.NextStage
      Progress.Title(title)

      nil
    end




    # set the packages to 'taboo' state
    def MarkTaboo(packages_taboo)
      packages_taboo = deep_copy(packages_taboo)
      # remove packages (set to taboo)
      if packages_taboo != nil &&
          Ops.greater_than(Builtins.size(packages_taboo), 0)
        Builtins.foreach(packages_taboo) do |p|
          Builtins.y2milestone(
            "marking taboo package: %1 -> %2",
            p,
            Pkg.PkgTaboo(p)
          )
        end
      end

      nil
    end


    def autoyastPackages
      base_selection = ""
      # busy message
      feedback = _("Reading data from Package Database...")
      if Mode.commandline
        CommandLine.PrintVerbose(feedback)
      else
        # popup
        Popup.ShowFeedback(feedback, _("Please wait..."))
      end

      Pkg.TargetFinish
      tmp = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      SCR.Execute(path(".target.mkdir"), Ops.add(tmp, "/tmproot"))
      Pkg.TargetInit(Ops.add(tmp, "/tmproot"), true)

      success = EnableSource()

      # Pkg::SourceStartManager(true);

      if Ops.get_string(@Config, "profile", "") != "" && !@profile_parsed
        if !readControlFile(Ops.get_string(@Config, "profile", ""))
          return :overview
        end
        # set the new selection
        Builtins.y2debug("Config: %1", @Config)

        if Ops.get_symbol(@Config, "type", :unknown) == :patterns
          base_pat = Ops.get_string(@Config, "base", "")

          if Ops.greater_than(Builtins.size(base_pat), 0)
            Pkg.ResolvableInstall(base_pat, :pattern)
            Builtins.y2milestone("Selecting pattern: %1", base_pat)
          end

          if Ops.greater_than(
              Builtins.size(Ops.get_list(@Config, "addons", [])),
              0
            )
            Builtins.foreach(Ops.get_list(@Config, "addons", [])) do |addon|
              Pkg.ResolvableInstall(addon, :pattern)
              Builtins.y2milestone("Selecting pattern: %1", addon)
            end
          end
        else
          Builtins.y2warning(
            "Unsupported software selection type: %1",
            Ops.get_symbol(@Config, "type", :unknown)
          )
        end

        if Ops.greater_than(
            Builtins.size(Ops.get_list(@Config, "packages", [])),
            0
          )
          Builtins.foreach(Ops.get_list(@Config, "packages", [])) do |p|
            Builtins.y2milestone(
              "selecting package for installation: %1 -> %2",
              p,
              Pkg.PkgInstall(p)
            )
          end
        end

        # mark taboo packages
        MarkTaboo(Ops.get_list(@Config, "taboo", []))

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

    def LoadConfig(config_name)
      @Config = Ops.get(@Configs, config_name, {})

      Builtins.haskey(@Configs, config_name)
    end

    def CommitConfig
      autoyastPackages if Ops.get_string(@Config, "profile", "") != ""

      name = Ops.get_string(@Config, "name", "")
      old_name = Ops.get_string(@Config, "old_name", "")

      if Builtins.haskey(@Configs, old_name) && old_name != ""
        @Configs = Builtins.filter(@Configs) { |k, v| k != old_name }
        Builtins.remove(@Config, "old_name")
      end

      Ops.set(@Configs, name, @Config)

      nil
    end


    def PackageCount
      ret = 0

      Builtins.foreach(@toCopy) do |source, srcmapping|
        Builtins.foreach(srcmapping) do |medium, packages|
          ret = Ops.add(ret, Builtins.size(packages))
        end
      end 


      ret
    end


    def UrlToId(urls)
      urls = deep_copy(urls)
      # all sources
      all = Pkg.SourceGetCurrent(false)

      sources = Builtins.maplist(urls) do |url|
        id = -1
        Builtins.foreach(all) do |i|
          generalData = Pkg.SourceGeneralData(i)
          if Ops.get_string(generalData, "url", "") == url
            id = i
            raise Break
          end
        end
        Builtins.y2error("Source %1 not found!", url) if id == -1
        id
      end

      Builtins.y2milestone("URL to repoid: %1 -> %2", urls, sources)

      deep_copy(sources)
    end


    def ReadContentFile(srcid)
      if Builtins.haskey(@content_cache, srcid)
        return Ops.get(@content_cache, srcid, {})
      end

      # make content file optional (for empty repos, bnc#500527)
      content = Pkg.SourceProvideOptionalFile(srcid, 1, "content")
      contentmap = Convert.convert(
        SCR.Read(path(".content_file"), content),
        :from => "any",
        :to   => "map <string, string>"
      )
      contentmap = {} if contentmap == nil
      Ops.set(@content_cache, srcid, contentmap)
      Builtins.y2debug("content_cache: %1", @content_cache)

      deep_copy(contentmap)
    end


    # Read all product-creator settings
    # @return true on success
    def Read
      # ProductCreator read dialog caption
      caption = _("Initializing Product Creator Configuration")

      steps = 1

      sl = 2
      Builtins.sleep(sl)

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # translators: progress stage 1/1
          _("Read the configuration")
        ],
        [
          # translators: progress step 1/1
          _("Reading the database..."),
          # translators: progress finished
          _("Finished")
        ],
        ""
      )

      # read database
      return false if Abort()
      Progress.NextStage

      c = {}
      if SCR.Read(path(".target.size"), @ConfigFile) != -1
        c = XML.XMLToYCPFile(@ConfigFile)
      end
      all = Ops.get_list(c, "configurations", [])
      @Configs = Builtins.listmap(all) do |i|
        name = Ops.get_string(i, "name", "")
        { name => i }
      end
      Builtins.y2milestone("Configs: %1", @Configs)

      # translators: error message
      Report.Error(_("Cannot read the configuration.")) if false
      Builtins.sleep(sl)


      return false if Abort()
      # translators: progress finished
      ProgressNextStage(_("Finished"))
      Builtins.sleep(sl)

      return false if Abort()
      @modified = false
      true
    end



    # Prepare map for writing  into XML
    # @return [Array]s of configurations
    def PrepareConfigs
      c = Builtins.maplist(@Configs) do |k, v|
        sources = Ops.get_list(v, "sources", [])
        # escape XML entities in URL
        # (e.g. iso:///?iso=image.iso&url=file:///local/images/ cannot be stored by the XML agent)
        if Ops.greater_than(Builtins.size(sources), 0)
          sources = Builtins.maplist(sources) { |src| String.EscapeTags(src) }

          Ops.set(v, "sources", sources)
        end
        base_repo = Ops.get_string(v, "base_repo", "")
        Ops.set(v, "base_repo", String.EscapeTags(base_repo)) if base_repo != ""
        deep_copy(v)
      end
      deep_copy(c)
    end

    # Write all product-creator settings
    # @return true on success
    def Write
      # ProductCreator read dialog caption
      caption = _("Saving Product Creator Configuration")

      steps = 2

      sl = 50
      Builtins.sleep(sl)

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # translators: progress stage 1/2
          _("Write the settings")
        ],
        [
          # translators: progress step 1/1
          _("Writing the settings..."),
          # translators: progress finished
          _("Finished")
        ],
        ""
      )

      # write settings
      return false if Abort()
      Progress.NextStage

      c = PrepareConfigs()
      xml = { "configurations" => c }

      if Ops.less_than(SCR.Read(path(".target.size"), @Rep), 0)
        SCR.Execute(path(".target.bash"), Ops.add("mkdir -p ", @Rep))
      end

      Builtins.y2milestone("Writing XML file %1: %2", @ConfigFile, xml)
      ret = XML.YCPToXMLFile(:cdcreator, xml, @ConfigFile)

      # translators: error message
      Report.Error(_("Error while writing settings.")) if !ret

      Progress.NextStage

      return false if Abort()
      # translators: progress finished
      ProgressNextStage(_("Finished"))
      Builtins.sleep(sl)

      return false if Abort()
      true
    end

    # Get all product-creator settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      true
    end

    # Dump the product-creator settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      {}
    end

    # Create a textual summary and a list of unconfigured cards
    # @return summary of the current configuration
    def Summary
      # translators: Configuration summary text for autoyast
      [_("Configuration summary ..."), []]
    end

    # Create an overview table with all configured cards
    # @return table items
    def Overview
      Builtins.y2milestone("Configs: %1", @Configs)
      overview = Builtins.maplist(@Configs) do |name, cfg|
        isofile = Ops.add(
          Ops.add(Ops.get_string(cfg, "iso-directory", ""), "/"),
          Ops.get_string(cfg, "isofile", "")
        )
        if Ops.less_than(SCR.Read(path(".target.size"), isofile), 0)
          isofile = _("No Files")
        end
        Item(
          Id(name),
          name,
          Ops.get_string(cfg, "product", ""),
          isofile,
          Ops.get_string(cfg, "gpg_key", "")
        )
      end
      deep_copy(overview)
    end


    # Get media urls
    # @param list list of ids
    # @return [Array] list of urls
    def getSourceURLs(ids)
      ids = deep_copy(ids)
      urls = Builtins.maplist(ids) do |i|
        media = Pkg.SourceGeneralData(i)
        Ops.get_string(media, "url", "")
      end

      deep_copy(urls)
    end


    # get path to directory source
    # @param [String] url
    # @return [String] path
    def getSourceDir(url)
      urlsegs = URL.Parse(url)
      Ops.get_string(urlsegs, "path", "")
    end

    # Return contents of isolinux.cfg from the given source
    # @return [String] with contents of file.
    def Readisolinux
      bootconfig = Ops.get_string(@Config, "bootconfig", "")
      return bootconfig if bootconfig != ""

      bootconfig_path = ""
      if Ops.get_string(@Config, "pkgtype", "") == "autoyast"
        bootconfig_path = Builtins.sformat(
          "%1/product-creator/isolinux.cfg",
          Directory.datadir
        )
      else
        arch = GetArch()
        arch = "s390x" if arch == "s390_64"
        bootconfig_path = Builtins.sformat("boot/%1/loader/isolinux.cfg", arch)


        srcids = []
        # bnc#496263
        if Ops.get_string(@Config, "base_repo", "") == ""
          srcids = [checkProductDependency]
        else
          srcids = UrlToId([Ops.get_string(@Config, "base_repo", "")])
        end

        Builtins.foreach(srcids) do |srcid|
          Builtins.y2milestone(
            "Downloading %1 from source %2",
            bootconfig_path,
            srcid
          )
          bootconfig_path = Pkg.SourceProvideOptionalFile(
            Ops.get(srcids, 0, 0),
            1,
            bootconfig_path
          )
          Builtins.y2debug("bootconfig_path: %1", bootconfig_path)
          if bootconfig_path == nil
            # try the old path as a fallback
            bootconfig_path = "boot/loader/isolinux.cfg"
            bootconfig_path = Pkg.SourceProvideOptionalFile(
              Ops.get(srcids, 0, 0),
              1,
              bootconfig_path
            )
            Builtins.y2debug("bootconfig_path: %1", bootconfig_path)

            raise Break if bootconfig_path != nil
          else
            Builtins.y2milestone("Found bootconfig in source %1", srcid)
            raise Break
          end
        end
      end
      if Ops.greater_or_equal(
          SCR.Read(path(".target.size"), bootconfig_path),
          0
        )
        bootconfig = Convert.to_string(
          SCR.Read(path(".target.string"), bootconfig_path)
        )
      else
        Builtins.y2error("cannot read file %1", bootconfig_path)
      end


      # replace tabs by spaces in ncurses UI (workaround for #142509)
      if Ops.get_boolean(UI.GetDisplayInfo, "TextMode", false) == true
        # tab -> 8 spaces
        bootconfig = String.Replace(bootconfig, "\t", "        ")
      end

      bootconfig
    end

    # Create XML Configuration
    def configSetup
      doc = {}
      Ops.set(
        doc,
        "listEntries",
        {
          "packages"       => "package",
          "addons"         => "addon",
          "configurations" => "config"
        }
      )
      Ops.set(doc, "cdataSections", ["bootconfig"])
      Ops.set(doc, "rootElement", "product-creator")
      Ops.set(doc, "systemID", "/usr/share/autoinstall/dtd/product-creator.dtd")
      Ops.set(doc, "nameSpace", "http://www.suse.com/1.0/yast2ns")
      Ops.set(doc, "typeNamespace", "http://www.suse.com/1.0/configns")
      XML.xmlCreateDoc(:cdcreator, doc)
      nil
    end

    def ExportPublicKey(keyid, dir)
      Builtins.y2debug("ExportPublicKey: %1 to %2", keyid, dir)
      # export the public key
      ret = GPG.ExportAsciiPublicKey(keyid, Ops.add(dir, "/content.key"))

      # export the public key
      ret = ret &&
        GPG.ExportAsciiPublicKey(keyid, Ops.add(dir, "/media.1/products.key"))

      # export the public key
      ret = ret &&
        GPG.ExportAsciiPublicKey(
          keyid,
          Ops.add(
            dir,
            Builtins.sformat("/gpg-pubkey-%1.asc", Builtins.tolower(keyid))
          )
        )

      Builtins.y2milestone("exported public key %1: %2", keyid, ret)
      ret
    end

    def SignSourceFiles(keyid, dir, passphrase)
      # sign the content file
      ret = GPG.SignAsciiDetached(keyid, Ops.add(dir, "/content"), passphrase)

      # sign the product file if exists
      if FileUtils.Exists(Ops.add(dir, "/media.1/products"))
        ret = ret &&
          GPG.SignAsciiDetached(
            keyid,
            Ops.add(dir, "/media.1/products"),
            passphrase
          )
      end

      # sign the add_on_products file
      if FileUtils.Exists(Ops.add(dir, "/add_on_products"))
        ret = ret &&
          GPG.SignAsciiDetached(
            keyid,
            Ops.add(dir, "/add_on_products"),
            passphrase
          )
      end

      Builtins.y2milestone("Signed source: %1", ret)
      ret
    end

    def SHA1Meta(dir, product_dir)
      # generate new sha1 sums for files in descr subdirectory
      # remove './' from the file names, ignore directory.yast file, sort the output
      command = Builtins.sformat(
        "(cd '%1/%2' && find . -type f -exec sha1sum \\{\\} \\; | sed -e 's#^\\(.\\{40\\}\\)  ./#META SHA1 \\1  #' | grep -v '^.\\{40\\}  directory.yast$' | LC_ALL=C sort -k 2)",
        String.Quote(dir),
        String.Quote(product_dir)
      )

      Builtins.y2milestone("Generating SHA1 sums: %1", command)

      # execute the command
      ret = Convert.to_map(SCR.Execute(path(".target.bash_output"), command))
      Builtins.y2milestone("Result: %1", ret)
      meta_sha1 = Ops.get_string(ret, "stdout", "")

      meta_sha1
    end

    def SHA1Key(dir)
      # generate new sha1 sums for files in descr subdirectory
      # remove './' from the file names, ignore directory.yast file, sort the output
      command = Builtins.sformat(
        "(cd '%1' && find . -type f -name 'gpg-pubkey-*.asc' -exec sha1sum \\{\\} \\; | sed -e 's#^\\(.\\{40\\}\\)  ./#KEY SHA1 \\1  #' | LC_ALL=C sort -k 2)",
        String.Quote(dir)
      )

      Builtins.y2milestone("Generating SHA1 key sums: %1", command)

      # execute the command
      ret = Convert.to_map(SCR.Execute(path(".target.bash_output"), command))
      Builtins.y2milestone("Result: %1", ret)
      key_sha1 = Ops.get_string(ret, "stdout", "")

      key_sha1
    end

    def UpdateContentFile(dir, prod_dir)
      ret = true

      meta_sha1 = SHA1Meta(dir, prod_dir)
      key_sha1 = SHA1Key(dir)

      # add the sum of add_on_products if it was created
      if FileUtils.Exists(Ops.add(dir, "/add_on_products"))
        command2 = Builtins.sformat("cd %1; sha1sum add_on_products", dir)
        Builtins.y2milestone(
          "Generating SHA1 sum for add_on_products: %1",
          command2
        )
        ret2 = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), command2)
        )
        Builtins.y2milestone("Result: %1", ret2)
        meta_sha1 = Ops.add(
          Ops.add(meta_sha1, "HASH SHA1 "),
          Ops.get_string(ret2, "stdout", "")
        )
      end

      command = Builtins.sformat(
        "/usr/bin/grep -v -e '^KEY ' -e '^META ' '%1/content'",
        String.Quote(dir)
      )
      out = Convert.to_map(SCR.Execute(path(".target.bash_output"), command))
      return false if Ops.get_integer(out, "exit", -1) != 0

      read_content = Ops.get_string(out, "stdout", "")
      Builtins.y2debug("content file: %1", read_content)

      # add trailing new line char if it's missing
      if Ops.greater_than(Builtins.size(read_content), 0) &&
          Builtins.substring(
            read_content,
            Ops.subtract(Builtins.size(read_content), 1),
            1
          ) != "\n"
        read_content = Ops.add(read_content, "\n")
      end

      # add trailing new line char if it's missing
      if Ops.greater_than(Builtins.size(meta_sha1), 0) &&
          Builtins.substring(
            meta_sha1,
            Ops.subtract(Builtins.size(meta_sha1), 1),
            1
          ) != "\n"
        meta_sha1 = Ops.add(meta_sha1, "\n")
      end

      # concatenate the meta and the key sums
      read_content = Ops.add(Ops.add(read_content, meta_sha1), key_sha1)
      Builtins.y2debug("new content file: %1", read_content)

      # write the file
      ret = SCR.Write(
        path(".target.string"),
        Ops.add(dir, "/content"),
        read_content
      )
      Builtins.y2milestone(
        "Updated content file %1: %2",
        Ops.add(dir, "/content"),
        ret
      )

      ret
    end

    # execute a command
    def Exec(command)
      Builtins.y2milestone("executing: %1", command)
      ret = Convert.to_integer(SCR.Execute(path(".target.bash"), command))

      if ret == 0
        Builtins.y2milestone("result: %1", ret)
      else
        Builtins.y2error("result: %1", ret)
      end

      ret == 0
    end

    def UpdateMD5File(directory)
      command = Builtins.sformat(
        "/bin/sh /usr/bin/create_md5sums '%1'",
        String.Quote(directory)
      )

      if Builtins.issubstring(directory, " ")
        command = Builtins.sformat(
          "cd '%1'; rm MD5SUMS; md5sum -- * > MD5SUMS",
          String.Quote(directory)
        )
      end
      ret = Exec(command)

      Builtins.y2milestone("MD5SUMS updated: %1", ret)

      ret
    end

    def CopyFile(srcid, mid, src, target)
      local_file = Pkg.SourceProvideFile(srcid, mid, src)
      Builtins.y2debug("local_file: %1", local_file)

      Exec(
        Builtins.sformat(
          "/bin/cp -a -f -- '%1' '%2'",
          String.Quote(local_file),
          String.Quote(target)
        )
      )
    end

    def CopyOptionalFile(srcid, mid, src, target)
      local_file = Pkg.SourceProvideOptionalFile(srcid, mid, src)
      Builtins.y2debug("local_file: %1", local_file)

      if local_file != nil && local_file != ""
        return Exec(
          Builtins.sformat(
            "/bin/cp -a -f -- '%1' '%2'",
            String.Quote(local_file),
            String.Quote(target)
          )
        )
      else
        Builtins.y2warning(
          "Optional file [%1:%2]%3 is missing",
          srcid,
          mid,
          src
        )
      end

      true
    end

    def CopyDirectoryR(srcid, mid, src, target, optional)
      Builtins.y2milestone(
        "CopyDirectoryRec: srcid: %1, mid: %2, src: %3, target: %4",
        srcid,
        mid,
        src,
        target
      )

      local_dir = Pkg.SourceProvideDirectory(srcid, mid, src, optional, true)
      Builtins.y2milestone("local_dir: %1", local_dir)

      if local_dir == nil || local_dir == ""
        if !optional
          # an error message, %1 is the directory, %2 is URL of the source
          Report.Error(
            Builtins.sformat(
              _("Cannot read directory %1\nfrom source %2."),
              src,
              Ops.get_string(Pkg.SourceGeneralData(srcid), "url", "")
            )
          )
        end

        return false
      end

      Exec(
        Builtins.sformat(
          "/bin/cp -a -f -- '%1' '%2'",
          String.Quote(local_dir),
          String.Quote(target)
        )
      )
    end

    def CopyDirectoryRec(srcid, mid, src, target)
      CopyDirectoryR(srcid, mid, src, target, false)
    end

    def CopyDirectoryRecOpt(srcid, mid, src, target)
      CopyDirectoryR(srcid, mid, src, target, true)
    end

    def GetList(srcid, mid, dir)
      # get file list from directory.yast
      file_list = Pkg.SourceProvideOptionalFile(
        srcid,
        mid,
        Builtins.sformat("%1/directory.yast", dir)
      )

      if file_list == nil || file_list == ""
        Builtins.y2error("directory.yast was not found, a YUM source?")
        return nil
      end

      f = Convert.to_string(SCR.Read(path(".target.string"), file_list))
      files = Builtins.splitstring(f, "\n")
      Builtins.y2milestone("Remote objects: %1", files)

      deep_copy(files)
    end

    def CopyDirectoryNonRec(srcid, mid, src, target)
      # get file list from directory.yast
      files = GetList(srcid, mid, "")
      files = [] if files == nil

      files = Builtins.filter(files) do |file|
        !Builtins.regexpmatch(file, "/$") && file != ""
      end
      Builtins.y2milestone("Remote files: %1", files)

      Builtins.foreach(files) do |remote_file|
        # copy the file as optional, the directory.yast file can be broken
        CopyOptionalFile(
          srcid,
          mid,
          Builtins.sformat("%1/%2", src, remote_file),
          Builtins.sformat("%1/%2", target, remote_file)
        )
      end 


      true
    end

    def CopyDocu(srcid, target)
      lst = GetList(srcid, 1, "")
      lst = [] if lst == nil

      ret = true

      if Builtins.contains(lst, "docu/")
        Builtins.y2milestone("Copying /docu subdirectory")
        Exec(Builtins.sformat("/bin/mkdir -p '%1/docu'", String.Quote(target)))

        r = CopyDirectoryRecOpt(srcid, 1, "/docu", target)

        if !r
          files = ["docu/RELEASE-NOTES.en.html", "docu/RELEASE-NOTES.en.rtf"]

          Builtins.y2milestone(
            "Directory listing may be missing using fixed list: %1",
            files
          )

          Builtins.foreach(files) do |f|
            CopyOptionalFile(srcid, 1, f, Ops.add(target, f))
          end
        end

        ret = ret && r
      end

      ret
    end

    def CopyPPCBoot(srcid, target)
      Builtins.y2milestone("Copying PPC boot files")
      ret = true

      Builtins.y2milestone("Copying /ppc subdirectory")
      r = CopyDirectoryRecOpt(srcid, 1, "/ppc", target)

      if !r
        Builtins.y2milestone(
          "Directory listing may be missing, copying /ppc/bootinfo.txt"
        )
        CopyFile(srcid, 1, "/ppc/bootinfo.txt", Ops.add(target, "/ppc"))
      end

      ret = ret && r


      Builtins.y2milestone("Copying /PS3 subdirectory")
      r = CopyDirectoryRecOpt(srcid, 1, "/PS3", target)

      if !r
        Builtins.y2milestone(
          "Directory listing may be missing, copying /ppc/bootinfo.txt"
        )
        Exec(
          Builtins.sformat(
            "/bin/mkdir -p '%1/PS3/otheros'",
            String.Quote(target)
          )
        )
        CopyOptionalFile(
          srcid,
          1,
          "/PS3/otheros/otheros.bld",
          Ops.add(target, "/PS3/otheros")
        )
      end

      ret = ret && r


      Builtins.y2milestone("Copying /suseboot subdirectory")
      r = CopyDirectoryRecOpt(srcid, 1, "/suseboot", target)
      Builtins.y2milestone("Result: %1", r)

      if !r
        files = [
          "/suseboot/inst32",
          "/suseboot/inst64",
          "/suseboot/os-chooser",
          "/suseboot/yaboot",
          "/suseboot/yaboot.cnf",
          "/suseboot/yaboot.ibm",
          "/suseboot/yaboot.txt"
        ]

        Builtins.y2milestone(
          "Directory listing may be missing using fixed list: %1",
          files
        )

        Builtins.foreach(files) do |f|
          CopyOptionalFile(srcid, 1, f, Ops.add(target, f))
        end
      end


      Builtins.y2milestone("Copying /etc subdirectory")
      r = CopyDirectoryRecOpt(srcid, 1, "/etc", target)

      if !r
        Builtins.y2milestone(
          "Directory listing may be missing, copying /etc/yaboot.conf"
        )
        CopyOptionalFile(srcid, 1, "/etc/yaboot.conf", Ops.add(target, "/etc"))
      end

      ret = ret && r

      ret
    end

    def UpDir(input)
      parts = Builtins.splitstring(input, "/")

      return "" if Ops.less_than(Builtins.size(parts), 1)

      # remove the last element
      parts = Builtins.remove(parts, Ops.subtract(Builtins.size(parts), 1))

      Builtins.mergestring(parts, "/")
    end


    def CopyFilesRegExp(srcid, mid, src, target, regexp)
      # get file list from directory.yast
      file_list = Pkg.SourceProvideOptionalFile(srcid, 1, "directory.yast")

      if file_list == nil || file_list == ""
        Builtins.y2error("directory.yast was not found, a YUM source?")
        return false
      end

      f = Convert.to_string(SCR.Read(path(".target.string"), file_list))
      files = Builtins.splitstring(f, "\n")
      Builtins.y2milestone("Remote objects: %1", files)

      files = Builtins.filter(files) do |file|
        !Builtins.regexpmatch(file, "/$") && Builtins.regexpmatch(file, regexp) &&
          file != ""
      end
      Builtins.y2milestone("Remote files: %1", files)


      Builtins.foreach(files) do |remote_file|
        CopyOptionalFile(
          srcid,
          mid,
          Builtins.sformat("%1/%2", src, remote_file),
          Builtins.sformat("%1/%2", target, remote_file)
        )
      end 


      true
    end

    def CreateProductDirectoryMap(base_src)
      ret = {}
      enabled_srcs = Pkg.SourceGetCurrent(true)
      known_products = []

      Builtins.foreach(enabled_srcs) do |id|
        if id == base_src
          # this is the base source
          Ops.set(ret, id, "/")
        else
          productData = Pkg.SourceProductData(id)
          prod_name = Ops.get_string(productData, "productname", "")

          prod_name = "add_on" if prod_name == nil && prod_name == ""

          prod_name_base = prod_name
          addon_index = 2

          while Builtins.contains(known_products, prod_name)
            prod_name = Ops.add(
              prod_name_base,
              Builtins.sformat("_%1", addon_index)
            )
            addon_index = Ops.add(addon_index, 1)
          end

          known_products = Builtins.add(known_products, prod_name)
          Ops.set(ret, id, Ops.add(Ops.add("Addons/", prod_name), "/"))

          Builtins.y2milestone(
            "Using directory '%1' for source %2 (%3)",
            prod_name,
            id,
            Ops.get_string(productData, "productname", "")
          )
        end
      end 


      Builtins.y2milestone("Directory mapping: %1", ret)

      deep_copy(ret)
    end


    # Check Product dependencies and determine product to be used for
    # booting. Also determine what is the main product.
    #
    def checkProductDependency
      sources = UrlToId(Ops.get_list(@Config, "sources", []))

      if Builtins.size(sources) == 1
        Builtins.y2milestone("Only one source selected")
        return Ops.get(sources, 0, -1)
      end

      # the products must be in the pool
      Pkg.SourceLoad

      product_deps = Pkg.ResolvableDependencies("", :product, "")
      Builtins.y2milestone("found products: %1", product_deps)

      # filter out unused products
      product_deps = Builtins.filter(product_deps) do |prod|
        Builtins.contains(sources, Ops.get_integer(prod, "source", -1))
      end

      Builtins.y2milestone("used products: %1", product_deps)

      # we have to sort the products according to requires to get the base product
      tsort_input = ""

      Builtins.foreach(product_deps) do |prod|
        provides = []
        requires = []
        # collect provides and requires dependencies
        Builtins.foreach(Ops.get_list(prod, "dependencies", [])) do |dep|
          kind = Ops.get_string(dep, "dep_kind", "")
          # replace ' ' -> '_' (tsort uses space as a separator)
          name = String.Replace(Ops.get_string(dep, "name", ""), " ", "_")
          if name != ""
            if kind == "provides"
              provides = Builtins.add(provides, name)
            elsif kind == "requires"
              requires = Builtins.add(requires, name)
            end
          end
        end
        src = Ops.get_integer(prod, "source", -1)
        Builtins.y2milestone(
          "Source %1: provides: %2, requires: %3",
          src,
          provides,
          requires
        )
        src_str = Builtins.sformat("@repository_id:%1@", src)
        # add requires dependencies to the tsort input
        Builtins.foreach(requires) do |r|
          tsort_input = Ops.add(
            tsort_input,
            Builtins.sformat("%1 %2\n", src_str, r)
          )
        end
        # add provides dependencies to the tsort input
        Builtins.foreach(provides) do |p|
          tsort_input = Ops.add(
            tsort_input,
            Builtins.sformat("%1 %2\n", p, src_str)
          )
        end
      end 


      Builtins.y2milestone("tsort input: %1", tsort_input)

      # run tsort
      sorted = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("echo '%1' | tsort | tac", String.Quote(tsort_input))
        )
      )
      sorted_prods = Builtins.splitstring(
        Ops.get_string(sorted, "stdout", ""),
        "\n"
      )
      Builtins.y2milestone("Sorted products: %1", sorted_prods)

      base_source = Ops.get(sources, 0, -1)

      Builtins.foreach(sorted_prods) do |line|
        src_id = Builtins.regexpsub(line, "@repository_id:([0-9]*)@", "\\1")
        if src_id != nil
          base_source = Builtins.tointeger(src_id)
          Builtins.y2milestone("Found base source: %1", base_source)
          raise Break
        end
      end 


      base_source
    end

    def CreateAddonFile(products)
      products = deep_copy(products)
      Builtins.y2milestone("Product map: %1", products)

      ret = ""

      Builtins.foreach(products) do |srcid, subdir|
        if subdir != nil && subdir != "" && subdir != "/"
          ret = Ops.add(ret, "\n") if Ops.greater_than(Builtins.size(ret), 0)

          ret = Ops.add(Ops.add(ret, "relurl://./"), subdir)
        end
      end 


      Builtins.y2milestone("addon_products content: %1", ret)

      ret
    end


    def BootFiles(srcid)
      Builtins.y2milestone(
        "Downloading boot/directory.yast from src %1...",
        srcid
      )
      local_directory_yast = Pkg.SourceProvideOptionalFile(
        srcid,
        1,
        "/boot/directory.yast"
      )

      Builtins.y2milestone(
        "directory.yast from src %1: %2",
        srcid,
        local_directory_yast
      )

      ret = []

      if local_directory_yast != nil
        listing = Convert.to_string(
          SCR.Read(path(".target.string"), local_directory_yast)
        )

        ret = Builtins.splitstring(listing, "\n")
        ret = Builtins.filter(ret) { |f| f != "" }
      end

      Builtins.y2milestone("Content of boot/directory.yast: %1", ret)

      deep_copy(ret)
    end


    # Write the modified file with pattern definitions
    # @param [String] file_path path to pattern file
    # @param [Array<Hash>] patterns list of patterns defined in this file
    # @return success
    def WritePatternFile(file_path, patterns)
      patterns = deep_copy(patterns)
      ret = true
      if @pattern_descr == nil
        @pattern_descr = deep_copy(AddOnCreator.pattern_descr)
      end

      SCR.Execute(path(".target.remove"), file_path)
      gzip = Builtins.substring(
        file_path,
        Ops.subtract(Builtins.size(file_path), 3),
        3
      ) == ".gz"
      if gzip
        file_path = Builtins.substring(
          file_path,
          0,
          Ops.subtract(Builtins.size(file_path), 3)
        )
      end

      file = ""
      Builtins.foreach(patterns) do |pattern|
        if file != ""
          file = Builtins.sformat(
            "%1\n" +
              "# --------------- %2 ----------------\n" +
              "\n",
            file,
            Ops.get_string(pattern, "Pat", "")
          )
        end
        file = Ops.add(
          file,
          Builtins.sformat(
            "=Ver: %1\n\n=Pat: %2\n",
            Ops.get_string(pattern, "Ver", "5.0"),
            Ops.get_string(pattern, "Pat", "")
          )
        )
        pattern = Builtins.remove(Builtins.remove(pattern, "Ver"), "Pat")
        last_key = ""
        Builtins.foreach(
          Convert.convert(pattern, :from => "map", :to => "map <string, any>")
        ) do |key, val|
          descr = Ops.get(@pattern_descr, key, {})
          # substring (key,0,3) is because of Des.lang, Sum.lang and Cat.lang
          shortkey = Builtins.substring(key, 0, 3)
          if Ops.get(@pattern_descr, shortkey, {}) != {} &&
              Builtins.substring(key, 3, 1) == "."
            descr = Ops.get(@pattern_descr, shortkey, {})
          else
            shortkey = key
          end
          if val == nil || val == "" || val == [] ||
              Ops.get_boolean(descr, "internal", false)
            next
          end
          file = Ops.add(file, "\n") if file != "" && last_key != shortkey
          if Ops.get_boolean(descr, "single_line", false)
            file = Ops.add(file, Builtins.sformat("=%1: %2\n", key, val))
          else
            file = Ops.add(file, Builtins.sformat("+%1:\n%2\n-%1:\n", key, val))
          end
          last_key = shortkey
        end
      end
      if file != ""
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "LANG=C date")
        )
        file = Ops.add(
          file,
          Builtins.sformat(
            "\n\n# Generated by YaST on %1.",
            Builtins.deletechars(Ops.get_string(out, "stdout", ""), "\n")
          )
        )
        SCR.Write(path(".target.string"), file_path, file)
        if gzip && gzip_installed
          Builtins.y2milestone(
            "compressing pattern file: %1",
            SCR.Execute(
              path(".target.bash"),
              Builtins.sformat("gzip '%1'", file_path)
            )
          )
        end
      end
      ret
    end

    def GetBootInfoRepo(repo)
      boot_files = BootFiles(repo)
      bootable_product = Ops.greater_than(Builtins.size(boot_files), 0)

      arch = GetArch()
      # ppc64 has /boot/ppc
      boot_architecture = Builtins.contains(boot_files, Ops.add(arch, "/")) ? arch : ""

      # TODO FIXME: add ppc 64 hack
      # if (arch)== "ppc64") ? "ppc" : arch;

      ret = {
        "bootable"          => bootable_product,
        "boot_architecture" => boot_architecture
      }

      Builtins.y2milestone("Bootinfo: %1", ret)

      deep_copy(ret)
    end

    def GetBootInfo
      base_url = Ops.get_string(@Config, "base_repo", "")

      Builtins.y2milestone("Configured base repository: %1", base_url)

      # detect the base source
      base_source = base_url != "" ?
        Ops.get(UrlToId([base_url]), 0, -1) :
        checkProductDependency

      ret = GetBootInfoRepo(base_source)
      ret = Builtins.add(ret, "base_source", base_source)

      deep_copy(ret)
    end

    # Create Skeleton
    # @return [Boolean] true on success
    def CreateSkeleton(base_source, bootable_product, boot_architecture)
      ret = 0
      success = true
      savespace = Ops.get_boolean(@Config, "savespace", false)
      sp = false
      sles_path = ""
      sles_src = 0
      descr_dir = ""
      arch = GetArch()

      Builtins.y2milestone("Config: %1", @Config)

      # Create skeleton directory
      @skel_root = Builtins.sformat(
        "%1/%2",
        Ops.get_string(@Config, "iso-directory", ""),
        Ops.get_string(@Config, "name", "")
      )
      SCR.Execute(path(".target.mkdir"), @skel_root)

      if bootable_product
        Exec(
          Builtins.sformat(
            "/bin/mkdir -p '%1/boot/%2'",
            String.Quote(@skel_root),
            String.Quote(boot_architecture)
          )
        )
      end

      enabled = Pkg.SourceGetCurrent(true)
      return false if Builtins.size(enabled) == 0
      Builtins.y2milestone("enabled sources: %1", enabled)
      source = ""
      descrDir = ""
      dataDir = ""

      if bootable_product
        if @_arch == "i386" || @_arch == "x86_64"
          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/boot/%2/loader'",
              String.Quote(@skel_root),
              String.Quote(boot_architecture)
            )
          )
        elsif @_arch == "ppc" || @_arch == "ppc64"
          # FIXME PS3 is optional
          Exec(
            Builtins.sformat("/bin/mkdir -p '%1/PS3'", String.Quote(@skel_root))
          )
          Exec(
            Builtins.sformat("/bin/mkdir -p '%1/ppc'", String.Quote(@skel_root))
          )
          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/suseboot'",
              String.Quote(@skel_root)
            )
          )
        end
      end

      @product_map = CreateProductDirectoryMap(base_source)

      # create directories for the addons
      Builtins.foreach(@product_map) do |srcid, dir|
        if dir != "/"
          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/%2'",
              String.Quote(@skel_root),
              String.Quote(dir)
            )
          )
        end
      end 


      main_skel_root = @skel_root

      Builtins.foreach(enabled) do |id|
        general_info = Pkg.SourceGeneralData(id)
        # no extra data for YUM sources
        next false if Ops.get_string(general_info, "type", "") == "YUM"
        this_source = Ops.get_map(@meta, id, {})
        source = Ops.get_string(this_source, "path", "")
        @meta_local = ReadContentFile(id)
        @skel_root = Ops.add(
          Ops.add(main_skel_root, "/"),
          Ops.get(@product_map, id, "")
        )
        Builtins.y2milestone("Using directory %1 for source %2", @skel_root, id)
        next false if source == ""
        # copy /docu (release notes) when present
        CopyDocu(id, @skel_root)
        Builtins.y2milestone("source: %1", source)
        descr_dir = Ops.get_string(
          this_source,
          ["productData", "descrdir"],
          "suse/setup/descr"
        )
        Builtins.y2debug("content: %1", @meta_local)
        if Ops.get_string(this_source, ["productData", "baseproductname"], "") != "" &&
            Builtins.issubstring(Ops.get_string(@meta_local, "FLAGS", ""), "SP")
          Builtins.y2milestone("Service pack detected")
          Builtins.y2debug("this source: %1", this_source)
          descrDir = Ops.get_string(
            this_source,
            ["productData", "descrdir"],
            "suse/setup/descr"
          )
          dataDir = Ops.get_string(
            this_source,
            ["productData", "datadir"],
            "suse"
          )
          Builtins.y2debug(
            "source data: %1",
            Ops.get_string(this_source, ["sourceData", "url"], "")
          )
          # Service Pack
          if bootable_product
            if savespace
              # Installation, rescue images
              CopyFile(
                id,
                1,
                Builtins.sformat("boot/%1/rescue", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )

              # Loader, x86 specific
              if @_arch == "i386" || @_arch == "x86_64"
                # recursive copy of /boot/$arch/loader/*
                CopyDirectoryRec(
                  id,
                  1,
                  Builtins.sformat("boot/%1/loader", boot_architecture),
                  Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
                )

                # nonrecursive copy of /boot/$arch/*
                CopyDirectoryNonRec(
                  id,
                  1,
                  Builtins.sformat("boot/%1", boot_architecture),
                  Builtins.sformat("%1/boot", @skel_root)
                )
              elsif @_arch == "ppc" || @_arch == "ppc64"
                # recursive copy of /boot
                CopyDirectoryRec(id, 1, "boot", @skel_root)
                CopyPPCBoot(id, @skel_root)
              else
                CopyDirectoryRec(id, 1, "boot", @skel_root)
              end
            else
              CopyDirectoryRec(id, 1, "boot", @skel_root)

              if @_arch == "ppc" || @_arch == "ppc64"
                CopyPPCBoot(id, @skel_root)
              end
            end

            # copy the driver update
            CopyOptionalFile(id, 1, "driverupdate", @skel_root)
          end

          # copy the descr directory
          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/%2'",
              String.Quote(@skel_root),
              String.Quote(descrDir)
            )
          )
          CopyDirectoryRec(
            id,
            1,
            descrDir,
            Builtins.sformat("%1/%2", @skel_root, UpDir(descrDir))
          )

          sp = true
        elsif Ops.get_string(
            this_source,
            ["productData", "baseproductname"],
            ""
          ) != ""
          # SLES
          Builtins.y2milestone("SLES source detected")

          sles_path = source
          sles_src = id
          Builtins.y2milestone("this source: %1", this_source)
          descrDir = Ops.get_string(
            this_source,
            ["productData", "descrdir"],
            "suse/setup/descr"
          )
          dataDir = Ops.get_string(
            this_source,
            ["productData", "datadir"],
            "suse"
          )
          Builtins.y2debug(
            "source data: %1",
            Ops.get_string(this_source, ["sourceData", "url"], "")
          )
          success = Convert.to_boolean(
            SCR.Execute(
              path(".target.mkdir"),
              Builtins.sformat(
                "'%1/%2'",
                String.Quote(@skel_root),
                String.Quote(dataDir)
              )
            )
          )
          if !success
            Builtins.y2error(
              "Cannot create directory: %1",
              Builtins.sformat(
                "'%1/%2'",
                String.Quote(@skel_root),
                String.Quote(dataDir)
              )
            )
            next false
          end

          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/%2'",
              String.Quote(@skel_root),
              String.Quote(descrDir)
            )
          )

          if savespace
            if bootable_product
              CopyFile(
                id,
                1,
                Builtins.sformat("boot/%1/rescue", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )
              CopyFile(
                id,
                1,
                Builtins.sformat("boot/%1/root", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )
              CopyOptionalFile(
                id,
                1,
                Builtins.sformat("boot/%1/root.fonts", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )
            end

            # copy content* files
            CopyFilesRegExp(id, 1, "/", @skel_root, "^content")

            CopyFile(id, 1, "control.xml", @skel_root)
          else
            if bootable_product
              CopyFile(
                id,
                1,
                Builtins.sformat("boot/%1/root", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )
              CopyOptionalFile(
                id,
                1,
                Builtins.sformat("boot/%1/root.fonts", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )
            end

            # copy base files, skip all directories
            CopyDirectoryNonRec(id, 1, "/", @skel_root)
          end

          Builtins.y2milestone(
            "source: %1, descrDir: %2, skel_root: %3",
            source,
            descrDir,
            @skel_root
          )
          # Descriptions, Selections and package databases
          CopyDirectoryRec(
            id,
            1,
            descrDir,
            Builtins.sformat("%1/%2", @skel_root, UpDir(descrDir))
          )

          # Prepare media files
          CopyDirectoryRec(id, 1, "media.1", @skel_root)
          Exec(
            Builtins.sformat(
              "/usr/bin/head -n 2 %1/media.1/media  >   %1/media.1/media.tmp && mv %1/media.1/media.tmp %1/media.1/media",
              String.Quote(@skel_root)
            )
          )
        else
          # copy base files, skip all directories
          CopyDirectoryNonRec(id, 1, "/", @skel_root)
        end
      end

      # set the root directory back
      @skel_root = main_skel_root

      if !sp
        Builtins.y2milestone("NOT SP")


        if sles_path != ""
          source = sles_path
          base_source = sles_src
        end

        descrDir = descr_dir if descrDir == ""

        if dataDir == ""
          dataDir = String.FirstChunk(descr_dir, "/")

          dataDir = "suse" if dataDir == ""
        end

        if bootable_product
          if savespace
            CopyFile(
              base_source,
              1,
              Builtins.sformat("boot/%1/rescue", boot_architecture),
              Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
            )
            CopyFile(
              base_source,
              1,
              Builtins.sformat("boot/%1/root", boot_architecture),
              Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
            )
            CopyOptionalFile(
              base_source,
              1,
              Builtins.sformat("boot/%1/root.fonts", boot_architecture),
              Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
            )
            # Loader, x86 specific
            if @_arch == "i386" || @_arch == "x86_64"
              # recursive copy of /boot/$boot_architecture/loader/*
              CopyDirectoryRec(
                base_source,
                1,
                Builtins.sformat("boot/%1/loader", boot_architecture),
                Builtins.sformat("%1/boot/%2", @skel_root, boot_architecture)
              )

              # nonrecursive copy of /boot/$boot_architecture/*
              CopyDirectoryNonRec(
                base_source,
                1,
                Builtins.sformat("boot/%1", boot_architecture),
                Builtins.sformat("%1/boot", @skel_root)
              )
            elsif @_arch == "ppc" || @_arch == "ppc64"
              CopyPPCBoot(base_source, @skel_root)

              # recursive copy of /boot
              CopyDirectoryRec(base_source, 1, "boot", @skel_root)
            else
              # recursive copy of /boot/loader/*
              CopyDirectoryRec(base_source, 1, "boot", @skel_root)
            end
          else
            CopyDirectoryRec(base_source, 1, "boot", @skel_root)

            if @_arch == "ppc" || @_arch == "ppc64"
              CopyPPCBoot(base_source, @skel_root)
            end
          end
        end
      end

      Builtins.foreach(enabled) do |source_id|
        general_info = Pkg.SourceGeneralData(source_id)
        # no extra action for YUM sources
        next if Ops.get_string(general_info, "type", "") == "YUM"
        this_source = Ops.get_map(@meta, source_id, {})
        source = Ops.get_string(this_source, "path", "")
        @meta_local = ReadContentFile(source_id)
        @skel_root = Ops.add(
          Ops.add(main_skel_root, "/"),
          Ops.get(@product_map, source_id, "")
        )
        Builtins.y2milestone(
          "Using directory %1 for source %2",
          @skel_root,
          source_id
        )
        # copy descriptions
        descrdir = Ops.get_string(
          @meta,
          [source_id, "productData", "descrdir"],
          "suse/setup/descr"
        )
        Exec(
          Builtins.sformat(
            "/bin/mkdir -p '%1/%2'",
            String.Quote(@skel_root),
            String.Quote(descrdir)
          )
        )
        CopyDirectoryRec(
          source_id,
          1,
          descrdir,
          Builtins.sformat("%1/%2", @skel_root, UpDir(descrdir))
        )
        datadir = Ops.get_string(
          @meta,
          [source_id, "productData", "datadir"],
          "suse"
        )
        slidedir = Ops.add(datadir, "/setup/slide/")
        if !savespace
          Builtins.y2milestone("slidedir: %1", slidedir)

          # check whether the slideshow directory is present
          l_dirlist = Pkg.SourceProvideOptionalFile(
            source_id,
            1,
            Ops.add(slidedir, "directory.yast")
          )
          if l_dirlist != nil
            l_slidedir = Pkg.SourceProvideDirectory(
              source_id,
              1,
              slidedir,
              true,
              true
            )

            if l_slidedir != nil && l_slidedir != ""
              # copy slide show
              Exec(
                Builtins.sformat(
                  "/bin/mkdir -p '%1/%2'",
                  String.Quote(@skel_root),
                  String.Quote(slidedir)
                )
              )
              Exec(
                Builtins.sformat(
                  "/bin/cp -a -- '%1' '%2/%3'",
                  String.Quote(l_slidedir),
                  String.Quote(@skel_root),
                  String.Quote(Ops.add(datadir, "/setup/"))
                )
              )
            end
          else
            Builtins.y2milestone("Slideshow is missing")
            if bootable_product
              Exec(
                Builtins.sformat(
                  "/bin/mkdir -p '%1/%2'",
                  String.Quote(@skel_root),
                  String.Quote(slidedir)
                )
              )
              Exec(
                Builtins.sformat(
                  "> '%1/%2/directory.yast'",
                  String.Quote(@skel_root),
                  String.Quote(slidedir)
                )
              )
            end
          end
        else
          Builtins.y2milestone("Save space - do not copy the slideshow")
          Exec(
            Builtins.sformat(
              "/bin/mkdir -p '%1/%2'",
              String.Quote(@skel_root),
              String.Quote(slidedir)
            )
          )
          Exec(
            Builtins.sformat(
              "> '%1/%2/directory.yast'",
              String.Quote(@skel_root),
              String.Quote(slidedir)
            )
          )
        end
        Builtins.y2milestone(
          "source: %1, descrDir: %2, skel_root: %3",
          source,
          descrDir,
          @skel_root
        )
        # copy media.1 directory
        CopyDirectoryRec(source_id, 1, "media.1", @skel_root)
        Exec(
          Builtins.sformat(
            "/usr/bin/head -n 2 '%1/media.1/media'  >   '%1/media.1/media.tmp' && mv '%1/media.1/media.tmp' '%1/media.1/media'",
            String.Quote(@skel_root)
          )
        )
        # create a copy of the autoyast profile (the new profile accepts even unsigned source)
        autoyast_copy = ""
        # the copy is not needed if the sourse will be signed with a gpg key
        if Ops.get_string(@Config, "profile", "") != "" &&
            Ops.get_string(@Config, "gpg_key", "") != ""
          prof = Ops.get_string(@Config, "profile", "")

          if !Profile.ReadXML(prof)
            Report.Error(_("Error reading control file."))
          else
            Builtins.y2milestone("Current profile: %1", Profile.current)

            if Ops.get(Profile.current, ["general", "signature-handling"]) == nil
              Ops.set(Profile.current, ["general", "signature-handling"], {})
            end

            Ops.set(
              Profile.current,
              ["general", "signature-handling", "accept_unsigned_file"],
              true
            )

            # add prefix to the name
            parts = Builtins.splitstring(prof, "/")
            Ops.set(
              parts,
              Ops.subtract(Builtins.size(parts), 1),
              Ops.add(
                "install_",
                Ops.get(parts, Ops.subtract(Builtins.size(parts), 1), "")
              )
            )
            prof = Builtins.mergestring(parts, "/")

            saved = Profile.Save(prof)
            Builtins.y2milestone(
              "Modified profile saved to %1: %2",
              prof,
              saved
            )

            if saved
              autoyast_copy = prof
            else
              # saving to the original location has failed, save copy to tmpdir
              tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
              prof = Ops.add(tmpdir, "/product-creator-autoyast_profile.xml")

              # save the copy
              saved = Profile.Save(prof)

              Builtins.y2milestone(
                "Copy of the profile saved to %1: %2",
                prof,
                saved
              )
              autoyast_copy = prof if saved
            end
          end
        end
        # copy autoyast profile
        if Ops.get_string(@Config, "profile", "") != "" &&
            Ops.get_boolean(@Config, "copy_profile", false)
          if autoyast_copy != ""
            # save the original file and the copy
            Exec(
              Builtins.sformat(
                "/bin/cp -- '%1' '%2/autoinst.xml'",
                String.Quote(autoyast_copy),
                String.Quote(@skel_root)
              )
            )
            Exec(
              Builtins.sformat(
                "/bin/cp -- '%1' '%2/autoinst.orig.xml'",
                String.Quote(Ops.get_string(@Config, "profile", "")),
                String.Quote(@skel_root)
              )
            )
          else
            # save the original file (a copy is not available)
            Exec(
              Builtins.sformat(
                "/bin/cp '%1' '%2/autoinst.xml'",
                String.Quote(Ops.get_string(@Config, "profile", "")),
                String.Quote(@skel_root)
              )
            )
          end
        end
        # Media nr.
        count = 1
        Exec(
          Builtins.sformat(
            "/bin/echo %1 >> '%2/media.1/media'",
            count,
            String.Quote(@skel_root)
          )
        )
        # make the source digitally unsigned (because signed descr/packages file has been modified)
        if boot_architecture != ""
          # remove the key and the checksum
          Exec(
            Builtins.sformat(
              "/bin/rm '%1/content.asc' '%1/content.key'",
              String.Quote(@skel_root)
            )
          )
          # remove the meta information from content file
          Exec(
            Builtins.sformat(
              "/usr/bin/grep -v -e '^KEY ' -e '^META ' '%1/content' > '%1/content.new'",
              String.Quote(@skel_root)
            )
          )
          Exec(
            Builtins.sformat(
              "/bin/mv '%1/content.new' '%1/content'",
              String.Quote(@skel_root)
            )
          )
          # mark the final product as 'base'
          if SCR.Execute(
              path(".target.bash"),
              Builtins.sformat(
                "/usr/bin/grep '^TYPE' '%1/content'",
                String.Quote(@skel_root)
              )
            ) != 0
            Exec(
              Builtins.sformat(
                "echo 'TYPE base' >> '%1/content'",
                String.Quote(@skel_root)
              )
            )
          end

          # recreate the index file
          # FIXME: use create_directory when it supports parameter with spaces
          #	Exec(sformat("/bin/rm -f '%1/directory.yast' && /usr/bin/create_directory.yast '%1'", String::Quote(skel_root)));
          Exec(
            Builtins.sformat(
              "/bin/rm -f '%1/directory.yast'; cd '%1'; ls | grep -v -e '^\\.$' -e '^\\.\\.$' > '%1/directory.yast'",
              String.Quote(@skel_root)
            )
          )
        end
        # remove unused patterns (they cannot be used due to missing packages)
        if Ops.get_symbol(@Config, "type", :unknown) == :patterns
          used_patterns = Ops.get_list(@Config, "addons", [])
          if Ops.get_string(@Config, "base", "") != ""
            used_patterns = Builtins.prepend(
              used_patterns,
              Ops.get_string(@Config, "base", "")
            )
          end
          Builtins.y2milestone("used patterns: %1", used_patterns)


          # addons 'doesn't include patterns added via dependency
          # better find the pattern dependencies with solver
          Builtins.foreach(used_patterns) do |p|
            Pkg.ResolvableInstall(p, :pattern)
          end
          Pkg.PkgSolve(true)
          Builtins.foreach(Pkg.ResolvableProperties("", :pattern, "")) do |pat|
            if Ops.get_symbol(pat, "status", :none) == :selected
              used_patterns = Builtins.add(
                used_patterns,
                Ops.get_string(pat, "name", "")
              )
              Builtins.y2milestone("selected pattern: %1", pat)
            end
          end

          Builtins.y2milestone("patterns + dependencies: %1", used_patterns)

          files = Convert.convert(
            SCR.Read(
              path(".target.dir"),
              Builtins.sformat("%1/%2", @skel_root, descrDir)
            ),
            :from => "any",
            :to   => "list <string>"
          )
          files = [] if files == nil

          files = Builtins.filter(files) do |f|
            Builtins.regexpmatch(f, "\\.pat$") ||
              Builtins.regexpmatch(f, "\\.pat.gz$")
          end

          Builtins.y2milestone("found pattern files: %1", files)

          refresh_diryast = false

          Builtins.foreach(files) do |file|
            file_path = Builtins.sformat("%1/%2/%3", @skel_root, descrDir, file)
            pts = Convert.convert(
              SCR.Read(path(".pattern.list"), file_path),
              :from => "any",
              :to   => "list <map>"
            )
            pattern_modified = false
            pts = Builtins.filter(pts) do |pt|
              pattern = Ops.get(
                Builtins.splitstring(Ops.get_string(pt, "Pat", ""), " \t"),
                0,
                ""
              )
              if !Builtins.contains(used_patterns, pattern) &&
                  Ops.get_boolean(pt, "Vis", true) != false # do not remove invisible patterns
                Builtins.y2debug("pattern to delete: %1", pattern)
                pattern_modified = true
                next false
              end
              Builtins.y2milestone("pattern %1 will stay", pattern)
              true
            end
            if pattern_modified
              success = success && WritePatternFile(file_path, pts)
              refresh_diryast = true
            end
          end

          Builtins.y2milestone("removed patterns: %1", success)

          if refresh_diryast
            # regenerate directory.yast and patterns file
            # FIXME: string cmd = sformat("/bin/rm -f -- '%1/%2/directory.yast' && /usr/bin/create_directory.yast '%1/%2'", String::Quote(skel_root), String::Quote(descrDir));
            cmd = Builtins.sformat(
              "/bin/rm -f '%1/%2/directory.yast'; cd '%1/%2'; ls | grep -v -e '^\\.$' -e '^\\.\\.$' > '%1/%2/directory.yast'",
              String.Quote(@skel_root),
              String.Quote(descrDir)
            )
            success = success && Exec(cmd)
            Builtins.y2milestone("success: %1", success)

            # this will print error message since they are either pat or pat.gz
            cmd = Builtins.sformat(
              "cd '%1/%2'; ls *.pat *.pat.gz > '%1/%2/patterns'",
              String.Quote(@skel_root),
              String.Quote(descrDir)
            )
            Exec(cmd)
          end
        end
        # update MD5SUMS file
        success = success &&
          UpdateMD5File(Builtins.sformat("%1/%2", @skel_root, descrDir))
        Builtins.y2debug("success: %1", success)
      end

      @skel_root = main_skel_root

      addon_file = CreateAddonFile(@product_map)
      if Ops.greater_than(Builtins.size(addon_file), 0)
        target_addon_file = Ops.add(main_skel_root, "/add_on_products")
        Builtins.y2milestone("Writing addon products to %1", target_addon_file)
        success = success &&
          SCR.Write(path(".target.string"), target_addon_file, addon_file)
      end

      Builtins.y2milestone("Created skeleton: %1", success)
      success
    end

    # see http://en.opensuse.org/Secure_Installation_Sources
    # @param [String] gpg_key GPG key ID or empty if the product should be unsigned
    # @param [String] initrd_file path to the initrd file
    # @return [Boolean] true on success
    def InsertKeyToInitrd(gpg_key, initrd_file)
      if gpg_key == ""
        Builtins.y2milestone(
          "Disabling signature checks in initrd %1",
          initrd_file
        )
      else
        Builtins.y2milestone(
          "Adding GPG key %1 to initrd %2",
          gpg_key,
          initrd_file
        )
      end

      # initrd is a cpio.xz archive

      parts = Builtins.splitstring(initrd_file, "/")
      if Ops.greater_than(Builtins.size(parts), 1)
        # remove the last element
        parts = Builtins.remove(parts, Ops.subtract(Builtins.size(parts), 1))
      end
      base = Builtins.mergestring(parts, "/")

      # uncompress the initrd
      Builtins.y2milestone("Uncompressing initrd: %1", initrd_file)
      ret = Exec(
        Builtins.sformat(
          "cd '%1' && unxz < '%2' > '%2.cpio'",
          String.Quote(base),
          String.Quote(initrd_file)
        )
      )
      return false if !ret

      new_file = ""

      if gpg_key == ""
        # remove the old file before unpacking
        ret = Exec(
          Builtins.sformat("rm -rf '%1/linuxrc.config'", String.Quote(base))
        )

        # unpack 'linuxrc.config' file
        ret = Exec(
          Builtins.sformat(
            "cd '%1' && cpio -i -H newc -F '%2.cpio' linuxrc.config",
            String.Quote(base),
            String.Quote(initrd_file)
          )
        )
        return false if !ret

        # add 'Insecure: 1' option
        ret = Exec(
          Builtins.sformat(
            "cd '%1' && echo 'Insecure:\t1' >> linuxrc.config",
            String.Quote(base)
          )
        )
        return false if !ret
        Builtins.y2milestone(
          "Updated linuxrc.config: %1",
          SCR.Read(path(".target.string"), Ops.add(base, "/linuxrc.config"))
        )

        # add linuxrc instead of a gpg key
        new_file = "linuxrc.config"
      else
        ret = GPG.ExportPublicKey(
          gpg_key,
          Builtins.sformat("%1/gpg-%2.gpg", base, gpg_key)
        )
        return false if !ret

        # add the exported GPG key
        new_file = Builtins.sformat("gpg-%1.gpg", gpg_key)
      end

      # uncompress the archive and add the GPG key or new linuxrc.config file
      command = Builtins.sformat(
        "cd '%1' && echo '%3' | cpio -o -H newc -A -F '%2.cpio'",
        String.Quote(base),
        String.Quote(initrd_file),
        String.Quote(new_file)
      )
      ret = Exec(command)
      return false if !ret

      if new_file != "linuxrc.config"
        # extract installkey.gpg from cpio archive
        command = Builtins.sformat(
          "cd '%1'; cpio -i -H newc -F '%2.cpio' installkey.gpg",
          String.Quote(base),
          String.Quote(initrd_file)
        )

        ret = Exec(command)
        return false if !ret

        # add our new key to installkey.gpg keyring
        command = Builtins.sformat(
          "cd '%1'; gpg --no-default-keyring --keyring ./installkey.gpg --import '%2'",
          String.Quote(base),
          String.Quote(new_file)
        )
        ret = Exec(command)
        return false if !ret

        # place new installkey.gpg back to the archive
        command = Builtins.sformat(
          "cd '%1' && echo installkey.gpg | cpio -o -H newc -A -F '%2.cpio'",
          String.Quote(base),
          String.Quote(initrd_file)
        )

        ret = Exec(command)
        return false if !ret
      end

      # compress the archive, remove the temporary files
      command = Builtins.sformat(
        "gzip --best < '%1.cpio' > '%1' && rm -f '%1.cpio' '%2'",
        String.Quote(initrd_file),
        String.Quote(new_file)
      )
      ret = Exec(command)

      ret
    end

    def DumpKernelFromObjectFile(object)
      Builtins.y2milestone("Extracting kernel from file %1", object)
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      target = Ops.add(tmpdir, "/tmp_kernel.gz")

      command = Builtins.sformat(
        "objcopy -O binary -j .kernel:vmlinux.strip '%1' '%2'",
        String.Quote(object),
        String.Quote(target)
      )
      ret = Exec(command) ? target : ""

      Builtins.y2milestone("Kernel extracted to %1", ret)

      ret
    end

    def GunzipKernel(kernel_gz)
      command = Builtins.sformat("gunzip -f %1", kernel_gz)
      success = Exec(command)
      ret = ""

      # remove .gz suffix from the file name
      ret = Builtins.regexpsub(kernel_gz, "^(.*)\\.gz$", "\\1") if success

      Builtins.y2milestone("Kernel unpacked to %1", ret)

      ret
    end

    def CreateMkzimageCommand
      ret = ""

      if (Ops.get_string(@Config, "arch", "") == "ppc" ||
          Ops.get_string(@Config, "arch", "") == "ppc64") &&
          !Arch.ppc
        # find the lilo package
        ppc_lilo = Pkg.ResolvableProperties("lilo", :package, "")
        Builtins.y2milestone("found lilo packages: %1", ppc_lilo)

        lilo_pkg = Ops.get(ppc_lilo, 0, {})

        Builtins.y2milestone("selected lilo package: %1", lilo_pkg)

        if lilo_pkg == nil || lilo_pkg == {}
          Builtins.y2error("lilo package was not found")
          return ""
        end

        # download the package
        downloaded_pkg = Pkg.SourceProvideFile(
          Ops.get_integer(lilo_pkg, "source", -1),
          Ops.get_integer(lilo_pkg, "medium_nr", -1),
          Ops.get_string(lilo_pkg, "path", "lilo")
        )

        Builtins.y2milestone("Downloaded lilo package: %1", downloaded_pkg)

        if downloaded_pkg == nil || downloaded_pkg == ""
          Builtins.y2error("Downloading package lilo failed")
          return ""
        end

        # create a tmpdir
        tmp_dir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
        tmp_lilo = Ops.add(
          Ops.add(tmp_dir, "/lilo-"),
          Ops.get_string(lilo_pkg, "version", "")
        )

        # remove the directory if it already exists (e.g. from the previous run)
        Exec(Ops.add("rm -rf ", tmp_lilo))

        SCR.Execute(path(".target.mkdir"), tmp_lilo)

        # unpack the package into the tmpdir
        unpack_cmd = Builtins.sformat(
          "cd '%1' && /usr/bin/rpm2cpio '%2' | /usr/bin/cpio -i --make-directories",
          String.Quote(tmp_lilo),
          String.Quote(downloaded_pkg)
        )

        if !Exec(unpack_cmd)
          Builtins.y2error("Unpacking lilo package failed")
          return ""
        end

        # use the linker from cross-ppc-binutils,
        # set --objdir option to the unpacked PPC lilo package
        ret = Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                "PATH=/opt/cross/powerpc-linux/bin:$PATH '",
                String.Quote(tmp_lilo)
              ),
              "/bin/mkzimage' --objdir '"
            ),
            String.Quote(tmp_lilo)
          ),
          "/lib/lilo' --board chrp --vmlinux '%1' --initrd '%2' --output '%3/new_inst' --tmp '%3'"
        )
      else
        ret = "/bin/mkzimage --board pmac --vmlinux '%1' --initrd '%2' --output '%3/new_inst' --tmp '%3'"
      end

      Builtins.y2milestone("mkzimage command template: %1", ret)
      ret
    end

    def InsertKeyToInitrds(gpg_key, base_dir)
      # get initrd list
      command = ""
      out = {}
      find_output = ""

      if Ops.greater_or_equal(
          SCR.Read(path(".target.size"), Ops.add(base_dir, "/boot")),
          0
        )
        Builtins.y2milestone("Searching for 'initrd' in %1/boot...", base_dir)
        command = Builtins.sformat(
          "cd '%1' && find boot -type f -name 'initrd'",
          String.Quote(base_dir)
        )
        out = Convert.to_map(SCR.Execute(path(".target.bash_output"), command))
        find_output = Ops.get_string(out, "stdout", "")
      end

      inst_mapping = {}

      if Ops.greater_or_equal(
          SCR.Read(path(".target.size"), Ops.add(base_dir, "/suseboot")),
          0
        )
        Builtins.y2milestone(
          "Searching for 'initrd*' in %1/suseboot...",
          base_dir
        )
        command = Builtins.sformat(
          "cd '%1' && find suseboot -type f -name 'initrd*'",
          String.Quote(base_dir)
        )
        out = Convert.to_map(SCR.Execute(path(".target.bash_output"), command))
        find_output = Ops.add(find_output, Ops.get_string(out, "stdout", ""))

        if Builtins.size(Ops.get_string(out, "stdout", "")) == 0
          Builtins.y2milestone("initrd not found, searching for inst*")

          command = Builtins.sformat(
            "cd '%1' && find suseboot -type f -name 'inst32'; find suseboot -type f -name 'inst64'",
            String.Quote(base_dir)
          )
          out = Convert.to_map(
            SCR.Execute(path(".target.bash_output"), command)
          )

          inst_files = Builtins.splitstring(
            Ops.get_string(out, "stdout", ""),
            "\n"
          )
          # remove empty strings
          inst_files = Builtins.filter(inst_files) { |inst| inst != "" }

          if Ops.greater_than(Builtins.size(inst_files), 0)
            Builtins.y2milestone("Found inst* files: %1", inst_files)

            index = 0
            # unpack the initrd from the inst* object
            Builtins.foreach(inst_files) do |inst|
              tmp_initrd = Builtins.sformat(
                "suseboot/.tmp_yast_initrd%1.gz",
                index
              )
              command = Builtins.sformat(
                "cd '%1' && objcopy -O binary -j .kernel:initrd '%2' '%3'",
                String.Quote(base_dir),
                String.Quote(inst),
                tmp_initrd
              )
              out = Convert.to_map(
                SCR.Execute(path(".target.bash_output"), command)
              )
              if Ops.get_integer(out, "exit", -1) == 0
                Builtins.y2milestone("Extracted %1 from %2", tmp_initrd, inst)
                find_output = Ops.add(Ops.add(find_output, tmp_initrd), "\n")

                inst_mapping = Builtins.add(inst_mapping, inst, tmp_initrd)
              end
              index = Ops.add(index, 1)
            end
          end
        end
      end
      arch = GetArch()
      initrds = Builtins.splitstring(find_output, "\n")
      # remove empty strings
      initrds = Builtins.filter(initrds) do |initrd|
        next false if initrd == ""
        # workaround for bnc#498464
        if arch == "s390x" && Builtins.issubstring(initrd, "boot/i386/")
          next false
        end
        true
      end
      Builtins.y2milestone("Found initrds: %1", initrds)

      ret = true
      Builtins.foreach(initrds) do |initrd|
        inserted = InsertKeyToInitrd(
          gpg_key,
          Ops.add(Ops.add(base_dir, "/"), initrd)
        )
        if !inserted
          Report.Error(
            Builtins.sformat(
              _("Could not add GPG key %1 to initrd\n%2.\n"),
              gpg_key,
              initrd
            )
          )
          ret = false
        end
      end 


      if Ops.greater_than(Builtins.size(inst_mapping), 0)
        # create the template command if needed (download the needed lilo package just once)
        mkzimage_template = CreateMkzimageCommand()

        if mkzimage_template != ""
          # put the initrd back to the inst file
          Builtins.foreach(inst_mapping) do |orig_inst, tmp_initrd|
            Builtins.y2milestone("%1 -> %2", tmp_initrd, orig_inst)
            if orig_inst == "suseboot/inst32" || orig_inst == "suseboot/inst64"
              # extract kernel
              gzkernel = DumpKernelFromObjectFile(
                Ops.add(Ops.add(base_dir, "/"), orig_inst)
              )

              if gzkernel != ""
                # unpack the kernel image - required by mkzimage
                kernel = GunzipKernel(gzkernel)
                tmp_dir = Convert.to_string(SCR.Read(path(".target.tmpdir")))

                initrd_copy = Builtins.sformat("%1/tmp_initrd", tmp_dir)

                # copy the initrd to a temp dir - mkzimage doesn't work properly
                # when there is a space in path
                ret = ret &&
                  Exec(
                    Builtins.sformat(
                      "mv '%1/%2' '%3'",
                      String.Quote(base_dir),
                      tmp_initrd,
                      initrd_copy
                    )
                  )

                # create new inst file
                # see mk_ppc_installation-images_bootbinaries.sh (installation-images)
                command = Builtins.sformat(
                  mkzimage_template,
                  kernel,
                  initrd_copy,
                  tmp_dir
                )
                ret = ret && Exec(command)

                # remove the temporary files
                command = Builtins.sformat(
                  "rm -f '%1' '%2'",
                  kernel,
                  initrd_copy
                )
                ret = ret && Exec(command)

                # move the new file to the target directory
                command = Builtins.sformat(
                  "mv '%1/new_inst' '%2/%3'",
                  tmp_dir,
                  String.Quote(base_dir),
                  orig_inst
                )
                ret = ret && Exec(command)
              end
            else
              Builtins.y2warning("Unsupported inst file: %1", orig_inst)
            end
          end
        else
          Builtins.y2error(
            "mkzimage command missing, not modifying initrd (%1)",
            inst_mapping
          )
        end
      end

      ret
    end

    def SignSUSEtagsSource(gpg_key, dir, passphrase)
      # export the key
      success = ExportPublicKey(gpg_key, dir)
      # update SHA1 sums
      success = success && UpdateContentFile(dir, "suse/setup/descr")

      return false if !success

      # sign the source
      success = SignSourceFiles(gpg_key, dir, passphrase)

      if success
        # update directory.yast file
        # FIXME string command = sformat("/bin/rm -f '%1/directory.yast' && /usr/bin/create_directory.yast '%1'", String::Quote(dir));
        Builtins.y2milestone("Updating directory.yast ...")
        success = success &&
          Exec(
            Builtins.sformat(
              "/bin/rm -f '%1/directory.yast'; cd '%1'; ls | grep -v -e '^\\.$' -e '^\\.\\.$' > '%1/directory.yast'",
              String.Quote(dir)
            )
          )
        success = success &&
          Exec(
            Builtins.sformat(
              "/bin/rm -f '%1/directory.yast'; cd '%1'; ls | grep -v -e '^\\.$' -e '^\\.\\.$' > '%1/directory.yast'",
              String.Quote(Ops.add(dir, "/media.1"))
            )
          )
      end

      success
    end

    def SignYUMSource(gpg_key, dir, passphrase)
      ret = GPG.SignAsciiDetached(
        gpg_key,
        Ops.add(dir, "/repodata/repomd.xml"),
        passphrase
      )
      ret = ret &&
        GPG.ExportAsciiPublicKey(
          gpg_key,
          Ops.add(dir, "/repodata/repomd.xml.key")
        )

      ret
    end

    # do not sign the sources, just update content files
    def UpdateContentFiles
      success = true

      Builtins.foreach(@product_map) do |srcid, dir|
        general_info = Pkg.SourceGeneralData(srcid)
        if Ops.get_string(general_info, "type", "") == "YaST"
          success = UpdateContentFile(
            Ops.add(Ops.add(@skel_root, "/"), dir),
            "suse/setup/descr"
          ) && success
          Builtins.y2milestone(
            "Updated content file in %1: %2",
            Ops.add(Ops.add(@skel_root, "/"), dir),
            success
          )
        end
      end 


      success
    end

    def SignSourceStep
      success = true

      # sign the files
      gpg_key = Ops.get_string(@Config, "gpg_key", "")

      if gpg_key != ""
        passphrase = Mode.commandline ?
          @gpg_passphrase :
          GPGWidgets.AskPassphrasePopup(gpg_key)

        # not aborted
        if passphrase != nil
          # sign each product
          Builtins.foreach(@product_map) do |srcid, dir|
            signed = false
            general_info = Pkg.SourceGeneralData(srcid)
            while !signed
              if Ops.get_string(general_info, "type", "") == "YaST"
                # sign the source
                signed = SignSUSEtagsSource(
                  gpg_key,
                  Ops.add(Ops.add(@skel_root, "/"), dir),
                  passphrase
                )
              else
                # sign the source
                signed = SignYUMSource(
                  gpg_key,
                  Ops.add(Ops.add(@skel_root, "/"), dir),
                  passphrase
                )
              end

              # yes/no popup: error message
              if !signed
                if Popup.YesNo(
                    _(
                      "Error: Could not digitally sign the source.\nTry again?\n"
                    )
                  )
                  passphrase = Mode.commandline ?
                    @gpg_passphrase :
                    GPGWidgets.AskPassphrasePopup(gpg_key)
                else
                  break
                end
              end
            end
            success = success && signed
          end
        else
          success = false
        end

        # insert the key into the installation initrd
        success = success && InsertKeyToInitrds(gpg_key, @skel_root)
      else
        # add 'Insecure: 1' to linuxrc.config
        success = success && InsertKeyToInitrds("", @skel_root)

        # update content files if the source is not signed (bnc #368146)
        success = success && UpdateContentFiles()
      end

      Builtins.y2milestone("Source signed: %1", success)
      success
    end


    # CopyMiscFiles
    # Copy other files to directory tree
    # @return [Boolean] true on success
    def CopyMiscFiles(boot_arch)
      cpCmd = ""

      arch = GetArch()
      arch = "s390x" if arch == "s390_64"

      Builtins.y2debug(
        "isolinux.cfg: %1",
        Ops.get_string(@Config, "bootconfig", "")
      )

      if Ops.get_string(@Config, "bootconfig", "") != ""
        Builtins.y2debug("custom config available")

        fname = Builtins.sformat(
          "%1/boot/%2/loader/isolinux.cfg",
          @skel_root,
          boot_arch
        )
        Builtins.y2milestone("Writing isolinux.cfg to %1", fname)

        SCR.Write(
          path(".target.string"),
          fname,
          Ops.get_string(@Config, "bootconfig", "")
        )
      end

      cpCmd = Builtins.sformat(
        "cp -- '%1/product-creator/message' '%2/boot/%3/loader'",
        String.Quote(Directory.datadir),
        String.Quote(@skel_root),
        boot_arch
      )

      Exec(cpCmd)

      cpCmd = Builtins.sformat(
        "cp -- '%1/product-creator/options.msg' '%2/boot/%3/loader'",
        String.Quote(Directory.datadir),
        String.Quote(@skel_root),
        boot_arch
      )

      Exec(cpCmd)

      true
    end

    def CheckUnavailableSources
      selected_items = UrlToId(Ops.get_list(@Config, "sources", []))

      # remove not found sources (with id = -1)
      selected_items = Builtins.filter(selected_items) do |source_id|
        Ops.greater_or_equal(source_id, 0)
      end

      # were all sources found?
      if Builtins.size(Ops.get_list(@Config, "sources", [])) !=
          Builtins.size(selected_items)
        not_found_sources = []

        # get list of missing sources
        Builtins.foreach(Ops.get_list(@Config, "sources", [])) do |selected_url|
          url_id = UrlToId([selected_url])
          if Ops.get(url_id, 0) == -1
            not_found_sources = Builtins.add(not_found_sources, selected_url)
          end
        end 


        # error message, %1 is list of URLs (one URL per line)
        Report.LongError(
          Builtins.sformat(
            _("These sources were not found:\n%1"),
            Builtins.mergestring(not_found_sources, "\n")
          )
        )
        return false
      end

      true
    end

    # Enable source and get source meta data
    # @return true on success
    def EnableSource
      Builtins.y2milestone("Config: %1", @Config)
      enableSources

      sources = UrlToId(Ops.get_list(@Config, "sources", []))

      ids = Pkg.SourceStartCache(true)

      return false if Builtins.size(ids) == 0

      Builtins.foreach(sources) do |i|
        m = {}
        Ops.set(m, "productData", Pkg.SourceProductData(i))
        Ops.set(m, "mediaData", Pkg.SourceMediaData(i))
        Ops.set(m, "sourceData", Pkg.SourceGeneralData(i))
        p = Ops.get_string(m, ["sourceData", "url"], "")
        parsed = URL.Parse(p)
        Ops.set(m, "path", Ops.get_string(parsed, "path", ""))
        Ops.set(@meta, i, m)
      end

      Builtins.y2milestone("meta: %1", @meta)
      true
    end


    # Get all possible sources
    # @return available enabled sources list for widget
    def GetDirSources(source)
      ids = Pkg.SourceStartCache(true)
      sources = []
      Builtins.foreach(ids) do |i|
        prod = Pkg.SourceProductData(i)
        media = Pkg.SourceMediaData(i)
        url = URL.Parse(Ops.get_string(media, "url", ""))
        if Ops.get_string(url, "scheme", "") == "dir"
          selected = source == Ops.get_string(url, "path", "")
          sources = Builtins.add(
            sources,
            Item(
              Id(Ops.get_string(url, "path", "")),
              Ops.get_string(url, "path", ""),
              selected
            )
          )
        end
      end

      deep_copy(sources)
    end


    def enableSources
      # used by standalone kiwi UI, which does onw sources handling...
      return if !@enable_sources

      # TODO FIXME: use better way to reset the source config in the package manager
      if @original_config != nil
        Builtins.y2milestone("Restoring original config: %1", @original_config)
        Pkg.SourceEditSet(@original_config)
        Pkg.SourceFinishAll
      else
        @original_config = Pkg.SourceEditGet
        Builtins.y2milestone(
          "Current source configuration: %1",
          @original_config
        )
      end

      Pkg.SourceStartManager(false)

      Builtins.y2milestone("sources: %1", Ops.get_list(@Config, "sources", []))
      sources = UrlToId(Ops.get_list(@Config, "sources", []))
      Builtins.y2milestone("source IDs: %1", sources)

      Builtins.foreach(Pkg.SourceGetCurrent(true)) do |id|
        Builtins.y2milestone("Disabling source %1", id)
        Pkg.SourceSetEnabled(id, false)
      end


      Builtins.foreach(sources) do |id|
        Builtins.y2milestone("Enabling source %1", id)
        Pkg.SourceSetEnabled(id, true)
      end

      Pkg.SourceStartManager(true)

      Builtins.y2milestone("All sources: %1", Pkg.SourceGetCurrent(false))
      Builtins.y2milestone("Enabled sources: %1", Pkg.SourceGetCurrent(true))

      nil
    end

    # Check if there is a language selected in the package manager,
    # if not then select the language used in the UI. Htis prevents the solver
    # from allocating too many resources (see bug #339756)
    def CheckLanguage
      if Pkg.GetPackageLocale == "" && Pkg.GetAdditionalLocales == []
        Builtins.y2warning(
          "No language selected, preselecting the current UI language: %1",
          UI.GetLanguage(true)
        )
        # if there is nothing selected yet then preset the language
        Pkg.SetPackageLocale(UI.GetLanguage(true))
      end

      nil
    end

    # Set packages to be copied to iso image tree
    # @return [Boolean]
    def setPackages
      base = Ops.get_string(@Config, "base", "")
      addons = Ops.get_list(@Config, "addons", [])
      packages = Ops.get_list(@Config, "packages", [])
      post_packages = Ops.get_list(@Config, "post-packages", [])
      kernel = Ops.get_string(@Config, "kernel", "")
      kernels = []

      if kernel == ""
        kernels = [
          "kernel-64k-pagesize",
          "kernel-bigsmp",
          "kernel-debug",
          "kernel-default",
          "kernel-smp",
          "kernel-sn2",
          "kernel-xen",
          "kernel-um",
          "kernel-vanilla"
        ]

        # add architecture dependent kernels
        # They might be available e.g. on an update source but they shoudln't be
        # added automatically because they might require unavailable packages
        # It can happen probably only on x86_64 when kernel-pae (i386 only)
        # is released on online update source (bnc#421995)
        arch = GetArch()

        if arch == "i386"
          kernels = Convert.convert(
            Builtins.union(kernels, ["kernel-pae", "kernel-xenpae"]),
            :from => "list",
            :to   => "list <string>"
          )
        elsif arch == "s390"
          kernels = Convert.convert(
            Builtins.union(kernels, ["kernel-s390"]),
            :from => "list",
            :to   => "list <string>"
          )
        elsif arch == "s390x"
          kernels = Convert.convert(
            Builtins.union(kernels, ["kernel-s390", "kernel-s390x"]),
            :from => "list",
            :to   => "list <string>"
          )
        elsif arch == "ppc64"
          kernels = Convert.convert(
            Builtins.union(
              kernels,
              [
                "kernel-iseries64",
                "kernel-pmac64",
                "kernel-pseries64",
                "kernel-ppc64"
              ]
            ),
            :from => "list",
            :to   => "list <string>"
          )
        end
      else
        kernels = Builtins.add(kernels, kernel)
      end


      if Ops.get_symbol(@Config, "type", :unknown) == :patterns
        # base pattern
        Pkg.ResolvableInstall(base, :pattern) if base != ""

        Builtins.foreach(addons) { |p| Pkg.ResolvableInstall(p, :pattern) } if Ops.greater_than(
          Builtins.size(addons),
          0
        )
      else
        Builtins.y2warning(
          "Unsupported software selection type: %1",
          Ops.get_symbol(@Config, "type", :unknown)
        )
      end

      packages = Convert.convert(
        Builtins.union(packages, post_packages),
        :from => "list",
        :to   => "list <string>"
      )
      packages = Convert.convert(
        Builtins.union(packages, kernels),
        :from => "list",
        :to   => "list <string>"
      )

      Builtins.y2milestone("Selected packages: %1", packages)

      Pkg.DoProvide(packages)

      CheckLanguage()

      # mark taboo packages
      taboo_packages = Ops.get_list(@Config, "taboo", [])

      if Ops.greater_than(Builtins.size(taboo_packages), 0)
        Builtins.y2milestone("Setting Taboo packages: %1", taboo_packages)
        MarkTaboo(taboo_packages)
      end

      ret = Pkg.PkgSolve(false)

      ret
    end

    def removeDestination
      isodir = Ops.add(
        Ops.add(Ops.get_string(@Config, "iso-directory", ""), "/"),
        Ops.get_string(@Config, "name", "")
      )
      Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("rm -rf -- '%1'", String.Quote(isodir))
        )
      ) == 0
    end

    def confirmDestinationRemoving
      # popup question, %1 is directory name
      if Popup.YesNo(
          Builtins.sformat(
            _("Remove the destination directory %1?"),
            Ops.add(
              Ops.add(Ops.get_string(@Config, "iso-directory", ""), "/"),
              Ops.get_string(@Config, "name", "")
            )
          )
        )
        # remove the destination
        return removeDestination
      end

      false
    end

    def verifyDestination
      isodir = Ops.add(
        Ops.add(Ops.get_string(@Config, "iso-directory", ""), "/"),
        Ops.get_string(@Config, "name", "")
      )
      if Ops.greater_than(
          Convert.to_integer(SCR.Read(path(".target.size"), isodir)),
          0
        )
        if Mode.commandline
          CommandLine.Print(
            Builtins.sformat(_("The destination %1 already exists."), isodir)
          )

          # TODO ask in interactive mode

          return false
        end
        if Popup.YesNo(
            Builtins.sformat(
              _(
                "Destination directory exists or is a file.\nRemove directory %1?"
              ),
              isodir
            )
          )
          Builtins.y2milestone("Removing directory %1", isodir)
          return removeDestination
        else
          Builtins.y2milestone("Directory %1 won't be removed", isodir)
        end
      end

      true
    end

    # Check if selected packages are available
    # @return [String] error message
    def checkPackageAvail
      error_msg = ""

      Progress.Title(_("Checking for package availability..."))

      selectedPackages = Pkg.GetPackages(:selected, true)
      Builtins.y2milestone(
        "Selected %1 packages: %2",
        Builtins.size(selectedPackages),
        Builtins.sort(selectedPackages)
      )

      failed = []
      @toCopy = {}

      versions = Builtins.listmap(Ops.get_list(@Config, "package_versions", [])) do |p|
        { Ops.get_string(p, "name", "") => Ops.get_string(p, "version", "") }
      end

      Builtins.foreach(selectedPackages) do |package|
        version = Ops.get(versions, package, "")
        package_data_list = Pkg.ResolvableProperties(package, :package, version)
        package_data = Ops.get(package_data_list, 0, {})
        if package_data == nil || package_data == {}
          failed = Builtins.add(failed, package)
        else
          Builtins.y2debug("package_data: %1", package_data)
          arch = Ops.get_string(package_data, "arch", "noarch")
          # find the package with correct version
          if version != ""
            package_data = {}
            Builtins.foreach(package_data_list) do |data|
              if Ops.get_string(data, "arch", "") == arch &&
                  Ops.get_string(data, "version", "") == version
                package_data = deep_copy(data)
              end
            end
          end

          src = Ops.get_integer(package_data, "source", -1)
          medianr = Ops.get_integer(package_data, "medium_nr", 1)

          pkglist = Ops.get(@toCopy, [src, medianr], [])

          pkglist = Builtins.add(
            pkglist,
            {
              "path" => Ops.get_string(package_data, "path", ""),
              "name" => package,
              "arch" => arch
            }
          )

          # add an empty map if the source doesn't exist
          Ops.set(@toCopy, src, {}) if !Builtins.haskey(@toCopy, src)

          Ops.set(@toCopy, [src, medianr], pkglist)
        end
      end
      @missing_packages = deep_copy(failed)
      if Ops.greater_than(Builtins.size(failed), 0)
        num = Builtins.size(failed)
        error_msg = Builtins.sformat(_("%1 package not available."), num)
      end
      Builtins.y2milestone("packages not found: %1", failed)
      Builtins.y2debug("Evaluated packages toCopy: %1", @toCopy)

      error_msg
    end


    def CallbackSourceReportStart(source_id, url, task)
      Builtins.y2debug("source_id: %1, url: %2, task: %3", source_id, url, task)

      nil
    end

    def CallbackSourceReportProgress(value)
      Builtins.y2debug("progress: %1%%", value)
      true
    end

    def CallbackSourceReportEnd(numeric_id, url, task, error, reason)
      Builtins.y2debug(
        "source_id: %1, url: %2, task: %3, error: %4, reason: %5",
        numeric_id,
        url,
        task,
        error,
        reason
      )

      nil
    end

    def InitDownload(task)
      Builtins.y2debug("InitDownload: %1", task)

      nil
    end

    def DestDownload
      Builtins.y2debug("DestDownload")

      nil
    end

    def StartDownload(url, localfile)
      # reformat the URL
      url_report = URL.FormatURL(URL.Parse(url), 60)

      if Mode.commandline
        CommandLine.PrintVerbose(url_report)
      else
        # change the label
        UI.ChangeWidget(
          Id(:pb),
          :Label,
          Builtins.sformat(_("Copying %1"), url_report)
        )
      end

      nil
    end


    def StartDownloadEmpty(url, localfile)
      Builtins.y2debug("StartDownload: %1", url)

      nil
    end

    def ProgressDownload(percent, bps_avg, bps_current)
      UI.PollInput != :abort
    end

    def RedirectCallbacks
      Pkg.CallbackSourceReportStart(
        fun_ref(
          method(:CallbackSourceReportStart),
          "void (integer, string, string)"
        )
      )
      Pkg.CallbackSourceReportProgress(
        fun_ref(method(:CallbackSourceReportProgress), "boolean (integer)")
      )
      Pkg.CallbackSourceReportEnd(
        fun_ref(
          method(:CallbackSourceReportEnd),
          "void (integer, string, string, symbol, string)"
        )
      )

      Pkg.CallbackInitDownload(fun_ref(method(:InitDownload), "void (string)"))
      Pkg.CallbackStartDownload(
        fun_ref(method(:StartDownload), "void (string, string)")
      )
      Pkg.CallbackProgressDownload(
        fun_ref(
          method(:ProgressDownload),
          "boolean (integer, integer, integer)"
        )
      )
      # use the standard callback handler
      Pkg.CallbackDoneDownload(
        fun_ref(
          PackageCallbacks.method(:DoneDownload),
          "void (integer, string)"
        )
      )
      Pkg.CallbackDestDownload(fun_ref(method(:DestDownload), "void ()"))

      nil
    end

    def ResetCallbacks
      Pkg.CallbackSourceReportStart(
        fun_ref(
          PackageCallbacks.method(:SourceReportStart),
          "void (integer, string, string)"
        )
      )
      Pkg.CallbackSourceReportProgress(
        fun_ref(
          PackageCallbacks.method(:SourceReportProgress),
          "boolean (integer)"
        )
      )
      Pkg.CallbackSourceReportEnd(
        fun_ref(
          PackageCallbacks.method(:SourceReportEnd),
          "void (integer, string, string, symbol, string)"
        )
      )

      Pkg.CallbackInitDownload(
        fun_ref(PackageCallbacks.method(:InitDownload), "void (string)")
      )
      Pkg.CallbackStartDownload(
        fun_ref(
          PackageCallbacks.method(:StartDownload),
          "void (string, string)"
        )
      )
      Pkg.CallbackProgressDownload(
        fun_ref(
          PackageCallbacks.method(:ProgressDownload),
          "boolean (integer, integer, integer)"
        )
      )
      Pkg.CallbackDoneDownload(
        fun_ref(
          PackageCallbacks.method(:DoneDownload),
          "void (integer, string)"
        )
      )
      Pkg.CallbackDestDownload(
        fun_ref(PackageCallbacks.method(:DestDownload), "void ()")
      )

      nil
    end

    # CopyPackages()
    # Copy selected package to target tree
    # @param integer id
    # @return [Boolean]
    def CopyPackages
      # TODO FIXME get datadir from the source
      datadir = "suse"
      basedir = Ops.add(
        Ops.add(
          Ops.add(Ops.get_string(@Config, "iso-directory", ""), "/"),
          Ops.get_string(@Config, "name", "")
        ),
        "/"
      )

      ret = true

      Builtins.y2milestone("Package summary: %1", @toCopy)

      Pkg.CallbackStartDownload(
        fun_ref(method(:StartDownloadEmpty), "void (string, string)")
      )

      # copy the packages
      Builtins.foreach(@toCopy) do |source, srcmapping|
        Builtins.foreach(srcmapping) do |medium, packages|
          Builtins.y2milestone(
            "Copying packages from source %1, medium %2",
            source,
            medium
          )
          Builtins.foreach(packages) do |package|
            Progress.Title(
              Builtins.sformat(
                _("Copying %1"),
                Ops.get_string(package, "name", "...")
              )
            )
            Progress.NextStep
            #string dir = basedir + product_map[source]:"/" + datadir + "/" + package["arch"]:"";
            dir = Ops.add(
              Ops.add(Ops.add(basedir, Ops.get(@product_map, source, "/")), "/"),
              Ops.get_string(package, "path", "")
            )
            dir_elements = Builtins.splitstring(dir, "/")
            dir_elements = Builtins.remove(
              dir_elements,
              Ops.subtract(Builtins.size(dir_elements), 1)
            )
            dir = Builtins.mergestring(dir_elements, "/")
            if SCR.Read(path(".target.dir"), dir) == nil
              Builtins.y2milestone("Creating dir: %1", dir)
              SCR.Execute(path(".target.mkdir"), dir)
              Builtins.y2debug(
                "dir contents: %1",
                Convert.to_list(SCR.Read(path(".target.dir"), dir))
              )
            end
            Builtins.y2milestone(
              "downloading package %1...",
              Ops.get_string(package, "path", "")
            )
            l_packge = Pkg.SourceProvideFile(
              source,
              medium,
              Ops.get_string(package, "path", "")
            )
            if l_packge == nil || l_packge == ""
              Report.Error(
                Builtins.sformat(
                  _("Cannot download package %1\n from source %2.\n"),
                  Ops.get_string(package, "path", ""),
                  source
                )
              )
              ret2 = false
              raise Break
            end
            cpCmd = Builtins.sformat(
              "cp -a '%1' '%2'",
              String.Quote(l_packge),
              String.Quote(dir)
            )
            Builtins.y2debug("%1", cpCmd)
            ret2 = SCR.Execute(path(".target.bash"), cpCmd)
            if ret2 != 0
              Popup.Error(
                _(
                  "Error while copying packages. \n\t\t    Check the created directory for possible hints."
                )
              )
              ret2 = false
              raise Break
            end
          end
        end
      end 



      Builtins.foreach(@product_map) do |src_ind, subdir|
        general_info = Pkg.SourceGeneralData(src_ind)
        # regenerate the metadata
        if Ops.get_string(general_info, "type", "") == "YUM"
          ret = ret &&
            Exec(
              Builtins.sformat(
                "/usr/bin/createrepo '%1/%2'",
                String.Quote(basedir),
                String.Quote(subdir)
              )
            )
        else
          # TODO FIXME get datadir from the source
          ret = ret &&
            Exec(
              Builtins.sformat(
                "cd '%1/%2/%3' && /usr/bin/create_package_descr -x setup/descr/EXTRA_PROV -M 3",
                String.Quote(basedir),
                String.Quote(subdir),
                String.Quote(datadir)
              )
            )

          # check if the metadata are gzipped
          compressed_meta = FileUtils.Exists(
            Builtins.sformat(
              "%1/%2/%3/setup/descr/packages.DU.gz",
              basedir,
              subdir,
              datadir
            )
          )
          Builtins.y2milestone("Compressed metadata: %1", compressed_meta)

          if compressed_meta
            ret = ret &&
              Exec(
                Builtins.sformat(
                  "cd '%1/%2/%3/setup/descr/' && gzip -9 -f packages packages.DU packages.en",
                  String.Quote(basedir),
                  String.Quote(subdir),
                  String.Quote(datadir)
                )
              )
          end
        end
      end 


      Pkg.CallbackStartDownload(
        fun_ref(method(:StartDownload), "void (string, string)")
      )

      ret
    end



    def readControlFile(filename)
      return true if @profile_parsed
      if !Profile.ReadXML(filename)
        Report.Error(_("Error reading control file."))
        return false
      end
      Builtins.y2debug("Current profile: %1", Profile.current)

      software = Ops.get_map(Profile.current, ["install", "software"], {})

      if Builtins.size(software) == 0
        software = Ops.get_map(Profile.current, "software", {})
      end

      Builtins.y2milestone("Software config: %1", software)

      if Builtins.haskey(software, "patterns")
        Builtins.y2milestone("Switching to profile based config")
        Ops.set(@Config, "type", :patterns)
        pats = Ops.get_list(software, "patterns", [])
        Ops.set(@Config, "base", Ops.get(pats, 0, ""))

        if Ops.greater_than(Builtins.size(pats), 1)
          Ops.set(@Config, "addons", Builtins.remove(pats, 0))
        end
      else
        Builtins.y2milestone("Using selections based config")
        Ops.set(@Config, "base", Ops.get_string(software, "base", ""))
        Ops.set(@Config, "addons", Ops.get_list(software, "addons", []))
      end

      PackageAI.toinstall = Ops.get_list(software, "packages", [])
      Ops.set(@Config, "packages", AutoinstSoftware.autoinstPackages)

      # add "post-packages"
      post_packages = Ops.get_list(software, "post-packages", [])
      if Ops.greater_than(Builtins.size(post_packages), 0)
        Builtins.y2milestone("Adding \"post-packages\": %1", post_packages)
        Ops.set(
          @Config,
          "packages",
          Builtins.union(Ops.get_list(@Config, "packages", []), post_packages)
        )
      end

      # TODO: remove also "remove-packages" from the list?
      # Is it safe to remove them due to possible dependencies??

      Builtins.y2milestone("Config: %1", @Config)
      @profile_parsed = true
      true
    end

    # Enable needed repositories
    #
    # The idea is to make patterns/packages available during selection
    # (bsc#1028661). The list of enabled repositories is stored at
    # ProductCreator.Config.
    #
    # @param selected [Array<Integer>] Selected sources
    # @see restore_repos_state
    def enable_needed_repos(selected)
      self.tmp_enabled = selected.each_with_object([]) do |src, list|
        general_info = Pkg.SourceGeneralData(src)
        list << src unless general_info["enabled"]
      end

      tmp_enabled.each do |src|
        log.info "Enabling and refreshing repository #{src}"
        Pkg.SourceSetEnabled(src, true)
        Pkg.SourceRefreshNow(src)
      end
    end

    # Restore repositories state
    #
    # Undo changes introduced by #enabled_needed_repos.
    #
    # @see enable_needed_repos
    def restore_repos_state
      tmp_enabled.each do |src|
        log.info "Disabling repository #{src}"
        Pkg.SourceSetEnabled(src, false)
      end
      tmp_enabled.clear
    end

    # Constructor
    def ProductCreator
      configSetup
      if FileUtils.Exists("/etc/sysconfig/autoinstall")
        @AYRepository = Misc.SysconfigRead(
          path(".sysconfig.autoinstall.REPOSITORY"),
          "/var/lib/autoinstall/repository/"
        )
      end

      nil
    end

    publish :function => :enableSources, :type => "void ()"
    publish :function => :checkProductDependency, :type => "integer ()"
    publish :function => :readControlFile, :type => "boolean (string)"
    publish :function => :EnableSource, :type => "boolean ()"
    publish :variable => :AYRepository, :type => "string"
    publish :variable => :meta, :type => "map"
    publish :variable => :meta_local, :type => "map"
    publish :variable => :missing_packages, :type => "list <string>"
    publish :variable => :skel_root, :type => "string"
    publish :variable => :profile_parsed, :type => "boolean"
    publish :variable => :max_size_mb, :type => "integer"
    publish :variable => :Config, :type => "map <string, any>"
    publish :variable => :Configs, :type => "map <string, map <string, any>>"
    publish :variable => :Rep, :type => "string"
    publish :variable => :ConfigFile, :type => "string"
    publish :variable => :gpg_passphrase, :type => "string"
    publish :variable => :AbortFunction, :type => "block <boolean>"
    publish :function => :SetPackageArch, :type => "boolean (string)"
    publish :function => :GetArch, :type => "string ()"
    publish :function => :GetPackageArch, :type => "string ()"
    publish :function => :ResetArch, :type => "void ()"
    publish :variable => :modified, :type => "boolean"
    publish :variable => :proposal_valid, :type => "boolean"
    publish :variable => :enable_sources, :type => "boolean"
    publish :function => :Modified, :type => "boolean ()"
    publish :function => :Abort, :type => "boolean ()"
    publish :function => :PollAbort, :type => "boolean ()"
    publish :function => :ReallyAbort, :type => "boolean ()"
    publish :function => :MarkTaboo, :type => "void (list <string>)"
    publish :function => :LoadConfig, :type => "boolean (string)"
    publish :function => :CommitConfig, :type => "void ()"
    publish :function => :PackageCount, :type => "integer ()"
    publish :function => :UrlToId, :type => "list <integer> (list <string>)"
    publish :function => :ReadContentFile, :type => "map <string, string> (integer)"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :PrepareConfigs, :type => "list ()"
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "list ()"
    publish :function => :Overview, :type => "list ()"
    publish :function => :getSourceURLs, :type => "list (list <integer>)"
    publish :function => :getSourceDir, :type => "string (string)"
    publish :function => :Readisolinux, :type => "string ()"
    publish :function => :configSetup, :type => "void ()"
    publish :function => :UpdateContentFile, :type => "boolean (string, string)"
    publish :function => :UpdateMD5File, :type => "boolean (string)"
    publish :function => :CreateProductDirectoryMap, :type => "map <integer, string> (integer)"
    publish :function => :CreateAddonFile, :type => "string (map <integer, string>)"
    publish :function => :BootFiles, :type => "list <string> (integer)"
    publish :function => :WritePatternFile, :type => "boolean (string, list <map>)"
    publish :function => :GetBootInfoRepo, :type => "map <string, any> (integer)"
    publish :function => :GetBootInfo, :type => "map <string, any> ()"
    publish :function => :CreateSkeleton, :type => "boolean (integer, boolean, string)"
    publish :function => :InsertKeyToInitrds, :type => "boolean (string, string)"
    publish :function => :SignSUSEtagsSource, :type => "boolean (string, string, string)"
    publish :function => :SignYUMSource, :type => "boolean (string, string, string)"
    publish :function => :UpdateContentFiles, :type => "boolean ()"
    publish :function => :SignSourceStep, :type => "boolean ()"
    publish :function => :CopyMiscFiles, :type => "boolean (string)"
    publish :function => :CheckUnavailableSources, :type => "boolean ()"
    publish :function => :GetDirSources, :type => "list <term> (string)"
    publish :function => :CheckLanguage, :type => "void ()"
    publish :function => :setPackages, :type => "boolean ()"
    publish :function => :removeDestination, :type => "boolean ()"
    publish :function => :confirmDestinationRemoving, :type => "boolean ()"
    publish :function => :verifyDestination, :type => "boolean ()"
    publish :function => :checkPackageAvail, :type => "string ()"
    publish :function => :CallbackSourceReportStart, :type => "void (integer, string, string)"
    publish :function => :CallbackSourceReportProgress, :type => "boolean (integer)"
    publish :function => :CallbackSourceReportEnd, :type => "void (integer, string, string, symbol, string)"
    publish :function => :InitDownload, :type => "void (string)"
    publish :function => :DestDownload, :type => "void ()"
    publish :function => :StartDownload, :type => "void (string, string)"
    publish :function => :StartDownloadEmpty, :type => "void (string, string)"
    publish :function => :ProgressDownload, :type => "boolean (integer, integer, integer)"
    publish :function => :RedirectCallbacks, :type => "void ()"
    publish :function => :ResetCallbacks, :type => "void ()"
    publish :function => :CopyPackages, :type => "boolean ()"
    publish :function => :ProductCreator, :type => "void ()"
  end

  ProductCreator = ProductCreatorClass.new
  ProductCreator.main
end
