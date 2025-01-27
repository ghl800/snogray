// envmap.h -- Environment maps
//
//  Copyright (C) 2006, 2007, 2008  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __ENVMAP_H__
#define __ENVMAP_H__

#include <string>

#include "ref.h"
#include "color.h"
#include "vec.h"
#include "image.h"


namespace snogray {


class Envmap : public RefCounted
{
public:

  virtual ~Envmap () { }

  // Return the color of this environment map in direction DIR.
  //
  virtual Color map (const Vec &dir) const = 0;

  // Return a "light-map" -- a lat-long format spheremap image
  // containing light values of the environment map -- for this
  // environment map.
  //
  virtual Ref<Image> light_map () const = 0;
};

// Return an appropriate subclass of Envmap, initialized from SPEC
// (usually a filename to load).  FMT is the type of environment-map.
//
// If FMT is "", any colon-separated prefix will be removed from SPEC,
// and used as the format name (and ther remainder of SPEC used as the
// actual filename); if FMT is "auto", SPEC will be left untouched, and
// an attempt will be made to guess the format based on the image size.
//
Ref<Envmap> load_envmap (const std::string &spec, const std::string &fmt = "");

// Return an appropriate subclass of Envmap, initialized from IMAGE.
// FMT is the type of environment-map (specifically, the type of mapping
// from direction to image coordinates).  If FMT is "" or "auto", an
// attempt will be made to guess the format based on the image size.
//
Ref<Envmap> make_envmap (const Ref<Image> &image, const std::string &fmt = "");


}

#endif /* __ENVMAP_H__ */


// arch-tag: 9695753e-771b-4555-83c4-593486374642
