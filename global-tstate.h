// global-tstate.h -- Global tracing state
//
//  Copyright (C) 2005, 2006, 2007  Miles Bader <miles@gnu.org>
//
// This file is subject to the terms and conditions of the GNU General
// Public License.  See the file COPYING in the main directory of this
// archive for more details.
//
// Written by Miles Bader <miles@gnu.org>
//

#ifndef __GLOBAL_TSTATE_H__
#define __GLOBAL_TSTATE_H__


#include "trace-stats.h"
#include "trace-params.h"
#include "mempool.h"


namespace snogray {

class IllumGlobalState;


class GlobalTraceState
{
public:

  GlobalTraceState (const TraceParams &_params);
  ~GlobalTraceState ();

  const TraceParams &params;

  IllumGlobalState *illum_global_state;

  // This mempool is reset every time control returns to the top level
  // of a trace tree, so should not be used for anything longer-lived
  // that that.
  //
  Mempool mempool;

  TraceStats stats;
};


}

#endif /* __GLOBAL_TSTATE_H__ */


// arch-tag: f3691316-99dd-4b9c-a405-8c816ba4e361
