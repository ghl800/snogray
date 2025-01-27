// hemi-dist.h -- Hemisphere distribution
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

#ifndef __HEMI_DIST_H__
#define __HEMI_DIST_H__

#include "dist.h"


namespace snogray {


class HemiDist : Dist
{
public:

  // Return a sample distributed around the Z-axis according to this
  // distribution, from the uniformly distributed parameters in PARAM.
  //
  Vec sample (const UV &param) const
  {
    return z_normal_symm_vec (sqrt (param.u), param.v);
  }

  // Return a sample distributed around the Z-axis according to this
  // distribution, from the uniformly distributed parameters in PARAM.
  // Also return the PDF of the resulting sample in _PDF.
  //
  Vec sample (const UV &param, float &_pdf) const
  {
    float cos_theta = param.u;
    _pdf = pdf ();
    return z_normal_symm_vec (cos_theta, param.v);
  }

  // Returns the PDF of a sample in direction DIR.
  //
  float pdf (const Vec &/*dir*/) const
  {
    return pdf ();
  }

  // Returns the pdf of a sample.
  //
  float pdf () const
  {
    return 0.5f * INV_PIf;
  }
};


}


#endif /* __HEMI_DIST_H__ */

// arch-tag: 06af2c27-b81d-4f17-90d1-07cf0a59f64b
