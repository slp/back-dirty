/*
   CairoGState.m

   Copyright (C) 2003 Free Software Foundation, Inc.

   August 31, 2003
   Written by Banlu Kemiyatorn <object at gmail dot com>
   Rewrite: Fred Kiefer <fredkiefer@gmx.de>
   Date: Jan 2006
 
   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#include <AppKit/NSAffineTransform.h>
#include <AppKit/NSBezierPath.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSGradient.h>
#include <AppKit/NSGraphics.h>
#include "cairo/CairoGState.h"
#include "cairo/CairoFontInfo.h"
#include "cairo/CairoSurface.h"
#include "cairo/CairoContext.h"
#include <math.h>


// Macro stolen from base/Header/Additions/GNUstepBase/GSObjRuntime.h
#ifndef	GS_MAX_OBJECTS_FROM_STACK
/**
 * The number of objects to try to get from varargs into an array on
 * the stack ... if there are more than this, use the heap.
 * NB. This MUST be a multiple of 2
 */
#define	GS_MAX_OBJECTS_FROM_STACK	128
#endif

// Macros stolen from base/Source/GSPrivate.h
/**
 * Macro to manage memory for chunks of code that need to work with
 * arrays of items.  Use this to start the block of code using
 * the array and GS_ENDITEMBUF() to end it.  The idea is to ensure that small
 * arrays are allocated on the stack (for speed), but large arrays are
 * allocated from the heap (to avoid stack overflow).
 */
#define	GS_BEGINITEMBUF(P, S, T) { \
  T _ibuf[(S) <= GS_MAX_OBJECTS_FROM_STACK ? (S) : 0]; \
  T *_base = ((S) <= GS_MAX_OBJECTS_FROM_STACK) ? _ibuf \
    : (T*)NSZoneMalloc(NSDefaultMallocZone(), (S) * sizeof(T)); \
  T *(P) = _base;

/**
 * Macro to manage memory for chunks of code that need to work with
 * arrays of items.  Use GS_BEGINITEMBUF() to start the block of code using
 * the array and this macro to end it.
 */
#define	GS_ENDITEMBUF() \
  if (_base != _ibuf) \
    NSZoneFree(NSDefaultMallocZone(), _base); \
  }

static float floatFromUserSpace(NSAffineTransform *ctm, float f)
{
  NSSize s = {f, f};

  if (ctm)
    {
      s = [ctm transformSize: s];
      f = (((s.width > 0.0) ? s.width : -s.width) + 
           ((s.height > 0.0) ? s.height : -s.height)) / 2;
    }
  return f;
}

static float floatToUserSpace(NSAffineTransform *ctm, float f)
{
  NSAffineTransform *ictm;
  
  ictm = [ctm copyWithZone: [ctm zone]];
  [ictm invert];
  f = floatFromUserSpace(ictm, f);
  RELEASE(ictm);
  return f;
}



@implementation CairoGState 

+ (void) initialize
{
  if (self == [CairoGState class])
    {
    }
}

- (void) dealloc
{
  if (_ct)
    {
      cairo_destroy(_ct);
    }
  RELEASE(_surface);

  [super dealloc];
}

- (id) copyWithZone: (NSZone *)zone
{
  CairoGState *copy = (CairoGState *)[super copyWithZone: zone];

  RETAIN(_surface);

  if (_ct)
    {
      cairo_status_t status;
 
      // FIXME: Need some way to do a copy
      // but there isnt anything like copy->_ct = cairo_copy(_ct);
      copy->_ct = cairo_create(cairo_get_target(_ct));
      status = cairo_status(copy->_ct);
      if (status != CAIRO_STATUS_SUCCESS)
        {
          NSLog(@"Cairo status '%s' in copy", cairo_status_to_string(status));
          copy->_ct = NULL;
        }
      else
        {
          cairo_path_t *cpath;
          cairo_matrix_t local_matrix;
#if CAIRO_VERSION > CAIRO_VERSION_ENCODE(1, 4, 0)
          cairo_rectangle_list_t *clip_rects;
          int	num_dashes;
#endif

          cairo_get_matrix(_ct, &local_matrix);
          cairo_set_matrix(copy->_ct, &local_matrix);
          status = cairo_status(copy->_ct);
          if (status != CAIRO_STATUS_SUCCESS)
            {
              NSLog(@"Cairo status '%s' in set matrix", cairo_status_to_string(status));
            }

          cpath = cairo_copy_path(_ct);
          status = cpath->status;
          if (status != CAIRO_STATUS_SUCCESS)
            {
              /*
                Due to an interesting programming concept in cairo this does not
                mean that an error has occured. It may as well just be that the 
                old path had no elements. 
                At least in cairo 1.4.10 (See file cairo-path.c, line 379).
              */
              // NSLog(@"Cairo status '%s' in copy path", cairo_status_to_string(status));
            }
          else
            {
              cairo_append_path(copy->_ct, cpath);
            }
          cairo_path_destroy(cpath);
          
          cairo_set_operator(copy->_ct, cairo_get_operator(_ct));
          cairo_set_source(copy->_ct, cairo_get_source(_ct));
          cairo_set_tolerance(copy->_ct, cairo_get_tolerance(_ct));
          cairo_set_antialias(copy->_ct, cairo_get_antialias(_ct));
          cairo_set_line_width(copy->_ct, cairo_get_line_width(_ct));
          cairo_set_line_cap(copy->_ct, cairo_get_line_cap(_ct));
          cairo_set_line_join(copy->_ct, cairo_get_line_join(_ct));
          cairo_set_miter_limit(copy->_ct, cairo_get_miter_limit(_ct));

#if CAIRO_VERSION > CAIRO_VERSION_ENCODE(1, 4, 0)
          // In cairo 1.4 there is a way get the dash.
          num_dashes = cairo_get_dash_count(_ct);
          if (num_dashes != 0)
            {
              double dash_offset;
              GS_BEGINITEMBUF(dashes, num_dashes, double);

              cairo_get_dash(_ct, dashes, &dash_offset);
              cairo_set_dash (copy->_ct, dashes, num_dashes, dash_offset);
              GS_ENDITEMBUF();
            }

          // In cairo 1.4 there also is a way to get the current clipping path
          clip_rects = cairo_copy_clip_rectangle_list(_ct);
          status = clip_rects->status;
          if (status == CAIRO_STATUS_SUCCESS)
            {
              int i;

              if (cairo_version() >= CAIRO_VERSION_ENCODE(1, 6, 0))
                {
                  for (i = 0; i < clip_rects->num_rectangles; i++)
                    {
                      cairo_rectangle_t rect = clip_rects->rectangles[i];

                      cairo_rectangle(copy->_ct, rect.x, rect.y, 
                                      rect.width, rect.height);
                      cairo_clip(copy->_ct);
                    }
                }
              else
                {
                  for (i = 0; i < clip_rects->num_rectangles; i++)
                    {
                      cairo_rectangle_t rect = clip_rects->rectangles[i];
                      NSSize size = [_surface size];

                      cairo_rectangle(copy->_ct, rect.x, 
                                      /* This strange computation is due 
                                         to the device offset missing for 
                                         clip rects in cairo < 1.6.0.  */
                                      rect.y + 2*(offset.y - size.height), 
                                      rect.width, rect.height);
                      cairo_clip(copy->_ct);
                    }
                }

              cairo_rectangle_list_destroy(clip_rects);
            }
          else if (status == CAIRO_STATUS_CLIP_NOT_REPRESENTABLE)
            {
              // We cannot get the exact clip, so we do the best we can
              double x1;
              double y1;
              double x2;
              double y2;

              cairo_clip_extents(_ct, &x1, &y1, &x2, &y2);
              cairo_rectangle(copy->_ct, x1, y1, x2 - x1, y2 - y1);
              cairo_clip(copy->_ct);
            }
          else
            {
              NSLog(@"Cairo status '%s' in copy clip", cairo_status_to_string(status));
            }
#endif
        }
    }

  return copy;
}

