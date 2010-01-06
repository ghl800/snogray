// illum-sample.h -- Directional sample used during illumination
//
//  Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __ILLUM_SAMPLE_H__
#define __ILLUM_SAMPLE_H__

#include <vector>

#include "vec.h"
#include "color.h"
#include "surface.h"
#include "mempool.h"


namespace snogray {

class Light;


// A single directional sample.  The origin is implicit, because illums
// are typically taken from a single point, so only the direction is
// included.
//
class IllumSample
{
public:

  // Various flag values that can be stored in the flags field of a
  // sample.  Most of these are related to the type of the BRDF the
  // sample passed through.
  //
  enum Flags {

    // This is used to reflect shadowing: if set, it is known that this
    // sample strikes a light with no intervening surfaces.
    //
    DIRECT		= 0x01,

    REFLECTIVE		= 0x02,
    TRANSMISSIVE 	= 0x04,
    SAMPLE_DIR		= REFLECTIVE|TRANSMISSIVE,

    SPECULAR		= 0x08,
    GLOSSY		= 0x10,
    DIFFUSE		= 0x20,
    SURFACE_CLASS	= SPECULAR|GLOSSY|DIFFUSE
 };


  // Generated by a light (BRDF fields initially zero).
  //
  IllumSample (const Vec &_dir, const Color &_val, float _light_pdf,
	       dist_t _dist, const Light *_light, unsigned _flags = 0)
    : dir (_dir), flags (_flags), isec_info (0),
      brdf_val (0), brdf_pdf (0),
      light_val (_val), light_pdf (_light_pdf), light_dist (_dist),
      light (_light)
  { }

  // Generated by a BRDF (light fields initially zero).
  //
  IllumSample (const Vec &_dir, const Color &_refl, float _brdf_pdf,
	       unsigned _flags)
    : dir (_dir), flags (_flags), isec_info (0),
      brdf_val (_refl), brdf_pdf (_brdf_pdf),
      light_val (0), light_pdf (0), light_dist (0), light (0)
  { }


  // The sample direction (the origin is implicit), in the
  // surface-normal coordinate system (where the surface normal is
  // (0,0,1)).
  //
  Vec dir;

  // Flags applying to this sample (see the Flags enum for various
  // values).
  //
  unsigned flags;

  // Information about the closest intersection for this sample's
  // incoming ray, or zero there is no intersection (or nothing has been
  // computed yet).
  //
  const Surface::IsecInfo *isec_info;


  //
  // BRDF-related info.  These values are only valid for BRDF-generated
  // samples (generated using Brdf::gen_samples), or for samples that
  // have been filtered through the BRDF (using Brdf::filter_samples).
  //

  // The value of the BRDF for this sample.
  //
  Color brdf_val;

  // The value of the "probability density function" for this sample in the
  // BRDF's sample distribution.
  //
  // However, if this is a specular sample (with the IllumSample::SPECULAR
  // flag set), the value is not defined (theoretically the value is
  // infinity for specular samples).
  //
  float brdf_pdf;


  //
  // Light-related info.  These values are only valid for Light-generated
  // samples (generated using Light::gen_samples), or for samples that
  // have been filtered through a light (using Light::filter_samples).
  //
  // Note that these values do not reflect shadowing.
  //

  // The amount of light from this sample.  Note that the value for a
  // single sample "represents" the entire power of the light; if multiple
  // samples are used, they are averaged later.
  //
  Color light_val;

  // The value of the "probability density function" for this sample in the
  // light's sample distribution.
  //
  // As a special case, a value of (exactly) zero means that this sample
  // was generated by a point light, whose sample distribution is a delta
  // function.
  //
  float light_pdf;

  // The distance to the light or surface which this ray strikes
  // (zero means "strikes nothing").  This value is mainly used to
  // determine priority if a sample can strike multiple lights (the
  // closest light wins).
  //
  float light_dist;

  // The light which this sample hits, or zero.
  //
  const Light *light;
};


// The STL allocator used by IllumSampleVec, which allocates from a Mempool.
//
typedef MempoolAlloc<IllumSample> IllumSampleVecAlloc;

// Vectors of IllumSamples
//
typedef std::vector<IllumSample, IllumSampleVecAlloc> IllumSampleVec;


}

#endif /* __ILLUM_SAMPLE_H__ */


// arch-tag: e0f3f775-1fab-4835-8d9f-4cd8b9729731
