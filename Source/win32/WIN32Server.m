/* WIN32Server - Implements window handling for MSWindows

   Copyright (C) 2002 Free Software Foundation, Inc.

   Written by: Fred Kiefer <FredKiefer@gmx.de>
   Date: March 2002
   
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
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
   */

#include <Foundation/NSDebug.h>
#include <Foundation/NSString.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSConnection.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSTimer.h>
#include <AppKit/AppKitExceptions.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSGraphics.h>
#include <AppKit/NSWindow.h>
#include <AppKit/NSView.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSCursor.h>
#include <AppKit/NSText.h>
#include <AppKit/DPSOperators.h>

#include "win32/WIN32Server.h"
#include "win32/WIN32Geometry.h"

static void 
validateWindow(HWND hwnd, RECT rect);
LRESULT CALLBACK MainWndProc(HWND hwnd, UINT uMsg,
			     WPARAM wParam, LPARAM lParam);

@implementation WIN32Server

/* Initialize AppKit backend */
+ (void)initializeBackend
{
  NSDebugLog(@"Initializing GNUstep win32 backend.\n");
  [GSDisplayServer setDefaultServerClass: [WIN32Server class]];
}

- (void) _initWin32Context
{
  WNDCLASSEX wc; 
  
  hinstance = (HINSTANCE)GetModuleHandle(NULL);

  // Register the main window class. 
  wc.cbSize = sizeof(wc);          
  //wc.style = CS_OWNDC; // | CS_HREDRAW | CS_VREDRAW; 
  wc.style = CS_HREDRAW | CS_VREDRAW; 
  wc.lpfnWndProc = (WNDPROC) MainWndProc; 
  wc.cbClsExtra = 0; 
  // Keep extra space for each window, for GS data
  wc.cbWndExtra = sizeof(WIN_INTERN); 
  wc.hInstance = hinstance; 
  wc.hIcon = NULL;
  wc.hCursor = NULL;
  wc.hbrBackground = GetStockObject(WHITE_BRUSH); 
  wc.lpszMenuName =  NULL; 
  wc.lpszClassName = "GNUstepWindowClass"; 
  wc.hIconSm = NULL;

  if (!RegisterClassEx(&wc)) 
       return; 

  // FIXME We should use GetSysColor to get standard colours from MS Window and 
  // use them in NSColor

  // Should we create a message only window here, so we can get events, even when
  // no windows are created?
}

- (void) setupRunLoopInputSourcesForMode: (NSString*)mode
{
  // FIXME
  NSTimer *timer;

  timer = [NSTimer timerWithTimeInterval: 0.1
		   target: self
		   selector: @selector(callback:)
		   userInfo: nil
		   repeats: YES];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: mode];
}

/**

*/
- (id) initWithAttributes: (NSDictionary *)info
{
  [self _initWin32Context];
  [super initWithAttributes: info];

  [self setupRunLoopInputSourcesForMode: NSDefaultRunLoopMode]; 
  [self setupRunLoopInputSourcesForMode: NSConnectionReplyMode]; 
  [self setupRunLoopInputSourcesForMode: NSModalPanelRunLoopMode]; 
  [self setupRunLoopInputSourcesForMode: NSEventTrackingRunLoopMode]; 
  return self;
}


- (void) _destroyWin32Context
{
  UnregisterClass("GNUstepWindowClass", hinstance);
}

/**

*/
- (void) dealloc
{
  [self _destroyWin32Context];
  [super dealloc];
}

/** Returns an instance of a class which implements the NSDraggingInfo
    protocol. */
- (id <NSDraggingInfo>) dragInfo
{
  [self subclassResponsibility: _cmd];
  return nil;
}

- (BOOL) slideImage: (NSImage*)image from: (NSPoint)from to: (NSPoint)to
{
  [self subclassResponsibility: _cmd];
  return NO;
}

