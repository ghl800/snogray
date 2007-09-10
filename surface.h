// surface.h -- Physical surface
//
//  Copyright (C) 2005, 2006, 2007  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __SURFACE_H__
#define __SURFACE_H__

#include "vec.h"
#include "ray.h"
#include "bbox.h"
#include "intersect.h"
#include "material.h"


namespace snogray {

class Material;
class SpaceBuilder;
class Trace;


// A surface is the basic object scenes are constructed of.
// Surfaces exist in 3D space, but are basically 2D -- volumetric
// properties are only modelled in certain special cases.
//
class Surface 
{
public:

  Surface (const Material *mat) : material (mat) { }
  virtual ~Surface () { }

  // A lightweight object used to return infomation from the
  // Surface::intersect method.  If that intersection ends up being used
  // for rendering, its IsecInfo::make_intersect method will be called
  // to create a (more heavyweight) Intersect object for doing
  // rendering.
  //
  // These objects should be allocated using placement new with the
  // IsecCtx object passed to Surface::intersect.
  //
  class IsecInfo
  {
  public:

    virtual ~IsecInfo () { }

    // Create an Intersect object for this intersection.
    //
    virtual Intersect make_intersect (const Ray &ray, Trace &trace) const = 0;

    // Return the surface which resulted in this intersection.
    //
    virtual const Surface *surface () const = 0;
  };

  // A special object passed into the Surface::intersect method, which
  // can be used with placement new to allocate a IsecInfo object.
  //
  class IsecCtx
  {
  public:

    IsecCtx (Trace &_trace) : trace (_trace) { }

    // Trace object representing global context of intersection.
    //
    Trace &trace;
  };

  // If this surface intersects RAY, change RAY's maximum bound (Ray::t1)
  // to reflect the point of intersection, and return a Surface::IsecInfo
  // object describing the intersection (which should be allocated using
  // placement-new with ISEC_CTX); otherwise return zero.
  //
  virtual const IsecInfo *intersect (Ray &ray, const IsecCtx &isec_ctx) const;

  // Return the strongest type of shadowing effect this surface has on
  // RAY.  If no shadow is cast, Material::SHADOW_NONE is returned;
  // otherwise if RAY is completely blocked, Material::SHADOW_OPAQUE is
  // returned; otherwise, Material::SHADOW_MEDIUM is returned.
  //
  virtual Material::ShadowType shadow (const ShadowRay &ray) const;

  // Return a bounding box for this surface.
  //
  virtual BBox bbox () const;

  // Add this (or some other) surfaces to the space being built by
  // SPACE_BUILDER.
  //
  virtual void add_to_space (SpaceBuilder &space_builder) const;
 
  // The "smoothing group" this surface belongs to, or zero if it belongs
  // to none.  The smoothing group affects shadow-casting: if two objects
  // are in the same smoothing group, they will not be shadowed by
  // back-surface shadows from each other; typically all triangles in a
  // mesh are in the same smoothing group.
  //
  virtual const void *smoothing_group () const;

  const Material *material;
};


}


// The user can use this via placement new: "new (ISEC_CTX) T (...)".
// The resulting object cannot be deleted using delete, but should be
// destructed (if necessary) explicitly:  "OBJ->~T()".
//
// All memory allocated from an Surface::IsecCtx object is automatically
// freed at some appropriate point.
//
inline void *
operator new (size_t size, const snogray::Surface::IsecCtx &isec_ctx)
{
  return operator new (size, isec_ctx.trace);
}

// There's no syntax for user to use this, but the compiler may call it
// during exception handling.
//
inline void
operator delete (void *mem, const snogray::Surface::IsecCtx &isec_ctx)
{
  operator delete (mem, isec_ctx.trace);
}


#endif /* __SURFACE_H__ */


// arch-tag: 85997b65-c9ab-4542-80be-0c3a114593ba
