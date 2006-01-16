// camera.h -- Camera datatype
//
//  Copyright (C) 2005, 2006  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __CAMERA_H__
#define __CAMERA_H__

#include <cmath>

#include "rand.h"
#include "space.h"
#include "ray.h"

namespace Snogray {

class Camera {
public:
  static const Pos DEFAULT_POS;
  static const float DEFAULT_ASPECT_RATIO = 4.0 / 3.0;
  static const float DEFAULT_HORIZ_FOV = M_PI / 4;

  // Whether the (camera-relative) Z-axis increases when we move forward
  // (into the image), or decreases.  Our native mode is "increases forward",
  // but imported scenes may use a different convention.
  //
  enum z_mode {
    Z_INCREASES_FORWARD,
    Z_DECREASES_FORWARD
  };

  Camera (const Pos &_pos = DEFAULT_POS,
	  float aspect = DEFAULT_ASPECT_RATIO,
	  float horiz_fov = DEFAULT_HORIZ_FOV)
    : pos (_pos), user_up (Vec (0, 1, 0)),
      forward (Vec (0, 0, 1)), up (Vec (0, 1, 0)), right (Vec (1, 0, 0)),
      z_mode (Z_INCREASES_FORWARD), fov_x (horiz_fov)
  {
    set_aspect_ratio (aspect);
  }

  void move (const Pos &_pos) { pos = _pos; }
  void move (const Vec &vec) { pos += vec; }

  void point (const Vec &vec, const Vec &_user_up)
  {
    user_up = _user_up;

    forward = vec.unit ();

    right = _user_up.cross (forward).unit ();
    up = forward.cross (right).unit ();

    if (z_mode == Z_DECREASES_FORWARD)
      right = -right;
  }
  void point (const Pos &targ, const Vec &_user_up)
  {
    point (targ - pos, _user_up);
  }
  void point (const Vec &vec)
  {
    point (vec, user_up);
  }
  void point (const Pos &targ)
  {
    point (targ, user_up);
  }

  void set_aspect_ratio (float ratio)
  {
    aspect_ratio = ratio;
    fov_y = fov_x / ratio;
    tan_half_fov_x = tan (fov_x / 2);
    tan_half_fov_y = tan (fov_y / 2);
  }

  void set_horiz_fov (float fov)
  {
    fov_x = fov;
    fov_y = fov_x / aspect_ratio;
    tan_half_fov_x = tan (fov_x / 2);
    tan_half_fov_y = tan (fov_y / 2);
  }
  void set_vert_fov (float fov)
  {
    fov_y = fov;
    fov_x = fov * aspect_ratio;
    tan_half_fov_x = tan (fov_x / 2);
    tan_half_fov_y = tan (fov_y / 2);
  }

  Ray get_ray (float u, float v) const
  {
    Pos targ = pos;

    targ += forward;
    targ += 2 * (u - 0.5) * right * tan_half_fov_x;
    targ += 2 * (v - 0.5) * up * tan_half_fov_y;

    return Ray (pos, targ);
  }
  Ray get_ray (unsigned x, unsigned y, unsigned width, unsigned height,
	       bool jitter = false)
    const
  {
    float fx = float (x), fy = float (height - y);
    
    if (jitter)
      {
	fx += random (1);
	fy += random (1);
      }

    float u = fx / (float)width;
    float v = fy / (float)height;

    return get_ray (u, v);
  }

  // Set whether the Z axis increases into the image or decreases
  //
  void set_z_mode (enum z_mode _z_mode)
  {
    if (_z_mode != z_mode)
      {
	right = -right;
	z_mode = _z_mode;
      }
  }

  Pos pos;
  Vec user_up;

  Vec forward, up, right;

  // How the Z axis behaves with respect to the camera
  //
  enum z_mode z_mode;

  float aspect_ratio; /* horiz / vert */

  float fov_x, fov_y;
  float tan_half_fov_x, tan_half_fov_y;
};

}

#endif /* __CAMERA_H__ */

// arch-tag: 45c04676-91b9-4fdb-ae65-2fd3ea0f0228
