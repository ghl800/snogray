// space.h -- Space-division abstraction (hierarchically arranges 3D space)
//
//  Copyright (C) 2005, 2007, 2008, 2009, 2010  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __SPACE_H__
#define __SPACE_H__

#include "ray.h"
#include "surface.h"
#include "render-context.h"


namespace snogray {


class Space
{
public:

  struct IntersectCallback;	// Callback for search methods

  virtual ~Space () { }

  // Return the closest surface in this space which intersects the
  // bounded-ray RAY, or zero if there is none.  RAY's length is
  // shortened to reflect the point of intersection.
  //
  const Surface::IsecInfo *intersect (Ray &ray, RenderContext &context) const;

  // Return true if any object intersects RAY.
  //
  bool intersects (const Ray &ray, RenderContext &context) const;

  // Return true if some surface in this space completely occludes
  // RAY.  If no surface completely occludes RAY, then return false,
  // and multiply TOTAL_TRANSMITTANCE by the transmittance of any
  // surfaces in this space which partially occlude RAY, evaluated in
  // medium MEDIUM.
  //
  // Note that this method does not try to handle non-trivial forms of
  // transparency/translucency (for instance, a "glass" material is
  // probably considered opaque because it changes light direction as
  // well as transmitting it), nor does it deal with anything except
  // surfaces.
  //
  // [This interface is slight awkward for reasons of speed --
  // returning and checking for a boolean value for common cases is
  // significantly faster than, for instance, a simple "transmittance"
  // method, which requires handling Color values for all cases.]
  //
  virtual bool occludes (const Ray &ray, const Medium &medium,
			 Color &total_transmittance,
			 RenderContext &context)
    const;

  // Call CALLBACK for each surface in the voxel tree that _might_
  // intersect RAY (any further intersection testing needs to be done
  // directly on the resulting surfaces).  CONTEXT is used to access
  // various cache data structures.  ISEC_STATS will be updated.
  //
  virtual void for_each_possible_intersector (const Ray &ray,
					      IntersectCallback &callback,
					      RenderContext &context,
					      RenderStats::IsecStats &isec_stats)
    const = 0;

protected:

  struct SearchState;		// Convenience class for subclasses
};


// A callback for `Space::for_each_possible_intersector'.  Users of
// `Space::for_each_possible_intersector' must subclass this,
// providing their own operator() method, and adding any extra data
// fields they need.
//
struct Space::IntersectCallback
{
  IntersectCallback () : stop (false) { }

  virtual ~IntersectCallback () { }

  // Test SURF to see if it really intersects, and return true if so.
  // Returning true does not necessarily stop the search; to do that,
  // call the IntersectCallback::stop_intersection method.
  //
  virtual bool operator() (const Surface *surf) = 0;

  void stop_iteration () { stop = true; }

  // If set to true, return from iterator immediately
  //
  bool stop;
};


// This structure is used to hold state during the search.  It not
// actually used by the Space class, but may be useful as a common
// superclass for internal state held by various Space subclasses.
//
struct Space::SearchState
{
  SearchState (IntersectCallback &_callback)
    : callback (_callback),
      node_intersect_calls (0), surf_isec_tests (0), surf_isec_hits (0)
  { }

  // Update the global statistical counters in ISEC_STATS with the
  // results from this search.
  //
  void update_isec_stats (RenderStats::IsecStats &isec_stats)
  {
    isec_stats.surface_intersects_tests   += surf_isec_tests;
    isec_stats.surface_intersects_hits    += surf_isec_hits;
    isec_stats.space_node_intersect_calls += node_intersect_calls;
  }

  // Call back to do surface testing.
  //
  IntersectCallback &callback;

  // Keep track of some intersection statistics.
  //
  unsigned long node_intersect_calls;
  unsigned surf_isec_tests, surf_isec_hits;
};


}

#endif // __SPACE_H__


// arch-tag: b992c2ec-257d-4b88-9001-83a90353e668
