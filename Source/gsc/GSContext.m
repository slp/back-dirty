/* -*- mode:ObjC -*-
   GSContext - Generic drawing context for non-PS backends

   Copyright (C) 1998,1999 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: Nov 1998
   
   This file is part of the GNU Objective C User Interface Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */

#include <AppKit/AppKitExceptions.h>
#include <AppKit/NSAffineTransform.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSView.h>
#include <AppKit/NSWindow.h>
#include <AppKit/GSDisplayServer.h>
#include <Foundation/NSException.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSData.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSDebug.h>

#include "gsc/GSContext.h"
#include "gsc/GSStreamContext.h"
#include "gsc/GSGState.h"

#define GSI_ARRAY_TYPES       GSUNION_OBJ

#if     GS_WITH_GC == 0
#define GSI_ARRAY_RELEASE(A, X)    [(X).obj release]
#define GSI_ARRAY_RETAIN(A, X)     [(X).obj retain]
#else
#define GSI_ARRAY_RELEASE(A, X)
#define GSI_ARRAY_RETAIN(A, X)     (X).obj
#endif

#ifdef GSIArray
#undef GSIArray
#endif
#include <base/GSIArray.h>

/* Error macros */
#define CHECK_NULL_OUTPUT(outvar) \
  do { if (outvar == NULL) {\
    DPS_ERROR(DPSnulloutput, @"NULL output variable specified"); \
    return; } } while(0)

#define CHECK_INVALID_FONT(ident) \
  do { if (ident >= [fontid count]) { \
    DPS_ERROR(DPSinvalidfont, @"Cannot find indicated font"); \
    return; } } while(0)

#define CHECK_STACK_UNDERFLOW(stack) \
  do { if (GSIArrayCount((GSIArray)stack) == 0) { \
    DPS_ERROR(DPSstackunderflow, @"Attempt to pop from empty stack"); \
    return; } } while(0)

#if 0
#define CHECK_TYPECHECK(obj, kind) \
  do { if ([kind class] != Nil && !GSObjCIsKindOf(GSObjCClass(obj), [kind class])) {\
    DPS_ERROR(DPStypecheck, @"Invalid object"); \
    return; } } while(0)
#else
#define CHECK_TYPECHECK(obj,kind)
#endif

#define ctxt_pop(object, stack, kind) \
  do { \
    CHECK_STACK_UNDERFLOW(stack); \
    object = (GSIArrayLastItem((GSIArray)stack)).obj; \
    CHECK_TYPECHECK(object, kind); \
    AUTORELEASE(RETAIN(object)); \
    GSIArrayRemoveLastItem((GSIArray)stack); \
  } while (0)

#define ctxt_push(object, stack) \
  GSIArrayAddItem((GSIArray)stack, (GSIArrayItem)object)

/* Globally unique gstate number */
static unsigned int unique_index = 0;

@interface GSContext (PrivateOps)
- (void)DPSdefineuserobject;
- (void)DPSexecuserobject: (int)index;
- (void)DPSundefineuserobject: (int)index;
- (void)DPSclear;
- (void)DPScopy: (int)n;
- (void)DPScount: (int *)n;
- (void)DPSdup;
- (void)DPSexch;
- (void)DPSindex: (int)i;
- (void)DPSpop;
@end

/**
   <unit>
   <heading>GSContext</heading>
   <p>
   This class is a reasonable attempt at providing PostScript-like
   drawing operations.  Don't even begin to think that this is a full
   PostScript implementation, however. Only operations that do not
   require stack handling are implemented.  Some other functions that
   would require stack handling and are needed for drawing are
   implemented in a different way (e.g. colorspace and images). These
   functions should also allow for a reasonable simulation of Quartz
   functionality.
   </p>
   </unit> */
@implementation GSContext 

