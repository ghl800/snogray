// random-rand.h -- Random number classes using rand()
//
//  Copyright (C) 2010  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __RANDOM_RAND_H__
#define __RANDOM_RAND_H__

#include <cstdlib>


namespace snogray {


// A wrapper for std::rand.
//
struct RNG
{
  RNG () {}
  RNG (unsigned seed) { std::srand (seed); }
  unsigned operator() () { return std::rand (); }
  unsigned min() { return 0; }
  unsigned max() { return RAND_MAX; }
};

// A wrapper class that turns an unsigned-generating RNG into a RNG that
// generates floats in the range 0-1.
//
template<typename RNG>
class FloatRNGAdaptor
{
public:

  FloatRNGAdaptor (RNG &_rng)
    : offs (_rng.min ()),
      scale (1 / float (_rng.max () - offs)),
      rng (_rng)
    { }

  float operator() () const { return float (rng() - offs) * scale; }

protected:

  unsigned offs;
  float scale;

  RNG &rng;
};


}

#endif // __RANDOM_RAND_H__