- (void) GSCurrentSurface: (CairoSurface **)surface: (int *)x : (int *)y
{
  if (x)
    *x = offset.x;
  if (y)
    *y = offset.y;
  if (surface)
    {
      *surface = _surface;
    }
}

- (void) GSSetSurface: (CairoSurface *)surface : (int)x : (int)y
{
  ASSIGN(_surface, surface);
  [self setOffset: NSMakePoint(x, y)];
  [self DPSinitgraphics];
}

- (void) setOffset: (NSPoint)theOffset
{
  if (_surface != nil)
    {
      NSSize size = [_surface size];

      cairo_surface_set_device_offset([_surface surface], -theOffset.x, 
                                      theOffset.y - size.height);
    }
  [super setOffset: theOffset];
}

- (void) showPage
{
  if (_ct)
    {
      cairo_show_page(_ct);
    }
}

/*
 * Color operations
 */
- (void) GSSetPatterColor: (NSImage*)image 
{
  // FIXME: Create a cairo surface from the image and set it as source.
  [super GSSetPatterColor: image];
}

/*
 * Text operations
 */

- (void) _setPoint
{
  NSPoint p;

  p = [path currentPoint];
  cairo_move_to(_ct, floorf(p.x), floorf(p.y));
}

- (void) DPScharpath: (const char *)s : (int)b
{
  if (_ct)
    {
      GS_BEGINITEMBUF(c, b + 1, char);

      [self _setPoint];
      memcpy(c, s, b);
      c[b] = 0;
      cairo_text_path(_ct, c);
      GS_ENDITEMBUF();
      if (cairo_status(_ct) == CAIRO_STATUS_SUCCESS)
        {
          cairo_path_t *cpath;
          cairo_path_data_t *data;
          int i;
         
          cpath = cairo_copy_path(_ct);
          
          for (i = 0; i < cpath->num_data; i += cpath->data[i].header.length) 
            {
              data = &cpath->data[i];
              switch (data->header.type) 
                {
                  case CAIRO_PATH_MOVE_TO:
                    [path moveToPoint: NSMakePoint(data[1].point.x, data[1].point.y)];
                    break;
                  case CAIRO_PATH_LINE_TO:
                    [path lineToPoint: NSMakePoint(data[1].point.x, data[1].point.y)];
                    break;
                  case CAIRO_PATH_CURVE_TO:
                    [path curveToPoint: NSMakePoint(data[3].point.x, data[3].point.y) 
                          controlPoint1: NSMakePoint(data[1].point.x, data[1].point.y)
                          controlPoint2: NSMakePoint(data[2].point.x, data[2].point.y)];
                    break;
                  case CAIRO_PATH_CLOSE_PATH:
                    [path closePath];
                    break;
                }
            }
          cairo_path_destroy(cpath);
        }
    }
}

- (void) DPSshow: (const char *)s
{
  if (_ct)
    {
      cairo_matrix_t saved_matrix;
      cairo_matrix_t local_matrix;
      NSPoint        p = [path currentPoint];
      device_color_t c;

      c = strokeColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);

      cairo_get_matrix(_ct, &saved_matrix);

      cairo_matrix_init_scale(&local_matrix, 1, 1);
      cairo_matrix_translate(&local_matrix, 0, [_surface size].height-(p.y*2));
      cairo_set_matrix(_ct, &local_matrix);

      cairo_move_to(_ct, p.x, p.y);
      cairo_show_text(_ct, s);

      cairo_set_matrix(_ct, &saved_matrix);
    }
}

- (void) GSSetFont: (GSFontInfo *)fontref
{
  cairo_matrix_t font_matrix;
  const CGFloat *matrix; 

  [super GSSetFont: fontref];

  if (_ct)
    {
      matrix = [font matrix];
      cairo_set_font_face(_ct, [((CairoFontInfo *)font)->_faceInfo fontFace]);
      cairo_matrix_init(&font_matrix, matrix[0], matrix[1], matrix[2],
			matrix[3], matrix[4], matrix[5]);
      cairo_set_font_matrix(_ct, &font_matrix);
    }
}

