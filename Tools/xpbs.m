/*
   xpbs.m

   GNUstep pasteboard server - X extension

   Copyright (C) 1999 Free Software Foundation, Inc.

   Author:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: April 1999

   This file is part of the GNUstep Project

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   You should have received a copy of the GNU General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

*/

#include <Foundation/Foundation.h>
#include <AppKit/NSPasteboard.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <x11/xdnd.h>

#ifndef X_HAVE_UTF8_STRING
#warning "XFRee86 UTF8 extension not used: gpbs supports ISO Latin 1 characters only"
#endif

static Atom	osTypeToX(NSString *t);
static NSString	*xTypeToOs(Atom t);

/*
 *	Non-predefined atoms that are used in the X selection mechanism
 */
static char* atom_names[] = {
  "CHARACTER_POSITION",
  "CLIENT_WINDOW",
  "HOST_NAME",
  "HOSTNAME",
  "LENGTH",
  "LIST_LENGTH",
  "NAME",
  "OWNER_OS",
  "SPAN",
  "TARGETS",
  "TIMESTAMP",
  "USER",
  "TEXT",
  "NULL",
  "FILE_NAME",
#ifdef X_HAVE_UTF8_STRING
  "UTF8_STRING"
#endif
};
static Atom atoms[sizeof(atom_names)/sizeof(char*)];


/*
 * Macros to access elements in atom_names array.
 */
#define XG_CHAR_POSITION        atoms[0]
#define XG_CLIENT_WINDOW        atoms[1]
#define XG_HOST_NAME            atoms[2]
#define XG_HOSTNAME             atoms[3]
#define XG_LENGTH               atoms[4]
#define XG_LIST_LENGTH          atoms[5]
#define XG_NAME                 atoms[6]
#define XG_OWNER_OS             atoms[7]
#define XG_SPAN                 atoms[8]
#define XG_TARGETS              atoms[9]
#define XG_TIMESTAMP            atoms[10]
#define XG_USER                 atoms[11]
#define XG_TEXT                 atoms[12]
#define XG_NULL                 atoms[13]
#define XG_FILE_NAME		atoms[14]
#ifdef X_HAVE_UTF8_STRING
#define XG_UTF8_STRING		atoms[15]
#endif



static Atom
osTypeToX(NSString *t)
{
  if ([t isEqualToString: NSStringPboardType] == YES)
#ifdef X_HAVE_UTF8_STRING
    return XG_UTF8_STRING;
#else
    return XA_STRING;
#endif
  else if ([t isEqualToString: NSColorPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSFileContentsPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSFilenamesPboardType] == YES)
    return XG_FILE_NAME;
  else if ([t isEqualToString: NSFontPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSRulerPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSPostScriptPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSTabularTextPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSRTFPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSRTFDPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSTIFFPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSDataLinkPboardType] == YES)
    return XG_NULL;
  else if ([t isEqualToString: NSGeneralPboardType] == YES)
    return XG_NULL;
  else
    return XG_NULL;
}

static NSString*
xTypeToOs(Atom t)
{
#ifdef X_HAVE_UTF8_STRING
  if (t == XG_UTF8_STRING)
#else
  if (t == XA_STRING)
#endif
    return NSStringPboardType;
  else if (t == XG_TEXT)
    return NSStringPboardType;
  else if (t == XG_FILE_NAME)
    return NSFilenamesPboardType;
  else
    return nil;
}



static Bool xAppendProperty(Display* display,
	      Window window,
	      Atom property,
	      Atom target,
	      int format,
	      unsigned char* data,
	      int number_items)
{
// Ensure that the error handler is set up.
//   xSetErrorHandler();

// Any routine that appends properties can generate a BadAlloc error.
//    xResetErrorFlag();

  if (number_items > 0)
    {
      XChangeProperty(display,
	window,
	property,
	target,
	format,
	PropModeAppend,
	data,
	number_items);

      XSync(display, False);

// Check if our write to a property generated an X error.
//        if (xError())
//            return False;
    }

  return True;
}

@interface	XPbOwner : NSObject
{
  NSPasteboard	*_pb;
  NSData	*_obj;
  NSString	*_name;
  Atom		_xPb;
  Time		_waitingForSelection;
  Time		_timeOfLastAppend;
  BOOL		_ownedByOpenStep;
}

