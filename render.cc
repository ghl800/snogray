// render.cc -- Main rendering loop
//
//  Copyright (C) 2006, 2007, 2008, 2009, 2010  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include "renderer.h"
#include "progress.h"

#include "render.h"


using namespace snogray;


static void
render_by_rows (Renderer &renderer,
		std::ostream &prog_stream, Progress::Verbosity verbosity)
{
  ImageOutput &output = renderer.output;

  // Start progress indicator
  //
  Progress prog (prog_stream, "rendering...",
		 renderer.lim_y, renderer.lim_y + output.height,
		 verbosity);

  prog.start ();

  for (unsigned row_offs = 0; row_offs < output.height; row_offs++)
    {
      renderer.render_block (renderer.lim_x, renderer.lim_y + row_offs,
			     output.width, 1);
      prog.update (renderer.lim_y + row_offs);
    }

  prog.end ();
}



static void
render_by_blocks (Renderer &renderer,
		  unsigned block_width, unsigned block_height,
		  std::ostream &prog_stream, Progress::Verbosity verbosity)
{
  ImageOutput &output = renderer.output;

  unsigned num_block_rows = (output.height + block_height - 1) / block_height;
  unsigned num_block_cols = (output.width + block_width - 1) / block_width;
  unsigned num_blocks = num_block_cols * num_block_rows;

  // Start progress indicator
  //
  Progress prog (prog_stream, "rendering...", 0, num_blocks, verbosity);

  prog.start ();

  unsigned cur_block_num = 0;

  // Iterate over every block, rendering each one.  Note that in the
  // case of a recovered image, many of these blocks may be outside
  // OUTPUT's "min_y" limit; that's OK -- rendering them will simply
  // have no effect.
  //
  for (unsigned block_y_offs = 0;
       block_y_offs < output.height;
       block_y_offs += block_height)
    {
      for (unsigned block_x_offs = 0;
	   block_x_offs < output.width;
	   block_x_offs += block_width)
	{
	  unsigned cur_block_width
	    = ((block_x_offs + block_width > output.width)
	       ? output.width - block_x_offs
	       : block_width);
	  unsigned cur_block_height
	    = ((block_y_offs + block_height > output.height)
	       ? output.height - block_y_offs
	       : block_height);

	  renderer.render_block (renderer.lim_x + block_x_offs,
				 renderer.lim_y + block_y_offs,
				 cur_block_width, cur_block_height);

	  prog.update (cur_block_num++);
      }

      output.flush ();
    }

  prog.end ();
}



void
snogray::render (const GlobalRenderState &global_render_state,
		 const Camera &camera,
		 unsigned width, unsigned height,
		 ImageOutput &output, unsigned offs_x, unsigned offs_y,
		 RenderStats &stats,
		 std::ostream &progress_stream, Progress::Verbosity verbosity)
{
  bool by_rows = global_render_state.params.get_bool ("render-by-rows", false);

  Renderer renderer (global_render_state, camera, width, height,
		     output, offs_x, offs_y, by_rows ? 1 : 16);

  // Do the actual rendering.
  //
  if (by_rows)
    render_by_rows (renderer, progress_stream, verbosity);
  else
    render_by_blocks (renderer, 16, 16, progress_stream, verbosity);

  stats = renderer.render_stats ();
}

// arch-tag: cbd1f440-1ebb-465b-a4e3-bd17777245f9