- (id) initWithContextInfo: (NSDictionary *)info
{
  NSString *contextType;
  NSZone   *z = [self zone];

  contextType = [info objectForKey: 
		  NSGraphicsContextRepresentationFormatAttributeName];
  if (contextType && [contextType isEqual: NSGraphicsContextPSFormat])
    {
      /* Don't call self, since we aren't initialized */
      [super dealloc];
      return [[GSStreamContext allocWithZone: z] initWithContextInfo: info];
    }

  /* A context is only associated with one server. Do not retain
     the server, however */
  server = GSCurrentServer();

  /* Initialize lists and stacks */
  opstack =  NSZoneMalloc(z, sizeof(GSIArray_t));
  GSIArrayInitWithZoneAndCapacity((GSIArray)opstack, z, 2);
  gstack =  NSZoneMalloc(z, sizeof(GSIArray_t));
  GSIArrayInitWithZoneAndCapacity((GSIArray)gstack, z, 2);
  gtable = NSCreateMapTable(NSIntMapKeyCallBacks,
                                 NSObjectMapValueCallBacks, 20);

  [super initWithContextInfo: info];

  return self;
}

/**
   Closes all backend resources and dealloc other ivars.
*/
- (void) dealloc
{
  NSDebugLog(@"Destroying GS Context");
  GSIArrayEmpty((GSIArray)opstack);
  NSZoneFree([self zone], opstack);
  GSIArrayEmpty((GSIArray)gstack);
  NSZoneFree([self zone], gstack);
  NSFreeMapTable(gtable);
  DESTROY(gstate);
  [super dealloc];
}

/**
   Returns YES, since this is a display context.
*/
- (BOOL)isDrawingToScreen
{
  return YES;
}

/**
   Returns the current GSGState object
*/
- (GSGState *) currentGState
{
  return gstate;
}

@end

@implementation GSContext (Ops)

/* ----------------------------------------------------------------------- */
/* Color operations */
/* ----------------------------------------------------------------------- */
- (void) DPScurrentalpha: (float *)a
{
  [gstate DPScurrentalpha: a];
}

- (void) DPScurrentcmykcolor: (float*)c : (float*)m : (float*)y : (float*)k 
{
  [gstate DPScurrentcmykcolor:c :m :y :k];
}

- (void) DPScurrentgray: (float*)gray 
{
  CHECK_NULL_OUTPUT(gray);
  [gstate DPScurrentgray: gray];
}

- (void) DPScurrenthsbcolor: (float*)h : (float*)s : (float*)b 
{
  CHECK_NULL_OUTPUT(h);
  CHECK_NULL_OUTPUT(s);
  CHECK_NULL_OUTPUT(b);
  [gstate DPScurrenthsbcolor:h :s :b];
}

- (void) DPScurrentrgbcolor: (float*)r : (float*)g : (float*)b 
{
  CHECK_NULL_OUTPUT(r);
  CHECK_NULL_OUTPUT(g);
  CHECK_NULL_OUTPUT(b);
  [gstate DPScurrentrgbcolor:r :g :b];
}

- (void) DPSsetalpha: (float)a
{
  [gstate DPSsetalpha: a];
}

- (void) DPSsetcmykcolor: (float)c : (float)m : (float)y : (float)k 
{
  [gstate DPSsetcmykcolor:c :m :y :k];
}

- (void) DPSsetgray: (float)gray 
{
  [gstate DPSsetgray: gray];
}

- (void) DPSsethsbcolor: (float)h : (float)s : (float)b 
{
  [gstate DPSsethsbcolor:h :s :b];
}

- (void) DPSsetrgbcolor: (float)r : (float)g : (float)b 
{
  [gstate DPSsetrgbcolor:r :g :b];
}

- (void) GSSetFillColorspace: (NSDictionary *)dict
{
  [self notImplemented: _cmd];
}

- (void) GSSetStrokeColorspace: (NSDictionary *)dict
{
  [self notImplemented: _cmd];
}

- (void) GSSetFillColor: (float *)values
{
  [self notImplemented: _cmd];
}

- (void) GSSetStrokeColor: (float *)values
{
  [self notImplemented: _cmd];
}

/* ----------------------------------------------------------------------- */
/* Text operations */
/* ----------------------------------------------------------------------- */
- (void) DPSashow: (float)x : (float)y : (const char *)s 
{
  [gstate DPSashow: x : y : s];
}

- (void) DPSawidthshow: (float)cx : (float)cy : (int)c : (float)ax : (float)ay : (const char *)s 
{
  [gstate DPSawidthshow: cx : cy : c : ax : ay : s];
}

