/* -*- mode:ObjC -*-
   XGServer - X11 Server Class

   Copyright (C) 1998,2002 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@gnu.org>
   Date: Mar 2002
   
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

#include "config.h"
#include <AppKit/AppKitExceptions.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSView.h>
#include <AppKit/NSWindow.h>
#include <Foundation/NSException.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSConnection.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSData.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSDebug.h>

#ifdef HAVE_WRASTER_H
#include "wraster.h"
#else
#include "x11/wraster.h"
#endif

#include "x11/XGServer.h"
#include "x11/XGInputServer.h"
#ifdef HAVE_GLX
#include "x11/XGOpenGL.h"
#endif 

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

extern int XGErrorHandler(Display *display, XErrorEvent *err);

static NSString *
_parse_display_name(NSString *name, int *dn, int *sn)
{
  int d, s;
  NSString *host;
  NSArray  *a;

  host = @"";
  d = s = 0;
  a = [name componentsSeparatedByString: @":"];
  if (name == nil)
    {
      NSLog(@"X DISPLAY environment variable not set,"
	    @" assuming local X server (DISPLAY=:0.0)");
    }
  else if ([name hasPrefix: @":"] == YES)
    {
      int bnum;
      bnum = sscanf([name cString], ":%d.%d", &d, &s);
      if (bnum == 1)
	s = 0;
      if (bnum < 1)
	d = 0;
    }  
  else if ([a count] != 2)
    {
      NSLog(@"X DISPLAY environment variable has bad format,"
	    @" assuming local X server (DISPLAY=:0.0)");
    }
  else
    {
      int bnum;
      NSString *dnum;
      host = [a objectAtIndex: 0];
      dnum = [a lastObject];
      bnum = sscanf([dnum cString], "%d.%d", &d, &s);
      if (bnum == 1)
	s = 0;
      if (bnum < 1)
	d = 0;
    }
  if (dn)
    *dn = d;
  if (sn)
    *sn = s;
  return host;
}

@interface XGServer (Window)
- (void) _setupRootWindow;
@end

@interface XGServer (Private)
- (void) setupRunLoopInputSourcesForMode: (NSString*)mode; 
@end

@interface XGScreenContext : NSObject
{
  RContext        *rcontext;
  XGDrawMechanism drawMechanism;
}

- initForDisplay: (Display *)dpy screen: (int)screen_number;
- (XGDrawMechanism) drawMechanism;
- (RContext *) context;
@end

@implementation XGScreenContext

- (RContextAttributes *) _getXDefaults
{
  int dummy;
  RContextAttributes *attribs;

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  attribs = (RContextAttributes *)malloc(sizeof(RContextAttributes));

  attribs->flags = 0;
  if ([defaults boolForKey: @"NSDefaultVisual"])
    attribs->flags |= RC_DefaultVisual;
  if ((dummy = [defaults integerForKey: @"NSDefaultVisual"]))
    {
      attribs->flags |= RC_VisualID;
      attribs->visualid = dummy;
    }
  if ((dummy = [defaults integerForKey: @"NSColorsPerChannel"]))
    {
      attribs->flags |= RC_ColorsPerChannel;
      attribs->colors_per_channel = dummy;
    }

  return attribs;
}

- initForDisplay: (Display *)dpy screen: (int)screen_number
{
  RContextAttributes	*attribs;
  XColor		testColor;
  unsigned char		r, g, b;

   /* Get the visual information */
  attribs = NULL;
  //attribs = [self _getXDefaults];
  rcontext = RCreateContext(dpy, screen_number, attribs);

  /*
   * If we have shared memory available, only use it when the XGPS-Shm
   * default is set to YES
   */
  if (rcontext->attribs->use_shared_memory == True
    && [[NSUserDefaults standardUserDefaults] boolForKey: @"XGPS-Shm"] != YES)
    rcontext->attribs->use_shared_memory = False;

  /*
   *	Crude tests to see if we can accelerate creation of pixels from
   *	8-bit red, green and blue color values.
   */
  if (rcontext->depth == 12 || rcontext->depth == 16)
    {
      drawMechanism = XGDM_FAST16;
      r = 8;
      g = 9;
      b = 7;
      testColor.pixel = (((r << 5) + g) << 6) + b;
      XQueryColor(rcontext->dpy, rcontext->cmap, &testColor);
      if (((testColor.red >> 11) != r)
	|| ((testColor.green >> 11) != g)
	|| ((testColor.blue >> 11) != b))
	{
	  NSLog(@"WARNING - XGServer is unable to use the "
	    @"fast algorithm for writing to a 16-bit display on "
	    @"this host - perhaps you'd like to adjust the code "
	    @"to work ... and submit a patch.");
	  drawMechanism = XGDM_PORTABLE;
	}
    }
  else if (rcontext->depth == 15)
    {
      drawMechanism = XGDM_FAST15;
      r = 8;
      g = 9;
      b = 7;
      testColor.pixel = (((r << 5) + g) << 5) + b;
      XQueryColor(rcontext->dpy, rcontext->cmap, &testColor);
      if (((testColor.red >> 11) != r)
	|| ((testColor.green >> 11) != g)
	|| ((testColor.blue >> 11) != b))
	{
	  NSLog(@"WARNING - XGServer is unable to use the "
	    @"fast algorithm for writing to a 15-bit display on "
	    @"this host - perhaps you'd like to adjust the code "
	    @"to work ... and submit a patch.");
	  drawMechanism = XGDM_PORTABLE;
	}
    }
  else if (rcontext->depth == 24 || rcontext->depth == 32)
    {
      drawMechanism = XGDM_FAST32;
      r = 32;
      g = 33;
      b = 31;
      testColor.pixel = (((r << 8) + g) << 8) + b;
      XQueryColor(rcontext->dpy, rcontext->cmap, &testColor);
      if (((testColor.red >> 8) == r)
        && ((testColor.green >> 8) == g)
        && ((testColor.blue >> 8) == b))
	{
	  drawMechanism = XGDM_FAST32;
	}
      else if (((testColor.red >> 8) == b)
	&& ((testColor.green >> 8) == g)
	&& ((testColor.blue >> 8) == r))
	{
	  drawMechanism = XGDM_FAST32_BGR;
	}
      else
	{
	  NSLog(@"WARNING - XGServer is unable to use the "
	    @"fast algorithm for writing to a 32-bit display on "
	    @"this host - perhaps you'd like to adjust the code "
	    @"to work ... and submit a patch.");
	  drawMechanism = XGDM_PORTABLE;
	}
    }
  else
    {
      NSLog(@"WARNING - XGServer is unable to use a "
	@"fast algorithm for writing to the display on "
	@"this host - perhaps you'd like to adjust the code "
	@"to work ... and submit a patch.");
      drawMechanism = XGDM_PORTABLE;
    }
  NSDebugLLog(@"XGTrace", @"Draw mech %d for screen %d", drawMechanism,
	screen_number);
  return self;
}