+ (XPbOwner*) ownerByXPb: (Atom)p;
+ (XPbOwner*) ownerByOsPb: (NSString*)p;
+ (void) receivedEvent: (void*)data
                  type: (RunLoopEventType)type
                 extra: (void*)extra
               forMode: (NSString*)mode;
+ (NSDate*) timedOutEvent: (void*)data
                     type: (RunLoopEventType)type
                  forMode: (NSString*)mode;
+ (void) xPropertyNotify: (XPropertyEvent*)xEvent;
+ (void) xSelectionClear: (XSelectionClearEvent*)xEvent;
+ (void) xSelectionNotify: (XSelectionEvent*)xEvent;
+ (void) xSelectionRequest: (XSelectionRequestEvent*)xEvent;

- (NSData*) data;
- (id) initWithXPb: (Atom)x osPb: (NSPasteboard*)o;
- (BOOL) ownedByOpenStep;
- (NSPasteboard*) osPb;
- (void) pasteboardChangedOwner: (NSPasteboard*)sender;
- (void) pasteboard: (NSPasteboard*)pb provideDataForType: (NSString*)type;
- (void) setData: (NSData*)obj;
- (void) setOwnedByOpenStep: (BOOL)flag;
- (void) setTimeOfLastAppend: (Time)when;
- (void) setWaitingForSelection: (Time)when;
- (Time) timeOfLastAppend;
- (Time) waitingForSelection;
- (Atom) xPb;
- (void) xSelectionClear;
- (void) xSelectionNotify: (XSelectionEvent*)xEvent;
- (void) xSelectionRequest: (XSelectionRequestEvent*)xEvent;
- (BOOL) xProvideSelection: (XSelectionRequestEvent*)xEvent;
- (Time) xTimeByAppending;
- (BOOL) xSendData: (unsigned char*) data format: (int) format 
	     items: (int) numItems type: (Atom) xType
		to: (Window) window property: (Atom) property;
@end



// Special subclass for the drag pasteboard
@interface	XDragPbOwner : XPbOwner
{
}
@end



/*
 *	The display we are using - everything refers to it.
 */
static Display		*xDisplay;
static Window		xRootWin;
static Window		xAppWin;
static NSMapTable	*ownByX;
static NSMapTable	*ownByO;
static NSString		*xWaitMode = @"XPasteboardWaitMode";

@implementation	XPbOwner

+ (void) initialize
{
  if (self == [XPbOwner class])
    {
      XPbOwner		*o;
      NSPasteboard	*p;
      Atom XA_CLIPBOARD;

      ownByO = NSCreateMapTable(NSObjectMapKeyCallBacks,
                      NSNonOwnedPointerMapValueCallBacks, 0);
      ownByX = NSCreateMapTable(NSIntMapKeyCallBacks,
                      NSNonOwnedPointerMapValueCallBacks, 0);

      xDisplay = XOpenDisplay(NULL);
      if (xDisplay == 0)
	{
	  NSLog(@"Unable to open X display - no X interoperation available");
	}
      else
	{
	  NSRunLoop	*l = [NSRunLoop currentRunLoop];
	  int		desc;

	  /*
	   * Set up atoms for use in X selection mechanism.
	   */
	  XInternAtoms(xDisplay, atom_names, sizeof(atom_names)/sizeof(char*),
	    False, atoms);

	  xRootWin = RootWindow(xDisplay, DefaultScreen(xDisplay));
	  xAppWin = XCreateSimpleWindow(xDisplay, xRootWin,
                                        0, 0, 100, 100, 1, 1, 0L);
	  /*
	   * Add the X descriptor to the run loop so we get callbacks when
	   * X events arrive.
	   */
	  desc = XConnectionNumber(xDisplay);

          [l addEvent: (void*)(gsaddr)desc
                 type: ET_RDESC
              watcher: (id<RunLoopEvents>)self
              forMode: NSDefaultRunLoopMode];

          [l addEvent: (void*)(gsaddr)desc
                 type: ET_RDESC
              watcher: (id<RunLoopEvents>)self
              forMode: NSConnectionReplyMode];

          [l addEvent: (void*)(gsaddr)desc
                 type: ET_RDESC
              watcher: (id<RunLoopEvents>)self
              forMode: xWaitMode];

	  XSelectInput(xDisplay, xAppWin, PropertyChangeMask);

	  XFlush(xDisplay);
	}

      /*
       * According to the new open desktop specification these
       * two pasteboards should be switched around. That is,
       * general should be XA_CLIPBOARD and selection 
       * XA_PRIMARY. The problem is that most X programs still
       * use the old way. So we do the same for now.
       */
      /* 
       * For the general pasteboard we establish an initial owner that is the
       * X selection system.  In this way, any X window selection already
       * active will be available to the GNUstep system.
       * This object is not released!
       */
      p = [NSPasteboard generalPasteboard];
      o = [[XPbOwner alloc] initWithXPb: XA_PRIMARY osPb: p];
      [o xSelectionClear];

      /* 
       * For the selection pasteboard we establish an initial owner that is the
       * X selection system.  In this way, any X window selection already
       * active will be available to the GNUstep system.
       * This object is not released!
       */
      XA_CLIPBOARD = XInternAtom(xDisplay, "CLIPBOARD", False);
      p = [NSPasteboard pasteboardWithName: @"Selection"];
      o = [[XPbOwner alloc] initWithXPb: XA_CLIPBOARD osPb: p];
      [o xSelectionClear];
      
      // Call this to get the class initialisation
      [XDragPbOwner class];
    }
}

