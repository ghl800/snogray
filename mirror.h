// mirror.h -- Mirror (reflective) material
//
//  Copyright (C) 2005  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __MIRROR_H__
#define __MIRROR_H__

#include "material.h"

namespace Snogray {

class Mirror : public Material
{
public:
  Mirror (float _reflectance, const Color &col, const LightModel *lmodel)
    : Material (col, lmodel),
      reflectance (col * _reflectance)
  { }
  Mirror (float _reflectance, const Color &col, float phong_exp)
    : Material (col, phong (phong_exp)),
      reflectance (col * _reflectance)
  { }
  Mirror (Color _reflectance, const Color &col, const LightModel *lmodel)
    : Material (col, lmodel),
      reflectance ( _reflectance)
  { }
  Mirror (Color _reflectance, const Color &col, float phong_exp)
    : Material (col, phong (phong_exp, _reflectance)),
      reflectance (_reflectance)
  { }

  virtual Color render (const Intersect &isec, TraceState &tstate) const;

  // Renders only the reflection about ISEC, without adding in other components
  //
  Color reflection (const Intersect &isec, TraceState &tstate) const;

  Color reflectance;
};

}

#endif /* __MIRROR_H__ */

// arch-tag: b622d70c-03ff-49ee-a020-2a44ccfcfdb1