/* Screen information */
- (NSSize) resolutionForScreen: (int)screen
{
  int xres, yres;
  HDC hdc;

  hdc = GetDC(NULL);
  xres = GetDeviceCaps(hdc, LOGPIXELSX);
  yres = GetDeviceCaps(hdc, LOGPIXELSY);
  ReleaseDC(NULL, hdc);
  
  return NSMakeSize(xres, yres);
}

- (NSRect) boundsForScreen: (int)screen
{
  return NSMakeRect(0, 0, GetSystemMetrics(SM_CXSCREEN), 
		    GetSystemMetrics(SM_CYSCREEN));
}

- (NSWindowDepth) windowDepthForScreen: (int)screen
{
  HDC hdc;
  int bits;
  //int planes;
      
  hdc = GetDC(NULL);
  bits = GetDeviceCaps(hdc, BITSPIXEL) / 3;
  //planes = GetDeviceCaps(hdc, PLANES);
  //NSLog(@"bits %d planes %d", bits, planes);
  ReleaseDC(NULL, hdc);
  
  return (_GSRGBBitValue | bits);
}

- (const NSWindowDepth *) availableDepthsForScreen: (int)screen
{
  int		 ndepths = 1;
  NSZone	*defaultZone = NSDefaultMallocZone();
  NSWindowDepth	*depths = 0;

  depths = NSZoneMalloc(defaultZone, sizeof(NSWindowDepth)*(ndepths + 1));
  // FIXME
  depths[0] = [self windowDepthForScreen: screen];
  depths[1] = 0;

  return depths;
}

- (NSArray *) screenList
{
  return [NSArray arrayWithObject: [NSNumber numberWithInt: 0]];
}

/**
   Returns the handle of the module instance.  */
- (void *) serverDevice
{
  return hinstance;
}

/**
   As the number of the window is actually is handle we return this.  */
- (void *) windowDevice: (int)win
{
  return (void *)win;
}

- (void) beep
{
  Beep(400, 500);
}  

@end

static inline
DWORD windowStyleForGSStyle(unsigned int style)
{
  DWORD wstyle = 0;

  if (style & NSTitledWindowMask)
    {
      wstyle |= WS_CAPTION;
    }
  if (style & NSClosableWindowMask)
    {
      wstyle |= WS_SYSMENU;
    }
  if (style & NSMiniaturizableWindowMask)
    {
      wstyle |= WS_MINIMIZEBOX;
    }
  if (style & NSResizableWindowMask)
    {
      wstyle |= WS_SIZEBOX;
    }

  if (wstyle)
    {
      wstyle |= WS_OVERLAPPED;
    }
  else
    {
      wstyle |= WS_POPUP;
    }
    
/*
  This does not work as NSBorderlessWindowMask is 0
  if (!(style & NSBorderlessWindowMask))
    {
      wstyle |= WS_BORDER;
    }
*/
  if (style & NSIconWindowMask)
    {
      wstyle = WS_ICONIC;
    }
  if (style & NSMiniWindowMask)
    {
      wstyle = WS_ICONIC;
    }

  //NSLog(@"Window wstyle %d for style %d", wstyle, style);
  return wstyle;
}

@implementation WIN32Server (WindowOps)

- (int) window: (NSRect)frame : (NSBackingStoreType)type : (unsigned int)style
	      : (int) screen
{
  HWND hwnd; 
  RECT r;
  DWORD wstyle = windowStyleForGSStyle(style);

  r = GSScreenRectToMS(frame);

  NSDebugLLog(@"WTrace", @"window: %@ : %d : %d : %d", NSStringFromRect(frame),
	      type, style, screen);
  NSDebugLLog(@"WTrace", @"         device frame: %d, %d, %d, %d", 
	      r.left, r.top, r.right - r.left, r.bottom - r.top);
  hwnd = CreateWindowEx(0,
			"GNUstepWindowClass",
			"GNUstepWindow",
			wstyle, 
			r.left, 
			r.top, 
			r.right - r.left, 
			r.bottom - r.top,
			(HWND) NULL,
			(HMENU) NULL,
			hinstance,
			(void*)type);
  NSDebugLLog(@"WTrace", @"         num/handle: %d", hwnd);

  [self _setWindowOwnedByServer: (int)hwnd];
  return (int)hwnd;
}

