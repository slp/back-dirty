/* 	-*-ObjC-*- */
/* XGOpenGL - openGL management using glX

   Copyright (C) 2002 Free Software Foundation, Inc.

   Author: Frederic De Jaeger
   Date: Nov 2002

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/ 

#ifndef _GNUstep_H_XGOpenGL
#define _GNUstep_H_XGOpenGL

#include <AppKit/NSOpenGL.h>

#define id _gs_avoid_id_collision
#include <GL/glx.h>
#undef id

@class NSView;
@class XGXSubWindow;
@class XGGLPixelFormat;

@interface XGGLContext : NSOpenGLContext
{
  GLXContext		glx_context;
  GLXWindow		glx_drawable;
  XGXSubWindow		*xsubwin;
  XGGLPixelFormat 	*format;
}
@end

@interface XGGLPixelFormat : NSOpenGLPixelFormat
{
@public
  GLXFBConfig  *conf_tab;
  int		n_elem;
}
@end

#endif
