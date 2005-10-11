// string-funs.h -- Random string helper functions
//
//  Copyright (C) 2005  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __STRING_FUNS__
#define __STRING_FUNS__

#include <string>

namespace Snogray {

// Return a string version of NUM
//
extern std::string stringify (unsigned num);

// Return a string version of NUM, with commas added every 3rd place
//
extern std::string commify (unsigned long long num, unsigned sep_count = 1);

}

#endif /* __STRING_FUNS__ */

// arch-tag: 9fcb681e-6711-4d6c-bc4a-293f5cbfabe3