- (void) termwindow: (int) winNum
{
  NSDebugLLog(@"WTrace", @"termwindow: %d", winNum);
  DestroyWindow((HWND)winNum); 
}

- (void) stylewindow: (unsigned int)style : (int) winNum
{
  DWORD wstyle = windowStyleForGSStyle(style);

  NSDebugLLog(@"WTrace", @"stylewindow: %d : %d", style, winNum);
  SetWindowLong((HWND)winNum, GWL_STYLE, wstyle);
}

- (void) setbackgroundcolor: (NSColor *)color : (int)win
{
}

/** Changes window's the backing store to type */
- (void) windowbacking: (NSBackingStoreType)type : (int) winNum
{
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong((HWND)winNum, GWL_USERDATA);

  NSDebugLLog(@"WTrace", @"windowbacking: %d : %d", type, winNum);
  if (win->useHDC)
    {
      HGDIOBJ old;

      old = SelectObject(win->hdc, win->old);
      DeleteObject(old);
      DeleteDC(win->hdc);
      win->hdc = NULL;
      win->old = NULL;
      win->useHDC = NO;
    }

  if (type != NSBackingStoreNonretained)
    {
      HDC hdc, hdc2;
      HBITMAP hbitmap;
      RECT r;

      GetClientRect((HWND)winNum, &r);
      hdc = GetDC((HWND)winNum);
      hdc2 = CreateCompatibleDC(hdc);
      hbitmap = CreateCompatibleBitmap(hdc, r.right - r.left, r.bottom - r.top);
      win->old = SelectObject(hdc2, hbitmap);
      win->hdc = hdc2;
      win->useHDC = YES;

      ReleaseDC((HWND)winNum, hdc);
    }
}

- (void) titlewindow: (NSString*)window_title : (int) winNum
{
  NSDebugLLog(@"WTrace", @"titlewindow: %@ : %d", window_title, winNum);
  SetWindowText((HWND)winNum, [window_title cString]);
}

- (void) miniwindow: (int) winNum
{
  NSDebugLLog(@"WTrace", @"miniwindow: %d", winNum);
  ShowWindow((HWND)winNum, SW_MINIMIZE); 
}

/** Returns NO as we don't provide mini windows on MS Windows */ 
- (BOOL) appOwnsMiniwindow
{
  return NO;
}

- (void) windowdevice: (int) winNum
{
  NSGraphicsContext *ctxt;

  NSDebugLLog(@"WTrace", @"windowdevice: %d", winNum);
  ctxt = GSCurrentContext();
  GSSetDevice(ctxt, (void*)winNum, 0, 0);
  DPSinitmatrix(ctxt);
  DPSinitclip(ctxt);
}

- (void) orderwindow: (int) op : (int) otherWin : (int) winNum
{
  NSDebugLLog(@"WTrace", @"orderwindow: %d : %d : %d", op, otherWin, winNum);
  if (op != NSWindowOut)
    {
      ShowWindow((HWND)winNum, SW_SHOW); 
    }

  switch (op)
    {
    case NSWindowOut:
      SetWindowPos((HWND)winNum, NULL, 0, 0, 0, 0, 
		   SWP_HIDEWINDOW | SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER);
      break;
    case NSWindowBelow:
      if (otherWin == 0)
	otherWin = (int)HWND_BOTTOM;
      SetWindowPos((HWND)winNum, (HWND)otherWin, 0, 0, 0, 0, 
		   SWP_NOSIZE | SWP_NOMOVE);
      break;
    case NSWindowAbove:
      if (otherWin == 0)
	{
	  otherWin = winNum;
	  winNum = (int)HWND_TOP;
	}
      SetWindowPos((HWND) otherWin, (HWND)winNum, 0, 0, 0, 0, 
		   SWP_NOSIZE | SWP_NOMOVE);
      break;
    }
}