- (void) GSSetFontSize: (float)size
{
  if (_ct)
    {
      size = floatFromUserSpace(ctm, size);
      cairo_set_font_size(_ct, size);
    }
}

- (void) GSShowText: (const char *)string : (size_t)length
{
  if (_ct)
    {
      GS_BEGINITEMBUF(chars, length + 1, char);
      device_color_t c;

      c = strokeColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);

      [self _setPoint];
      memcpy(chars, string, length);
      chars[length] = 0;
      cairo_show_text(_ct, chars);
      GS_ENDITEMBUF();
    }
}

- (void) GSShowGlyphs: (const NSGlyph *)glyphs : (size_t)length
{
  if (_ct)
    {
      cairo_matrix_t local_matrix;
      NSAffineTransformStruct	matrix = [ctm transformStruct];
      device_color_t c;

      c = strokeColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);

      [self _setPoint];
      // FIXME: Hack to get font in rotated view working
      cairo_save(_ct);
      cairo_matrix_init(&local_matrix, matrix.m11, matrix.m12, matrix.m21,
                        matrix.m22, 0, 0);
      cairo_transform(_ct, &local_matrix);
      // Undo the 
      cairo_matrix_init_scale(&local_matrix, 1, -1);
      cairo_matrix_translate(&local_matrix, 0,  -[_surface size].height);
      cairo_transform(_ct, &local_matrix);

      [(CairoFontInfo *)font drawGlyphs: glyphs
                        length: length
                        on: _ct];
      cairo_restore(_ct);
    }
}

/*
 * GState operations
 */

- (void) DPSinitgraphics
{
  cairo_status_t status;
  cairo_matrix_t local_matrix;

  [super DPSinitgraphics];

  if (_ct)
    {
      cairo_destroy(_ct);
    }
  if (!_surface)
    {
      return;
    }
  _ct = cairo_create([_surface surface]);
  status = cairo_status(_ct);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Cairo status '%s' in DPSinitgraphics", cairo_status_to_string(status));
      _ct = NULL;
      return;
    }
  
  // cairo draws the other way around.
  // At this point in time viewIsFlipped has not been set, but it is
  // OK to ignore this here, as in that case the matrix will later 
  // get flipped by GUI,
  cairo_matrix_init_scale(&local_matrix, 1, -1);
  cairo_matrix_translate(&local_matrix, 0,  -[_surface size].height);
  cairo_set_matrix(_ct, &local_matrix);

  // Cairo's default line width is 2.0
  cairo_set_line_width(_ct, 1.0);
  cairo_set_operator(_ct, CAIRO_OPERATOR_OVER);
  cairo_new_path(_ct);

  _strokeadjust = 1;
}

- (void) DPScurrentflat: (float *)flatness
{
  if (_ct)
    {
      *flatness = (float)cairo_get_tolerance(_ct) * 2;
    }
}

- (void) DPScurrentlinecap: (int *)linecap
{
  cairo_line_cap_t lc;

  if (_ct)
    {
      lc = cairo_get_line_cap(_ct);
      *linecap = lc;
    }
  /*
     switch (lc)
     {
     case CAIRO_LINE_CAP_BUTT:
     *linecap = 0;
     break;
     case CAIRO_LINE_CAP_ROUND:
     *linecap = 1;
     break;
     case CAIRO_LINE_CAP_SQUARE:
     *linecap = 2;
     break;
     default:
     NSLog(@"ERROR Line cap unknown");
     exit(-1);
     }
   */
}

- (void) DPScurrentlinejoin: (int *)linejoin
{
  cairo_line_join_t lj;

  if (_ct)
    {
      lj = cairo_get_line_join(_ct);
      *linejoin = lj;
    }
  /*
     switch (lj)
     {
     case CAIRO_LINE_JOIN_MITER:
     *linejoin = 0;
     break;
     case CAIRO_LINE_JOIN_ROUND:
     *linejoin = 1;
     break;
     case CAIRO_LINE_JOIN_BEVEL:
     *linejoin = 2;
     break;
     default:
     NSLog(@"ERROR Line join unknown");
     exit(-1);
     }
   */
}

- (void) DPScurrentlinewidth: (float *)width
{
  if (_ct)
    {
      *width = (float)cairo_get_line_width(_ct);
      *width = floatToUserSpace(ctm, *width);
    }
}

- (void) DPScurrentmiterlimit: (float *)limit
{
  if (_ct)
    {
      *limit = (float)cairo_get_miter_limit(_ct);
      *limit = floatToUserSpace(ctm, *limit);
    }
}

- (void) DPScurrentstrokeadjust: (int *)b
{
    // FIXME
}

- (void) DPSsetdash: (const float *)pat : (int)size : (float)foffset
{
  if (_ct)
    {
      GS_BEGINITEMBUF(dpat, size, double);
      double doffset = (double)floatFromUserSpace(ctm, foffset);
      int i;

      i = size;
      while (i)
        {
          i--;
          // FIXME: When using the correct values, some dashes look wrong
          dpat[i] = (double)floatFromUserSpace(ctm, pat[i]) * 1.4;
        }
      cairo_set_dash(_ct, dpat, size, doffset);
      GS_ENDITEMBUF();
    }
}

- (void) DPSsetflat: (float)flatness
{
  [super DPSsetflat: flatness];
  if (_ct)
    {
      // Divide GNUstep flatness by 2 to get Cairo tolerance - this produces
      // results visually similar to OS X.
      cairo_set_tolerance(_ct, flatness / 2);
    }
}

- (void) DPSsetlinecap: (int)linecap
{
  if (_ct)
    {
      cairo_set_line_cap(_ct, (cairo_line_cap_t)linecap);
    }
}

- (void) DPSsetlinejoin: (int)linejoin
{
  if (_ct)
    {
      cairo_set_line_join(_ct, (cairo_line_join_t)linejoin);
    }
}

- (void) DPSsetlinewidth: (float)width
{
  if (_ct)
    {
      cairo_set_line_width(_ct, floatFromUserSpace(ctm, width));
    }
}