- (void) DPScharpath: (const char *)s : (int)b 
{
  [gstate DPScharpath: s : b];
}

- (void) DPSshow: (const char *)s 
{
  [gstate DPSshow: s];
}

- (void) DPSwidthshow: (float)x : (float)y : (int)c : (const char *)s 
{
  [gstate DPSwidthshow: x : y : c : s];
}

- (void) DPSxshow: (const char *)s : (const float*)numarray : (int)size 
{
  [gstate DPSxshow: s : numarray : size];
}

- (void) DPSxyshow: (const char *)s : (const float*)numarray : (int)size 
{
  [gstate DPSxyshow: s : numarray : size];
}

- (void) DPSyshow: (const char *)s : (const float*)numarray : (int)size 
{
  [gstate DPSyshow: s : numarray : size];
}

- (void) GSSetCharacterSpacing: (float)extra
{
  [self notImplemented: _cmd];
}

- (void) GSSetFont: (NSFont*)font
{
  [gstate setFont: font];
}

- (void) GSSetFontSize: (float)size
{
  [self notImplemented: _cmd];
}

- (NSAffineTransform *) GSGetTextCTM
{
  [self notImplemented: _cmd];
  return nil;
}

- (NSPoint) GSGetTextPosition
{
  [self notImplemented: _cmd];
  return NSMakePoint(0,0);
}

- (void) GSSetTextCTM: (NSAffineTransform *)ctm
{
  [self notImplemented: _cmd];
}

- (void) GSSetTextDrawingMode: (GSTextDrawingMode)mode
{
  [self notImplemented: _cmd];
}

- (void) GSSetTextPosition: (NSPoint)loc
{
  [self notImplemented: _cmd];
}

- (void) GSShowText: (const char *)string : (size_t) length
{
  [self notImplemented: _cmd];
}

- (void) GSShowGlyphs: (const NSGlyph *)glyphs : (size_t) length
{
  [self notImplemented: _cmd];
}

/* ----------------------------------------------------------------------- */
/* Gstate Handling */
/* ----------------------------------------------------------------------- */

- (void) DPSgrestore
{
  if (GSIArrayCount((GSIArray)gstack) == 0)
    return;
  RELEASE(gstate);
  gstate = (GSIArrayLastItem((GSIArray)gstack)).obj;
  ctxt_pop(gstate, gstack, GSGState);
  RETAIN(gstate);
}

- (void) DPSgsave
{
  ctxt_push(gstate, gstack);
  AUTORELEASE(gstate);
  gstate = [gstate copy];
}

- (void) DPSinitgraphics
{
  [gstate DPSinitgraphics];
}

- (void) DPSsetgstate: (int)gst
{
  if (gst)
    {
      [self DPSexecuserobject: gst];
      RELEASE(gstate);
      ctxt_pop(gstate, opstack, GSGState);
      RETAIN(gstate);
    }
  else
    DESTROY(gstate);
}

- (int) GSDefineGState
{
  if(gstate == nil)
    {
      DPS_ERROR(DPSundefined, @"No gstate");
      return 0;
    }
  NSMapInsert(gtable, (void *)++unique_index, AUTORELEASE([gstate copy]));
  return unique_index;
}

- (void) GSUndefineGState: (int)gst
{
  [self DPSundefineuserobject: gst];
}

- (void) GSReplaceGState: (int)gst
{
  if(gst <= 0)
    return;
  NSMapInsert(gtable, (void *)gst, AUTORELEASE([gstate copy]));
}

/* ----------------------------------------------------------------------- */
/* Gstate operations */
/* ----------------------------------------------------------------------- */
- (void) DPScurrentflat: (float*)flatness
{
  CHECK_NULL_OUTPUT(flatness);
  [gstate DPScurrentflat: flatness];
}

- (void) DPScurrentlinecap: (int*)linecap
{
  [gstate DPScurrentlinecap: linecap];
}

- (void) DPScurrentlinejoin: (int*)linejoin
{
  [gstate DPScurrentlinejoin: linejoin];
}

- (void) DPScurrentlinewidth: (float*)width
{
  [gstate DPScurrentlinewidth: width];
}