+ (XPbOwner*) ownerByOsPb: (NSString*)p
{
  return (XPbOwner*)NSMapGet(ownByO, (void*)(gsaddr)p);
}

+ (XPbOwner*) ownerByXPb: (Atom)x
{
  return (XPbOwner*)NSMapGet(ownByX, (void*)(gsaddr)x);
}


/*
 *	This is the event handler called by the runloop when the X descriptor
 *	has data available to read.
 */
+ (void) receivedEvent: (void*)data
                  type: (RunLoopEventType)type
                 extra: (void*)extra
               forMode: (NSString*)mode
{
  int		count;

  NSAssert(type == ET_RDESC, NSInternalInconsistencyException);

  while ((count = XPending(xDisplay)) > 0)
    {
      while (count-- > 0)
	{
	  XEvent	xEvent;

	  XNextEvent(xDisplay, &xEvent);

	  switch (xEvent.type)
	    {
	      case PropertyNotify:
		[self xPropertyNotify: (XPropertyEvent*)&xEvent];
		NSDebugLLog(@"Pbs", @"PropertyNotify.");
		break;

	      case SelectionNotify:
		[self xSelectionNotify: (XSelectionEvent*)&xEvent];
		NSDebugLLog(@"Pbs", @"SelectionNotify.");
		break;

	      case SelectionClear:
		[self xSelectionClear: (XSelectionClearEvent*)&xEvent];
		NSDebugLLog(@"Pbs", @"SelectionClear.");
		break;

	      case SelectionRequest:
		[self xSelectionRequest: (XSelectionRequestEvent*)&xEvent];
		NSDebugLLog(@"Pbs", @"SelectionRequest.");
		break;

	      default:
		NSDebugLLog(@"Pbs", @"Unexpected X event.");
		break;
	    }
	}
    }
}

/*
 *	This handler called if an operation times out - never happens 'cos we
 *	don't supply any timeouts - included for protocol conformance.
 */
+ (NSDate*) timedOutEvent: (void*)data
                     type: (RunLoopEventType)type
                  forMode: (NSString*)mode
{
  return nil;
}

#define FULL_LENGTH 8192L	/* Amount to read */

+ (void) xSelectionClear: (XSelectionClearEvent*)xEvent
{
  XPbOwner	*o;

  o = [self ownerByXPb: xEvent->selection];
  if (o == nil)
    {
      NSDebugLLog(@"Pbs", @"Selection clear for unknown selection - '%s'.",
	XGetAtomName(xDisplay, xEvent->selection));
      return;
    }

  if (xEvent->window != (Window)xAppWin)
    {
      NSDebugLLog(@"Pbs", @"Selection clear for wrong (not our) window.");
      return;
    }

  [o xSelectionClear];
}