- (void) DPSsetmiterlimit: (float)limit
{
  if (_ct)
    {
      cairo_set_miter_limit(_ct, floatFromUserSpace(ctm, limit));
    }
}

- (void) DPSsetstrokeadjust: (int)b
{
  _strokeadjust = b;
}

/*
 * Path operations
 */

- (void) _adjustPath: (float)offs
{
  unsigned            count = [path elementCount];
  NSBezierPathElement type;
  NSPoint             points[3] = {{0.0, 0.0}, {0.0, 0.0}, {0.0, 0.0}};
  NSPoint             last_points[3] = {{0.0, 0.0}, {0.0, 0.0}, {0.0, 0.0}};
  unsigned            i;
  int                 index, last_index;

  for (i = 0; i < count; i++)
    {
      type = [path elementAtIndex:i associatedPoints:points];

      if (type == NSCurveToBezierPathElement) break;

      points[0].x = floorf(points[0].x) + offs;
      points[0].y = floorf(points[0].y) + offs;

      index = i;
      last_index = i - 1;

      if (type == NSClosePathBezierPathElement)
        {
          index = 0;
          [path elementAtIndex:0 associatedPoints:points];
          if (fabs(last_points[0].x - points[0].x) < 1.0)
            {
              last_points[0].x = floorf(last_points[0].x) + offs;
              points[0].x = last_points[0].x;
            }
          else if (fabs(last_points[0].y - points[0].y) < 1.0)
            {
              last_points[0].y = floorf(last_points[0].y) + offs;
              points[0].y = last_points[0].y;
            }
          else
            {
              index = -1;
            }
        }
      else if (fabs(last_points[0].x - points[0].x) < 1.0)
        { // Vertical path
          points[0].x = floorf(points[0].x) + offs;
          points[0].y = floorf(points[0].y);
          if (type == NSLineToBezierPathElement)
            {
              last_points[0].x = points[0].x;
            }
        }
      else if (fabs(last_points[0].y - points[0].y) < 1.0)
        { // Horizontal path
          points[0].x = floorf(points[0].x);
          points[0].y = floorf(points[0].y) + offs;
          if (type == NSLineToBezierPathElement)
            {
              last_points[0].y = points[0].y;
            }
        }

      // Save adjusted values into NSBezierPath
      if (index >= 0)
        [path setAssociatedPoints:points atIndex:index];
      if (last_index >= 0)
        [path setAssociatedPoints:last_points atIndex:last_index];

      last_points[0].x = points[0].x;
      last_points[0].y = points[0].y;
    }
}

- (void) _setPath: (BOOL)fillOrClip
{
  unsigned count = [path elementCount];
  unsigned i;
  SEL elmsel = @selector(elementAtIndex:associatedPoints:);
  IMP elmidx = [path methodForSelector: elmsel];

  if (_strokeadjust)
    {
      float offs;

      if ((remainderf((float)cairo_get_line_width(_ct), 2.0) == 0.0)
          || fillOrClip == YES)
        offs = 0.0;
      else
        offs = 0.5;

      [self _adjustPath:offs];
    }

  // reset current cairo path
  cairo_new_path(_ct);
  for (i = 0; i < count; i++) 
    {
      NSBezierPathElement type;
      NSPoint points[3];

      type = (NSBezierPathElement)(*elmidx)(path, elmsel, i, points);
      switch(type) 
        {
          case NSMoveToBezierPathElement:
            cairo_move_to(_ct, points[0].x, points[0].y);
            break;
          case NSLineToBezierPathElement:
            cairo_line_to(_ct, points[0].x, points[0].y);
            break;
          case NSCurveToBezierPathElement:
            cairo_curve_to(_ct, points[0].x, points[0].y, 
                           points[1].x, points[1].y, 
                           points[2].x, points[2].y);
            break;
          case NSClosePathBezierPathElement:
            cairo_close_path(_ct);
            break;
          default:
            break;
        }
    }
}

- (void) DPSclip
{
  if (_ct)
    {
      [self _setPath:YES];
      cairo_clip(_ct);
     }
}

- (void) DPSeoclip
{
  if (_ct)
    {
      [self _setPath:YES];
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_EVEN_ODD);
      cairo_clip(_ct);
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_WINDING);
    }
}

- (void) DPSeofill
{
  if (_ct)
    {
      device_color_t c;

      if (pattern != nil)
        {
          [self eofillPath: path withPattern: pattern];
          return;
        }

      c = fillColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);
      [self _setPath:YES];
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_EVEN_ODD);
      cairo_fill(_ct);
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_WINDING);
    }
  [self DPSnewpath];
}

- (void) DPSfill
{
  if (_ct)
    {
      device_color_t c;

      if (pattern != nil)
        {
          [self fillPath: path withPattern: pattern];
          return;
        }

      c = fillColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);
      [self _setPath:YES];
      cairo_fill(_ct);
    }
  [self DPSnewpath];
}

- (void) DPSinitclip
{
  if (_ct)
    {
      cairo_reset_clip(_ct);
    }
}

- (void) DPSstroke
{
  if (_ct)
    {
      device_color_t c;

      c = strokeColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);
      [self _setPath:NO];
      cairo_stroke(_ct);
    }
  [self DPSnewpath];
}