- (void) movewindow: (NSPoint)loc : (int)winNum
{
  POINT p;

  NSDebugLLog(@"WTrace", @"movewindow: %@ : %d", NSStringFromPoint(loc), 
	      winNum);
  p = GSWindowOriginToMS((HWND)winNum, loc);

  SetWindowPos((HWND)winNum, NULL, p.x, p.y, 0, 0, 
	       SWP_NOZORDER | SWP_NOSIZE | SWP_NOREDRAW);
}

- (void) placewindow: (NSRect)frame : (int) winNum
{
  RECT r;
  RECT r2;
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong((HWND)winNum, GWL_USERDATA);

  NSDebugLLog(@"WTrace", @"placewindow: %@ : %d", NSStringFromRect(frame), 
	      winNum);
  r = GSScreenRectToMS(frame);
  GetWindowRect((HWND)winNum, &r2);

  SetWindowPos((HWND)winNum, NULL, r.left, r.top, r.right - r.left, r.bottom - r.top, 
	       SWP_NOZORDER | SWP_NOREDRAW);

  if ((win->useHDC) &&
      (r.right - r.left != r2.right - r2.left) &&
      (r.bottom - r.top != r2.bottom - r2.top))
    {
      HDC hdc, hdc2;
      HBITMAP hbitmap;
      HGDIOBJ old;
      
      //NSLog(@"Change backing store to %d %d", r.right - r.left, r.bottom - r.top);
      old = SelectObject(win->hdc, win->old);
      DeleteObject(old);
      DeleteDC(win->hdc);
      win->hdc = NULL;
      win->old = NULL;
      
      GetClientRect((HWND)winNum, &r);
      hdc = GetDC((HWND)winNum);
      hdc2 = CreateCompatibleDC(hdc);
      hbitmap = CreateCompatibleBitmap(hdc, r.right - r.left, r.bottom - r.top);
      win->old = SelectObject(hdc2, hbitmap);
      win->hdc = hdc2;
      
      ReleaseDC((HWND)winNum, hdc);
    }
}

- (BOOL) findwindow: (NSPoint)loc : (int) op : (int) otherWin 
		   : (NSPoint *)floc : (int*) winFound
{
  return NO;
}

- (NSRect) windowbounds: (int) winNum
{
  RECT r;

  GetWindowRect((HWND)winNum, &r);
  return MSScreenRectToGS(r);
}

- (void) setwindowlevel: (int) level : (int) winNum
{
  NSDebugLLog(@"WTrace", @"setwindowlevel: %d : %d", level, winNum);
}

- (int) windowlevel: (int) winNum
{
  return 0;
}

- (NSArray *) windowlist
{
  return nil;
}

- (int) windowdepth: (int) winNum
{
  return 0;
}

/** Set the maximum size of the window */
- (void) setmaxsize: (NSSize)size : (int) winNum
{
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong((HWND)winNum, GWL_USERDATA);
  POINT p;

  p.x = size.width;
  p.y = size.height;
  win->minmax.ptMaxTrackSize = p;
}

/** Set the minimum size of the window */
- (void) setminsize: (NSSize)size : (int) winNum
{
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong((HWND)winNum, GWL_USERDATA);
  POINT p;

  p.x = size.width;
  p.y = size.height;
  win->minmax.ptMinTrackSize = p;
}

/** Set the resize incremenet of the window */
- (void) setresizeincrements: (NSSize)size : (int) winNum
{
}

/** Causes buffered graphics to be flushed to the screen */
- (void) flushwindowrect: (NSRect)rect : (int) winNum
{
  RECT r = GSWindowRectToMS((HWND)winNum, rect);
  validateWindow((HWND)winNum, r);
}