- (void) dealloc
{
  // FIXME: context.c does not include a clean up function for Rcontext, 
  // so we try do it here.
  if (rcontext)
    {
      XFreeGC(rcontext->dpy, rcontext->copy_gc);
      if (rcontext->drawable)
        {
	  XDestroyWindow(rcontext->dpy, rcontext->drawable);
	}
      if (rcontext->pixels)
        {
	  free(rcontext->pixels);
	}
      if (rcontext->colors)
        {
	  free(rcontext->colors);
	}
      free(rcontext->attribs);
      free(rcontext);
    }
  [super dealloc];
}

- (XGDrawMechanism) drawMechanism
{
  return drawMechanism;
}

- (RContext *) context
{
  return rcontext;
}

@end


/**
   <unit>
   <heading>XGServer</heading>
   </unit>
*/
@implementation XGServer 

/* Initialize AppKit backend */
+ (void)initializeBackend
{
  NSDebugLog(@"Initializing GNUstep x11 backend.\n");
  [GSDisplayServer setDefaultServerClass: [XGServer class]];
}

/**
   Returns a pointer to the current X-Windows display variable for
   the current context.
*/
+ (Display*) currentXDisplay
{
  return [(XGServer*)GSCurrentServer() xDisplay];
}

- _initXContext
{
  int			screen_number, display_number;
  NSString		*display_name, *host;
  XGScreenContext       *screen;

  host = [[NSUserDefaults standardUserDefaults] stringForKey: @"NSHost"];
  display_name = [server_info objectForKey: GSDisplayName];
  if (display_name == nil)
    {
      NSString *dn = [server_info objectForKey: GSDisplayNumber];
      NSString *sn = [server_info objectForKey: GSScreenNumber];
      if (dn || sn)
	{
	  if (dn == NULL)
	    dn = @"0";
	  if (sn == NULL)
	    sn = @"0";
	  if (host == nil)
	    host = @"";
	  display_name = [NSString stringWithFormat: @"%@:%@.%@", host, dn,sn];
	}
    }

  if (display_name == nil)
    {
      if (host == nil)
	{
	  NSString	*d = [[[NSProcessInfo processInfo] environment]
	    objectForKey: @"DISPLAY"];

	  host = _parse_display_name(d, &display_number, &screen_number);
	  if (display_number != 0)
	    {
	      NSLog(@"NOTE: Only one display per host fully supported.");
	    }
	  if ([host isEqual: @""] == NO)
	    {
	      /**
	       * If we are using the DISPLAY environment variable to
	       * determine where to display, set the NSHost default
	       * so that other parts of the system know where we are
	       * displaying.
	       */
	      [[NSUserDefaults standardUserDefaults] registerDefaults:
		  [NSDictionary dictionaryWithObject: host
			                      forKey: @"NSHost"]];
	    }
	}
      else if ([host isEqual: @""] == NO)
	{
	  /**
	   * If the NSHost default told us to display somewhere, we need
	   * to generate a display name for X from the host name and the
	   * default display and screen numbers (zero).
	   */
	  display_name = [NSString stringWithFormat: @"%@:0.0", host];
	}
    }

  if (display_name)
    {
      dpy = XOpenDisplay([display_name cString]);
    }
  else
    { 
      dpy = XOpenDisplay(NULL);
      display_name = [NSString stringWithCString: XDisplayName(NULL)];
    }

  if (dpy == NULL)
    {
      char *dname = XDisplayName([display_name cString]);
      [NSException raise: NSWindowServerCommunicationException
		  format: @"Unable to connect to X Server `%s'", dname];
    }

  /* Parse display information */
  _parse_display_name(display_name, &display_number, &screen_number);
  NSDebugLog(@"Opened display %@, display %d screen %d", 
	     display_name, display_number, screen_number);
  [server_info setObject: display_name forKey: GSDisplayName];
  [server_info setObject: [NSNumber numberWithInt: display_number]
		  forKey: GSDisplayNumber];
  [server_info setObject: [NSNumber numberWithInt: screen_number] 
	          forKey: GSScreenNumber];

  /* Setup screen*/
  if (screenList == NULL)
    screenList = NSCreateMapTable(NSIntMapKeyCallBacks,
                                 NSObjectMapValueCallBacks, 20);

  screen = [[XGScreenContext alloc] initForDisplay: dpy screen: screen_number];
  AUTORELEASE(screen);
  NSMapInsert(screenList, (void *)screen_number, (void *)screen);
  defScreen = screen_number;

  XSetErrorHandler(XGErrorHandler);

  if (GSDebugSet(@"XSynchronize") == YES)
    XSynchronize(dpy, True);

  [self _setupRootWindow];
  inputServer = [[XIMInputServer allocWithZone: [self zone]] 
		  initWithDelegate: nil display: dpy name: @"XIM"];
  return self;
}