- (NSDictionary *) GSReadRect: (NSRect)r
{
  NSMutableDictionary *dict;
  NSSize ssize;
  NSAffineTransform *matrix;
  double x, y;
  int ix, iy;
  cairo_format_t format = CAIRO_FORMAT_ARGB32;
  cairo_surface_t *surface;
  cairo_surface_t *isurface;
  cairo_t *ct;
  cairo_status_t status;
  int size;
  int i;
  NSMutableData *data;
  unsigned char *cdata;

  if (!_ct)
    {
      return nil;
    }

  r = [ctm rectInMatrixSpace: r];
  x = NSWidth(r);
  y = NSHeight(r);
  ix = abs(floor(x));
  iy = abs(floor(y));
  ssize = NSMakeSize(ix, iy);

  dict = [NSMutableDictionary dictionary];
  [dict setObject: [NSValue valueWithSize: ssize] forKey: @"Size"];
  [dict setObject: NSDeviceRGBColorSpace forKey: @"ColorSpace"];
  
  [dict setObject: [NSNumber numberWithUnsignedInt: 8] forKey: @"BitsPerSample"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 32]
	forKey: @"Depth"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 4] 
	forKey: @"SamplesPerPixel"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 1]
	forKey: @"HasAlpha"];

  matrix = [self GSCurrentCTM];
  [matrix translateXBy: -r.origin.x - offset.x 
	  yBy: r.origin.y + NSHeight(r) - offset.y];
  [dict setObject: matrix forKey: @"Matrix"];

  size = ix*iy*4;
  data = [NSMutableData dataWithLength: size];
  if (data == nil)
    return nil;
  cdata = [data mutableBytes];

  surface = cairo_get_target(_ct);
  isurface = cairo_image_surface_create_for_data(cdata, format, ix, iy, 4*ix);
  status = cairo_surface_status(isurface);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Cairo status '%s' in GSReadRect", cairo_status_to_string(status));
      return nil;
    }

  ct = cairo_create(isurface);
  status = cairo_status(ct);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Cairo status '%s' in GSReadRect", cairo_status_to_string(status));
      cairo_surface_destroy(isurface);
      return nil;
    }

  if (_surface != nil)
    {
      ssize = [_surface size];
    }
  else 
    {
      ssize = NSMakeSize(0, 0);
    }
  cairo_set_source_surface(ct, surface, -r.origin.x, 
                           -ssize.height + r.size.height + r.origin.y);
  cairo_rectangle(ct, 0, 0, ix, iy);
  cairo_paint(ct);
  cairo_destroy(ct);
  cairo_surface_destroy(isurface);

  for (i = 0; i < 4 * ix * iy; i += 4)
    {
      unsigned char d = cdata[i];

#if GS_WORDS_BIGENDIAN
      cdata[i] = cdata[i + 1];
      cdata[i + 1] = cdata[i + 2];
      cdata[i + 2] = cdata[i + 3];
      cdata[i + 3] = d;
#else
      cdata[i] = cdata[i + 2];
      //cdata[i + 1] = cdata[i + 1];
      cdata[i + 2] = d;
      //cdata[i + 3] = cdata[i + 3];
#endif 
    }

  [dict setObject: data forKey: @"Data"];

  return dict;
}

static void
_set_op(cairo_t *ct, NSCompositingOperation op)
{
  switch (op)
    {
    case NSCompositeClear:
      cairo_set_operator(ct, CAIRO_OPERATOR_CLEAR);
      break;
    case NSCompositeCopy:
      cairo_set_operator(ct, CAIRO_OPERATOR_SOURCE);
      break;
    case NSCompositeSourceOver:
      cairo_set_operator(ct, CAIRO_OPERATOR_OVER);
      break;
    case NSCompositeSourceIn:
      cairo_set_operator(ct, CAIRO_OPERATOR_IN);
      break;
    case NSCompositeSourceOut:
      cairo_set_operator(ct, CAIRO_OPERATOR_OUT);
      break;
    case NSCompositeSourceAtop:
      cairo_set_operator(ct, CAIRO_OPERATOR_ATOP);
      break;
    case NSCompositeDestinationOver:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_OVER);
      break;
    case NSCompositeDestinationIn:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_IN);
      break;
    case NSCompositeDestinationOut:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_OUT);
      break;
    case NSCompositeDestinationAtop:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_ATOP);
      break;
    case NSCompositeXOR:
      cairo_set_operator(ct, CAIRO_OPERATOR_XOR);
      break;
    case NSCompositePlusDarker:
      // FIXME: There is no match for this operation in cairo!!!
      cairo_set_operator(ct, CAIRO_OPERATOR_SATURATE);
      break;
    case NSCompositeHighlight:
      // MacOSX 10.4 documentation maps this value onto NSCompositeSourceOver
      cairo_set_operator(ct, CAIRO_OPERATOR_OVER);
      break;
    case NSCompositePlusLighter:
      cairo_set_operator(ct, CAIRO_OPERATOR_ADD);
      break;
    default:
      cairo_set_operator(ct, CAIRO_OPERATOR_SOURCE);
    }
}

/* For debugging */
- (void) drawOrientationMarkersIn: (cairo_t *)ct
{
  cairo_rectangle(_ct, 0, 0, 20, 10);
  cairo_set_source_rgba(_ct, 0, 1, 0, 1);
  cairo_fill(_ct);
  cairo_rectangle(_ct, 0, 30, 20, 10);
  cairo_set_source_rgba(_ct, 0, 0, 1, 1);
  cairo_fill(_ct);
}