- (void) styleoffsets: (float *) l : (float *) r : (float *) t : (float *) b
		     : (unsigned int) style 
{
  DWORD wstyle = windowStyleForGSStyle(style);
  RECT rect = {100, 100, 200, 200};
  
  AdjustWindowRectEx(&rect, wstyle, NO, 0);

  *l = 100 - rect.left;
  *r = rect.right - 200;
  *t = 100 - rect.top;
  *b = rect.bottom - 200;

  //NSLog(@"Sytle %d offset %f %f %f %f", wstyle, *l, *r, *t, *b);
}

- (void) docedited: (int) edited : (int) winNum
{
}

- (void) setinputstate: (int)state : (int)winNum
{
  if (state == GSTitleBarKey)
    {
      SetActiveWindow((HWND)winNum);
    }
}

/** Forces focus to the window so that all key events are sent to this
    window */
- (void) setinputfocus: (int) winNum
{
  NSDebugLLog(@"WTrace", @"setinputfocus: %d", winNum);
  NSDebugLLog(@"Focus", @"Setting input focus to %d");
  if (winNum)
    SetFocus((HWND)winNum);
}

- (NSPoint) mouselocation
{
  POINT p;

  if (!GetCursorPos(&p))
    {  
      NSLog(@"GetCursorPos failed with %d", GetLastError());
      return NSZeroPoint;
    }

  return MSScreenPointToGS(p.x, p.y);
}

- (NSPoint) mouseLocationOnScreen: (int)screen window: (int *)win
{
  return [self mouselocation];
}

- (BOOL) capturemouse: (int) winNum
{
  NSDebugLLog(@"WTrace", @"capturemouse: %d", winNum);
  SetCapture((HWND)winNum);
  return YES;
}

- (void) releasemouse
{
  NSDebugLLog(@"WTrace", @"releasemouse");
  ReleaseCapture();
}

- (void) hidecursor
{
  NSDebugLLog(@"WTrace", @"hidecursor");
  ShowCursor(NO);
}

- (void) showcursor
{
  ShowCursor(YES);
}

- (void) standardcursor: (int)style : (void **)cid
{
  HCURSOR hCursor;

  NSDebugLLog(@"WTrace", @"standardcursor: %d", style);
  switch (style)
    {
    case GSArrowCursor:
      hCursor = LoadCursor(NULL, IDC_ARROW);
      break;
    case GSIBeamCursor:
      hCursor = LoadCursor(NULL, IDC_IBEAM);
      break;
    default:
      hCursor = LoadCursor(NULL, IDC_ARROW);
      break;
    }
  *cid = (void*)hCursor;
}

- (void) imagecursor: (NSPoint)hotp : (int) w :  (int) h 
		    : (int)colors : (const char *)image : (void **)cid
{
  /*
  HCURSOR cur;
  BYTE *and;
  BYTE *xor;

  xor = image;
  cur = CreateCursor(hinstance, (int)hotp.x, (int)hotp.y,  (int)w, (int)h, and, xor);
  *cid = (void*)hCursor;
  */
}

- (void) setcursorcolor: (NSColor *)fg : (NSColor *)bg : (void*) cid
{
  /* FIXME The colour is currently ignored
  if (fg != nil)
    {
      ICONINFO iconinfo;

      if (GetIconInfo((HCURSOR)cid, &iconinfo))
	{
	  iconinfo.hbmColor = ; 
	}
    }
  */

  SetCursor((HCURSOR)cid);
}

@end

static void 
validateWindow(HWND hwnd, RECT rect)
{
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong((HWND)hwnd, GWL_USERDATA);

  if (win->useHDC)
    {
      HDC hdc = GetDC((HWND)hwnd);
      WINBOOL result;

      result = BitBlt(hdc, rect.left, rect.top, 
		      (rect.right - rect.left), (rect.bottom - rect.top), 
		      win->hdc, rect.left, rect.top, SRCCOPY);
      if (!result)
        {
	  NSLog(@"validated window %d %@", hwnd, 
		NSStringFromRect(MSWindowRectToGS((HWND)hwnd, rect)));
	  NSLog(@"validateWindow failed %d", GetLastError());
      }
      ReleaseDC((HWND)hwnd, hdc);
    }
}