/**
   Opens the X display (using a helper method) and sets up basic
   display mechanisms, such as visuals and colormaps.
*/
- (id) initWithAttributes: (NSDictionary *)info
{
  [super initWithAttributes: info];
  [self _initXContext];

  [self setupRunLoopInputSourcesForMode: NSDefaultRunLoopMode]; 
  [self setupRunLoopInputSourcesForMode: NSConnectionReplyMode]; 
  [self setupRunLoopInputSourcesForMode: NSModalPanelRunLoopMode]; 
  [self setupRunLoopInputSourcesForMode: NSEventTrackingRunLoopMode]; 
  return self;
}

/**
   Closes all X resources, the X display and dealloc other ivars.
*/
- (void) dealloc
{
  NSDebugLog(@"Destroying X11 Server");
  DESTROY(inputServer);
  [self _destroyServerWindows];
  NSFreeMapTable(screenList);
  XCloseDisplay(dpy);
  [super dealloc];
}

/**
  Returns a pointer to the X windows display variable
*/
- (Display *) xDisplay
{
  return dpy;
}

- (XGScreenContext *) _screenContextForScreen: (int)screen_number
{
  int count = ScreenCount(dpy);
  XGScreenContext *screen;

  if (screen_number >= count)
    {
      [NSException raise: NSInvalidArgumentException
		   format: @"Request for invalid screen"];
    }

  screen = NSMapGet(screenList, (void *)screen_number);
  if (screen == NULL)
    {
      XGScreenContext *screen;
      screen = [[XGScreenContext alloc] 
		 initForDisplay: dpy screen: screen_number];
      AUTORELEASE(screen);
      NSMapInsert(screenList, (void *)screen_number, (void *)screen);
    }
  return screen;
}

