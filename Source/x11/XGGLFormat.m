/* -*- mode:ObjC -*-
   XGGLContext - backend implementation of NSOpenGLContext

   Copyright (C) 1998,2002 Free Software Foundation, Inc.

   Written by:  Frederic De Jaeger
   Date: Nov 2002
   
   This file is part of the GNU Objective C User Interface Library.

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

#include "config.h"
#ifdef HAVE_GLX
#include <Foundation/NSDebug.h>
#include <Foundation/NSException.h>
#include <Foundation/NSData.h>
#include <GNUstepGUI/GSDisplayServer.h>
#include "x11/XGServer.h"
#include "x11/XGOpenGL.h"
#include <X11/Xlib.h>

#define MAKE_DISPLAY(dpy) Display *dpy;\
  dpy = [(XGServer *)GSCurrentServer() xDisplay];\
  NSAssert(dpy != NULL, NSInternalInconsistencyException)


@implementation XGGLPixelFormat

/* FIXME:
     we assume that the ABI of NSOpenGLPixelFormatAttribute matches the ABI 
     of glX. Apparently, this is true for the most useful attributes.
*/

- (void) getValues: (GLint *)vals 
      forAttribute: (NSOpenGLPixelFormatAttribute)attrib 
  forVirtualScreen: (GLint)screen
{
  GLint error;
  MAKE_DISPLAY(dpy);

  NSAssert(((GSglxMinorVersion (dpy) >= 3) ? (void *)configurations.fbconfig : (void *)configurations.visualinfo) != NULL
	        && configurationCount > 0,
            NSInternalInconsistencyException);

  if (GSglxMinorVersion(dpy) >= 3)
    {
      error = glXGetFBConfigAttrib(dpy, configurations.fbconfig[0], attrib, vals);
      if ( error != 0 )
          NSDebugMLLog( @"GLX", @"Can not get FB attribute for pixel format %@ - Errror %u",
                                self, error );
    }
  else
    {
      error = glXGetConfig(dpy, configurations.visualinfo, attrib, vals);
      if ( error != 0 )
          NSDebugMLLog( @"GLX", @"Can not get FB attribute for pixel format %@ - Errror %u",
                                self, error );
      if ( error != 0 )
          NSDebugMLLog( @"GLX", @"Can not get FB attribute for pixel format %@ - Errror %u",
                                self, error );
    }
}

- (id)initWithAttributes:(NSOpenGLPixelFormatAttribute *)attribs
{
  int AccumSize;
  NSOpenGLPixelFormatAttribute *ptr = attribs;
  NSMutableData *data = [NSMutableData data];
  GLint drawable_type = 0;
  MAKE_DISPLAY(dpy);

#define append(a, b) do {int v1 = a; int v2 = b; [data appendBytes: &v1 length: sizeof(v1)];\
  [data appendBytes: &v2 length: sizeof(v2)];} while (0)