+ (void) xPropertyNotify: (XPropertyEvent*)xEvent
{
  XPbOwner	*o;

  o = [self ownerByXPb: xEvent->atom];
  if (o == nil)
    {
      NSDebugLLog(@"Pbs", @"Property notify for unknown property - '%s'.",
	XGetAtomName(xDisplay, xEvent->atom));
      return;
    }

  if (xEvent->window != (Window)xAppWin)
    {
      NSDebugLLog(@"Pbs", @"Property notify for wrong (not our) window.");
      return;
    }

  if (xEvent->time != 0)
    {
      [o setTimeOfLastAppend: xEvent->time];
    }
}

+ (void) xSelectionNotify: (XSelectionEvent*)xEvent
{
  XPbOwner	*o;

  o = [self ownerByXPb: xEvent->selection];
  if (o == nil)
    {
      NSDebugLLog(@"Pbs", @"Selection notify for unknown selection - '%s'.",
	XGetAtomName(xDisplay, xEvent->selection));
      return;
    }

  if (xEvent->requestor != (Window)xAppWin)
    {
      NSDebugLLog(@"Pbs", @"Selection notify for wrong (not our) window.");
      return;
    }

  if (xEvent->property == (Atom)None)
    {
      NSLog(@"Owning program failed to convert data.");
      return;
    }
  else
    {
      NSDebugLLog(@"Pbs", @"Selection (%s) notify - '%s'.",
	XGetAtomName(xDisplay, xEvent->selection),
	XGetAtomName(xDisplay, xEvent->property));
    }

  [o xSelectionNotify: xEvent];
}

+ (void) xSelectionRequest: (XSelectionRequestEvent*)xEvent
{
  XPbOwner		*o;

  o = [self ownerByXPb: xEvent->selection];
  if (o == nil)
    {
      NSDebugLLog(@"Pbs", @"Selection request for unknown selection - '%s'.",
	XGetAtomName(xDisplay, xEvent->selection));
      return;
    }

  if (xEvent->requestor == (Window)xAppWin)
    {
      NSDebugLLog(@"Pbs", @"Selection request for wrong (our) window.");
      return;
    }

  if (xEvent->property == None)
    {
      NSDebugLLog(@"Pbs", @"Selection request without reply property set.");
      return;
    }

  [o xSelectionRequest: xEvent];
}

- (NSData*) data
{
  return _obj;
}

- (void) dealloc
{
  RELEASE(_pb);
  RELEASE(_obj);
  /*
   * Remove self from map of X pasteboard owners.
   */
  NSMapRemove(ownByX, (void*)(gsaddr)_xPb);
  NSMapRemove(ownByO, (void*)(gsaddr)_name);
  [super dealloc];
}

- (id) initWithXPb: (Atom)x osPb: (NSPasteboard*)o
{
  _pb = RETAIN(o);
  _name = [_pb name];
  _xPb = x;
  /*
   * Add self to map of all X pasteboard owners.
   */
  NSMapInsert(ownByX, (void*)(gsaddr)_xPb, (void*)(gsaddr)self);
  NSMapInsert(ownByO, (void*)(gsaddr)_name, (void*)(gsaddr)self);
  return self;
}

- (NSPasteboard*) osPb
{
  return _pb;
}

- (BOOL) ownedByOpenStep
{
  return _ownedByOpenStep;
}

- (void) pasteboardChangedOwner: (NSPasteboard*)sender
{
  Window	w;
  /*
   *	If this gets called, a GNUstep object has grabbed the pasteboard
   *	or has changed the types of data available from the pasteboard
   *	so we must tell the X server that we have the current selection.
   *	To conform to ICCCM we need to specify an up-to-date timestamp.
   */
  XSetSelectionOwner(xDisplay, _xPb, xAppWin, [self xTimeByAppending]);
  w = XGetSelectionOwner(xDisplay, _xPb);
  if (w != xAppWin)
    {
      NSLog(@"Failed to set X selection owner to the pasteboard server.");
    }
  [self setOwnedByOpenStep: YES];
}