- (void) DPSimage: (NSAffineTransform *)matrix : (int)pixelsWide
		 : (int)pixelsHigh : (int)bitsPerSample 
		 : (int)samplesPerPixel : (int)bitsPerPixel
		 : (int)bytesPerRow : (BOOL)isPlanar
		 : (BOOL)hasAlpha : (NSString *)colorSpaceName
		 : (const unsigned char *const[5])data
{
  cairo_format_t format;
  NSAffineTransformStruct tstruct;
  cairo_surface_t *surface;
  unsigned char	*tmp = NULL;
  int i = 0;
  int j;
  int index;
  unsigned int pixels = pixelsHigh * pixelsWide;
  unsigned char *rowData;
  cairo_matrix_t local_matrix;
  cairo_status_t status;

  if (!_ct)
    {
      return;
    }

  if (isPlanar || !([colorSpaceName isEqualToString: NSDeviceRGBColorSpace] ||
		    [colorSpaceName isEqualToString: NSCalibratedRGBColorSpace]))
    {
      // FIXME: Need to conmvert to something that is supported
      NSLog(@"Image format not support in cairo backend.\n colour space: %@ planar %d", colorSpaceName, isPlanar);
      return;
    }

  // default is 8 bit grayscale 
  if (!bitsPerSample)
    bitsPerSample = 8;
  if (!samplesPerPixel)
    samplesPerPixel = 1;

  // FIXME - does this work if we are passed a planar image but no hints ?
  if (!bitsPerPixel)
    bitsPerPixel = bitsPerSample * samplesPerPixel;
  if (!bytesPerRow)
    bytesPerRow = (bitsPerPixel * pixelsWide) / 8;

  /* make sure its sane - also handles row padding if hint missing */
  while ((bytesPerRow * 8) < (bitsPerPixel * pixelsWide))
    bytesPerRow++;

  switch (bitsPerPixel)
    {
    case 32:
      tmp = malloc(pixels * 4);
      if (!tmp)
        {
          NSLog(@"Could not allocate drawing space for image");
          return;
        }

      rowData = (unsigned char *)data[0];
      index = 0;

      for (i = 0; i < pixelsHigh; i++)
        {
          unsigned char *d = rowData;

          for (j = 0; j < pixelsWide; j++)
            {
#if GS_WORDS_BIGENDIAN
              tmp[index++] = d[3];
              tmp[index++] = d[0];
              tmp[index++] = d[1];
              tmp[index++] = d[2];
#else
              tmp[index++] = d[2];
              tmp[index++] = d[1];
              tmp[index++] = d[0];
              tmp[index++] = d[3];
#endif 
              d += 4;
            }
          rowData += bytesPerRow;
        }
      format = CAIRO_FORMAT_ARGB32;
      break;
    case 24:
      tmp = malloc(pixels * 4);
      if (!tmp)
        {
          NSLog(@"Could not allocate drawing space for image");
          return;
        }

      rowData = (unsigned char *)data[0];
      index = 0;

      for (i = 0; i < pixelsHigh; i++)
        {
          unsigned char *d = rowData;

          for (j = 0; j < pixelsWide; j++)
            {
#if GS_WORDS_BIGENDIAN
              tmp[index++] = 0;
              tmp[index++] = d[0];
              tmp[index++] = d[1];
              tmp[index++] = d[2];
#else
              tmp[index++] = d[2];
              tmp[index++] = d[1];
              tmp[index++] = d[0];
              tmp[index++] = 0;
#endif
              d += 3;
            }
          rowData += bytesPerRow;
        }
      format = CAIRO_FORMAT_RGB24;
      break;
    default:
      NSLog(@"Image format not support");
      return;
    }

  surface = cairo_image_surface_create_for_data((void*)tmp,
						format,
						pixelsWide,
						pixelsHigh,
						pixelsWide * 4);
  status = cairo_surface_status(surface);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Cairo status '%s' in DPSimage", cairo_status_to_string(status));
      if (tmp)
        {
          free(tmp);
        }

      return;
    }

  cairo_save(_ct);
  cairo_set_operator(_ct, CAIRO_OPERATOR_SOURCE);

  // Set the basic transformation
  tstruct =  [ctm transformStruct];
  cairo_matrix_init(&local_matrix,
		    tstruct.m11, tstruct.m12,
		    tstruct.m21, tstruct.m22, 
		    tstruct.tX, tstruct.tY);
  cairo_transform(_ct, &local_matrix);

  // add the local tranformation
  tstruct = [matrix transformStruct];
  cairo_matrix_init(&local_matrix,
		    tstruct.m11, tstruct.m12,
		    tstruct.m21, tstruct.m22, 
		    tstruct.tX, tstruct.tY);
  cairo_transform(_ct, &local_matrix);

  {
    cairo_pattern_t *cpattern;
    cairo_matrix_t source_matrix;
 
    cpattern = cairo_pattern_create_for_surface(surface);
    cairo_matrix_init_scale(&source_matrix, 1, -1);
    cairo_matrix_translate(&source_matrix, 0, -pixelsHigh);
    cairo_pattern_set_matrix(cpattern, &source_matrix);
    if (cairo_version() >= CAIRO_VERSION_ENCODE(1, 6, 0))
      {
        cairo_pattern_set_extend(cpattern, CAIRO_EXTEND_PAD);
      }
    cairo_set_source(_ct, cpattern);
    cairo_pattern_destroy(cpattern);
    cairo_rectangle(_ct, 0, 0, pixelsWide, pixelsHigh);
  }
 
  cairo_clip(_ct);
  cairo_paint(_ct);
  //[self drawOrientationMarkersIn: _ct];
  cairo_surface_destroy(surface);
  cairo_restore(_ct);

  if (tmp)
    {
      free(tmp);
    }
}

- (void) compositerect: (NSRect)aRect op: (NSCompositingOperation)op
{
  if (_ct)
    {
      NSBezierPath *oldPath = path;
      device_color_t c;

      cairo_save(_ct);
      _set_op(_ct, op);

      c = fillColor;
      gsColorToRGB(&c);
      // The underlying concept does not allow to determine if alpha is set or not.
      cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);
      // This is almost a rectclip::::, but the path stays unchanged.
      path = [NSBezierPath bezierPathWithRect: aRect];
      [path transformUsingAffineTransform: ctm];
      [self _setPath:YES];
      cairo_clip(_ct);
      cairo_paint(_ct);
      cairo_restore(_ct);
      path = oldPath;
    }
}

