// image-io.cc -- Low-level image input and output
//
//  Copyright (C) 2005, 2006  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#include <string>
#include <cerrno>
#include <stdexcept>

#include "image-io.h"

using namespace Snogray;


// Handy functions to throw an error.  The file-name is prepended.

void
ImageIo::err (const char *msg, bool use_errno)
{
  std::string buf (filename);
  buf += ": ";
  buf += msg;
  if (use_errno)
    {
      buf += ": ";
      buf += strerror (errno);
    }
  throw std::runtime_error (buf);
}

void
ImageIo::open_err (const char *dir, const char *msg, bool use_errno)
{
  std::string buf ("Error opening ");
  buf += dir;
  buf += " file";
  if (msg && *msg)
    {
      buf += ": ";
      buf += msg;
    }
  err (buf.c_str(), use_errno);
}

void
ImageSink::open_err (const char *msg, bool use_errno)
{
  ImageIo::open_err ("output", msg, use_errno);
}

void
ImageSource::open_err (const char *msg, bool use_errno)
{
  ImageIo::open_err ("input", msg, use_errno);
}

void
ImageSink::flush ()
{
  // do nothing
}

float
ImageSink::max_intens () const
{
  return 0;			// no (meaningful) maximum, i.e. floating-point
}

ImageSource::~ImageSource () { }
ImageSink::~ImageSink () { }


// arch-tag: 3e9296c6-5ac7-4c39-8b79-45ce81b5d480