- (void) pasteboard: (NSPasteboard*)pb provideDataForType: (NSString*)type
{
  [self setData: nil];

  /*
   *	If this gets called, a GNUstep object wants the pasteboard contents
   *	and a plain old X application is providing them, so we must grab
   *	the info.
   */
  if ([type isEqual: NSStringPboardType])
    {
      Time	whenRequested;

      /*
       * Do a nul append to a property to get a timestamp, if it returns the
       * 'CurrentTime' constant then we haven't been able to get one.
       */
      whenRequested = [self xTimeByAppending];
      if (whenRequested != CurrentTime)
	{
	  NSDate	*limit;

	  /*
	   * Ok - we got a timestamp, so we can ask the selection system for
	   * the pasteboard data that was/is valid for theat time.
	   * Ask the X system to provide the pasteboard data in the
	   * appropriate property of our application root window.
	   */
#ifdef X_HAVE_UTF8_STRING
	  XConvertSelection(xDisplay, [self xPb], XG_UTF8_STRING,
	    [self xPb], xAppWin, whenRequested);
#else // X_HAVE_UTF8_STRING not defined
	  XConvertSelection(xDisplay, [self xPb], XA_STRING,
	    [self xPb], xAppWin, whenRequested);
#endif // X_HAVE_UTF8_STRING not defined
	  XFlush(xDisplay);

	  /*
	   * Run an event loop to read X events until we have aquired the
	   * pasteboard data we need.
	   */
	  limit = [NSDate dateWithTimeIntervalSinceNow: 20.0];
	  [self setWaitingForSelection: whenRequested];
	  while ([self waitingForSelection] == whenRequested)
	    {
	      [[NSRunLoop currentRunLoop] runMode: xWaitMode
				       beforeDate: limit];
	      if ([limit timeIntervalSinceNow] <= 0.0)
		break;	/* Timeout */
	    }
	  if ([self waitingForSelection] != 0)
	    {
	      [self setWaitingForSelection: 0];
	      NSLog(@"Timed out waiting for X selection");
	    }
	}
    }
  else
    {
      NSLog(@"Request for non-string info from X pasteboard");
    }
  [pb setData: [self data] forType: type];
}

- (void) setData: (NSData*)obj
{
  ASSIGN(_obj, obj);
}

- (void) setOwnedByOpenStep: (BOOL)f
{
  _ownedByOpenStep = f;
}

- (void) setTimeOfLastAppend: (Time)when
{
  _timeOfLastAppend = when;
}

- (void) setWaitingForSelection: (Time)when
{
  _waitingForSelection = when;
}

- (Time) timeOfLastAppend
{
  return _timeOfLastAppend;
}

- (Time) waitingForSelection
{
  return _waitingForSelection;
}

- (Atom) xPb
{
  return _xPb;
}

static BOOL appendFailure;
static int
xErrorHandler(Display *d, XErrorEvent *e)
{
  appendFailure = YES;
  return 0;
}

- (void) xSelectionClear
{
  NSArray	*types;

  /*
   * Really we should check to see what types of data the selection owner is
   * making available, and declare them all - but as a temporary HACK we just
   * declare string data.
   */
  types = [NSArray arrayWithObject: NSStringPboardType];
  [_pb declareTypes: types owner: self];
  [self setOwnedByOpenStep: NO];
}

- (void) xSelectionNotify: (XSelectionEvent*)xEvent
{
  int		status;
  unsigned char	*data;
  Atom		actual_target;
#ifdef X_HAVE_UTF8_STRING
  Atom		new_target = XG_UTF8_STRING;
#else // X_HAVE_UTF8_STRING not defined
  Atom		new_target = XA_STRING;
#endif // X_HAVE_UTF8_STRING
  int		actual_format;
  unsigned long	bytes_remaining;
  unsigned long	number_items;

  if ([self waitingForSelection] > xEvent->time)
    {
      NSLog(@"Unexpected selection notify - time %u.", xEvent->time);
      return;
    }
  [self setWaitingForSelection: 0];

  /*
   * Read data from property identified in SelectionNotify event.
   */
  status = XGetWindowProperty(xDisplay,
				xEvent->requestor,
				xEvent->property,
				0L,                             // offset
				FULL_LENGTH,
				True,               // Delete prop when read.
				new_target,
				&actual_target,
				&actual_format,
				&number_items,
				&bytes_remaining,
				&data);

  if ((status == Success) && (number_items > 0))
    {
// Convert data to text string.
// string = PropertyToString(xDisplay,new_target,number_items,(char*)data);

#ifdef X_HAVE_UTF8_STRING
      if (actual_target == XG_UTF8_STRING)
	{
	  NSData	*d;
	  NSString	*s;

	  d = [[NSData alloc] initWithBytes: (void *)data
	                             length: number_items];
	  s = [[NSString alloc] initWithData: d
	                            encoding: NSUTF8StringEncoding];
	  RELEASE(d);
	  d = [NSSerializer serializePropertyList: s];
	  RELEASE(s);
	  [self setData: d];
	}
#else // X_HAVE_UTF8_STRING not defined
      if (new_target == XA_STRING)
	{
	  NSData	*d;
	  NSString	*s;

	  d = [[NSData alloc] initWithBytes: (void*)data 
			      length: number_items];
	  s = [[NSString alloc] initWithData: d
				encoding: NSISOLatin1StringEncoding];
	  RELEASE(d);
	  d = [NSSerializer serializePropertyList: s];
	  RELEASE(s);
	  [self setData: d];
	}
#endif // X_HAVE_UTF8_STRING not defined
      else
	{
	  NSLog(@"Unsupported data type from X selection.");
	}

      if (data)
	XFree(data);
    }
}