- (void) compositeGState: (CairoGState *)source 
                fromRect: (NSRect)srcRect 
                 toPoint: (NSPoint)destPoint 
                      op: (NSCompositingOperation)op
                fraction: (float)delta
{
  cairo_surface_t *src;
  NSSize ssize = NSZeroSize;
  BOOL copyOnSelf;
  /* The source rect in the source base coordinate space.
     This rect is the minimum bounding rect of srcRect. */
  NSRect srcRectInBase = NSZeroRect;
  /* The destination point in the target base coordinate space */
  NSPoint destPointInBase = NSZeroPoint;
  /* The origin of srcRectInBase */
  double minx, miny;
  /* The composited content size */
  double width, height;
  /* The adjusted destination point in the target base coordinate space */
  double x, y;
  /* Alternative source rect origin in the source current CTM */
  NSPoint srcRectAltOrigin;
  /* Alternative source rect origin in the source base coordinate space */
  NSPoint srcRectAltOriginInBase;
  /* The source rect origin in the source base coordinate space */
  NSPoint srcRectOriginInBase;
  BOOL originFlippedBetweenBaseAndSource = NO;
  /* The delta between the origins of srcRect and srcRectInBase */
  double dx, dy;
  cairo_pattern_t *cpattern;
  cairo_matrix_t source_matrix;

  if (!_ct || !source->_ct)
    {
      return;
    }

  //NSLog(@"Composite surface %p source size %@ target size %@", self->_surface, NSStringFromSize([self->_surface size]), NSStringFromSize([source->_surface size]));
  src = cairo_get_target(source->_ct);
  copyOnSelf = (src == cairo_get_target(_ct));
  srcRectAltOrigin = NSMakePoint(srcRect.origin.x, srcRect.origin.y + srcRect.size.height);
  srcRectAltOriginInBase =  [source->ctm transformPoint: srcRectAltOrigin];
  srcRectOriginInBase = [source->ctm transformPoint: srcRect.origin];

  cairo_save(_ct);

  /* When the target and source are the same surface, we use the group tricks */
  if (copyOnSelf) cairo_push_group(_ct);

  cairo_new_path(_ct);
  _set_op(_ct, op); 

  //NSLog(@"Point %@", NSStringFromPoint(destPoint));

  /* Scales and/or rotates the local destination point with the current AppKit CTM */
  destPointInBase = [ctm transformPoint: destPoint];
  //NSLog(@"Point in base %@", NSStringFromPoint(destPointInBase));

  /* Scales and/or rotates the source rect and retrieves the minimum bounding
     rectangle that encloses it and makes it our source area */
  [source->ctm boundingRectFor: srcRect result: &srcRectInBase];
  //NSLog(@"Bounding rect %@ from %@", NSStringFromRect(srcRectInBase), NSStringFromRect(srcRect)); 

  /* Find whether the source rect origin in the base is the same than in the 
     source current CTM.
     We need to know the origin in the base to compute how much the source 
     bounding rect origin is shifted relatively to the closest source rect corner.
     We use this delta (dx, dy) to correctly composite from a rotated source. */
  originFlippedBetweenBaseAndSource = 
    ((srcRect.origin.y < srcRectAltOrigin.y && srcRectOriginInBase.y > srcRectAltOriginInBase.y)
    || (srcRect.origin.y > srcRectAltOrigin.y && srcRectOriginInBase.y < srcRectAltOriginInBase.y));
  if (originFlippedBetweenBaseAndSource)
    {
      srcRectOriginInBase = srcRectAltOriginInBase;
    }
  dx = srcRectOriginInBase.x - srcRectInBase.origin.x;
  dy = srcRectOriginInBase.y - srcRectInBase.origin.y;

  //NSLog(@"Point in base adjusted %@", NSStringFromPoint(NSMakePoint(destPointInBase.x - dx, destPointInBase.y - dy)));

  if (source->_surface != nil)
    {
      ssize = [source->_surface size];
    }

  if (cairo_version() >= CAIRO_VERSION_ENCODE(1, 8, 0))
    {      
      // For cairo > 1.8 we seem to need this adjustment
      srcRectInBase.origin.y -= 2 * (source->offset.y - ssize.height);
    }

  x = floorf(destPointInBase.x);
  y = floorf(destPointInBase.y + 0.5);
  minx = NSMinX(srcRectInBase);
  miny = NSMinY(srcRectInBase);
  width = NSWidth(srcRectInBase);
  height = NSHeight(srcRectInBase);

  /* We respect the AppKit CTM effect on the origin 'aPoint' (see 
     -[ctm transformPoint:]), but we ignore the scaling and rotation effect on 
     the composited content and size. Which means we never rotate or scale the 
     content we composite.
     We use a pattern as a trick to simulate a target CTM change, this way we 
     don't touch the source CTM even when both source and target are identical 
     (e.g. scrolling case).
     We must use a pattern matrix that matches the AppKit base CTM set up in 
     -DPSinitgraphics to ensure no transform is applied to the source content, 
     translation adjustements related to destination point and source rect put 
     aside. */
  cpattern = cairo_pattern_create_for_surface(src);
  cairo_matrix_init_scale(&source_matrix, 1, -1);
  //cairo_matrix_translate(&source_matrix, 0,  -[_surface size].height);
  cairo_matrix_translate(&source_matrix, minx - x + dx, miny - y + dy - ssize.height);
  cairo_pattern_set_matrix(cpattern, &source_matrix);
  cairo_set_source(_ct, cpattern);
  cairo_pattern_destroy(cpattern);
  cairo_rectangle(_ct, x, y, width, height);
  cairo_clip(_ct);

  if (delta < 1.0)
    {
      cairo_paint_with_alpha(_ct, delta);
    }
  else
    {
      cairo_paint(_ct);
    }

  if (copyOnSelf)
    {
      cairo_pop_group_to_source(_ct);
      cairo_paint(_ct);
    }

  cairo_restore(_ct);
}

