// scene.cc -- Scene description datatype
//
//  Copyright (C) 2005  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include "scene.h"

using namespace Snogray;
using namespace std;

// The scene "owns" all its components, so frees them when it is destroyed
//
Scene::~Scene ()
{
  for (list<Obj *>::iterator oi = objs.begin();
       oi != objs.end(); oi++)
    delete *oi;
  for (list<Light *>::iterator li = lights.begin();
       li != lights.end(); li++)
    delete *li;
  for (list<Material *>::iterator mi = materials.begin();
       mi != materials.end(); mi++)
    delete *mi;
}


// "Closest" intersection testing (tests all objects for intersection
// with a ray, returns the distance to the closest intersection)

struct SceneClosestIntersectCallback : Voxtree::IntersectCallback
{
  SceneClosestIntersectCallback (const Ray &ray, Voxtree::Stats *stats = 0)
    : IntersectCallback (stats), isec (ray), num_calls (0)
  { }

  virtual void operator() (Obj *);

  Intersect isec;

  unsigned num_calls;
};

void
SceneClosestIntersectCallback::operator () (Obj *obj)
{
  isec.update (obj);
  num_calls++;
}

Intersect
Scene::closest_intersect (const Ray &ray)
{
  SceneClosestIntersectCallback
    closest_isec_cb (ray, &stats.voxtree_closest_intersect);

  stats.scene_closest_intersect_calls++;

  obj_voxtree.for_each_possible_intersector (ray, closest_isec_cb);

  closest_isec_cb.isec.finish ();

  stats.obj_closest_intersect_calls += closest_isec_cb.num_calls;

  return closest_isec_cb.isec;
}


// Shadow intersection testing

struct SceneShadowedCallback : Voxtree::IntersectCallback
{
  SceneShadowedCallback (Light &_light, const Ray &_light_ray,
			 const Obj *_ignore = 0,
			 Voxtree::Stats *stats = 0)
    : IntersectCallback (stats), 
      light (_light), light_ray (_light_ray), ignore (_ignore),
      shadowed (false), num_tests (0)
  { }

  virtual void operator() (Obj *);

  Light &light;
  const Ray &light_ray;
  const Obj *ignore;

  bool shadowed;

  unsigned num_tests;
};

void
SceneShadowedCallback::operator () (Obj *obj)
{
  if (obj != ignore && !obj->no_shadow)
    {
      num_tests++;

      shadowed = obj->intersects (light_ray);

      if (shadowed)
	{
	  // Remember which object cast a shadow from this light, so we
	  // can try it first next time.
	  //
	  light.shadow_hint = obj;

	  // Stop looking any further.
	  //
	  stop_iteration ();
	}
    }
}

bool
Scene::shadowed (Light &light, const Ray &light_ray, const Obj *ignore)
{
  stats.scene_shadowed_tests++;

  // See if this light has a shadow hint (the last object that cast a shadow
  // from it); if it does, then try that object first, as it stands a better
  // chance of hitting than usual (because nearby points are often shadowed
  // from a given light by the same object).
  //
  if (light.shadow_hint && light.shadow_hint != ignore)
    {
      if (light.shadow_hint->intersects (light_ray))
	// It worked!  Return quickly.
	{
	  stats.shadow_hint_hits++;
	  return true;
	}
      else
	// It didn't work; clear this hint out.
	{
	  stats.shadow_hint_misses++;
	  light.shadow_hint = 0;
	}
    }

  SceneShadowedCallback
    shadowed_cb (light, light_ray, ignore, &stats.voxtree_shadowed);

  obj_voxtree.for_each_possible_intersector (light_ray, shadowed_cb);

  stats.obj_intersects_tests += shadowed_cb.num_tests;

  return shadowed_cb.shadowed;
}


// Main rendering entry point

Color
Scene::render (const Intersect &isec)
{
  if (isec.obj)
    {
      // If the dot product of the surface normal with the eye ray is
      // negative, we're looking at the back of the surface; we render
      // this as a striking color to make it easier to detect mistakes.
      // However to accomodate small cumulative errors, we allow very
      // small negative dot-products as if they were zero.

      if (isec.normal.dot (isec.eye_dir) >= 0 -0.0001)
	{
	  // We're looking at the top of the surface, continue with rendering.
	  // Iterate over every light, calculating its contribution to our
	  // color.

	  Color total_color;	// Accumulated colors from all light sources

	  for (list<Light *>::const_iterator li = lights.begin();
	       li != lights.end(); li++)
	    {
	      Light *light = *li;
	      Ray light_ray = Ray (isec.point, light->pos);

	      // If the dot-product of the light-ray with the surface normal
	      // is negative, that means the light is behind the surface, so
	      // cannot light it ("self-shadowing"); otherwise, see if some
	      // other object casts a shadow.

	      if (isec.normal.dot (light_ray.dir) >= 0
		  && !shadowed (*light, light_ray, isec.obj))
		{
		  // This point is not shadowed, either by ourselves or by any
		  // other object, so calculate the lighting contribution from
		  // LIGHT.

		  Color light_color
		    = light->color / (light_ray.len * light_ray.len);

		  total_color
		    += isec.obj->material->render (
					     isec, light_ray.dir, light_color);
		}
	    }

	  return total_color;
	}
      else
	// We're looking at the back of the surface, render as wacky color.
	//
	return Color::funny;
    }
  else
    return background;
}

// arch-tag: ecdd27ee-862e-436b-b0c6-357007955558
