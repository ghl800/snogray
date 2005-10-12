// lambert.cc -- Lambertian lighting model
//
//  Copyright (C) 2005  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include "lambert.h"

#include "intersect.h"

using namespace Snogray;

Color
Lambert::illum (const Intersect &isec, const Color &color,
		const Vec &light_dir, const Color &light_color)
  const
{
  float diffuse_component = isec.normal.dot (light_dir);

  if (diffuse_component > 0)
    return color * light_color * diffuse_component;
  else
    return Color::black;
}

// arch-tag: f61dbf3f-a5eb-4747-9bc5-18e793f35b6e