- (void) DPScurrentmiterlimit: (float*)limit
{
  CHECK_NULL_OUTPUT(limit);
  [gstate DPScurrentmiterlimit: limit];
}

- (void) DPScurrentpoint: (float*)x : (float*)y
{
  CHECK_NULL_OUTPUT(x);
  CHECK_NULL_OUTPUT(y);
  [gstate DPScurrentpoint:x :y];
}

- (void) DPScurrentstrokeadjust: (int*)b
{
  CHECK_NULL_OUTPUT(b);
  [gstate DPScurrentstrokeadjust: b];
}

- (void) DPSsetdash: (const float*)pat : (int)size : (float)offset
{
  [gstate DPSsetdash: pat : size : offset]; 
}

- (void) DPSsetflat: (float)flatness
{
  [gstate DPSsetflat: flatness];
}

- (void) DPSsethalftonephase: (float)x : (float)y
{
  [self notImplemented: _cmd];
}

- (void) DPSsetlinecap: (int)linecap
{
  [gstate DPSsetlinecap: linecap];
}

- (void) DPSsetlinejoin: (int)linejoin
{
  [gstate DPSsetlinejoin: linejoin];
}

- (void) DPSsetlinewidth: (float)width
{
  [gstate DPSsetlinewidth: width];
}

- (void) DPSsetmiterlimit: (float)limit
{
  [gstate DPSsetmiterlimit: limit];
}

- (void) DPSsetstrokeadjust: (int)b
{
  [gstate DPSsetstrokeadjust: b];
}

/* ----------------------------------------------------------------------- */
/* Matrix operations */
/* ----------------------------------------------------------------------- */
- (void) DPSconcat: (const float*)m
{
  [gstate DPSconcat: m];
}

- (void) DPSinitmatrix
{
  [gstate DPSinitmatrix];
}

- (void) DPSrotate: (float)angle
{
  [gstate DPSrotate: angle];
}

- (void) DPSscale: (float)x : (float)y
{
  [gstate DPSscale:x :y];
}

- (void) DPStranslate: (float)x : (float)y
{
  [gstate DPStranslate:x :y];
}

- (NSAffineTransform *) GSCurrentCTM
{
  return [gstate GSCurrentCTM];
}

- (void) GSSetCTM: (NSAffineTransform *)ctm
{
  [gstate GSSetCTM: ctm];
}

- (void) GSConcatCTM: (NSAffineTransform *)ctm
{
  [gstate GSConcatCTM: ctm];
}

/* ----------------------------------------------------------------------- */
/* Paint operations */
/* ----------------------------------------------------------------------- */
- (void) DPSarc: (float)x : (float)y : (float)r : (float)angle1 
	       : (float)angle2
{
  [gstate DPSarc: x : y : r : angle1 : angle2];
}

- (void) DPSarcn: (float)x : (float)y : (float)r : (float)angle1 
		: (float)angle2
{
  [gstate DPSarcn: x : y : r : angle1 : angle2];
}

- (void) DPSarct: (float)x1 : (float)y1 : (float)x2 : (float)y2 : (float)r;
{
  [gstate DPSarct: x1 : y1 : x2 : y2 : r];
}

- (void) DPSclip
{
  [gstate DPSclip];
}

- (void) DPSclosepath
{
  [gstate DPSclosepath];
}

- (void) DPScurveto: (float)x1 : (float)y1 : (float)x2 : (float)y2 
		   : (float)x3 : (float)y3
{
  [gstate DPScurveto: x1 : y1 : x2 : y2 : x3 : y3];
}

- (void) DPSeoclip
{
  [gstate DPSeoclip];
}

- (void) DPSeofill
{
  [gstate DPSeofill];
}

- (void) DPSfill
{
  [gstate DPSfill];
}

- (void) DPSflattenpath
{
  [gstate DPSflattenpath];
}

- (void) DPSinitclip
{
  [gstate DPSinitclip];
}

- (void) DPSlineto: (float)x : (float)y
{
  [gstate DPSlineto: x : y];
}

- (void) DPSmoveto: (float)x : (float)y
{
  [gstate DPSmoveto: x : y];
}

- (void) DPSnewpath
{
  [gstate DPSnewpath];
}