- (void) xSelectionRequest: (XSelectionRequestEvent*)xEvent
{
  XSelectionEvent	notify_event;
  BOOL			status;

  status = [self xProvideSelection: xEvent];

  /*
   * Set up the selection notify information from the event information
   * so we comply with the ICCCM.
   */
  notify_event.display    = xEvent->display;
  notify_event.type       = SelectionNotify;
  notify_event.requestor  = xEvent->requestor;
  notify_event.selection  = xEvent->selection;
  notify_event.target     = xEvent->target;
  notify_event.time       = xEvent->time;
  notify_event.property   = xEvent->property;

  /*
   * If for any reason we cannot provide the data to the requestor, we must
   * send a selection notify with a property of 'None' so that the requestor
   * knows the request failed.
   */
  if (status == NO)
    notify_event.property = None;

  XSendEvent(xEvent->display, xEvent->requestor, False, 0L,
    (XEvent*)&notify_event);
}

- (BOOL) xProvideSelection: (XSelectionRequestEvent*)xEvent
{
  NSArray	*types = [_pb types];
  unsigned	numOsTypes = [types count];
  NSString	*osType = nil;
  Atom		xType = XG_NULL;
  unsigned char	*data = 0;
  int		format = 0;
  int		numItems = 0;
  unsigned	i;

  if (xEvent->target == XG_TARGETS)
    {
      unsigned	numTypes = 0;
      Atom	xTypes[numOsTypes];

      /*
       * The requestor wants a list of the types we can supply it with.
       */
      for (i = 0; i < numOsTypes; i++)
	{
	  NSString	*type = [types objectAtIndex: i];
	  Atom		t;

	  t = osTypeToX(type);
	  if (t != XG_NULL)
	    {
	      unsigned	j;

	      for (j = 0; j < numTypes; j++)
		{
		  if (xTypes[j] == t)
		    break;
		}
	      if (j == numTypes)
		{
		  xTypes[numTypes++] = t;
		}
	    }
	}
      if (numTypes > 0)
	{
	  /*
	   * We can supply one or more types of data to the requestor so
	   * we will give it a list of the types supported.
	   */
	  xType = XA_ATOM;
	  data = malloc(numTypes*sizeof(Atom));
	  memcpy(data, xTypes, numTypes*sizeof(Atom));
	  numItems = numTypes;
	  format = 32;
	}
      else
	{
	  /*
	   * No OS types that are convertable to X types.
	   */
	  xType = XG_NULL;
	}
    }
  else
    {
      if (xEvent->target == AnyPropertyType)
	{
	  /*
	   * The requestor will accept any type of data - so we use the first
	   * OpenStep type that corresponds to a known X type.
	   */
	  for (i = 0; i < numOsTypes; i++)
	    {
	      NSString	*type = [types objectAtIndex: i];
	      Atom	t = osTypeToX(type);

	      if (t != XG_NULL)
		{
		  osType = type;
		  xType = t;
		  break;
		}
	    }
	}
      else
	{
	  /*
           * Find an available OpenStep pasteboard type that corresponds
	   * to the requested X type.
	   */
	  for (i = 0; i < numOsTypes; i++)
	    {
	      NSString	*type = [types objectAtIndex: i];
	      Atom	t = osTypeToX(type);

	      if (t == xEvent->target)
		{
		  osType = type;
		  xType = t;
		  break;
		}
	    }
	}

      /*
       * Now we know what type of data is required - so get it from the
       * pasteboard and convert to a format X can understand.
       */
      if (osType != nil)
	{
	  if ([osType isEqualToString: NSStringPboardType])
	    {
	      NSString	*s = [_pb stringForType: NSStringPboardType];
#ifdef X_HAVE_UTF8_STRING
	      NSData *d = [s dataUsingEncoding: NSUTF8StringEncoding];
#else // X_HAVE_UTF8_STRING not defined
	      NSData *d = [s dataUsingEncoding: NSISOLatin1StringEncoding];
#endif // X_HAVE_UTF8_STRING not defined

	      format = 8;
	      if (d != nil)
	        {
		  numItems = [d length];
		  data = malloc(numItems + 1);
		  if (data)
		    [d getBytes: data];
		}
	    }
	  else
	    {
	      NSLog(@"Trying to convert from unsupported type - '%@'", osType);
	    }
	}
    }

  return [self xSendData: data format: format items: numItems type: xType
    to: xEvent->requestor property: xEvent->property];
}

