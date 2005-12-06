// surface.cc -- Physical surface
//
//  Copyright (C) 2005  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include <stdexcept>

#include "surface.h"
#include "voxtree.h"

using namespace Snogray;

Surface::~Surface () { } // stop gcc bitching

// Add this (or some other ...) surfaces to SPACE
//
void
Surface::add_to_space (Voxtree &space)
{
  space.add (this);
}

// Stubs -- these should be abstract methods, but C++ doesn't allow a
// class with abstract methods to be used in a list/vector, so we just
// signal a runtime error if they're ever called.

static void barf () __attribute__ ((noreturn));
static void
barf ()
{
  throw std::runtime_error ("tried to render abstract surface");
}

dist_t
Surface::intersection_distance (const Ray &ray, IsecParams &isec_params, unsigned num) const { barf (); }
Intersect Surface::intersect_info (const Ray &ray, const IsecParams &isec_params) const { barf (); }
BBox Surface::bbox () const { barf (); }
const Material *Surface::material () const { barf (); }


// arch-tag: a62e1854-d7ca-4cb3-a8dc-9be328c53430