/**
   Returns a pointer to a structure which describes aspects of the
   X windows display 
*/
- (void *) xrContextForScreen: (int)screen_number
{
  return [[self _screenContextForScreen: screen_number] context];
}

/**
   Returns the XGDrawMechanism, which roughly describes the depth of
   the screen and how pixels should be drawn to the screen for maximum
   speed.
*/
- (XGDrawMechanism) drawMechanismForScreen: (int)screen_number
{
 return [[self _screenContextForScreen: screen_number] drawMechanism];
}

/**
   Returns the root window of the display 
*/
- (Window) xDisplayRootWindowForScreen: (int)screen_number;
{
  return RootWindow(dpy, screen_number);
}

/**
   Returns the closest color in the current colormap to the indicated
   X color
*/
- (XColor)xColorFromColor: (XColor)color forScreen: (int)screen_number
{
  Status ret;
  RColor rcolor;
  RContext *context = [self xrContextForScreen: screen_number];
  XAllocColor(dpy, context->cmap, &color);
  rcolor.red   = color.red / 256;
  rcolor.green = color.green / 256;
  rcolor.blue  = color.blue / 256;
  ret = RGetClosestXColor(context, &rcolor, &color);
  if (ret == False)
    NSLog(@"Failed to alloc color (%d,%d,%d)\n",
          (int)rcolor.red, (int)rcolor.green, (int)rcolor.blue);
  return color;
}

/**
   Returns the application root window, which is used for many things
   such as window hints 
*/
- (Window) xAppRootWindow
{
  return generic.appRootWindow;
}


/**
  Wait for all contexts to finish processing. Only used with XDPS graphics.
*/
+ (void) waitAllContexts
{
  if ([[GSCurrentContext() class] 
	respondsToSelector: @selector(waitAllContexts)])
    [[GSCurrentContext() class] waitAllContexts];
}

- (void) beep
{
  XBell(dpy, 50);
}

- glContextClass
{
#ifdef HAVE_GLX
  return [XGGLContext class];
#else
  return nil;
#endif
}

- glPixelFormatClass
{
#ifdef HAVE_GLX
  return [XGGLPixelFormat class];
#else
  return nil;
#endif
}


@end

@implementation XGServer (InputMethod)
- (NSString *) inputMethodStyle
{
  return inputServer ? [(XIMInputServer *)inputServer inputMethodStyle] : nil;
}

- (NSString *) fontSize: (int *)size
{
  return inputServer ? [(XIMInputServer *)inputServer fontSize: size] : nil;
}

- (BOOL) clientWindowRect: (NSRect *)rect
{
  return inputServer
    ? [(XIMInputServer *)inputServer clientWindowRect: rect] : NO;
}

- (BOOL) statusArea: (NSRect *)rect
{
  return inputServer ? [(XIMInputServer *)inputServer statusArea: rect] : NO;
}

- (BOOL) preeditArea: (NSRect *)rect
{
  return inputServer ? [(XIMInputServer *)inputServer preeditArea: rect] : NO;
}

- (BOOL) preeditSpot: (NSPoint *)p
{
  return inputServer ? [(XIMInputServer *)inputServer preeditSpot: p] : NO;
}

- (BOOL) setStatusArea: (NSRect *)rect
{
  return inputServer
    ? [(XIMInputServer *)inputServer setStatusArea: rect] : NO;
}

- (BOOL) setPreeditArea: (NSRect *)rect
{
  return inputServer
    ? [(XIMInputServer *)inputServer setPreeditArea: rect] : NO;
}

- (BOOL) setPreeditSpot: (NSPoint *)p
{
  return inputServer
    ? [(XIMInputServer *)inputServer setPreeditSpot: p] : NO;
}