- (void) DPSpathbbox: (float*)llx : (float*)lly : (float*)urx : (float*)ury
{
  [gstate DPSpathbbox: llx : lly : urx : ury];
}

- (void) DPSrcurveto: (float)x1 : (float)y1 : (float)x2 : (float)y2 
		    : (float)x3 : (float)y3
{
  [gstate DPSrcurveto: x1 : y1 : x2 : y2 : x3 : y3];
}

- (void) DPSrectclip: (float)x : (float)y : (float)w : (float)h
{
  [gstate DPSrectclip: x : y : w : h];
}

- (void) DPSrectfill: (float)x : (float)y : (float)w : (float)h
{
  [gstate DPSrectfill:x :y :w :h];
}

- (void) DPSrectstroke: (float)x : (float)y : (float)w : (float)h
{
  [gstate DPSrectstroke:x :y :w :h];
}

- (void) DPSreversepath
{
  [gstate DPSreversepath];
}

- (void) DPSrlineto: (float)x : (float)y
{
  [gstate DPSrlineto: x : y];
}

- (void) DPSrmoveto: (float)x : (float)y
{
  [gstate DPSrmoveto: x : y];
}

- (void) DPSstroke
{
  [gstate DPSstroke];
}

- (void) GSSendBezierPath: (NSBezierPath *)path
{
  [gstate GSSendBezierPath: path];
}

- (void) GSRectClipList: (const NSRect *)rects : (int) count
{
  [gstate GSRectClipList: rects : count];
}

- (void) GSRectFillList: (const NSRect *)rects : (int) count
{
  [gstate GSRectFillList: rects : count];
}

/* ----------------------------------------------------------------------- */
/* Window system ops */
/* ----------------------------------------------------------------------- */
- (void) DPScurrentoffset: (int *)x : (int *)y
{
  if (x && y)
    {
      NSPoint offset = [gstate offset];
      *x = offset.x;
      *y = offset.y;
    }
}

- (void) DPSsetoffset: (short int)x : (short int)y
{
  [gstate setOffset: NSMakePoint(x,y)];
}

/*-------------------------------------------------------------------------*/
/* Graphics Extension Ops */
/*-------------------------------------------------------------------------*/
- (void) DPScomposite: (float)x : (float)y : (float)w : (float)h 
		     : (int)gstateNum : (float)dx : (float)dy : (int)op
{
  NSRect rect;
  NSPoint p;
  GSGState *g = gstate;

  if (gstateNum)
    {
      [self DPSexecuserobject: gstateNum];
      ctxt_pop(g, opstack, GSGState);
    }

  rect = NSMakeRect(x, y, w, h);
  p    = NSMakePoint(dx, dy);

  [gstate compositeGState: g fromRect: rect toPoint: p op: op];
}

- (void) DPScompositerect: (float)x : (float)y : (float)w : (float)h : (int)op
{
  [gstate  compositerect: NSMakeRect(x, y, w, h) op: op];
}

- (void) DPSdissolve: (float)x : (float)y : (float)w : (float)h 
		    : (int)gstateNum : (float)dx : (float)dy : (float)delta
{
  NSRect rect;
  NSPoint p;
  GSGState *g = gstate;

  if (gstateNum)
    {
      [self DPSexecuserobject: gstateNum];
      ctxt_pop(g, opstack, GSGState);
    }

  rect = NSMakeRect(x, y, w, h);
  p    = NSMakePoint(dx, dy);

  [gstate dissolveGState: g fromRect: rect toPoint: p delta: delta];
}

- (void) GSDrawImage: (NSRect) rect: (void *) imageref
{
  [self notImplemented: _cmd];
}

/* ----------------------------------------------------------------------- */
/* Client functions */
/* ----------------------------------------------------------------------- */
- (void) DPSPrintf: (char *)fmt : (va_list)args
{
  /* Do nothing. We can't parse PostScript */
}

- (void) DPSWriteData: (char *)buf : (unsigned int)count
{
  /* Do nothing. We can't parse PostScript */
}

@end

/* ----------------------------------------------------------------------- */
/* NSGraphics Ops */	
/* ----------------------------------------------------------------------- */
@implementation GSContext (NSGraphics)
/*
 * Render Bitmap Images
 */
