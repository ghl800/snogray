// image-exr.h -- EXR format image handling
//
//  Copyright (C) 2005, 2006, 2007  Miles Bader <miles@gnu.org>
//
// This source code is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 3, or (at
// your option) any later version.  See the file COPYING for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __IMAGE_EXR_H__
#define __IMAGE_EXR_H__

#include <ImfRgbaFile.h>

#include "image-io.h"


namespace snogray {

class ExrImageSink : public ImageSink
{  
public:

  ExrImageSink (const std::string &filename, unsigned width, unsigned height,
		const ValTable &params = ValTable::NONE);

  // Return true if output has an alpha (opacity) channel.
  //
  virtual bool has_alpha_channel () const
  {
    return outf.channels() & Imf::WRITE_A;
  }

  virtual void write_row (const ImageRow &row);

private:

  Imf::RgbaOutputFile outf;

  std::vector<Imf::Rgba> row_buf;

  unsigned cur_y;
};

class ExrImageSource : public ImageSource
{  
public:

  ExrImageSource (const std::string &filename,
		  const ValTable &params = ValTable::NONE);

  // Return true if input has an alpha (opacity) channel.
  //
  virtual bool has_alpha_channel () const
  {
    return inf.channels() & Imf::WRITE_A;
  }

  virtual void read_row (ImageRow &row);

private:

  Imf::RgbaInputFile inf;

  std::vector<Imf::Rgba> row_buf;

  unsigned cur_y;
};

}

#endif /* __IMAGE_EXR_H__ */


// arch-tag: aefc9982-81ff-4087-a25a-85c97c09475d