- (BOOL) xSendData: (unsigned char*) data format: (int) format 
	     items: (int) numItems type: (Atom) xType
		to: (Window) window property: (Atom) property
{
  BOOL status = NO;
  
  /*
   * If we have managed to convert data of the appropritate type, we must now
   * append the data to the property on the requesting window.
   * We do this in small chunks, checking for errors, in case the window
   * manager puts a limit on the data size we can use.
   * This is not thread-safe - but I think that's a general problem with X.
   */
  if (data != 0 && numItems != 0 && format != 0)
    {
      int	(*oldHandler)(Display*, XErrorEvent*);
      int	mode = PropModeReplace;
      int	pos = 0;
      int	maxItems = 4096 * 8 / format;

      appendFailure = NO;
      oldHandler = XSetErrorHandler(xErrorHandler);

      while (appendFailure == NO && pos < numItems)
	{
	  if (pos + maxItems > numItems)
	    {
	      maxItems = numItems - pos;
	    }
	  XChangeProperty(xDisplay, window, property,
	    xType, format, mode, &data[pos*format/8], maxItems);
	  mode = PropModeAppend;
	  pos += maxItems;
	  XSync(xDisplay, False);
	}
      XFree(data);
      XSetErrorHandler(oldHandler);
      if (appendFailure == NO)
	{
	  status = YES;
	}
    }
  return status;
}

- (Time) xTimeByAppending
{
  NSDate	*limit;
  Time		whenRequested;
  Atom		actualType = 0;
  int		actualFormat = 0;
  unsigned long	ni;
  unsigned long	ba;
  unsigned char	*pr;

  /*
   * Do a nul append to a property to get a timestamp,
   * - but first we must determine the property-type and format.
   */
  XGetWindowProperty(xDisplay, xAppWin, [self xPb], 0, 0, False,
    AnyPropertyType, &actualType, &actualFormat, &ni, &ba, &pr);
  if (pr != 0)
    XFree(pr);
    
  if (actualType == None)
    {
      /*
       * The property doesn't exist - so we will be creating a new (empty)
       * property.
       */
#ifdef X_HAVE_UTF8_STRING
      actualType = XG_UTF8_STRING;
#else // X_HAVE_UTF8_STRING not defined
      actualType = XA_STRING;
#endif // X_HAVE_UTF8_STRING not defined
      actualFormat = 8;
    }

  XChangeProperty(xDisplay, xAppWin, [self xPb], actualType, actualFormat,
    PropModeAppend, 0, 0);
  XFlush(xDisplay);
  limit = [NSDate dateWithTimeIntervalSinceNow: 3.0];
  [self setTimeOfLastAppend: 0];
  /*
   * Run an event loop until we get a notification for our nul append.
   * this will give us an up-to-date timestamp as required by ICCCM.
   */
  while ([self timeOfLastAppend] == 0)
    {
      [[NSRunLoop currentRunLoop] runMode: xWaitMode
			       beforeDate: limit];
      if ([limit timeIntervalSinceNow] <= 0.0)
	break;	/* Timeout */
    }
  if ((whenRequested = [self timeOfLastAppend]) == 0)
    {
      NSLog(@"Timed out waiting for X append");
      whenRequested = CurrentTime;
    }
  return whenRequested;
}