/** Unlike -compositeGState, -drawGSstate fully respects the AppKit CTM but 
doesn't support to use the receiver cairo target as the source. */
- (void) drawGState: (CairoGState *)source 
           fromRect: (NSRect)aRect 
            toPoint: (NSPoint)aPoint 
                 op: (NSCompositingOperation)op
           fraction: (float)delta
{
  NSAffineTransformStruct tstruct =  [ctm transformStruct];
  cairo_surface_t *src = cairo_get_target(source->_ct);
  double width, height;
  double x, y;
  cairo_pattern_t *cpattern;
  cairo_matrix_t local_matrix;
  cairo_matrix_t source_matrix;

  if (!_ct || !source->_ct)
    {
      return;
    }

  cairo_save(_ct);

  cairo_new_path(_ct);
  _set_op(_ct, op);
  
  if (cairo_version() >= CAIRO_VERSION_ENCODE(1, 8, 0))
    {
      NSSize size = [source->_surface size];
      
      // For cairo > 1.8 we seem to need this adjustment
      aRect.origin.y -= 2*(source->offset.y - size.height);
    }

  x = floorf(aPoint.x);
  y = floorf(aPoint.y + 0.5);
  width = NSWidth(aRect);
  height = NSHeight(aRect);

  // NOTE: We don't keep the Cairo matrix in sync with the AppKit matrix (aka 
  // -[NSGraphicsContext GSCurrentCTM])

  /* Prepare a Cairo matrix with the current AppKit CTM */
  cairo_matrix_init(&local_matrix,
		    tstruct.m11, tstruct.m12,
		    tstruct.m21, tstruct.m22, 
		    tstruct.tX, tstruct.tY);
  /* Append the local point transformation */
  cairo_matrix_translate(&local_matrix, x - aRect.origin.x, y - aRect.origin.y);
  /* Concat to the Cairo matrix created in -DPSinitgraphics, which adjusts the 
     mismatch between the Cairo top left vs AppKit bottom left origin. */
  cairo_transform(_ct, &local_matrix);

  //[self drawOrientationMarkersIn: _ct];

  cpattern = cairo_pattern_create_for_surface(src);
  cairo_matrix_init_scale(&source_matrix, 1, -1);
  cairo_matrix_translate(&source_matrix, 0, -[source->_surface size].height);
  cairo_pattern_set_matrix(cpattern, &source_matrix);
  cairo_set_source(_ct, cpattern);
  cairo_pattern_destroy(cpattern);
  cairo_rectangle(_ct, aRect.origin.x, aRect.origin.y, width, height);
  cairo_clip(_ct);

  if (delta < 1.0)
    {
      cairo_paint_with_alpha(_ct, delta);
    }
  else
    {
      cairo_paint(_ct);
    }

  cairo_restore(_ct);
}

@end

@implementation CairoGState (PatternColor)

- (void *) saveClip
{
#if CAIRO_VERSION > CAIRO_VERSION_ENCODE(1, 4, 0)
  cairo_status_t status;
  cairo_rectangle_list_t *clip_rects = cairo_copy_clip_rectangle_list(_ct);

  status = cairo_status(_ct);
  if (status == CAIRO_STATUS_SUCCESS)
    {
      return clip_rects;
    }
#endif

  return NULL;
}

- (void) restoreClip: (void *)savedClip
{
#if CAIRO_VERSION > CAIRO_VERSION_ENCODE(1, 4, 0)
  if (savedClip)
    {
      int i;
      cairo_rectangle_list_t *clip_rects = (cairo_rectangle_list_t *)savedClip;
      
      cairo_reset_clip(_ct);
      if (cairo_version() >= CAIRO_VERSION_ENCODE(1, 6, 0))
        {
          for (i = 0; i < clip_rects->num_rectangles; i++)
            {
              cairo_rectangle_t rect = clip_rects->rectangles[i];
              
              cairo_rectangle(_ct, rect.x, rect.y, 
                              rect.width, rect.height);
              cairo_clip(_ct);
            }
        }
      else
        {
          for (i = 0; i < clip_rects->num_rectangles; i++)
            {
              cairo_rectangle_t rect = clip_rects->rectangles[i];
              NSSize size = [_surface size];
              
              cairo_rectangle(_ct, rect.x, 
                              /* This strange computation is due 
                                 to the device offset missing for 
                                 clip rects in cairo < 1.6.0.  */
                              rect.y + 2*(offset.y - size.height), 
                              rect.width, rect.height);
              cairo_clip(_ct);
            }
        }
      cairo_rectangle_list_destroy(clip_rects);
    }
#endif
}

@end

@implementation CairoGState (NSGradient)

- (void) drawGradient: (NSGradient*)gradient
           fromCenter: (NSPoint)startCenter
               radius: (CGFloat)startRadius
             toCenter: (NSPoint)endCenter 
               radius: (CGFloat)endRadius
              options: (NSUInteger)options
{
  int i;
  int stops = [gradient numberOfColorStops];
  NSPoint startP = [ctm transformPoint: startCenter];
  NSPoint endP = [ctm transformPoint: endCenter];
  cairo_pattern_t *cpattern = cairo_pattern_create_radial(startP.x, startP.y, 
                                                          floatFromUserSpace(ctm, startRadius),
                                                          endP.x, endP.y, 
                                                          floatFromUserSpace(ctm, endRadius));
  for (i = 0; i < stops; i++)
    {
      NSColor *color;
      CGFloat location;
      double red;
      double green;
      double blue;
      double alpha;

      [gradient getColor: &color
                location: &location
                atIndex: i];
      red = [color redComponent];
      green = [color greenComponent];
      blue = [color blueComponent];
      alpha = [color alphaComponent];
      cairo_pattern_add_color_stop_rgba(cpattern, location,
                                        red, green, blue, alpha);
    }
  cairo_save(_ct);
  cairo_set_source(_ct, cpattern);
  cairo_pattern_destroy(cpattern);
  cairo_paint(_ct);
  cairo_restore(_ct);
}

- (void) drawGradient: (NSGradient*)gradient
            fromPoint: (NSPoint)startPoint
              toPoint: (NSPoint)endPoint
              options: (NSUInteger)options
{
  int i;
  int stops = [gradient numberOfColorStops];
  NSPoint startP = [ctm transformPoint: startPoint];
  NSPoint endP = [ctm transformPoint: endPoint];
  cairo_pattern_t *cpattern = cairo_pattern_create_linear(startP.x, startP.y,
                                                          endP.x, endP.y);

  for (i = 0; i < stops; i++)
    {
      NSColor *color;
      CGFloat location;
      double red;
      double green;
      double blue;
      double alpha;

      [gradient getColor: &color
                location: &location
                atIndex: i];
      red = [color redComponent];
      green = [color greenComponent];
      blue = [color blueComponent];
      alpha = [color alphaComponent];
      cairo_pattern_add_color_stop_rgba(cpattern, location,
                                        red, green, blue, alpha);
    }
  cairo_save(_ct);
  cairo_set_source(_ct, cpattern);
  cairo_pattern_destroy(cpattern);
  cairo_paint(_ct);
  cairo_restore(_ct);
}

@end
