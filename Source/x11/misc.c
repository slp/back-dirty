/* 
 *  Raster graphics library
 * 
 *  Copyright (c) 1997-2000 Alfredo K. Kojima
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *  
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *  
 *  You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the Free
 *  Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
#include <config.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <X11/Xlib.h>

#include "x11/wraster.h"


void 
RBevelImage(RImage *image, int bevel_type)
{
    RColor color;
    RColor cdelta;
    int w, h;

    if (image->width<3 || image->height<3)
        return;

    w = image->width;
    h = image->height;
    if (bevel_type>0) {  /* raised */
        /* top */
        cdelta.alpha = 0;
        cdelta.red = cdelta.green = cdelta.blue = 80;
        ROperateLine(image, RAddOperation, 0, 0, w-1, 0, &cdelta);
        if (bevel_type==RBEV_RAISED3 && w>3)
            ROperateLine(image, RAddOperation, 1, 1, w-3, 1,&cdelta);

        /* left */
        ROperateLine(image, RAddOperation, 0, 1, 0, h-1, &cdelta);
        if (bevel_type==RBEV_RAISED3 && h>3)
            ROperateLine(image, RAddOperation, 1, 2, 1, h-3, &cdelta);

	/* bottom */
        color.alpha = 255;
        color.red = color.green = color.blue = 0;
        cdelta.red = cdelta.green = cdelta.blue = 40;
        if (bevel_type==RBEV_RAISED2 || bevel_type==RBEV_RAISED3) {
            ROperateLine(image, RSubtractOperation, 0, h-2, w-3, 
				   h-2, &cdelta);
            RDrawLine(image, 0, h-1, w-1, h-1, &color);
        } else {
            ROperateLine(image, RSubtractOperation, 0, h-1, w-1, h-1,
				   &cdelta);
        }

	/* right */
        if (bevel_type==RBEV_RAISED2 || bevel_type==RBEV_RAISED3) {
            ROperateLine(image, RSubtractOperation, w-2, 0, w-2, h-2,
				   &cdelta);
            RDrawLine(image, w-1, 0, w-1, h-2, &color);
        } else {
            ROperateLine(image, RSubtractOperation, w-1, 0, w-1, h-2,
				   &cdelta);
        }
    } else { /* sunken */
        cdelta.alpha = 0;
        cdelta.red = cdelta.green = cdelta.blue = 40;
        ROperateLine(image, RSubtractOperation, 0, 0, w-1, 0, 
			       &cdelta);        /* top */
        ROperateLine(image, RSubtractOperation, 0, 1, 0, h-1, 
			       &cdelta);	/* left */
        cdelta.red = cdelta.green = cdelta.blue = 80;
        ROperateLine(image, RAddOperation, 0, h-1, w-1, h-1, &cdelta); /* bottom */
        ROperateLine(image, RAddOperation, w-1, 0, w-1, h-2, &cdelta); /* right */
    }
}


void
RClearImage(RImage *image, RColor *color)
{
    if (image->format == RRGBAFormat) {
	    unsigned char *d = image->data;
	    int i;

	    for (i = 0; i < image->width; i++) {
		*d++ = color->red;
		*d++ = color->green;
		*d++ = color->blue;
		*d++ = color->alpha;
	    }
	    for (i = 1; i < image->height; i++, d += image->width*4) {
		memcpy(d, image->data, image->width*4);
	    }
    } else {
	    unsigned char *d = image->data;
	    int i;

	    for (i = 0; i < image->width; i++) {
		*d++ = color->red;
		*d++ = color->green;
		*d++ = color->blue;
	    }
	    for (i = 1; i < image->height; i++, d += image->width*3) {
		memcpy(d, image->data, image->width*3);
	    }
    }
#if 0
    if (color->alpha==255) {
	if (image->format == RRGBAFormat) {
	    unsigned char *d = image->data;
	    int i;

	    for (i = 0; i < image->width; i++) {
		*d++ = color->red;
		*d++ = color->green;
		*d++ = color->blue;
		*d++ = 0xff;
	    }
	    for (i = 1; i < image->height; i++, d += image->width*4) {
		memcpy(d, image->data, image->width*4);
	    }
	} else {
	    unsigned char *d = image->data;
	    int i;
	    
	    for (i = 0; i < image->width; i++) {
		*d++ = color->red;
		*d++ = color->green;
		*d++ = color->blue;
	    }
	    for (i = 1; i < image->height; i++, d += image->width*3) {
		memcpy(d, image->data, image->width*3);
	    }
	}
    } else {
	int bytes = image->width*image->height;
	int i;
	unsigned char *d;
	int alpha, nalpha, r, g, b;

	d = image->data;

	alpha = color->alpha;
	r = color->red * alpha;
	g = color->green * alpha;
	b = color->blue * alpha;
	nalpha = 255 - alpha;

	for (i=0; i<bytes; i++) {
	    *d = (((int)*d * nalpha) + r)/256;
	    d++;
	    *d = (((int)*d * nalpha) + g)/256;
	    d++;
	    *d = (((int)*d * nalpha) + b)/256;
	    d++;
	    if (image->format == RRGBAFormat) {
		d++;
	    }
	}
    }
#endif
}

const char*
RMessageForError(int errorCode)
{
    switch (errorCode) {
     case RERR_NONE:
	return "no error";

     case RERR_OPEN:
	return "could not open file";

     case RERR_READ:
	return "error reading from file";

     case RERR_WRITE:
	return "error writing to file";

     case RERR_NOMEMORY:
	return "out of memory";

     case RERR_NOCOLOR:
	return "out of color cells";

     case RERR_BADIMAGEFILE:
	return "invalid or corrupted image file";

     case RERR_BADFORMAT:
	return "the image format in the file is not supported and can't be loaded";

     case RERR_BADINDEX:
	return "image file does not contain requested image index";

     case RERR_BADVISUALID:
	return "request for an invalid visual ID";

     case RERR_STDCMAPFAIL:
	return "failed to create standard colormap";

     case RERR_XERROR:
	return "internal X error";

     default:
     case RERR_INTERNAL:
	return "internal error";
    }
}
