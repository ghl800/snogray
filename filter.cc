// filter.cc -- Filter datatype
//
//  Copyright (C) 2006, 2007, 2010  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include "excepts.h"
#include "val-table.h"
#include "mitchell-filt.h"
#include "gauss-filt.h"
#include "triangle-filt.h"
#include "box-filt.h"

#include "filter.h"


using namespace snogray;


// Return a new a filter depending on the parameters in PARAMS.
//
Filter *
Filter::make (const ValTable &params)
{
  std::string filter_type = params.get_string ("filter");

  if (filter_type.empty ())
    return new MitchellFilt ();
  else
    {
      ValTable filter_params
	= params.filter_by_prefix ("filter." + filter_type + ".");

      if (filter_type == "none")
	return 0;
      else if (filter_type == "mitchell")
	return new MitchellFilt (filter_params);
      else if (filter_type == "gauss")
	return new GaussFilt (filter_params);
      else if (filter_type == "triangle")
	return new TriangleFilt (filter_params);
      else if (filter_type == "box")
	return new BoxFilt (filter_params);
      else
	throw std::runtime_error (filter_type + ": unknown output filter type");
    }
}

// arch-tag: b777ab5a-d4d2-44af-a23b-e8012cab289c
