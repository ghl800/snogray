// ray-io.h -- Debugging output for Ray type
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

#ifndef __RAY_IO_H__
#define __RAY_IO_H__

#include <iosfwd>

#include "ray.h"

namespace snogray {

std::ostream& operator<< (std::ostream &os, const Ray &ray);

}

#endif // __RAY_IO_H__