- (void) NSDrawBitmap: (NSRect) rect : (int) pixelsWide : (int) pixelsHigh
		     : (int) bitsPerSample : (int) samplesPerPixel 
		     : (int) bitsPerPixel : (int) bytesPerRow : (BOOL) isPlanar
		     : (BOOL) hasAlpha : (NSString *) colorSpaceName
		     : (const unsigned char *const [5]) data
{
  NSAffineTransform *trans;
  NSSize scale;

  // Compute the transformation matrix
  scale = NSMakeSize(NSWidth(rect) / pixelsWide, 
		     NSHeight(rect) / pixelsHigh);
  trans = [NSAffineTransform transform];
  [trans translateToPoint: rect.origin];
  [trans scaleBy: scale.width : scale.height];

  /* This does essentially what the DPS...image operators do, so
     as to avoid an extra method call */
  [gstate DPSimage: trans 
	          : pixelsWide : pixelsHigh 
		  : bitsPerSample : samplesPerPixel 
		  : bitsPerPixel : bytesPerRow 
		  : isPlanar
		  : hasAlpha : colorSpaceName
		  : data];
}

- (void) GSWSetViewIsFlipped: (BOOL) flipped
{
  if(gstate)
    gstate->viewIsFlipped = flipped;
}

/* ----------------------------------------------------------------------- */
/* Data operations - Obsolete but possibly still useful */
/* ----------------------------------------------------------------------- */

- (void)DPSdefineuserobject
{
  int n;
  id obj;
  NSNumber *number;
  ctxt_pop(obj, opstack, NSObject);
  ctxt_pop(number, opstack, NSNumber);
  n = [number intValue];
  if (n < 0)
    DPS_ERROR(DPSinvalidparam, @"Invalid userobject index");
  else 
    NSMapInsert(gtable, (void *)n, obj);
}

- (void)DPSexecuserobject: (int)index
{
  if (index < 0 || NSMapGet(gtable, (void *)index) == nil)
    {
      DPS_ERROR(DPSinvalidparam, @"Invalid userobject index");
      return;
    }
  ctxt_push((id)NSMapGet(gtable, (void *)index), opstack);
}

- (void)DPSundefineuserobject: (int)index
{
  if (index < 0 || NSMapGet(gtable, (void *)index) == nil)
    {
      DPS_ERROR(DPSinvalidparam, @"Invalid gstate index");
      return;
    }
  NSMapRemove(gtable, (void *)index);
}

- (void)DPSclear 
{
  GSIArrayEmpty((GSIArray)opstack);
  GSIArrayInitWithZoneAndCapacity((GSIArray)opstack, [self zone], 2);
}

- (void)DPScopy: (int)n 
{
  unsigned count = GSIArrayCount((GSIArray)opstack);
  int i;

  for (i = 0; i < n; i++)
    {
      NSObject *obj = (GSIArrayItemAtIndex((GSIArray)opstack, count - n + i)).obj;

      ctxt_push(obj, opstack);
    }
}

- (void)DPScount: (int *)n 
{
  CHECK_NULL_OUTPUT(n);
  *n = GSIArrayCount((GSIArray)opstack);
}

- (void)DPSdup 
{
  NSObject *obj = (GSIArrayLastItem((GSIArray)opstack)).obj;

  ctxt_push(obj, opstack);
}

- (void)DPSexch 
{
  unsigned count = GSIArrayCount((GSIArray)opstack);

  if (count < 2)
    {
      DPS_ERROR(DPSstackunderflow, @"Attempt to exch in empty stack");
      return;
    }
  GSIArrayInsertItem((GSIArray)opstack, 
		 GSIArrayLastItem((GSIArray)opstack), count-2);
  GSIArrayRemoveLastItem((GSIArray)opstack);
}

- (void)DPSindex: (int)i 
{
  unsigned count = GSIArrayCount((GSIArray)opstack);
  NSObject *obj = (GSIArrayItemAtIndex((GSIArray)opstack, count - i)).obj;

  ctxt_push(obj, opstack);
}

- (void)DPSpop 
{
  id obj;
  ctxt_pop(obj, opstack, NSObject);
}
@end