#define append1(a) do {int v1 = a; [data appendBytes: &v1 length: sizeof(v1)];} while (0)

  if (GSglxMinorVersion (dpy) < 3)
    {
      append1 (GLX_RGBA);
    }
  else
    {
      append(GLX_RENDER_TYPE, GLX_RGBA_BIT);
      //append(GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT|GLX_PIXMAP_BIT);
      //append(GLX_X_RENDERABLE,YES);
      //append(GLX_X_VISUAL_TYPE,GLX_TRUE_COLOR);
    }

  while (*ptr)
    {
      switch(*ptr)
        {
          // it means all the same on GLX - there is no diffrent here
          case NSOpenGLPFASingleRenderer:
          case NSOpenGLPFAAllRenderers:
          case NSOpenGLPFAAccelerated:
            if (GSglxMinorVersion(dpy) < 3)
              append(GLX_USE_GL,YES);
            break;
          case  NSOpenGLPFADoubleBuffer:
            append(GLX_DOUBLEBUFFER, YES);
            break;
          case NSOpenGLPFAStereo:
            append(GLX_STEREO, YES);
            break;
          case NSOpenGLPFAAuxBuffers:
            ptr++;
            append(GLX_AUX_BUFFERS, *ptr);
            break;
          case NSOpenGLPFAColorSize:
            ptr++;
            append(GLX_RED_SIZE, *ptr);
            append(GLX_GREEN_SIZE, *ptr);
            append(GLX_BLUE_SIZE, *ptr);
            break;
          case NSOpenGLPFAAlphaSize:
            ptr++;
            append(GLX_ALPHA_SIZE, *ptr);
            break;
          case NSOpenGLPFADepthSize:
            ptr++;
            append(GLX_DEPTH_SIZE, *ptr);
            break;
          case NSOpenGLPFAStencilSize:
            ptr++;
            append(GLX_STENCIL_SIZE, *ptr);
            break;
          case NSOpenGLPFAAccumSize:
            ptr++;
            //has to been tested - I did it in that way....
            //FIXME?  I don't understand...
            //append(GLX_ACCUM_RED_SIZE, *ptr/3);
            //append(GLX_ACCUM_GREEN_SIZE, *ptr/3);
            //append(GLX_ACCUM_BLUE_SIZE, *ptr/3);
            AccumSize=*ptr;  
            switch (AccumSize)
              {
                case 8:
                  append(GLX_ACCUM_RED_SIZE, 3);
                  append(GLX_ACCUM_GREEN_SIZE, 3);
                  append(GLX_ACCUM_BLUE_SIZE, 2);
                  append(GLX_ACCUM_ALPHA_SIZE, 0);
                  break;
                case 15:
                case 16:
                  append(GLX_ACCUM_RED_SIZE, 5);
                  append(GLX_ACCUM_GREEN_SIZE, 5);
                  append(GLX_ACCUM_BLUE_SIZE, 5);
                  append(GLX_ACCUM_ALPHA_SIZE, 0);
                  break;
                case 24:
                  append(GLX_ACCUM_RED_SIZE, 8);
                  append(GLX_ACCUM_GREEN_SIZE, 8);
                  append(GLX_ACCUM_BLUE_SIZE, 8);
                  append(GLX_ACCUM_ALPHA_SIZE, 0);
                  break;
                case 32:
                  append(GLX_ACCUM_RED_SIZE, 8);
                  append(GLX_ACCUM_GREEN_SIZE, 8);
                  append(GLX_ACCUM_BLUE_SIZE, 8);
                  append(GLX_ACCUM_ALPHA_SIZE, 8);
                  break;
              }
            break;
          case NSOpenGLPFAWindow: 
            drawable_type |= GLX_WINDOW_BIT;
            break;
          case NSOpenGLPFAPixelBuffer: 
            drawable_type |= GLX_PBUFFER_BIT;
            break;
          case NSOpenGLPFAOffScreen:
            drawable_type |= GLX_PIXMAP_BIT;
            break;

          //can not be handle by X11
          case NSOpenGLPFAMinimumPolicy:
            break;
          // can not be handle by X11
          case NSOpenGLPFAMaximumPolicy:
            break;

          //FIXME all of this stuff...
          case NSOpenGLPFAFullScreen:
          case NSOpenGLPFASampleBuffers:
          case NSOpenGLPFASamples:
          case NSOpenGLPFAAuxDepthStencil:
          case NSOpenGLPFARendererID:
          case NSOpenGLPFANoRecovery:
          case NSOpenGLPFAClosestPolicy:
          case NSOpenGLPFARobust:
          case NSOpenGLPFABackingStore:
          case NSOpenGLPFAMPSafe:
          case NSOpenGLPFAMultiScreen:
          case NSOpenGLPFACompliant:
          case NSOpenGLPFAScreenMask:
          case NSOpenGLPFAVirtualScreenCount:

          case NSOpenGLPFAAllowOfflineRenderers:
          case NSOpenGLPFAColorFloat:
          case NSOpenGLPFAMultisample:
          case NSOpenGLPFASupersample:
          case NSOpenGLPFASampleAlpha:
            break;
        }
      ptr ++;
    }

  if ( drawable_type )
    {
      append(GLX_DRAWABLE_TYPE,drawable_type);
    }

  append1(None);

  //FIXME, what screen number ?
  if (GSglxMinorVersion (dpy) >= 3)
    {
      configurations.fbconfig = glXChooseFBConfig(dpy, DefaultScreen(dpy), 
                                                  [data mutableBytes], 
                                                  &configurationCount);
      if ( configurations.fbconfig == NULL )
          NSDebugMLLog( @"GLX", @"Can not choose FB config for pixel format %@",
                                self );
    }
  else
    {
      configurations.visualinfo = glXChooseVisual(dpy, DefaultScreen(dpy), 
                                                  [data mutableBytes]);
      if((void *)configurations.visualinfo != NULL)
	configurationCount = 1;
      else
          NSDebugMLLog( @"GLX", @"Can not choose FB config for pixel format %@",
                                self );
    }
  
  if (((GSglxMinorVersion (dpy) >= 3) ? (void *)configurations.fbconfig : 
       (void *)configurations.visualinfo) == NULL)
    {
      NSDebugMLLog(@"GLX", @"no pixel format found matching what is required");
      RELEASE(self);

      return nil;
    }
  else
    {
      NSDebugMLLog(@"GLX", @"We found %d pixel formats", configurationCount);
      
      return self;
    }
}

- (XVisualInfo *)xvinfo
{
  MAKE_DISPLAY(dpy);

  if (GSglxMinorVersion(dpy) >= 3)
    {
      return glXGetVisualFromFBConfig(dpy, configurations.fbconfig[0]);
    }
  else
    {
      return configurations.visualinfo;
    }
}

- (GLXContext)createGLXContext: (XGGLContext *)share
{
  GLXContext context;
  MAKE_DISPLAY(dpy);

  if (GSglxMinorVersion(dpy) >= 3)
    {
      context = glXCreateNewContext(dpy, configurations.fbconfig[0], 
                                 GLX_RGBA_TYPE, [share glxcontext], YES);
    }
  else
    {
      context = glXCreateContext(dpy, configurations.visualinfo, 
                              [share glxcontext], GL_TRUE);
    }
  if ( context == NULL )
      NSDebugMLLog( @"GLX", @"Can not create GL context for pixel format %@ - Errror %u",
                            self, glGetError() );

  return context;
}

- (GLXWindow) drawableForWindow: (Window)xwindowid
{
  GLint error;
  GLXWindow win;
  MAKE_DISPLAY(dpy);

  if (GSglxMinorVersion(dpy) >= 3)
    {
      win = glXCreateWindow(dpy, configurations.fbconfig[0], 
                             xwindowid, NULL);
    }
  else
    {
      win = xwindowid;
    }

  error = glGetError();
  if ( error != GL_NO_ERROR )
      NSDebugMLLog( @"GLX", @"Can not create GL window for pixel format %@ - Errror %u",
                            self, error );
  return win;
}

- (void) dealloc
{
  //FIXME 	
  //are we sure that X Connection is still up here ?
  MAKE_DISPLAY(dpy);

  if (GSglxMinorVersion(dpy) >= 3)
    {
      XFree(configurations.fbconfig);
    }
  else
    {
      XFree(configurations.visualinfo);
    }

  NSDebugMLLog(@"GLX", @"deallocation");
  [super dealloc];
}

- (int)numberOfVirtualScreens
{
  //FIXME
  //This looks like a reasonable value to return...
  return 1;
}

@end
#endif
