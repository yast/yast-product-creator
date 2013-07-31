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

# File:	include/product-creator/routines.ycp
# Package:	Configuration of product-creator
# Summary:	Miscelanous functions for configuration of product-creator.
# Authors:	Anas Nashif <nashif@suse.de>
#
# $Id$
module Yast
  module ProductCreatorRoutinesInclude
    def initialize_product_creator_routines(include_target)
      textdomain "product-creator"

      Yast.import "Kiwi"
      Yast.import "Progress"
    end

    # shortcut for returning "descripton" value from a map describing config.xml
    def get_description(config, key)
      config = deep_copy(config)
      Ops.get_string(config, ["description", 0, key, 0, Kiwi.content_key], "")
    end

    # shortcut for returning "preferences" value from a map describing config.xml
    def get_preferences(config, key, defval)
      config = deep_copy(config)
      defval = deep_copy(defval)
      Builtins.sformat(
        "%1",
        Ops.get(config, ["preferences", 0, key, 0, Kiwi.content_key], defval)
      )
    end

    # update the whole map with a new key in preferences section
    def save_preferences(config, key, val)
      config = deep_copy(config)
      Ops.set(config, ["preferences", 0, key], [{ Kiwi.content_key => val }])
      deep_copy(config)
    end

    # get the primary value of image type to be built ('type' from 'preferences')
    def get_current_task(config)
      config = deep_copy(config)
      task = ""
      Builtins.foreach(Ops.get_list(config, ["preferences", 0, "type"], [])) do |typemap|
        if task == "" # take the 1st one if none is default
          task = Ops.get_string(typemap, "image", task)
        end
        if Builtins.tolower(Ops.get_string(typemap, "primary", "false")) == "true"
          task = Ops.get_string(typemap, "image", task)
          raise Break
        end
      end
      if task == ""
        Builtins.y2milestone("no task found, setting to 'iso'")
        task = "iso"
      end
      task
    end

    # return the size info for current image type
    def get_current_size_map(config, task)
      config = deep_copy(config)
      ret = {}
      Builtins.foreach(Ops.get_list(config, ["preferences", 0, "type"], [])) do |typemap|
        if task == Ops.get_string(typemap, "image", "")
          ret = Ops.get_map(typemap, ["size", 0], {})
        end
      end
      deep_copy(ret)
    end


    # get the value of boot image directory
    def get_bootdir(config, task)
      config = deep_copy(config)
      dir = ""
      Builtins.foreach(Ops.get_list(config, ["preferences", 0, "type"], [])) do |typemap|
        if task == Ops.get_string(typemap, "image", "")
          dir = Ops.get_string(typemap, "boot", "")
          raise Break
        end
      end
      dir
    end
  end
end
