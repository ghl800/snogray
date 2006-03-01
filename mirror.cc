// mirror.cc -- Mirror (reflective) material
//
//  Copyright (C) 2005, 2006  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include <cmath>

#include "mirror.h"

#include "intersect.h"
#include "scene.h"

using namespace Snogray;

Color
Mirror::reflection (const Intersect &isec) const
{
  // Render reflection

  Vec mirror_dir = isec.ray.dir.reflection (isec.normal);
  Ray mirror_ray (isec.point, mirror_dir);

  return isec.subtrace (Trace::REFLECTION).render (mirror_ray);
}

Color
Mirror::render (const Intersect &isec) const
{
  float cos_refl_angle = dot (isec.normal, isec.viewer);
  float medium_ior = isec.trace.medium ? isec.trace.medium->ior : 1;
  Color fres_refl
    = reflectance * Fresnel (medium_ior, ior).reflectance (cos_refl_angle);

  Color total_color;

  if (fres_refl > Eps)
    total_color += fres_refl * reflection (isec);

  if (1 - fres_refl > Eps)
    total_color += (1 - fres_refl) * Material::render (isec);

  return total_color;
}

// arch-tag: b895139d-fe9f-414a-9665-3b5e4b8f691a