@end



// This are copies of functions from XGContextEvent.m. 
// We should create a separate file for them.
static inline
Atom *
mimeTypeForPasteboardType(Display *xDisplay, NSZone *zone, NSArray *types)
{
  Atom *typelist;
  int count = [types count];
  int i;

  typelist = NSZoneMalloc(zone, (count+1) * sizeof(Atom));
  for (i = 0; i < count; i++)
    {
      NSString *mime = [NSPasteboard mimeTypeForPasteboardType: 
		       [types objectAtIndex: i]];
      typelist[i] = XInternAtom(xDisplay, [mime cString], False);
    }
  typelist[count] = 0;

  return typelist;
}

static inline
NSArray *
pasteboardTypeForMimeType(Display *xDisplay, NSZone *zone, Atom *typelist)
{
  Atom *type = typelist;
  NSMutableArray *newTypes = [[NSMutableArray allocWithZone: zone] init];

  while(*type != None)
    {
      char *s = XGetAtomName(xDisplay, *type);
      
      if (s)
	{
	  [newTypes addObject: [NSPasteboard pasteboardTypeForMimeType: 
	    [NSString stringWithCString: s]]];
	}
    }
  
  return AUTORELEASE(newTypes);
}

static DndClass dnd;

@implementation	XDragPbOwner

+ (void) initialize
{
  if (self == [XDragPbOwner class])
    {
      NSPasteboard	*p;

      xdnd_init(&dnd, xDisplay);
      p = [NSPasteboard pasteboardWithName: NSDragPboard];
      [[XDragPbOwner alloc] initWithXPb: dnd.XdndSelection osPb: p];
    }
}

- (void) pasteboardChangedOwner: (NSPasteboard*)sender
{
  NSArray *types;
  Atom *typelist;

  // Some GNUstep application did grap the drag pasteboard. Report this to X.
  if (xdnd_set_selection_owner(&dnd, xAppWin, None))
    {
      NSLog(@"Failed to set X drag selection owner to the pasteboard server.");
    }
  [self setOwnedByOpenStep: YES];

  // We also have to set the supported types for our window
  types = [_pb types];
  typelist = mimeTypeForPasteboardType(xDisplay, [self zone], types);
  xdnd_set_type_list(&dnd, xAppWin, typelist);
  NSZoneFree([self zone], typelist);
}

- (NSArray*) availableTypes
{
  Window window;
  Atom *types;
  NSArray *newTypes;
	
  window = XGetSelectionOwner(xDisplay, dnd.XdndSelection);
  if (window == None)
    return nil;
  xdnd_get_type_list(&dnd, window, &types);
  newTypes = pasteboardTypeForMimeType(xDisplay, [self zone], types);
  free(types);
  return newTypes;
}

- (void) pasteboard: (NSPasteboard*)pb provideDataForType: (NSString*)type
{
  NSString *mime = [NSPasteboard mimeTypeForPasteboardType: type];
  Atom mType = XInternAtom(xDisplay, [mime cString], False);
  Window window;
  Time	whenRequested = CurrentTime;
  NSDate	*limit;

  [self setData: nil];
  // How can we get the selection owner?
  window = XGetSelectionOwner(xDisplay, dnd.XdndSelection);

  xdnd_convert_selection(&dnd, window, xAppWin, mType);
  XFlush(xDisplay);

  /*
   * Run an event loop to read X events until we have aquired the
   * pasteboard data we need.
   */
  limit = [NSDate dateWithTimeIntervalSinceNow: 20.0];
  [self setWaitingForSelection: whenRequested];
  while ([self waitingForSelection] == whenRequested)
    {
      [[NSRunLoop currentRunLoop] runMode: xWaitMode
				  beforeDate: limit];
      if ([limit timeIntervalSinceNow] <= 0.0)
	break;	/* Timeout */
    }
  if ([self waitingForSelection] != 0)
    {
      [self setWaitingForSelection: 0];
      NSLog(@"Timed out waiting for X selection");
    }
  [pb setData: [self data] forType: type];
}

- (void) xSelectionClear
{
  // Do nothing as we don't know, which new types will be supplied
  [self setOwnedByOpenStep: NO];
}

@end
