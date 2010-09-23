-- load-pbrt.lua -- Load a PBRT scene file
--
--  Copyright (C) 2010  Miles Bader <miles@gnu.org>
--
-- This source code is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation; either version 3, or (at
-- your option) any later version.  See the file COPYING for more details.
--
-- Written by Miles Bader <miles@gnu.org>
--

--
-- This is a snogray loader for scene files intended for the PBRT
-- renderer ("Physically Based Ray Tracer"; see http://pbrt.org),
-- which use a vaguely Renderman-style syntax.  It works pretty well
-- for many scenes (the geometry, at least, is almost always correct),
-- and is quite fast (actually faster than PBRT's native yacc/lex-
-- based loader in many cases).  Of course there are some issues:
--
-- + Not all materials/lights/shapes/shape-parameters, etc are
--   supported.  When it's reasonable to substitute something else,
--   use an approximation, or simply ignore a parameter, that is done;
--   otherwise loading fails with an appropriate error.
--
-- + Most "global" options (integrators, output file, etc) are not
--   supported, as there's currently no mechanism to transfer those
--   from the scene loader to snogray.  These are ignored with an
--   appropriate warning message; often it's possible for the user to
--   then use an equivalent command-line option.
--
-- + It loads PBRT v2 scene files; notable differences from v1:
--   * "LookAt" handedness is reversed (to correct scene files intended
--     for PBRT v1, add "Scale 1 1 -1" before the LookAt directive)
--   * Include files are searched for relative to the including file
--


local lpeg = require 'lpeg'
local lu = require 'lpeg-utils'


-- local abbreviations for lpeg primitives
local P, R, S, C = lpeg.P, lpeg.R, lpeg.S, lpeg.C

local parse_err = lu.parse_err
-- parse_warn is actually a real function below


----------------------------------------------------------------
-- utility functions
--

-- we use these in various places
--
local mod = math.mod
local smatch = string.match

local function push (stack, thing)
   stack[#stack + 1] = thing
end
local function pop (stack)
   -- in the case of an empty stack, nil is returned
   local tos = stack[#stack]
   stack[#stack] = nil
   return tos
end

local function find_file (name, state)
   -- The original PBRT always just opens files relative to the CWD,
   -- and scen files tend to assume that will be the directory the
   -- base scene file is in.  Newer versions of PBRT open files
   -- relative to the directory the referencing scene file is in.
   -- For compatibility, we try both (first the latter, then the
   -- former).

   local cur_rel_name = filename_in_dir (name, filename_dir (state.filename))
   local base_rel_name = filename_in_dir (name, state.base_dir)

   local try = io.open (cur_rel_name, "r")
   if (try) then
      try:close()
      return cur_rel_name
   else
      return base_rel_name
   end
end

local max_identical_warning_msgs = 3
local warning_msg_counts = {}

-- A wrapper around lu.parse_warn that suppresses excess numbers of
-- warning messages.
--
local function parse_warn (msg)
   local count = warning_msg_counts[msg] or 0
   if count < max_identical_warning_msgs then
      warning_msg_counts[msg] = count + 1
      if count + 1 == max_identical_warning_msgs then
	 msg = msg.." (further warnings suppressed)"
      end
      lu.parse_warn (msg)
   end
end


----------------------------------------------------------------
-- lexical elements; these mostly include optional preceding
-- whitespace, to make uses of them more concise.

-- low-level
--
local COMMENT = lpeg.P"#" * lu.LINE
local SYNC = lu.ERR_POS
-- The following is about 5% faster on some big files than the more
--   obvious WS = (lu.REQ_WS + COMMENT)^0
local WS = lu.OPT_WS * (COMMENT * lu.OPT_WS)^0
local NUM = WS * lu.FLOAT
local STRING_ESC_NL = P"n" * lpeg.Cc("\n")
local STRING_ESC_TAB = P"t" * lpeg.Cc("\t")
local STRING_ESC_CONT = P"\n" * lpeg.Cc("")
local STRING_ESC_LIT = lpeg.C (S"\\\"")
local STRING_ESC = S"\\" * (STRING_ESC_NL + STRING_ESC_TAB + STRING_ESC_CONT + STRING_ESC_LIT)
local STRING_SPAN = lpeg.C ((1 - S"\\\"")^1)
local STRING_CONTENTS = lpeg.Cf ((STRING_SPAN + STRING_ESC)^0,
			   function (x,y) return x..y end)
local STRING = WS * P"\"" * SYNC * STRING_CONTENTS * P"\""

-- arrays
--
local NUM_ARRAY = lpeg.Ct ((WS * P"[" * SYNC * NUM^0 * WS * SYNC * P"]") + NUM)
local STRING_ARRAY = lpeg.Ct ((WS * P"[" * SYNC * STRING^0 * WS * SYNC * P"]") + STRING)
local ARRAY = NUM_ARRAY + STRING_ARRAY


----------------------------------------------------------------
-- parameter-list parsing
--

local function validate_stride_3_array_param (ctor, name, val, vtype)
   if vtype ~= "number" then
      parse_err ("parameter \""..name.."\" values must be numeric")
   end
   if mod (#val, 3) ~= 0 then
      parse_err ("parameter \""..name.."\" must have a multiple of 3 values")
   end

   -- if CTOR is a function, then we use it to encapsulate the items
   --
   if ctor then
      local new_val = {}
      for i = 1, #val, 3 do
	 new_val[#new_val + 1] = ctor (val[i], val[i+1], val[i+2])
      end
      val = new_val
   end

   return name, val
end

local function validate_string_param (name, val, vtype)
   if vtype ~= "string" then
      parse_err ("parameter \""..name.."\" values must be strings")
   end
   return name, val
end

local function validate_color_param (name, val, vtype)
   -- a single string is ok too, as it may be a constant-texture name
   if vtype == 'string' and #val == 1 then
      return name, val
   else
      return validate_stride_3_array_param (color, name, val, vtype)
   end
end


local param_validators = {
   float
      = function (name, val, vtype)
	   -- a single string is ok too, as it may be a constant-texture name
	   if vtype ~= "number" and (vtype ~= 'string' or #val ~= 1) then
	      parse_err ("parameter \""..name.."\" values must be numeric")
	   end
	   return name, val
	end,
   string = validate_string_param,
   texture = validate_string_param,
   integer
      = function (name, val, vtype)
	   if vtype ~= "number" then
	      parse_err ("parameter \""..name.."\" values must be numeric")
	   end
	   for _, v in ipairs (val) do
	      if mod (v, 1) ~= 0 then
		 parse_err ("parameter \""..name.."\" values must be integers")
	      end
	   end
	   return name, val
	end,
   bool
      = function (name, val, vtype)
	   for k, v in ipairs (val) do
	      if v == "false" then
		 val[k] = false
	      elseif v == "true" then
		 val[k] = true
	      else
		 parse_err ("parameter \""..name.."\" values must be \"true\" or \"false\"")
	      end
	   end
	   return name, val
	end,

   color = validate_color_param,
   rgb = function (name, val, vtype)
	    name, val = validate_color_param (name, val, vtype)
	    return "color "..smatch (name, " (.*)"), val
	 end,

   point = function (...) return validate_stride_3_array_param (false, ...) end,
   vector = function (...) return validate_stride_3_array_param (false, ...) end,
   normal = function (...) return validate_stride_3_array_param (false, ...) end,

   spectrum = validate_string_param
}

local function validate_param (name, val)
   local vtype = type (val[1])
   local ptype = smatch (name, "%a*")
   local validator = param_validators[ptype]
   if validator then
      return validator (name, val, vtype)
   else
      parse_err ("invalid type \""..ptype.."\" in parameter \""..name.."\"")
   end
end

local function accum_param (table, param, val)
   if next (table) == nil then
      table = {}  -- make new table, since lpeg.Cc doesn't
   end
   table[param] = val
   return table
end

-- param grammar
--
local PARAM = (STRING * ARRAY) / validate_param
local PARAM_LIST = lpeg.Cf (lpeg.Cc{} * PARAM^0, accum_param)


----------------------------------------------------------------
-- spectrums
--

-- Load the spectrum file FILENAME and return its contents.
--
local function load_spectrum (filename, state)
   filename = find_file (filename, state)

   local spectrum = state.spectrums[filename]

   if not spectrum then
      spectrum = {}

      local function add_entry (lambda, val)
	 spectrum[#spectrum + 1] = {lambda, val}
      end

      local OWS = lu.OPT_HORIZ_WS
      local RWS = lu.REQ_HORIZ_WS
      local NUM = lu.FLOAT
      local ENTRY = (NUM * RWS * NUM * OWS) / add_entry
      local LINE = SYNC * OWS * (ENTRY + COMMENT) * lu.NL

      lu.parse_file (filename, LINE)

      print ("* loaded "..tostring(#spectrum).." entries from: "
	     ..filename_rel(filename, state.base_dir))

      state.spectrums[filename] = spectrum
   end

   return spectrum
end

-- Translate (badly) SPECTRUM to a color.
--
local function spectrum_to_color (spectrum)
   -- just lookup the values at the center of the sRGB primaries
   local r = linear_interp_lookup (spectrum, 610) [2]
   local g = linear_interp_lookup (spectrum, 550) [2]
   local b = linear_interp_lookup (spectrum, 465) [2]
   return color (r, g, b)
end


----------------------------------------------------------------
-- parameter-list access
--

-- If NAME is a string like "A/B/C/... X" puts entries like "A X", "B
-- X", "C X", ..., into TABLE; for any other string, just put NAME
-- into TABLE.  If NAME is a TABLE, recursively process each element.
--
local function split_param_name (name, table)
   if type (name) == 'table' then
      for i = 1, #name do
	 table = split_param_name (name[i], table or {})
      end
   else
      local first_name_prefix = smatch (name, "^(%a*)/")
      if first_name_prefix then
	 local first_name = first_name_prefix..smatch (name, " .*")
	 local rest_of_name = string.sub (name, #first_name_prefix + 2)
	 table = split_param_name (rest_of_name, table or {})
	 table[#table + 1] = first_name
      elseif table then
	 table[#table + 1] = name
      else
	 table = name
      end
   end
   return table
end

-- If NAME is a string (and doesn't match the pattern described in the
-- next paragraph), looks up NAME in PARAMS, and if found, return
-- remove NAME from PARAMS and return value and NAME as two return
-- values.  If the parameter does not exist and DEFAULT is not nil,
-- DEFAULT is returned; otherwise an error is signalled.
--
-- If NAME is a table, then this function is recursively called with
-- each element of the table until a non-nil value is found, and then
-- that value found and its name are returned.  If none is found, then
-- DEFAULT is returned as above.
--
-- If NAME is a string of the form "A/B/... X", then NAME is split
-- into a table of strings of the form {"A B", "B X", "C X", ...}, and
-- the table looked up as per the previous paragraph.
--
local split_name_cache = {}
local function get_param (state, params, name, default)
   -- We cache multi-type names that should be split into a table
   --
   local pname = split_name_cache[name]
   if not pname then
      pname = split_param_name (name)
      split_name_cache[name] = pname
   end

   if type (pname) == 'table' then
      -- A table of names, try to lookup each one, and only give an
      -- error if none is found.

      for i = 1, #pname do
	 local val, found = get_param (state, params, pname[i], false)
	 if found then
	    return val, found
	 end
      end

      if default ~= nil then
	 return default
      else
	 local err_name = nil
	 for i = 1, #pname do
	    local one_name = "\""..pname[i].."\""
	    if err_name then
	       err_name = err_name.." or "..one_name
	    else
	       err_name = one_name
	    end
	 end
	 parse_err ("missing "..err_name.." parameter")
      end
   else
      -- A single name, just look it up in the param list.

      local val = params[pname]
      if val ~= nil then
	 params[pname] = nil -- remove the entry from PARAMS
	 return val, pname
      elseif default ~= nil then
	 return default
      else
	 parse_err ("missing \""..pname.."\" parameter")
      end
   end
end

-- If NAME is a string (and doesn't match the pattern described in the
-- next paragraph), look up NAME in PARAMS; if found, and has a single
-- value, remove the entry from PARAMS return the value and NAME as
-- two return values.  If the parameter exists but has multiple
-- values, then an error is signalled.  If the parameter does not
-- exist and DEFAULT is not nil, DEFAULT is returned; otherwise an
-- error is signalled.
--
-- If NAME is a table, then this function is recursively called with
-- each element of the table until a non-nil value is found, and then
-- that value found and its name are returned.  If none is found, then
-- DEFAULT is returned as above.
--
local function get_single_param (state, params, name, default)
   local val, found = get_param (state, params, name, default)

   if found then
      if #val ~= 1 then
	 parse_err ("\""..found.."\" parameter requires a single value")
      end

      val = val[1]
   end

   return val, found
end


local texture_param_names_cache = {}

-- If NAME is a string (and doesn't match the pattern described in the
-- next paragraph), look up both NAME and NAME with "texture"
-- substituted for the first word in PARAMS.  If a single string value
-- is found, then remove the entry from PARAMS and return the texture
-- with that name (signalling an error if there is no texture by that
-- name), and NAME, as two return values.  Otherwise, if there's a
-- non-string single value, remove it from PARAMS and return it and
-- NAME.  If the parameter exists but has multiple values, then an
-- error is signalled.  If the parameter does not exist and DEFAULT is
-- not nil, DEFAULT is returned; otherwise an error is signalled.
--
-- If NAME is a table, then this function is recursively called with
-- each element of the table until a non-nil value is found, and then
-- that value found and its name are returned.  If none is found, then
-- DEFAULT is returned as above.
--
local function get_texture_param (state, params, name, default)
   -- Convert NAME into a list of NAME and NAME with "texture"
   -- substituted for the first word.  We also handle lists of names
   --
   local pname = texture_param_names_cache[name]
   if not pname then
      pname = {}

      -- If NAME is a string, add NAME and NAME with "texture"
      -- substituted for the first word to the end of the table PNAME.
      -- If NAME is a table, recursively call add_texture_param_names
      -- on each of its elements.
      --
      local function add_texture_param_names (name)
	 if type (name) == 'table' then
	    for i = 1, #name do
	       add_texture_param_names (name[i])
	    end
	 else
	    pname[#pname + 1] = name
	    pname[#pname + 1] = "texture"..smatch(name, " .*")
	 end
      end

      add_texture_param_names (name)

      texture_param_names_cache[name] = pname
   end

   -- Now look up both of them.
   --
   local val, found = get_single_param (state, params, pname, default)

   if found then
      -- Handle named texture references.
      --
      if type (val) == 'string' then
	 local tname = val
	 val = state.named_textures[tname]
	 if not val then
	    parse_err ("parameter \""..found
			  .."\" used unknown texture \""..tname.."\"")
	 end
      end
   end

   return val, found
end

local function get_point_param (state, params, name, default)
   local val, found = get_param (state, params, name, default)
   if found then
      if #val ~= 3 then
	 parse_err ("\""..name.."\" parameter requires a single point")
      end
      val = pos (unpack (val))
   end
   return val, found
end

local function get_vector_param (state, params, name, default)
   local val, found = get_param (state, params, name, default)
   if found then
      if #val ~= 3 then
	 parse_err ("\""..name.."\" parameter requires a single vector")
      end
      val = vec (unpack (val))
   end
   return val, found
end

local function get_spectrum_param (state, params, name, default)
   local filename, found = get_single_param (state, params, name, default)
   local spectrum = default
   if found then
      spectrum = load_spectrum (filename, state)
   end
   return spectrum, found
end

-- This handles both "color xxx" and "spectrum xxx" and does a dodgy job
-- of translating the latter to a color...
--
local spectrum_param_names_cache = {}
local function get_color_param (state, params, name, default)
   local color, found = get_single_param (state, params, name, false)
   if not found then
      local sname = spectrum_param_names_cache[name]
      if not sname then
	 sname = "spectrum"..smatch(name, " .*")
	 spectrum_param_names_cache[name] = sname
      end
      color, found = get_single_param (state, params, sname, default)
      if found and type (color) == 'string' then
	 local sn = color
	 color = spectrum_to_color (load_spectrum (color, state))
	 print ("* loaded spectrum \""..sn.."\" as "..tostring(color))
      end
   end
   return color, found
end

-- Signal an error for any parameter remaining in PARAMS.
--
local function check_unused_params (params)
   for param in pairs (params) do
      parse_err ("invalid parameter \""..param.."\"")
   end
end


----------------------------------------------------------------
-- materials
--

local material_parsers = {}

-- matte (lambertian)
--
function material_parsers.matte (state, params)
   -- ignored params: "float sigma"
   local kd = get_texture_param (state, params, "color Kd", 1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   params["float sigma"] = nil -- ignore
   params["texture sigma"] = nil -- ignore
   return lambert {kd, bump = bump}
end

-- clay (not implemented; workaround: use cook_torrance)
--
function material_parsers.clay (state, params)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   local kd = {0.383626, 0.260749, 0.274207}
   return lambert {kd, bump = bump}
end

-- "bluepaint" (not implemented; workaround: use cook_torrance)
--
function material_parsers.bluepaint (state, params)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   local kd = {0.3094, 0.39667, 0.70837}
   return cook_torrance {d = kd, s = .6, m = .5, bump = bump}
end

-- plastic (cook-torrance)
--
function material_parsers.plastic (state, params)
   local kd = get_texture_param (state, params, "color Kd", 1)
   local ks = get_texture_param (state, params, "color Ks", 1) * 5
   local rough = get_texture_param (state, params, "float roughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   return cook_torrance {d = kd, s = ks, m = rough, bump = bump}
end

-- translucent (cook-torrance, just ignore translucency)
--
function material_parsers.translucent (state, params)
   local kd = get_texture_param (state, params, "color Kd", 1)
   local ks = get_texture_param (state, params, "color Ks", 1) * 5
   local rough = get_texture_param (state, params, "float roughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   params["color reflect"] = nil -- ignore
   params["texture reflect"] = nil -- ignore
   params["color transmit"] = nil -- ignore
   params["texture transmit"] = nil -- ignore
   return cook_torrance {d = kd, s = ks, m = rough, bump = bump}
end

-- glass
--
function material_parsers.glass (state, params)
   -- unsupported params: "texture index"
   -- ignored params: "color Kr", "color Kt"   
   local ior = get_single_param (state, params, "float index", 1.5)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   params["color Kr"] = nil
   params["texture Kr"] = nil
   params["color Kt"] = nil
   params["texture Kt"] = nil
   return glass {ior = ior, bump = bump}
end

-- mirror
--
function material_parsers.mirror (state, params)
   local kr = get_texture_param (state, params, "color Kr", 1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   return mirror {reflectance = kr, bump = bump}
end

-- uber (not implemented; workaround: use cook-torrance)
--
function material_parsers.uber (state, params)
   -- ignored params: "color/float opacity", "color Kr"
   local kd = get_texture_param (state, params, "color Kd", 1)
   local ks = get_texture_param (state, params, "color Ks", 1)
   local kr,krn = get_texture_param (state, params, "color Kr", false)
   local rough = get_texture_param (state, params, "float roughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   local opacity,opacityn
      = get_texture_param (state, params, "float/color opacity", 1)
   -- warn about stuff that we're ignoring, but might actually be important
   if kr and kr ~= color(0) then
      parse_warn ("\""..krn.."\" parameter ignored")
   end
   if opacity ~= 1 then
      -- ignore, but it's important enough to warn about
      parse_warn ("\""..opacityn.."\" parameter ignored")
   end
   return cook_torrance {d = kd, s = ks, m = rough, bump = bump}
end

-- substrate (not implement; workaround: use cook-torrance)
--
function material_parsers.substrate (state, params)
   local kd = get_texture_param (state, params, "color Kd", .5)
   local ks = get_texture_param (state, params, "color Ks", .5)
   local urough = get_texture_param (state, params, "float uroughness", .1)
   local vrough = get_texture_param (state, params, "float vroughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   -- we just cheat and mix urough and vrough together...
   local rough = (urough + vrough) / 2  -- handles both textures and floats
   -- tweak params to try and match...
   ks = ks * 2
   return cook_torrance {d = kd, s = ks, m = rough, bump = bump}
end

-- shinymetal (we use cook-torrance with an appropriate IOR)
--
function material_parsers.shinymetal (state, params)
   local kd = get_texture_param (state, params, "color Kd", 1)
   local ks = get_texture_param (state, params, "color Ks", 1)
   local rough = get_texture_param (state, params, "float roughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   --ks = ks * 2
   return cook_torrance {d = kd, s = ks, m = rough, ior = {0.15, 3}, bump = bump}
end

-- metal (we use cook-torrance with an appropriate IOR)
--
function material_parsers.metal (state, params)
   local eta = get_spectrum_param (state, params, "spectrum eta")
   local k = get_spectrum_param (state, params, "spectrum k")
   local rough = get_texture_param (state, params, "float roughness", .1)
   local bump = get_texture_param (state, params, "float bumpmap", false)
   -- just cheat and use a fixed wavelength of 550nm (green light)
   local lambda = 550
   eta = linear_interp_lookup (eta, lambda) [2]
   k = linear_interp_lookup (k, lambda) [2]
   return cook_torrance {d = 0, s = 1, m = rough, ior = ior(eta,k), bump = bump}
end


----------------------------------------------------------------
-- textures
--

local function apply_texture_2d_mapping (tex, state, params)
   local mapping = get_single_param (state, params, "string mapping", "uv")
   if mapping == "uv" then
      -- default mapping
      local su = get_single_param (state, params, "float uscale", 1)
      local sv = get_single_param (state, params, "float vscale", 1)
      local du = get_single_param (state, params, "float udelta", 0)
      local dv = get_single_param (state, params, "float vdelta", 0)
      if su ~= 1 or sv ~= 1 then
	 tex = tex * scale (su, sv)
      end
      if du ~= 0 or dv ~= 0 then
	 tex = tex * translate (du, dv)
      end
   elseif mapping == "spherical" then
      tex = state.xform (lat_long_map_tex (tex))
   elseif mapping == "cylindrical" then
      tex = state.xform (cylinder_map_tex (tex))
   elseif mapping == "planar" then
      local v1 = get_vector_param (state, params, "vector v1", vec(1,0,0))
      local v2 = get_vector_param (state, params, "vector v2", vec(0,1,0))
      local du = get_single_param (state, params, "float udelta", 0)
      local dv = get_single_param (state, params, "float vdelta", 0)
      local up = cross (v1, v2)
      local pxf = xform{v1.x, up.x, v2.x, du,
			v1.y, up.y, v2.y, dv,
			v1.z, up.z, v2.z, 0,
			0,    0,    0,     1}
      tex = pxf (plane_map_tex (tex))
   else
      parse_err ("unknown 2d texture mapping \""..mapping.."\"")
   end
   return tex
end

local texture_parsers = {}

-- checkerboard texture
--
function texture_parsers.checkerboard (state, type, params)
   local dims = get_single_param (state, params, "integer dimension", 2)
   local tex1 = get_texture_param (state, params, "color tex1", 1)
   local tex2 = get_texture_param (state, params, "color tex2", 2)
   params["string aamode"] = nil -- ignore
   if dims == 2 then
      return apply_texture_2d_mapping (check_tex (tex1, tex2), state, params)
   elseif dims == 3 then
      return state.xform (check3d_tex (tex1, tex2))
   else
      parse_err (tostring(dims).."-dimensional checkerboard not supported")
   end
end

-- imagemap texture
--
function texture_parsers.imagemap (state, type, params)
   -- unsupported params: "string wrap" (non-default)
   -- ignored params: "float maxanisotropy", "bool trilinear", "float gamma"
   local filename = get_single_param (state, params, "string filename")
   local wrap = get_single_param (state, params, "string wrap", false)
   local scale = get_texture_param (state, params, "float/color scale", false)

   params["float maxanisotropy"] = nil -- ignore
   params["bool trilinear"] = nil      -- ignore
   params["float gamma"] = nil      -- ignore
   if wrap and wrap ~= "repeat" then
      parse_warn ("non-repeating texture-wrap mode \""..wrap.."\" ignored")
   end

   filename = find_file (filename, state)

   local tex
   if type == 'float' then
      tex = mono_image_tex (filename)
   else
      tex = image_tex (filename)
   end

   tex = apply_texture_2d_mapping (tex, state, params)

   if scale then
      tex = tex * scale
   end

   return tex
end

-- constant texture (used in scene files for named constants)
--
function texture_parsers.constant (state, type, params)
   return get_single_param (state, params, "color/float value", 1)
end

-- scale texture (multiplies its two inputs)
--
function texture_parsers.scale (state, type, params)
   local tex1 = get_texture_param (state, params, "color/float tex1", 1)
   local tex2 = get_texture_param (state, params, "color/float tex2", 1)
   return tex1 * tex2
end

-- mix texture (linearly interpolates between its two inputs based on another)
--
function texture_parsers.mix (state, type, params)
   local amount = get_texture_param (state, params, "float amount", 1)
   local tex1 = get_texture_param (state, params, "color/float tex1", 1)
   local tex2 = get_texture_param (state, params, "color/float tex2", 1)
   return linterp_tex (amount, tex1, tex2)
end

-- windy texture
--
function texture_parsers.windy (state, type, params)
   local wind_strength
      = scale (.1) (perlin_series_tex {octaves = 3, auto_scale = false})
   local wave_height
      = perlin_series_tex {octaves = 6, auto_scale = false}
   local tex = abs_tex (wind_strength) * wave_height
   local scale = get_texture_param (state, params, "float scale", 1) * 0.5
   local xf = state.xform:inverse ()
   return xf (tex * scale)
end

-- fbm texture
--
function texture_parsers.fbm (state, type, params)
   local octaves = get_single_param (state, params, "integer octaves", 8)
   local omega = get_single_param (state, params, "float roughness", .5)
   local xf = state.xform:inverse ()
   return xf (perlin_series_tex {octaves = octaves, omega = omega,
				 auto_scale = false})
end

-- wrinkled texture (basically same as fbm, but uses absolute value of
-- perlin noise)
--
function texture_parsers.wrinkled (state, type, params)
   local octaves = get_single_param (state, params, "integer octaves", 8)
   local omega = get_single_param (state, params, "float roughness", .5)
   local xf = state.xform:inverse ()
   return xf (perlin_abs_series_tex {octaves = octaves, omega = omega,
				     auto_scale = false})
end


----------------------------------------------------------------
-- shapes
--

local shape_parsers = {}

-- mesh shape
--
function shape_parsers.trianglemesh (state, mat, params)
   -- ignored params: "vector S"
   local points = get_param (state, params, "point P")
   local normals = get_param (state, params, "normal N", false)
   local indices = get_param (state, params, "integer indices")
   local alpha, alphan = get_texture_param (state, params, "float alpha", false)
   local uvs = (get_param (state, params, "float uv", false)
	     or get_param (state, params, "float st", false))

   params["bool discarddegenerateUVs"] = nil -- ignore

   if alpha then
      -- ignore, but it's important enough to warn about
      parse_warn ("\""..alphan.."\" parameter ignored")
   end

   if mod (#indices, 3) ~= 0 then
      parse_err ("number of indices ("..tostring(#indices)..")"
		 .." not a multiple of 3")
   end
   if normals and #normals ~= #points then
      parse_err ("number of normals ("..tostring(#normals)..")"
		 .." does not match number of points ("..tostring(#points)..")")
   end
   if uvs and #uvs * 3 ~= #points * 2 then
      parse_err ("number of uvs ("..tostring(#uvs)..")"
		 .." does not match number of points ("..tostring(#points/3)..")")
   end

   local xf = state.xform

   -- arghhh wotta hack...XXXXXXXXXXXXXX
   if #indices <= 6 and state.area_light_intens then
      local i0 = indices[1] * 3
      local p0 = xf (pos (points[i0+1], points[i0+2], points[i0+3]))
      local i1 = indices[2] * 3
      local p1 = xf (pos (points[i1+1], points[i1+2], points[i1+3]))
      local i2 = indices[3] * 3
      local p2 = xf (pos (points[i2+1], points[i2+2], points[i2+3]))
      if #indices == 3 then
	 return triangle (mat, p0, p1-p0, p2-p0)
      else
	 local i3 = indices[4] * 3
	 local p3 = xf (pos (points[i3+1], points[i3+2], points[i3+3]))
	 local i4 = indices[5] * 3
	 local p4 = xf (pos (points[i4+1], points[i4+2], points[i4+3]))
	 local i5 = indices[6] * 3
	 local p5 = xf (pos (points[i5+1], points[i5+2], points[i5+3]))
	 return surface_group{
	    triangle (mat, p0, p1-p0, p2-p0),
	    triangle (mat, p3, p4-p3, p5-p3)
	 }
      end
   end
   -- XXXXXXXXXXXXXX

   if state.reverse_normal then
      -- Do two things: negate all the normals, and reverse the indices
      -- for each triangle (as vertex order affects the "geometric normal")
      --
      if normals then
	 for i = 1, #normals do
	    normals[i] = -normals[i]
	 end
      end
      for i = 1, #indices, 3 do
	 local tmp = indices[i]
	 indices[i] = indices[i + 2]
	 indices[i + 2] = tmp
      end
   end

   -- Make an empty mesh, initialized to "left-handed" to reflect
   -- PBRT's conventions.
   --
   local M = mesh (mat)
   M.left_handed = false;

   -- Use bulk-add methods to add the vertices/normals/triangle/etc.
   -- This is a fair bit faster than doing it one-by-one, for large
   -- meshes.
   --
   local base_vert = M:add_vertices (points)
   M:add_triangles (indices, base_vert)
   if normals then
      M:add_normals (normals, base_vert)
   end
   if uvs then
      M:add_uvs (uvs, base_vert)
   end

   -- Transform the mesh in place using our transform.
   --
   M:transform (xf);

   return M
end

-- loopsubdiv shape (not implement; workaround: ignore the subdivision
-- entirely and just render the underlying mesh)
--
function shape_parsers.loopsubdiv (state, mat, params)
   params["integer nlevels"] = nil -- ignore
   local M = shape_parsers.trianglemesh (state, mat, params)
   -- if not M.vertex_normals then
   --    -- turn on mesh-smoothing in an attempt to hide the low-poly
   --    -- underling mesh...
   --    M:compute_vertex_normals ()
   -- end
   return M
end

-- cylinder shape
--
function shape_parsers.cylinder (state, mat, params)
   -- unsupported params: "float phimax"
   local radius = get_single_param (state, params, "float radius", 1)
   local zmin = get_single_param (state, params, "float zmin", -1)
   local zmax = get_single_param (state, params, "float zmax", 1)
   local xf = state.xform

   if zmin ~= -1 or zmax ~= 1 then
      local _scale = (zmax - zmin) / 2
      local offs = zmin + _scale
      xf = xf (translate (0, 0, offs) (scale (1, 1, _scale)))
   end
   if radius ~= 1 then
      xf = xf (scale (radius, radius, 1))
   end

   if state.reverse_normal then
      parse_err "ReverseOrientation not supported for cylinder shape"
   end

   return cylinder (mat, xf)
end

-- sphere shape
--
function shape_parsers.sphere (state, mat, params)
   -- unsupported params: "float zmin", "float zmax", "float phimax"
   local radius = get_single_param (state, params, "float radius", 1)
   local xf = state.xform
   if radius ~= 1 then
      xf = xf (scale (radius))
   end
   if state.reverse_normal then
      parse_err "ReverseOrientation not supported for sphere shape"
   end
   return sphere2 (mat, xf)
end

-- disk shape
--
function shape_parsers.disk (state, mat, params)
   -- unsupported params: "float innerradius", "float phimax"
   local radius = get_single_param (state, params, "float radius", 1)
   local height = get_single_param (state, params, "float height", 0)
   local center = state.xform (pos (0, 0, height))
   local norm_xform = state.xform:inverse():transpose ()
   local rad1 = norm_xform (vec (0, radius, 0))
   local rad2 = norm_xform (vec (radius, 0, 0))
   if state.reverse_normal then
      rad2 = -rad2
   end
   return ellipse (mat, center, rad1, rad2)
end


----------------------------------------------------------------
-- lights
--

local light_parsers = {}

-- point light
--
function light_parsers.point (state, params)
   local intens = get_texture_param (state, params, "color I")
   local from = get_point_param (state, params, "point from", pos(0,0,0))
   return point_light (state.xform (from), intens)
end

-- distant light
--
function light_parsers.distant (state, params)
   local intens = get_texture_param (state, params, "color L", 1)
   local from = get_point_param (state, params, "point from", pos(0,0,0))
   local to = get_point_param (state, params, "point to", pos(0,0,1))
   local dir = state.xform ((from - to):unit ())
   return far_light (dir, math.pi, intens)
end

-- infinite light
--
function light_parsers.infinite (state, params)
   -- ignored params: "integer nsamples"
   local mapname = get_single_param (state, params, "string mapname", false)
   local scale = get_texture_param (state, params, "float/color scale", false)

   -- There are two sorts of infinite light: one which loads the image
   -- from a file, specified with a "string mapname" parameter, and
   -- one which has a constant intensity, specified with a "color L"
   -- parameter.  We handle the latter by actually making a small
   -- image with all pixels containing L.
   --
   local envmap
   if mapname then
      -- image read from file

      envmap = image (find_file (mapname, state))

      if scale then
	 -- need to scale values (ugh, pixel-by-pixel...)
	 local w, h = envmap.width, envmap.height
	 for j = 0, h - 1 do
	    for i = 0, w - 1 do
	       envmap:set (i, j, envmap (i, j) * scale)
	    end
	 end
      end
   else
      -- constant-valued environment map

      local L = get_color_param (state, params, "color L", color (1))
      if scale then
	 L = L * scale
      end

      -- Make a small image to contain the constant level.
      -- envmap_light internally scales the pixels by a cosine factor
      -- (so that sampling is evenly distributed over the sphere), so
      -- we need make the map big enough so that the cosine scaling
      -- doesn't screw things up (otherwise we could just use a small
      -- 2x1 pixel image!)... 128 x 64 is probably unnecessarily
      -- large, but it's safe.
      --
      local w, h = 128, 64
      envmap = image (w, h)
      for j = 0, h - 1 do
	 for i = 0, w - 1 do
	    envmap:set (i, j, L)
	 end
      end
   end

   -- envmap_light (currently!) uses a "y major" coordinate system,
   -- whereas PBRT scenes expect a z-major system, so translate.
   --
   local xf = state.xform (rot_z (-math.pi/2) (xform_y_to_z))

   return envmap_light (envmap, frame (xf))
end


----------------------------------------------------------------
-- main command
--

function load_pbrt_in_state (state, scene, camera)

   local function add (surface)
      if state.object then
	 state.object:add (surface)
      else
	 scene:add (surface)
      end
   end

   local function check_mat ()
      if state.material then
	 if state.area_light_intens then
	    return glow (state.area_light_intens, state.material)
	 else
	    return state.material
	 end
      elseif state.area_light_intens then
	 return glow (state.area_light_intens)
      else
	 return lambert (1)
      end
   end

   -- commands
   --
   local function accel_cmd (...)
      parse_warn "Accelerator command ignored"
   end
   local function area_light_cmd (kind, params)
      if kind ~= "area" and  kind ~= "diffuse" then
	 parse_err "AreaLightSource only supports a type of \"area\"/\"diffuse\""
      end

      -- unsupported params: "texture L"
      -- ignored params: "integer nsamples"
      local intens = get_color_param (state, params, "color L")
      local scale = get_single_param (state, params, "color/float scale", false)
      if scale then
	 intens = intens * scale
      end
      params["integer nsamples"] = nil -- ignore
      check_unused_params (params)

      state.area_light_intens = intens
   end
   local function attrib_begin_cmd ()
      push (state.attrib_stack,
	    {state.material, state.xform, state.area_light_intens,
	     state.reverse_normal})
   end
   local function attrib_end_cmd ()
      local tos = pop (state.attrib_stack)
      if tos then
	 state.material = tos[1]
	 state.xform = tos[2]
	 state.area_light_intens = tos[3]
	 state.reverse_normal = tos[4]
      else
	 parse_err "AttributeEnd command does not match any AttributeBegin"
      end
   end
   local function camera_cmd (type, params)
      if type ~= "perspective" then
	 parse_err "Camera command only supports \"perspective\" type"
      end

      -- camera paremters
      local fov = get_single_param (state, params, "float fov", 90)
      local focus = get_single_param (state, params, "float focaldistance",
				      false)
      local lradius = get_single_param (state, params, "float lensradius", 0)
      local screen_win = get_param (state, params, "float screenwindow", false)
      local hither = get_single_param (state, params, "float hither", 1e-3)
      local yon = get_single_param (state, params, "float yon", 1e30)
      params["float frameaspectratio"] = nil -- ignore
      params["float shutteropen"] = nil	     -- ignore
      params["float shutterclose"] = nil     -- ignore
      check_unused_params (params)

      -- PBRT doesn't have separate camera units, so its camera metrics
      -- are in scene-units.
      --
      camera.scene_unit = 1

      -- It's not correct to just set verticle-FOV here -- PBRT
      -- actually sets the FOV for whichever dimension is smallest
      -- (usually Y, but not always).
      --
      camera:set_vert_fov (fov * math.pi / 180)

      if focus then
	 camera.focus = focus
      end
      camera.aperture = lradius * 2

      local cam_to_world = state.xform:inverse ()

      camera:transform (cam_to_world)

      state.named_coord_systems["camera"] = cam_to_world
   end
   local function coord_sys_cmd (name)
      state.named_coord_systems[name] = state.xform
   end
   local function coord_sys_xform_cmd (name)
      state.xform = state.named_coord_systems[name]
      if not state.xform then
	 parse_err ("unknown named coordinate system \""..name.."\"")
      end
   end
   local function film_cmd (kind, params)
      if kind ~= "image" then
	 parse_err "Film command only supports a type of \"image\""
      end
      local w = get_single_param (state, params, "integer xresolution", 640)
      local h = get_single_param (state, params, "integer yresolution", 480)
      parse_warn ("Film command ignored; size = "
		     ..tostring(w).."x"..tostring(h))
   end
   local function identity_cmd ()
      state.xform = identity_xform
   end
   local function light_cmd (kind, params)
      local light_parser = light_parsers[kind]
      if light_parser then
	 add (light_parser (state, params))
	 -- none of our lights support "integer nsamples", so ignore it
	 params["integer nsamples"] = nil -- ignore
	 check_unused_params (params)
      else
	 parse_err ("unknown LightSource type \""..kind.."\"")
      end
   end
   local function lookat_cmd (pos_x, pos_y, pos_z, targ_x, targ_y, targ_z, up_x, up_y, up_z)
      local loc = pos (pos_x, pos_y, pos_z)
      local targ = pos (targ_x, targ_y, targ_z)
      local user_up = vec (up_x, up_y, up_z)
      local dir = (targ - loc):unit ()
      local left = cross (user_up:unit (), dir):unit ()
      local up = cross (dir, left)
      local cam_to_world = xform{left.x, up.x, dir.x, loc.x,
      				 left.y, up.y, dir.y, loc.y,
      				 left.z, up.z, dir.z, loc.z,
      				 0,       0,    0,     1}
      -- local right = cross (dir, user_up:unit ()):unit ()
      -- local up = cross (right, dir)
      -- local cam_to_world = xform{right.x, up.x, dir.x, loc.x,
      -- 				 right.y, up.y, dir.y, loc.y,
      -- 				 right.z, up.z, dir.z, loc.z,
      -- 				 0,       0,    0,     1}
      local world_to_cam = cam_to_world:inverse ()
      state.xform = state.xform * world_to_cam
   end
   local function material_cmd (kind, params)
      local mat_parser = material_parsers[kind]
      if mat_parser then
	 state.material = mat_parser (state, params)
	 check_unused_params (params)
      else
	 parse_err ("unknown Material type \""..kind.."\"")
      end
   end
   local function make_named_material_cmd (name, params)
      local kind = get_single_param (state, params, "string type")
      local mat_parser = material_parsers[kind]
      if mat_parser then
	 state.named_materials[name] = mat_parser (state, params)
	 check_unused_params (params)
      else
	 parse_err ("unknown Material type \""..kind.."\"")
      end
   end
   local function named_material_cmd (name)
      local mat = state.named_materials[name]
      if mat then
	 state.material = mat
      else
	 parse_err ("unknown named material \""..name.."\"")
      end
   end
   local function obj_begin_cmd (name)
      attrib_begin_cmd ()

      push (state.obj_stack, {state.object_name, state.object})

      state.object_name = name
      state.object = surface_group ()
   end
   local function obj_end_cmd ()
      local tos = pop (state.obj_stack)
      if tos then
	 state.objects[state.object_name] = subspace (state.object)
	 state.object_name = tos[1]
	 state.object = tos[2]
	 attrib_end_cmd ()
      else
	 parse_err "ObjectEnd command does not match any ObjectBegin"
      end
   end
   local function obj_instance_cmd (name)
      local obj = state.objects[name]
      if obj then
	 add (instance (obj, state.xform))
      else
	 parse_err ("object \""..name.."\" does not exist")
      end
   end
   local function pixelfilter_cmd (...)
      parse_warn "PixelFilter command ignored"
   end
   local function renderer_cmd (...)
      parse_warn "Renderer command ignored"
   end
   local function reverse_orientation_cmd (...)
      state.reverse_normal = not state.reverse_normal
   end
   local function rotate_cmd (angle, axis_x, axis_y, axis_z)
      local axis = vec (axis_x, axis_y, axis_z)
      angle = angle * math.pi / 180
      state.xform = state.xform * rotate (axis, angle)
   end
   local function sampler_cmd (...)
      parse_warn "Sampler command ignored"
   end
   local function scale_cmd (x, y, z)
      state.xform = state.xform * scale (x, y, z)
   end
   local function searchpath_cmd ()
      parse_warn "SearchPath command ignored"
   end
   local function shape_cmd (kind, params)
      local mat = check_mat ()
      local shape_parser = shape_parsers[kind]
      if shape_parser then
	 add (shape_parser (state, mat, params))
	 check_unused_params (params)
      else
	 parse_err ("unknown shape type \""..kind.."\"")
      end
   end
   local function surfaceintegrator_cmd (...)
      parse_warn "SurfaceIntegrator command ignored"
   end
   local function texture_cmd (name, type, kind, params)
      local tex_parser = texture_parsers[kind]
      if tex_parser then
	 local tex = tex_parser (state, type, params)
	 state.named_textures[name] = tex
	 check_unused_params (params)
      else
	 parse_err ("unknown texture type \""..kind.."\"")
      end
   end
   local function transform_begin_cmd ()
      push (state.xform_stack, state.xform)
   end
   local function transform_end_cmd ()
      local tos = pop (state.xform_stack)
      if tos then
	 state.xform = tos
      else
	 parse_err "TransformEnd command does not match any TransformBegin"
      end
   end
   local function transform_cmd (matrix)
      if #matrix ~= 16 or type (matrix[1]) ~= "number" then
	 parse_err "Transform requires a 16-element numeric array"
      end
      state.xform =  state.xform * xform (matrix):transpose()
   end
   local function translate_cmd (x, y, z)
      state.xform = state.xform * translate (x, y, z)
   end
   local function volumeintegrator_cmd (...)
      parse_warn "VolumeIntegrator command ignored"
   end
   local function volume_cmd (...)
      parse_warn "Volume command ignored"
   end
   local function world_begin_cmd ()
      state.xform = identity_xform
      state.named_coord_systems["world"] = state.xform
   end
   local function world_end_cmd ()
      if #state.xform_stack > 0 then
	 parse_err "transform stack not empty at WorldEnd"
      end
      if #state.attrib_stack > 0 then
	 parse_err "attribute stack not empty at WorldEnd"
      end
   end
   local function include_cmd (include_file)
      include_file = find_file (include_file, state)

      print ("* include: "..filename_rel (include_file, state.base_dir))

      local old_filename = state.filename
      state.filename = include_file

      load_pbrt_in_state (state, scene, camera)

      state.filename = old_filename
   end

   -- PBRT grammar
   --
   local ACCELERATOR = (P"Accelerator" * STRING * PARAM_LIST) / accel_cmd
   local AREALIGHTSOURCE =  (P"AreaLightSource" * STRING * PARAM_LIST) / area_light_cmd
   local ATTRIBUTEBEGIN = P"AttributeBegin" / attrib_begin_cmd
   local ATTRIBUTEEND = P"AttributeEnd" / attrib_end_cmd
   local CAMERA = (P"Camera" * STRING * PARAM_LIST) / camera_cmd
   local CONCATTRANSFORM = (P"ConcatTransform" * NUM_ARRAY) / transform_cmd
   local COORDINATESYSTEM = (P"CoordinateSystem" * STRING) / coord_sys_cmd
   local COORDSYSTRANSFORM = (P"CoordSysTransform" * STRING) / coord_sys_xform_cmd
   local FILM = (P"Film" * STRING * PARAM_LIST) / film_cmd
   local IDENTITY = P"Identity" / identity_cmd
   local LIGHTSOURCE = (P"LightSource" * STRING * PARAM_LIST) / light_cmd
   local LOOKAT = (P"LookAt" * NUM * NUM * NUM * NUM * NUM * NUM * NUM * NUM * NUM) / lookat_cmd
   local MAKENAMEDMATERIAL = (P"MakeNamedMaterial" * STRING * PARAM_LIST) / make_named_material_cmd
   local MATERIAL = (P"Material" * STRING * PARAM_LIST) / material_cmd
   local NAMEDMATERIAL = (P"NamedMaterial" * STRING) / named_material_cmd
   local OBJECTBEGIN = (P"ObjectBegin" * STRING) / obj_begin_cmd
   local OBJECTEND = P"ObjectEnd" / obj_end_cmd
   local OBJECTINSTANCE = (P"ObjectInstance" * STRING) / obj_instance_cmd
   local PIXELFILTER = (P"PixelFilter" * STRING * PARAM_LIST) / pixelfilter_cmd
   local RENDERER = (P"Renderer" * STRING * PARAM_LIST) / renderer_cmd
   local REVERSEORIENTATION = P"ReverseOrientation" / reverse_orientation_cmd
   local ROTATE = (P"Rotate" * NUM * NUM * NUM * NUM) / rotate_cmd
   local SAMPLER = (P"Sampler" * STRING * PARAM_LIST) / sampler_cmd
   local SCALE = (P"Scale" * NUM * NUM * NUM) / scale_cmd
   local SEARCHPATH = (P"SearchPath" * STRING) / searchpath_cmd
   local SHAPE = (P"Shape" * STRING * PARAM_LIST) / shape_cmd
   local SURFACEINTEGRATOR = (P"SurfaceIntegrator" * STRING * PARAM_LIST) / surfaceintegrator_cmd
   local TEXTURE = (P"Texture" * STRING * STRING * STRING * PARAM_LIST) / texture_cmd
   local TRANSFORMBEGIN = P"TransformBegin" / transform_begin_cmd
   local TRANSFORMEND = P"TransformEnd" / transform_end_cmd
   local TRANSFORM = (P"Transform" * NUM_ARRAY) / transform_cmd
   local TRANSLATE = (P"Translate" * NUM * NUM * NUM) / translate_cmd
   local VOLUMEINTEGRATOR = (P"VolumeIntegrator" * STRING * PARAM_LIST) / volumeintegrator_cmd
   local VOLUME = (P"Volume" * STRING * PARAM_LIST) / volume_cmd
   local WORLDBEGIN = P"WorldBegin" / world_begin_cmd
   local WORLDEND = P"WorldEnd" / world_end_cmd
   local INCLUDE = (P"Include" * STRING) / include_cmd

   local COMMAND
      = (WS * SYNC
	 * (ACCELERATOR + AREALIGHTSOURCE + ATTRIBUTEBEGIN +
	    ATTRIBUTEEND + CAMERA + CONCATTRANSFORM + COORDINATESYSTEM +
	    COORDSYSTRANSFORM + FILM + IDENTITY + LIGHTSOURCE + LOOKAT +
	    MAKENAMEDMATERIAL + MATERIAL + NAMEDMATERIAL + OBJECTBEGIN +
	    OBJECTEND + OBJECTINSTANCE + PIXELFILTER + RENDERER +
	    REVERSEORIENTATION + ROTATE + SAMPLER + SCALE + SEARCHPATH +
	    SHAPE + SURFACEINTEGRATOR + TEXTURE + TRANSFORMBEGIN +
	    TRANSFORMEND + TRANSFORM + TRANSLATE + VOLUMEINTEGRATOR +
	    VOLUME + WORLDBEGIN + WORLDEND + INCLUDE))

   lu.parse_file (state.filename, COMMAND + WS)

   return true
end

function load_pbrt (filename, scene, camera)
   local init_state = {
      scene = scene,
      camera = camera,

      xform = identity_xform,

      material = nil,
      area_light_intens = nil,
      reverse_normal = false,

      object = nil,		-- current object being defined
      object_name = nil,	-- its name (if any)

      named_coord_systems = {},	-- table of named coordinate systems
      named_textures = {},
      named_materials = {},

      xform_stack = {},		-- stack for TransformBegin/TransformEnd
      attrib_stack = {},	-- stack for AttributeBegin/AttributeEnd
      obj_stack = {},		-- stack for ObjectBegin/ObjectEnd

      objects = {},		-- object database (for instancing)

      spectrums = {},		-- named spectrum cache

      filename = filename,
      base_dir = filename_dir (filename)
   }
   return load_pbrt_in_state (init_state, scene, camera)
end
