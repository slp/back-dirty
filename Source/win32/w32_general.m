/* WIN32Server - Implements window handling for MSWindows

   Copyright (C) 2005 Free Software Foundation, Inc.

   Written by: Fred Kiefer <FredKiefer@gmx.de>
   Date: March 2002
   Part of this code have been written by:
   Tom MacSween <macsweent@sympatico.ca>
   Date August 2005

   This file is part of the GNU Objective C User Interface Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

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

#include "w32_Events.h"

@implementation WIN32Server (w32_General)

- (void) decodeWM_CLOSEParams:(WPARAM)wParam :(LPARAM)lParam :(HWND)hwnd;
{
  NSEvent * ev;
  NSPoint eventLocation = NSMakePoint(0, 0);
  ev = [NSEvent otherEventWithType: NSAppKitDefined
		      location: eventLocation
		      modifierFlags: 0
		      timestamp: 0
		      windowNumber: (int)hwnd
		      context: GSCurrentContext()
		      subtype: GSAppKitWindowClose
		      data1: 0
		      data2: 0];
		    
  // need to send the event... or handle it directly.
  [EVENT_WINDOW(hwnd) sendEvent:ev];
  
  ev=nil;
  flags._eventHandled=YES;
}
      
- (void) decodeWM_NCDESTROYParams: (WPARAM)wParam : (LPARAM)lParam : (HWND)hwnd
{
}

- (void) decodeWM_DESTROYParams: (WPARAM)wParam : (LPARAM)lParam : (HWND)hwnd
{
  WIN_INTERN *win = (WIN_INTERN *)GetWindowLong(hwnd, GWL_USERDATA);

  // Clean up window-specific data objects. 
	
  if (win->useHDC)
    {
      HGDIOBJ old;
	    
      old = SelectObject(win->hdc, win->old);
      DeleteObject(old);
      DeleteDC(win->hdc);
    }
  objc_free(win);
  flags._eventHandled=YES;

}

- (void) decodeWM_QUERYOPENParams: (WPARAM)wParam : (LPARAM)lParam : (HWND)hwnd
{
}

- (void) decodeWM_SYSCOMMANDParams: (WPARAM)wParam : (LPARAM)lParam : (HWND)hwnd
{
  // stubbed for future development

   switch (wParam)
   {
      case SC_CLOSE:
      break;
      case SC_CONTEXTHELP:
      break;
      case SC_HOTKEY:
      break;
      case SC_HSCROLL:
      break;
      case SC_KEYMENU:
      break;
      case SC_MAXIMIZE:
      break;
      case SC_MINIMIZE:
       flags.HOLD_MINI_FOR_SIZE=TRUE;
       flags.HOLD_MINI_FOR_MOVE=TRUE;  
      break;
      case SC_MONITORPOWER:
      break;
      case SC_MOUSEMENU:
      break;
      case SC_MOVE:
      break;
      case SC_NEXTWINDOW:
      break;  
      case SC_PREVWINDOW:
      break;
      case SC_RESTORE:
      break;
      case SC_SCREENSAVE:
      break;
      case SC_SIZE:
      break;
      case SC_TASKLIST:
      break;
      case SC_VSCROLL:
      break;
        
      default:
      break;
   }
}

- (void) decodeWM_COMMANDParams: (WPARAM)wParam : (LPARAM)lParam : (HWND)hwnd
{
} 

- (void) resetForGSWindowStyle:(HWND)hwnd w32Style:(DWORD)aStyle
{
  // to be completed for styles
  LONG result;

  ShowWindow(hwnd, SW_HIDE);
  SetLastError(0);
   result=SetWindowLong(hwnd, GWL_EXSTYLE, WS_EX_APPWINDOW);
   result=SetWindowLong(hwnd, GWL_STYLE, (LONG)aStyle);
  // should check error here...
  ShowWindow(hwnd, SW_SHOWNORMAL);
}
      
@end 