@end // XGServer (InputMethod)


//==== Additional code for NSTextView =========================================
//
//  WARNING  This section is not genuine part of the XGServer implementation.
//  -------
//
//  The methods implemented in this section override some of the internal
//  methods defined in NSTextView so that the class can support input methods
//  (XIM) in cooperation with XGServer.
//
//  Note that the orverriding is done by defining the methods in a category,
//  the name of which is not explicitly mentioned in NSTextView.h; the
//  category is called 'InputMethod'.
//

#include <AppKit/NSClipView.h>
#include <AppKit/NSTextView.h>

@implementation NSTextView (InputMethod)

- (void) _updateInputMethodState
{
  NSRect    frame;
  int	    font_size;
  NSRect    status_area;
  NSRect    preedit_area;
  id	    displayServer = (XGServer *)GSCurrentServer();

  if (![displayServer respondsToSelector: @selector(inputMethodStyle)])
    return;

  if (![displayServer fontSize: &font_size])
    return;

  if ([[self superview] isKindOfClass: [NSClipView class]])
    frame = [[self superview] frame];
  else
    frame = [self frame];

  status_area.size.width  = 2 * font_size;
  status_area.size.height = font_size + 2;
  status_area.origin.x    = 0;
  status_area.origin.y    = frame.size.height - status_area.size.height;

  if ([[displayServer inputMethodStyle] isEqual: @"OverTheSpot"])
    {
      preedit_area.origin.x    = 0;
      preedit_area.origin.y    = 0;
      preedit_area.size.width  = frame.size.width;
      preedit_area.size.height = status_area.size.height;

      [displayServer setStatusArea: &status_area];
      [displayServer setPreeditArea: &preedit_area];
    }
  else if ([[displayServer inputMethodStyle] isEqual: @"OffTheSpot"])
    {
      preedit_area.origin.x    = status_area.size.width + 2;
      preedit_area.origin.y    = status_area.origin.y;
      preedit_area.size.width  = frame.origin.x + frame.size.width
	- preedit_area.origin.x;
      preedit_area.size.height = status_area.size.height;

      [displayServer setStatusArea: &status_area];
      [displayServer setPreeditArea: &preedit_area];
    }
  else
    {
      // Do nothing for the RootWindow style.
    }
}

- (void) _updateInputMethodWithInsertionPoint: (NSPoint)insertionPoint
{
  id displayServer = (XGServer *)GSCurrentServer();

  if (![displayServer respondsToSelector: @selector(inputMethodStyle)])
    return;

  if ([[displayServer inputMethodStyle] isEqual: @"OverTheSpot"])
    {
      id	view;
      NSRect	frame;
      NSPoint	p;
      NSRect	client_win_rect;
      NSPoint	screenXY_of_frame;
      double	x_offset;
      double	y_offset;
      int	font_size;
      NSRect	doc_rect;
      NSRect	doc_visible_rect;
      BOOL	cond;
      float	x = insertionPoint.x;
      float	y = insertionPoint.y;

      [displayServer clientWindowRect: &client_win_rect];
      [displayServer fontSize: &font_size];

      cond = [[self superview] isKindOfClass: [NSClipView class]];
      if (cond)
	view = [self superview];
      else
	view = self;

      frame = [view frame];
      screenXY_of_frame = [[view window] convertBaseToScreen: frame.origin];

      // N.B. The window of NSTextView isn't necessarily the same as the input
      // method's client window.
      x_offset = screenXY_of_frame.x - client_win_rect.origin.x; 
      y_offset = (client_win_rect.origin.y + client_win_rect.size.height)
	- (screenXY_of_frame.y + frame.size.height) + font_size;

      x += x_offset;
      y += y_offset;
      if (cond) // If 'view' is of NSClipView, then
	{
	  // N.B. Remember, (x, y) are the values with respect to NSTextView.
	  // We need to know the corresponding insertion position with respect
	  // to NSClipView.
	  doc_rect = [(NSClipView *)view documentRect];
	  doc_visible_rect = [view documentVisibleRect];
	  y -= doc_visible_rect.origin.y - doc_rect.origin.y;
	}

      p = NSMakePoint(x, y);
      [displayServer setPreeditSpot: &p];
    }
}

@end // NSTextView
//==== End: Additional Code for NSTextView ====================================
