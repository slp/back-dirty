/*
copyright 2002 Alexander Malmberg <alexander@malmberg.org>

   This file is part of GNUstep.

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

#include <math.h>

#include <Foundation/NSObject.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSPathUtilities.h>
#include <Foundation/NSFileManager.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSDebug.h>
#include <AppKit/GSFontInfo.h>
#include <AppKit/NSAffineTransform.h>

//#include "gsc/GSContext.h"
#include "gsc/GSGState.h"

#include "ftfont.h"

#include "blit.h"


#define DI (*di)


/** font handling interface **/

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_CACHE_H

#include FT_CACHE_IMAGE_H
#include FT_CACHE_SMALL_BITMAPS_H
#include FT_CACHE_CHARMAP_H

#include FT_OUTLINE_H


/*
from the back-art-subpixel-text defaults key
0: normal rendering
1: subpixel, rgb
2: subpixel, bgr
*/
static int subpixel_text;


@interface FTFontInfo : GSFontInfo <FTFontInfo>
{
  const char *filename;
  FTC_ImageDesc imgd;

  FTC_ImageDesc fallback;
}
@end


@interface FTFontInfo_subpixel : FTFontInfo
@end


static NSMutableArray *fcfg_allFontNames;
static NSMutableDictionary *fcfg_allFontFamilies;
static NSMutableDictionary *fcfg_all_fonts;


static NSMutableSet *families_seen, *families_pending;


@interface FTFaceInfo : NSObject
{
@public
  NSArray *files;
  int weight;
  unsigned int traits;
}
@end

@implementation FTFaceInfo

-(NSString *) description
{
  return [NSString stringWithFormat: @"<FTFaceInfo %p: %@ %i %i>",
    self, files, weight, traits];
}

@end


static int traits_from_string(NSString *s, unsigned int *traits, unsigned int *weight)
{
static struct
{
  NSString *str;
  unsigned int trait;
  int weight;
} suffix[] = {
/* TODO */
{@"Normal"         ,0                         ,-1},

{@"Ultralight"     ,0                         , 1},
{@"Thin"           ,0                         , 2},
{@"Light"          ,0                         , 3},
{@"Extralight"     ,0                         , 3},
{@"Book"           ,0                         , 4},
{@"Regular"        ,0                         , 5},
{@"Plain"          ,0                         , 5},
{@"Display"        ,0                         , 5},
{@"Roman"          ,0                         , 5},
{@"Semilight"      ,0                         , 5},
{@"Medium"         ,0                         , 6},
{@"Demi"           ,0                         , 7},
{@"Demibold"       ,0                         , 7},
{@"Semi"           ,0                         , 8},
{@"Semibold"       ,0                         , 8},
{@"Bold"           ,NSBoldFontMask            , 9},
{@"Extra"          ,NSBoldFontMask            ,10},
{@"Extrabold"      ,NSBoldFontMask            ,10},
{@"Heavy"          ,NSBoldFontMask            ,11},
{@"Heavyface"      ,NSBoldFontMask            ,11},
{@"Ultrabold"      ,NSBoldFontMask            ,12},
{@"Black"          ,NSBoldFontMask            ,12},
{@"Ultra"          ,NSBoldFontMask            ,13},
{@"Ultrablack"     ,NSBoldFontMask            ,13},
{@"Fat"            ,NSBoldFontMask            ,13},
{@"Extrablack"     ,NSBoldFontMask            ,14},
{@"Obese"          ,NSBoldFontMask            ,14},
{@"Nord"           ,NSBoldFontMask            ,14},

{@"Italic"         ,NSItalicFontMask          ,-1},

{@"Cond"           ,NSCondensedFontMask       ,-1},
{@"Condensed"      ,NSCondensedFontMask       ,-1},
{nil,0,-1}
};
  int i;

  *weight = 5;
  *traits = 0;
//  printf("do '%@'\n", s);
  while ([s length] > 0)
    {
//      printf("  got '%@'\n", s);
      if ([s hasSuffix: @"-"])
	{
//	  printf("  do -\n");
	  s = [s substringToIndex: [s length] - 1];
	  continue;
	}
      for (i = 0; suffix[i].str; i++)
	{
	  if (![s hasSuffix: suffix[i].str])
	    continue;
//	  printf("  found '%@'\n", suffix[i].str);
	  if (suffix[i].weight != -1)
	    *weight = suffix[i].weight;
	  (*traits) |= suffix[i].trait;
	  s = [s substringToIndex: [s length] - [suffix[i].str length]];
	  break;
	}
      if (!suffix[i].str)
	break;
    }
//  printf("end up with '%@'\n", s);
  return [s length];
}


static void add_face(NSString *family, NSString *face, NSDictionary *d,
	NSString *path, BOOL valid_face)
{
  FTFaceInfo *fi;
  int weight;
  unsigned int traits;
  NSString *full_name;

//  printf("'%@'-'%@' |%@|\n", family, face, d);

  if (valid_face)
    {
      int p;
      if ([face isEqual: @"Normal"])
	full_name = family;
      else
	full_name = [NSString stringWithFormat: @"%@-%@", family, face];
      p = traits_from_string(face, &traits, &weight);
/*      if (p > 0)
	NSLog(@"failed to split: %@ to %i %04x %i", face, p, traits, weight);
      else
	NSLog(@"got %04x %i for %@", traits, weight, face);*/
    }
  else
    {
      int p = traits_from_string(family, &traits, &weight);
      full_name = family;
      if (p > 0)
	{
	  face = [family substringFromIndex: p];
	  family = [family substringToIndex: p];
	  if ([face length] <= 0)
	    face = @"Normal";
	  else
	    full_name = [NSString stringWithFormat: @"%@-%@", family, face];
	}
      else
	face = @"Normal";

      if ([families_seen member: family])
	{
//	  NSLog(@"#2 already seen %@", family);
	  return;
	}
      [families_pending addObject: family];
//      NSLog(@"split %@ to '%@' '%@' %04x %i", full_name, family, face, traits, weight);
    }

  if ([fcfg_allFontNames containsObject: full_name])
    return;

  fi = [[FTFaceInfo alloc] init];

    {
      NSArray *files = [d objectForKey: @"Files"];
      int i, c = [files count];

      if (!files)
	{
	  NSLog(@"No filename specified for font '%@'!", full_name);
	  DESTROY(fi);
	  return;
	}

      fi->files = [[NSMutableArray alloc] init];
      for (i = 0; i < c; i++)
	{
	  [(NSMutableArray *)fi->files addObject:
	    [path stringByAppendingPathComponent:
	      [files objectAtIndex: i]]];
	}
    }

  if ([d objectForKey: @"Weight"])
    weight = [[d objectForKey: @"Weight"] intValue];
  fi->weight = weight;

  if ([d objectForKey: @"Traits"])
    traits = [[d objectForKey: @"Traits"] intValue];
  fi->traits = traits;

  NSDebugLLog(@"ftfont", @"adding '%@' '%@'", full_name, fi);

//  printf("'%@'  fi=|%@|\n", full_name, fi);
  [fcfg_all_fonts setObject: fi forKey: full_name];
  [fcfg_allFontNames addObject: full_name];

    {
      NSArray *a;
      NSMutableArray *ma;
      a = [NSArray arrayWithObjects:
	full_name,
	face,
	[NSNumber numberWithInt: weight],
	[NSNumber numberWithUnsignedInt: traits],
	nil];
      ma = [fcfg_allFontFamilies objectForKey: family];
      if (!ma)
	{
	  ma = [[NSMutableArray alloc] init];
	  [fcfg_allFontFamilies setObject: ma forKey: family];
	  [ma release];
	}
      [ma addObject: a];
    }

  DESTROY(fi);
}


static void load_font_configuration(void)
{
  int i, j, c;
  NSArray *paths;
  NSString *path, *font_path;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *files;
  NSDictionary *d;

  fcfg_all_fonts = [[NSMutableDictionary alloc] init];
  fcfg_allFontFamilies = [[NSMutableDictionary alloc] init];
  fcfg_allFontNames = [[NSMutableArray alloc] init];

  families_seen = [[NSMutableSet alloc] init];
  families_pending = [[NSMutableSet alloc] init];

  paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask, YES);
  for (i = 0; i < [paths count]; i++)
    {
      path = [paths objectAtIndex: i];
      path = [path stringByAppendingPathComponent: @"Fonts"];
//      printf("try %@\n", path);
      files = [fm directoryContentsAtPath: path];
      c = [files count];

      for (j = 0; j < c; j++)
	{
	  NSString *family, *face;
	  NSEnumerator *e;
	  NSDictionary *face_info;
	  NSString *font_info_path;

	  font_path = [files objectAtIndex: j];
	  if (![[font_path pathExtension] isEqual: @"nfont"])
	    continue;

	  family = [font_path stringByDeletingPathExtension];

	  if ([families_seen member: family])
	    {
	      NSDebugLLog(@"ftfont", @"'%@' already seen, skipping", family);
	      continue;
	    }
	  [families_seen addObject: family];

	  font_path = [path stringByAppendingPathComponent: font_path];

	  font_info_path = [font_path stringByAppendingPathComponent: @"FontInfo.plist"];
	  if (![fm fileExistsAtPath: font_info_path])
	    continue;
	  d = [NSDictionary dictionaryWithContentsOfFile: font_info_path];
	  if (!d)
	    continue;
	  d = [d objectForKey: @"Faces"];

	  e = [d keyEnumerator];
	  while ((face = [e nextObject]))
	    {
	      face_info = [d objectForKey: face];
	      if ([face_info isKindOfClass: [NSString class]])
		face_info = [NSArray arrayWithObject: face_info];
	      if ([face_info isKindOfClass: [NSArray class]])
		face_info = [NSDictionary dictionaryWithObject: face_info
		                                      forKey: @"Files"];

	      add_face(family, face, face_info, font_path, YES);
	    }
	}

      for (j = 0; j < c; j++)
	{
	  NSString *family;

	  font_path = [files objectAtIndex: j];
	  if (![[font_path pathExtension] isEqual: @"font"])
	    continue;

	  family = [font_path stringByDeletingPathExtension];
	  font_path = [path stringByAppendingPathComponent: font_path];
	  d = [NSDictionary dictionaryWithObject:
	    [NSArray arrayWithObjects:
	      family,
	      [family stringByAppendingPathExtension: @"afm"],
	      nil]
	    forKey: @"Files"];
	  add_face(family, nil, d, font_path, NO);
	}
      [families_seen unionSet: families_pending];
      [families_pending removeAllObjects];
    }

  NSDebugLLog(@"ftfont", @"got %i fonts in %i families",
    [fcfg_allFontNames count], [fcfg_allFontFamilies count]);

  if (![fcfg_allFontNames count])
    {
      NSLog(@"No fonts found!");
      exit(1);
    }

  DESTROY(families_seen);
  DESTROY(families_pending);
}


@interface FTFontEnumerator : GSFontEnumerator
@end

@implementation FTFontEnumerator
- (void) enumerateFontsAndFamilies
{
  ASSIGN(allFontNames, fcfg_allFontNames);
  ASSIGN(allFontFamilies, fcfg_allFontFamilies);
}
@end


static FT_Library ft_library;
static FTC_Manager ftc_manager;
static FTC_ImageCache ftc_imagecache;
static FTC_SBitCache ftc_sbitcache;
static FTC_CMapCache ftc_cmapcache;


static FT_Error ft_get_face(FTC_FaceID fid, FT_Library lib, FT_Pointer data, FT_Face *pface)
{
  FT_Error err;
  NSArray *rfi = (NSArray *)fid;
  int i, c = [rfi count];

//	NSLog(@"ft_get_face: %@ '%s'", rfi, [[rfi objectAtIndex: 0] cString]);

  err = FT_New_Face(lib, [[rfi objectAtIndex: 0] cString], 0, pface);
  if (err)
    {
      NSLog(@"Error when loading '%@' (%08x)", [rfi objectAtIndex: 0], err);
      return err;
    }

  for (i = 1; i < c; i++)
    {
//		NSLog(@"   do '%s'", [[rfi objectAtIndex: i] cString]);
      err = FT_Attach_File(*pface, [[rfi objectAtIndex: i] cString]);
      if (err)
	{
	  NSLog(@"Error when loading '%@' (%08x)", [rfi objectAtIndex: i], err);
	  /* pretend it's alright */
	}
    }
  return 0;
}


@implementation FTFontInfo
- initWithFontName: (NSString*)name matrix: (const float *)fmatrix
{
  FT_Face face;
  FT_Size size;
  NSArray *rfi;
  FTFaceInfo *font_entry;

  if (subpixel_text)
    {
      [self release];
      self = [FTFontInfo_subpixel alloc];
    }

  self = [super init];


  NSDebugLLog(@"ftfont", @"[%@ -initWithFontName: %@  matrix: (%g %g %g %g %g %g)]\n",
	      self, name,
	      fmatrix[0], fmatrix[1], fmatrix[2],
	      fmatrix[3], fmatrix[4], fmatrix[5]);

  font_entry = [fcfg_all_fonts objectForKey: name];
  if (!font_entry)
    {
      font_entry = [fcfg_all_fonts objectForKey: [fcfg_allFontNames objectAtIndex: 0]];
      NSLog(@"Warning: can't find font '%@', falling back to '%@'",
	    name, [fcfg_allFontNames objectAtIndex: 0]);
    }

  rfi = font_entry->files;
  weight = font_entry->weight;
  traits = font_entry->traits;

  fontName = [name copy];
  memcpy(matrix, fmatrix, sizeof(matrix));

  /* TODO: somehow make gnustep-gui send unicode our way. utf8? ugly, but it works */
  mostCompatibleStringEncoding = NSUTF8StringEncoding;
  encodingScheme = @"iso10646-1";

  imgd.font.pix_width = matrix[0];
  imgd.font.pix_height = matrix[3];
  imgd.font.face_id = (FTC_FaceID)rfi;

  /* TODO: make this configurable */
/*	fallback = imgd;
	fallback.font.face_id = @"/usr/local/share/fonts/truetype/CODE2000.TTF";*/


  if (FTC_Manager_Lookup_Size(ftc_manager, &imgd.font, &face, &size))
    {
      NSLog(@"FTC_Manager_Lookup_Size failed for '%@'!\n", name);
      return self;
    }

//	xHeight = size->metrics.height / 64.0;
  ascender = fabs(size->metrics.ascender / 64.0);
  descender = fabs(size->metrics.descender / 64.0);
  xHeight = ascender + descender; /* TODO */
  maximumAdvancement = NSMakeSize((size->metrics.max_advance / 64.0), ascender + descender);

  fontBBox = NSMakeRect(0, descender, maximumAdvancement.width, ascender + descender);
  descender = -descender;

/*	printf("h=%g  a=%g d=%g  max=(%g %g)  (%g %g)+(%g %g)\n",
		xHeight, ascender, descender,
		maximumAdvancement.width, maximumAdvancement.height,
		fontBBox.origin.x, fontBBox.origin.y,
		fontBBox.size.width, fontBBox.size.height);*/

  return self;
}

-(void) set
{
  NSLog(@"ignore -set method of font '%@'\n", fontName);
}


extern void GSToUnicode();

/* TODO: the current point probably needs updating after drawing is done */

-(void) drawString: (const char *)s
	at: (int)x:(int)y
	to: (int)x0:(int)y0:(int)x1:(int)y1:(unsigned char *)buf:(int)bpl
	color:(unsigned char)r:(unsigned char)g:(unsigned char)b:(unsigned char)alpha
	transform: (NSAffineTransform *)transform
	deltas: (const float *)delta_data : (int)delta_size : (int)delta_flags;
{
/* TODO */
}


-(void) drawString: (const char *)s
	at: (int)x : (int)y
	to: (int)x0 : (int)y0 : (int)x1 : (int)y1 : (unsigned char *)buf : (int)bpl
	color:(unsigned char)r : (unsigned char)g : (unsigned char)b : (unsigned char)alpha
	transform: (NSAffineTransform *)transform
	drawinfo: (draw_info_t *)di
{
#if 0
  NSLog(@"ignoring drawString");
#else
  const unsigned char *c;
  unsigned char ch;
  unsigned int uch;

  FTC_CMapDescRec cmap;
  unsigned int glyph;

  int use_sbit;

  FTC_SBit sbit;
  FTC_ImageDesc cur;

  FT_Matrix ftmatrix;
  FT_Vector ftdelta;


  if (!alpha)
    return;

  /* TODO: if we had guaranteed upper bounds on glyph image size we
     could do some basic clipping here */

  x1 -= x0;
  y1 -= y0;
  x -= x0;
  y -= y0;


/*	NSLog(@"[%@ draw using matrix: (%g %g %g %g %g %g)]\n",
		self,
		matrix[0], matrix[1], matrix[2],
		matrix[3], matrix[4], matrix[5]
		);*/

  cur = imgd;
  {
    float xx, xy, yx, yy;

    xx = matrix[0] * transform->matrix.m11 + matrix[1] * transform->matrix.m21;
    yx = matrix[0] * transform->matrix.m12 + matrix[1] * transform->matrix.m22;
    xy = matrix[2] * transform->matrix.m11 + matrix[3] * transform->matrix.m21;
    yy = matrix[2] * transform->matrix.m12 + matrix[3] * transform->matrix.m22;

    /* if we're drawing 'normal' text (unscaled, unrotated, reasonable
       size), we can and should use the sbit cache */
    if (fabs(xx - ((int)xx)) < 0.01 && fabs(yy - ((int)yy)) < 0.01 &&
	fabs(xy) < 0.01 && fabs(yx) < 0.01 &&
	xx < 72 && yy < 72 && xx > 0.5 && yy > 0.5)
      {
	use_sbit = 1;
	cur.font.pix_width = xx;
	cur.font.pix_height = yy;

	if (cur.font.pix_width < 16 && cur.font.pix_height < 16 &&
	    cur.font.pix_width > 6 && cur.font.pix_height > 6)
	  cur.type = ftc_image_mono;
	else
	  cur.type = ftc_image_grays;
//			imgd.type|=|ftc_image_flag_unhinted; /* TODO? when? */
      }
    else
      {
	float f;
	use_sbit = 0;

	f = fabs(xx * yy - xy * yx);
	if (f > 1)
	  f = sqrt(f);
	else
	  f = 1.0;

	f = (int)f;

	cur.font.pix_width = cur.font.pix_height = f;
	ftmatrix.xx = xx / f * 65536.0;
	ftmatrix.xy = xy / f * 65536.0;
	ftmatrix.yx = yx / f * 65536.0;
	ftmatrix.yy = yy / f * 65536.0;
	ftdelta.x = ftdelta.y = 0;
      }
  }


/*	NSLog(@"drawString: '%s' at: %i:%i  to: %i:%i:%i:%i:%p\n",
		s, x, y, x0, y0, x1, y1, buf);*/

  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  for (c = s; *c; c++)
    {
/* TODO: do the same thing in outlineString:... */
      ch = *c;
      if (ch < 0x80)
	{
	  uch = ch;
	}
      else if (ch < 0xc0)
	{
	  uch = 0xfffd;
	}
      else if (ch < 0xe0)
	{
#define ADD_UTF_BYTE(shift, internal) \
  ch = *++c; \
  if (ch >= 0x80 && ch < 0xc0) \
    { \
      uch |= (ch & 0x3f) << shift; \
      internal \
    } \
  else \
    { \
      uch = 0xfffd; \
      c--; \
    }

	  uch = (ch & 0x1f) << 6;
	  ADD_UTF_BYTE(0, )
	}
      else if (ch < 0xf0)
	{
	  uch = (ch & 0x0f) << 12;
	  ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, ))
	}
      else if (ch < 0xf8)
	{
	  uch = (ch & 0x07) << 18;
	  ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, )))
	}
      else if (ch < 0xfc)
	{
	  uch = (ch & 0x03) << 24;
	  ADD_UTF_BYTE(18, ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, ))))
	}
      else if (ch < 0xfe)
	{
	  uch = (ch & 0x01) << 30;
	  ADD_UTF_BYTE(24, ADD_UTF_BYTE(18, ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, )))))
	}
      else
	uch = 0xfffd;
#undef ADD_UTF_BYTE

      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, uch);
      cur.font.face_id = imgd.font.face_id;
      if (!glyph)
	{
	  cmap.face_id = fallback.font.face_id;
	  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, uch);
	  if (glyph)
	    cur.font.face_id = fallback.font.face_id;
	  cmap.face_id = imgd.font.face_id;
	}

      if (use_sbit)
	{
	  if (FTC_SBitCache_Lookup(ftc_sbitcache, &cur, glyph, &sbit, NULL))
	    continue;

	  if (!sbit->buffer)
	    {
	      x += sbit->xadvance;
	      continue;
	    }

	  if (sbit->format == ft_pixel_mode_grays)
	    {
	      int gx = x + sbit->left, gy = y - sbit->top;
	      int sbpl = sbit->pitch;
	      int sx = sbit->width, sy = sbit->height;
	      const unsigned char *src = sbit->buffer;
	      unsigned char *dst = buf;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (gx < 0)
		{
		  sx += gx;
		  src -= gx;
		  gx = 0;
		}
	      else if (gx > 0)
		{
		  dst += DI.bytes_per_pixel * gx;
		}

	      sx += gx;
	      if (sx > x1)
		sx = x1;
	      sx -= gx;

	      if (sx > 0)
		{
		  if (alpha >= 255)
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA_OPAQUE(dst, src, r, g, b, sx);
		  else
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA(dst, src, r, g, b, alpha, sx);
		}
	    }
	  else if (sbit->format == ft_pixel_mode_mono)
	    {
	      int gx = x + sbit->left, gy = y - sbit->top;
	      int sbpl = sbit->pitch;
	      int sx = sbit->width, sy = sbit->height;
	      const unsigned char *src = sbit->buffer;
	      unsigned char *dst = buf;
	      int src_ofs = 0;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (gx < 0)
		{
		  sx += gx;
		  src -= gx / 8;
		  src_ofs = (-gx) & 7;
		  gx = 0;
		}
	      else if (gx > 0)
		{
		  dst += DI.bytes_per_pixel * gx;
		}

	      sx += gx;
	      if (sx > x1)
		sx = x1;
	      sx -= gx;

	      if (sx > 0)
		{
		  if (alpha >= 255)
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_MONO_OPAQUE(dst, src, src_ofs, r, g, b, sx);
		  else
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_MONO(dst, src, src_ofs, r, g, b, alpha, sx);
		}
	    }
	  else
	    {
	      NSLog(@"unhandled font bitmap format %i", sbit->format);
	    }

	  x += sbit->xadvance;
	}
      else
	{
	  FT_Face face;
	  FT_Glyph gl;
	  FT_BitmapGlyph gb;

	  if (FTC_Manager_Lookup_Size(ftc_manager, &cur.font, &face, 0))
	    continue;

	  /* TODO: for rotations of 90, 180, 270, and integer
	     scales hinting might still be a good idea. */
	  if (FT_Load_Glyph(face, glyph, FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP))
	    continue;

	  if (FT_Get_Glyph(face->glyph, &gl))
	    continue;

	  if (FT_Glyph_Transform(gl, &ftmatrix, &ftdelta))
	    {
	      NSLog(@"glyph transformation failed!");
	      continue;
	    }
	  if (FT_Glyph_To_Bitmap(&gl, ft_render_mode_normal, 0, 1))
	    {
	      FT_Done_Glyph(gl);
	      continue;
	    }
	  gb = (FT_BitmapGlyph)gl;


	  if (gb->bitmap.pixel_mode == ft_pixel_mode_grays)
	    {
	      int gx = x + gb->left, gy = y - gb->top;
	      int sbpl = gb->bitmap.pitch;
	      int sx = gb->bitmap.width, sy = gb->bitmap.rows;
	      const unsigned char *src = gb->bitmap.buffer;
	      unsigned char *dst = buf;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (gx < 0)
		{
		  sx += gx;
		  src -= gx;
		  gx = 0;
		}
	      else if (gx > 0)
		{
		  dst += DI.bytes_per_pixel * gx;
		}

	      sx += gx;
	      if (sx > x1)
		sx = x1;
	      sx -= gx;

	      if (sx > 0)
		{
		  if (alpha >= 255)
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA_OPAQUE(dst, src, r, g, b, sx);
		  else
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA(dst, src, r, g, b, alpha, sx);
		}
	    }
/* TODO: will this case ever appear? */
/*			else if (gb->bitmap.pixel_mode==ft_pixel_mode_mono)*/
	  else
	    {
	      NSLog(@"unhandled font bitmap format %i", gb->bitmap.pixel_mode);
	    }

	  ftdelta.x += gl->advance.x >> 10;
	  ftdelta.y += gl->advance.y >> 10;

	  FT_Done_Glyph(gl);
	}
    }

#endif
}


- (NSSize) advancementForGlyph: (NSGlyph)aGlyph
{
  FTC_CMapDescRec cmap;
  unsigned int glyph;

  FT_Glyph g;

  FTC_ImageDesc *cur;

  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  cur = &imgd;
  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, aGlyph);
  if (!glyph)
    {
      cmap.face_id = fallback.font.face_id;
      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, aGlyph);
      if (glyph)
	cur = &fallback;
    }

  if (FTC_ImageCache_Lookup(ftc_imagecache, cur, glyph, &g, NULL))
    {
//		NSLog(@"advancementForGlyph: %04x -> %i not found\n", aGlyph, glyph);
      return NSZeroSize;
    }

/*	NSLog(@"advancementForGlyph: %04x -> %i  %08xx%08x\n",
		aGlyph, glyph, g->advance.x, g->advance.y);*/

  return NSMakeSize(g->advance.x / 65536.0, g->advance.y / 65536.0);
}

- (NSRect) boundingRectForGlyph: (NSGlyph)aGlyph
{
  FTC_CMapDescRec cmap;
  FTC_ImageDesc *cur;
  unsigned int glyph;
  FT_BBox bbox;

  FT_Glyph g;

  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  cur = &imgd;
  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, aGlyph);
  if (!glyph)
    {
      cmap.face_id = fallback.font.face_id;
      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, aGlyph);
      if (glyph)
	cur = &fallback;
    }

  if (FTC_ImageCache_Lookup(ftc_imagecache, cur, glyph, &g, NULL))
    {
//		NSLog(@"boundingRectForGlyph: %04x -> %i\n", aGlyph, glyph);
      return fontBBox;
    }

  FT_Glyph_Get_CBox(g, ft_glyph_bbox_gridfit, &bbox);

/*	printf("got cbox for %04x: %i, %i - %i, %i\n",
		aGlyph, bbox.xMin, bbox.yMin, bbox.xMax, bbox.yMax);*/

  return NSMakeRect(bbox.xMin / 64.0, bbox.yMin / 64.0,
		    (bbox.xMax - bbox.xMin) / 64.0, (bbox.yMax - bbox.yMin) / 64.0);
}

- (float) widthOfString: (NSString*)string
{
  unichar ch;
  int i, c = [string length];
  int total;

  FTC_CMapDescRec cmap;
  unsigned int glyph;

  FTC_SBit sbit;

  FTC_ImageDesc *cur;


  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  total = 0;
  for (i = 0; i < c; i++)
    {
      ch = [string characterAtIndex: i];
      cur = &imgd;
      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, ch);
      if (!glyph)
	{
	  cmap.face_id = fallback.font.face_id;
	  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, ch);
	  if (glyph)
	    cur = &fallback;
	  cmap.face_id = imgd.font.face_id;
	}

      /* TODO: shouldn't use sbit cache for this */
      if (1)
	{
	  if (FTC_SBitCache_Lookup(ftc_sbitcache, cur, glyph, &sbit, NULL))
	    continue;

	  total += sbit->xadvance;
	}
      else
	{
	  NSLog(@"non-sbit code not implemented");
	}
    }
  return total;
}



/*

conic: (a,b,c)
p=(1-t)^2*a + 2*(1-t)*t*b + t^2*c

cubic: (a,b,c,d)
p=(1-t)^3*a + 3*(1-t)^2*t*b + 3*(1-t)*t^2*c + t^3*d



p(t)=(1-t)^3*a + 3*(1-t)^2*t*b + 3*(1-t)*t^2*c + t^3*d
t=m+ns=
n=l-m


q(s)=p(m+ns)=

(d-3c+3b-a)*n^3 * s^3 +
((3d-9c+9b-3a)*m+3c-6b+3a)*n^2 * s^2 +
((3d-9c+9b-3a)*m^2+(6c-12b+6a)*m+3b-3a)*n * s +
(d-3c+3b-a)*m^3+(3c-6b+3a)*m^2+(3b-3a)m+a


q(t)=(1-t)^3*aa + 3*(1-t)^2*t*bb + 3*(1-t)*t^2*cc + t^3*dd =

(dd-3cc+3bb-aa)*t^3 +
(3cc-6bb+3aa)*t^2 +
(3bb-3aa)*t +
aa


aa = (d-3*c+3*b-a)*m^3+(3*c-6*b+3*a)*m^2+(3*b-3*a)*m+a
3*bb-3*aa = ((3*d-9*c+9*b-3*a)*m^2+(6*c-12*b+6*a)*m+3*b-3*a)*n
3*cc-6*bb+3*aa = ((3*d-9*c+9*b-3*a)*m+3*c-6*b+3*a)*n^2
dd-3*cc+3*bb-aa = (d-3*c+3*b-a)*n^3


aa= (d - 3c + 3b - a) m^3  + (3c - 6b + 3a) m^2  + (3b - 3a) m + a

bb= (( d - 3c + 3b -  a) m^2  + (2c - 4b + 2a) m +  b -  a) n
  + aa

cc= ((d - 3c + 3b - a) m + c - 2b + a) n^2
 + 2*bb
 + aa

dd= (d - 3c + 3b - a) n^3
 + 3*cc
 + 3*bb
 + aa




p(t) = (1-t)^2*e + 2*(1-t)*t*f + t^2*g
 ~=
q(t) = (1-t)^3*a + 3*(1-t)^2*t*b + 3*(1-t)*t^2*c + t^3*d


p(0)=q(0) && p(1)=q(1) ->
a=e
d=g


p(0.5) = 1/8*(2a + 4f + 2d)
q(0.5) = 1/8*(a + 3*b + 3*c + d)

b+c=1/3*(a+4f+d)

p(1/4) = 1/64*
p(3/4) = 1/64*( 4e+24f+36g)

q(1/4) = 1/64*
q(3/4) = 1/64*(  a +  9b + 27c + 27d)

3b+c=1/3*(3a+8f+d)


3b+c=1/3*(3a+8f+d)
 b+c=1/3*(a+4f+d)

b=1/3*(e+2f)
c=1/3*(2f+g)


q(t) = (1-t)^3*e + (1-t)^2*t*(e+2f) + (1-t)*t^2*(2f+g) + t^3*g =
((1-t)^3+(1-t)^2*t)*e + (1-t)^2*t*2f + (1-t)*t^2*2f + (t^3+(1-t)*t^2)*g =

((1-t)^3+(1-t)^2*t)*e + 2f*(t*(1-t)*( (1-t)+t)) + (t^3+(1-t)*t^2)*g =
((1-t)^3+(1-t)^2*t)*e + 2*(1-t)*t*f + (t^3+(1-t)*t^2)*g =
(1-t)^2*e + 2*(1-t)*t*f + t^2*g

p(t)=q(t)

*/

static int charpath_move_to(FT_Vector *to, void *user)
{
  GSGState *self = (GSGState *)user;
  NSPoint d;
  d.x = to->x / 65536.0;
  d.y = to->y / 65536.0;
  [self DPSclosepath]; /* TODO: this isn't completely correct */
  [self DPSmoveto: d.x:d.y];
  return 0;
}

static int charpath_line_to(FT_Vector *to, void *user)
{
  GSGState *self = (GSGState *)user;
  NSPoint d;
  d.x = to->x / 65536.0;
  d.y = to->y / 65536.0;
  [self DPSlineto: d.x:d.y];
  return 0;
}

static int charpath_conic_to(FT_Vector *c1, FT_Vector *to, void *user)
{
  GSGState *self = (GSGState *)user;
  NSPoint a, b, c, d;
  [self DPScurrentpoint: &a.x:&a.y];
  d.x = to->x / 65536.0;
  d.y = to->y / 65536.0;
  b.x = c1->x / 65536.0;
  b.y = c1->y / 65536.0;
  c.x = (b.x * 2 + d.x) / 3.0;
  c.y = (b.y * 2 + d.y) / 3.0;
  b.x = (b.x * 2 + a.x) / 3.0;
  b.y = (b.y * 2 + a.y) / 3.0;
  [self DPScurveto: b.x:b.y : c.x:c.y : d.x:d.y];
  return 0;
}

static int charpath_cubic_to(FT_Vector *c1, FT_Vector *c2, FT_Vector *to, void *user)
{
  GSGState *self = (GSGState *)user;
  NSPoint b, c, d;
  b.x = c1->x / 65536.0;
  b.y = c1->y / 65536.0;
  c.x = c2->x / 65536.0;
  c.y = c2->y / 65536.0;
  d.x = to->x / 65536.0;
  d.y = to->y / 65536.0;
  [self DPScurveto: b.x:b.y : c.x:c.y : d.x:d.y];
  return 0;
}


static FT_Outline_Funcs funcs = {
move_to:charpath_move_to,
line_to:charpath_line_to,
conic_to:charpath_conic_to,
cubic_to:charpath_cubic_to,
shift:10,
delta:0,
};


/* TODO: sometimes gets 'glyph transformation failed', probably need to
add code to avoid loading bitmaps for glyphs */
-(void) outlineString: (const char *)s
		   at: (float)x : (float)y
	       gstate: (void *)func_param
{
  unichar *c;
  int i;
  FTC_CMapDescRec cmap;
  unsigned int glyph;

  unichar *uch;
  int ulen;

  FTC_ImageDesc cur;


  FT_Matrix ftmatrix;
  FT_Vector ftdelta;

  ftmatrix.xx = 65536;
  ftmatrix.xy = 0;
  ftmatrix.yx = 0;
  ftmatrix.yy = 65536;
  ftdelta.x = x * 64.0;
  ftdelta.y = y * 64.0;


  uch = NULL;
  ulen = 0;
  GSToUnicode(&uch, &ulen, s, strlen(s), NSUTF8StringEncoding, NSDefaultMallocZone(), 0);


  cur = imgd;

  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  for (c = uch, i = 0; i < ulen; i++, c++)
    {
      FT_Face face;
      FT_Glyph gl;
      FT_OutlineGlyph og;

      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, *c);
      cur.font.face_id = imgd.font.face_id;
      if (!glyph)
	{
	  cmap.face_id = fallback.font.face_id;
	  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, *c);
	  if (glyph)
	    cur.font.face_id = fallback.font.face_id;
	  cmap.face_id = imgd.font.face_id;
	}

      if (FTC_Manager_Lookup_Size(ftc_manager, &cur.font, &face, 0))
	continue;
      if (FT_Load_Glyph(face, glyph, FT_LOAD_DEFAULT))
	continue;

      if (FT_Get_Glyph(face->glyph, &gl))
	continue;

      if (FT_Glyph_Transform(gl, &ftmatrix, &ftdelta))
	{
	  NSLog(@"glyph transformation failed!");
	  continue;
	}
      og = (FT_OutlineGlyph)gl;

      ftdelta.x += gl->advance.x >> 10;
      ftdelta.y += gl->advance.y >> 10;

      FT_Outline_Decompose(&og->outline, &funcs, func_param);

      FT_Done_Glyph(gl);

    }

  free(uch);
}


+(void) initializeBackend
{
  [GSFontEnumerator setDefaultClass: [FTFontEnumerator class]];
  [GSFontInfo setDefaultClass: [FTFontInfo class]];

  if (FT_Init_FreeType(&ft_library))
    NSLog(@"FT_Init_FreeType failed");
  if (FTC_Manager_New(ft_library, 0, 0, 4096 * 24, ft_get_face, 0, &ftc_manager))
    NSLog(@"FTC_Manager_New failed");
  if (FTC_SBitCache_New(ftc_manager, &ftc_sbitcache))
    NSLog(@"FTC_SBitCache_New failed");
  if (FTC_ImageCache_New(ftc_manager, &ftc_imagecache))
    NSLog(@"FTC_ImageCache_New failed");
  if (FTC_CMapCache_New(ftc_manager, &ftc_cmapcache))
    NSLog(@"FTC_CMapCache_New failed");

  load_font_configuration();

  subpixel_text = [[NSUserDefaults standardUserDefaults]
    integerForKey: @"back-art-subpixel-text"];
}


@end


@implementation FTFontInfo_subpixel

-(void) drawString: (const char *)s
	at: (int)x : (int)y
	to: (int)x0 : (int)y0 : (int)x1 : (int)y1 : (unsigned char *)buf : (int)bpl
	color:(unsigned char)r : (unsigned char)g : (unsigned char)b : (unsigned char)alpha
	transform: (NSAffineTransform *)transform
	drawinfo: (draw_info_t *)di
{
  const unsigned char *c;
  unsigned char ch;
  unsigned int uch;

  FTC_CMapDescRec cmap;
  unsigned int glyph;

  int use_sbit;

  FTC_SBit sbit;
  FTC_ImageDesc cur;

  FT_Matrix ftmatrix;
  FT_Vector ftdelta;

  BOOL subpixel = NO;


  if (!alpha)
    return;

  /* TODO: if we had guaranteed upper bounds on glyph image size we
     could do some basic clipping here */

  x1 -= x0;
  y1 -= y0;
  x -= x0;
  y -= y0;


/*	NSLog(@"[%@ draw using matrix: (%g %g %g %g %g %g)]\n",
		self,
		matrix[0], matrix[1], matrix[2],
		matrix[3], matrix[4], matrix[5]
		);*/

  cur = imgd;
  {
    float xx, xy, yx, yy;

    xx = matrix[0] * transform->matrix.m11 + matrix[1] * transform->matrix.m21;
    yx = matrix[0] * transform->matrix.m12 + matrix[1] * transform->matrix.m22;
    xy = matrix[2] * transform->matrix.m11 + matrix[3] * transform->matrix.m21;
    yy = matrix[2] * transform->matrix.m12 + matrix[3] * transform->matrix.m22;

    /* if we're drawing 'normal' text (unscaled, unrotated, reasonable
       size), we can and should use the sbit cache */
    if (fabs(xx - ((int)xx)) < 0.01 && fabs(yy - ((int)yy)) < 0.01 &&
	fabs(xy) < 0.01 && fabs(yx) < 0.01 &&
	xx < 72 && yy < 72 && xx > 0.5 && yy > 0.5)
      {
	use_sbit = 1;
	cur.font.pix_width = xx;
	cur.font.pix_height = yy;

/*	if (cur.font.pix_width < 16 && cur.font.pix_height < 16 &&
	    cur.font.pix_width > 6 && cur.font.pix_height > 6)
	  cur.type = ftc_image_mono;
	else*/
	  cur.type = ftc_image_grays, subpixel = YES, cur.font.pix_width *= 3, x *= 3;
//			imgd.type|=|ftc_image_flag_unhinted; /* TODO? when? */
      }
    else
      {
	float f;
	use_sbit = 0;

	f = fabs(xx * yy - xy * yx);
	if (f > 1)
	  f = sqrt(f);
	else
	  f = 1.0;

	f = (int)f;

	cur.font.pix_width = cur.font.pix_height = f;
	ftmatrix.xx = xx / f * 65536.0;
	ftmatrix.xy = xy / f * 65536.0;
	ftmatrix.yx = yx / f * 65536.0;
	ftmatrix.yy = yy / f * 65536.0;
	ftdelta.x = ftdelta.y = 0;
      }
  }


/*	NSLog(@"drawString: '%s' at: %i:%i  to: %i:%i:%i:%i:%p\n",
		s, x, y, x0, y0, x1, y1, buf);*/

  cmap.face_id = imgd.font.face_id;
  cmap.u.encoding = ft_encoding_unicode;
  cmap.type = FTC_CMAP_BY_ENCODING;

  for (c = s; *c; c++)
    {
/* TODO: do the same thing in outlineString:... */
      ch = *c;
      if (ch < 0x80)
	{
	  uch = ch;
	}
      else if (ch < 0xc0)
	{
	  uch = 0xfffd;
	}
      else if (ch < 0xe0)
	{
#define ADD_UTF_BYTE(shift, internal) \
  ch = *++c; \
  if (ch >= 0x80 && ch < 0xc0) \
    { \
      uch |= (ch & 0x3f) << shift; \
      internal \
    } \
  else \
    { \
      uch = 0xfffd; \
      c--; \
    }

	  uch = (ch & 0x1f) << 6;
	  ADD_UTF_BYTE(0, )
	}
      else if (ch < 0xf0)
	{
	  uch = (ch & 0x0f) << 12;
	  ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, ))
	}
      else if (ch < 0xf8)
	{
	  uch = (ch & 0x07) << 18;
	  ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, )))
	}
      else if (ch < 0xfc)
	{
	  uch = (ch & 0x03) << 24;
	  ADD_UTF_BYTE(18, ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, ))))
	}
      else if (ch < 0xfe)
	{
	  uch = (ch & 0x01) << 30;
	  ADD_UTF_BYTE(24, ADD_UTF_BYTE(18, ADD_UTF_BYTE(12, ADD_UTF_BYTE(6, ADD_UTF_BYTE(0, )))))
	}
      else
	uch = 0xfffd;
#undef ADD_UTF_BYTE

      glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, uch);
      cur.font.face_id = imgd.font.face_id;
      if (!glyph)
	{
	  cmap.face_id = fallback.font.face_id;
	  glyph = FTC_CMapCache_Lookup(ftc_cmapcache, &cmap, uch);
	  if (glyph)
	    cur.font.face_id = fallback.font.face_id;
	  cmap.face_id = imgd.font.face_id;
	}

      if (use_sbit)
	{
	  if (FTC_SBitCache_Lookup(ftc_sbitcache, &cur, glyph, &sbit, NULL))
	    continue;

	  if (!sbit->buffer)
	    {
	      x += sbit->xadvance;
	      continue;
	    }

	  if (sbit->format == ft_pixel_mode_grays)
	    {
	      int gx = x + sbit->left, gy = y - sbit->top;
	      int px0 = (gx - 2 < 0? gx - 4 : gx - 2) / 3;
	      int px1 = (gx + sbit->width + 2 < 0? gx + sbit->width + 2: gx + sbit->width + 4) / 3;
	      int llip = gx - px0 * 3;
	      int sbpl = sbit->pitch;
	      int sx = sbit->width, sy = sbit->height;
	      int psx = px1 - px0;
	      const unsigned char *src = sbit->buffer;
	      unsigned char *dst = buf;
	      unsigned char scratch[psx * 3];
	      int mode = subpixel_text == 2? 2 : 0;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (px1 > x1)
	        px1 = x1;
	      if (px0 < 0)
		{
		  px0 = -px0;
		}
	      else
		{
		  px1 -= px0;
		  dst += px0 * DI.bytes_per_pixel;
		  px0 = 0;
		}

	      if (px1 <= 0)
		{
		  x += sbit->xadvance;
		  continue;
		}

	      for (; gy < sy; gy++, src += sbpl, dst += bpl)
		{
		  int i, j;
		  for (i = 0, j = -llip; i < psx * 3; i+=3)
		    {
		      scratch[i+mode] =
			((j > -1 && j<sx    ? src[j    ] * 3 : 0)
		       + (j >  0 && j<sx + 1? src[j - 1] * 2 : 0)
		       + (j >  1 && j<sx + 2? src[j - 2]     : 0)
		       + (j > -2 && j<sx - 1? src[j + 1] * 2 : 0)
		       + (j > -3 && j<sx - 2? src[j + 2]     : 0)) / 9;
		      j++;
		      scratch[i+1] =
			((j > -1 && j<sx    ? src[j    ] * 3 : 0)
		       + (j >  0 && j<sx + 1? src[j - 1] * 2 : 0)
		       + (j >  1 && j<sx + 2? src[j - 2]     : 0)
		       + (j > -2 && j<sx - 1? src[j + 1] * 2 : 0)
		       + (j > -3 && j<sx - 2? src[j + 2]     : 0)) / 9;
		      j++;
		      scratch[i+(mode^2)] =
			((j > -1 && j<sx    ? src[j    ] * 3 : 0)
		       + (j >  0 && j<sx + 1? src[j - 1] * 2 : 0)
		       + (j >  1 && j<sx + 2? src[j - 2]     : 0)
		       + (j > -2 && j<sx - 1? src[j + 1] * 2 : 0)
		       + (j > -3 && j<sx - 2? src[j + 2]     : 0)) / 9;
		      j++;
		    }
		  DI.render_blit_subpixel(dst,
					  scratch + px0 * 3, r, g, b, alpha,
					  px1);
		}
	    }
	  else if (sbit->format == ft_pixel_mode_mono)
	    {
	      int gx = x + sbit->left, gy = y - sbit->top;
	      int sbpl = sbit->pitch;
	      int sx = sbit->width, sy = sbit->height;
	      const unsigned char *src = sbit->buffer;
	      unsigned char *dst = buf;
	      int src_ofs = 0;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (gx < 0)
		{
		  sx += gx;
		  src -= gx / 8;
		  src_ofs = (-gx) & 7;
		  gx = 0;
		}
	      else if (gx > 0)
		{
		  dst += DI.bytes_per_pixel * gx;
		}

	      sx += gx;
	      if (sx > x1)
		sx = x1;
	      sx -= gx;

	      if (sx > 0)
		{
		  if (alpha >= 255)
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_MONO_OPAQUE(dst, src, src_ofs, r, g, b, sx);
		  else
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_MONO(dst, src, src_ofs, r, g, b, alpha, sx);
		}
	    }
	  else
	    {
	      NSLog(@"unhandled font bitmap format %i", sbit->format);
	    }

	  x += sbit->xadvance;
	}
      else
	{
	  FT_Face face;
	  FT_Glyph gl;
	  FT_BitmapGlyph gb;

	  if (FTC_Manager_Lookup_Size(ftc_manager, &cur.font, &face, 0))
	    continue;

	  /* TODO: for rotations of 90, 180, 270, and integer
	     scales hinting might still be a good idea. */
	  if (FT_Load_Glyph(face, glyph, FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP))
	    continue;

	  if (FT_Get_Glyph(face->glyph, &gl))
	    continue;

	  if (FT_Glyph_Transform(gl, &ftmatrix, &ftdelta))
	    {
	      NSLog(@"glyph transformation failed!");
	      continue;
	    }
	  if (FT_Glyph_To_Bitmap(&gl, ft_render_mode_normal, 0, 1))
	    {
	      FT_Done_Glyph(gl);
	      continue;
	    }
	  gb = (FT_BitmapGlyph)gl;


	  if (gb->bitmap.pixel_mode == ft_pixel_mode_grays)
	    {
	      int gx = x + gb->left, gy = y - gb->top;
	      int sbpl = gb->bitmap.pitch;
	      int sx = gb->bitmap.width, sy = gb->bitmap.rows;
	      const unsigned char *src = gb->bitmap.buffer;
	      unsigned char *dst = buf;

	      if (gy < 0)
		{
		  sy += gy;
		  src -= sbpl * gy;
		  gy = 0;
		}
	      else if (gy > 0)
		{
		  dst += bpl * gy;
		}

	      sy += gy;
	      if (sy > y1)
		sy = y1;

	      if (gx < 0)
		{
		  sx += gx;
		  src -= gx;
		  gx = 0;
		}
	      else if (gx > 0)
		{
		  dst += DI.bytes_per_pixel * gx;
		}

	      sx += gx;
	      if (sx > x1)
		sx = x1;
	      sx -= gx;

	      if (sx > 0)
		{
		  if (alpha >= 255)
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA_OPAQUE(dst, src, r, g, b, sx);
		  else
		    for (; gy < sy; gy++, src += sbpl, dst += bpl)
		      RENDER_BLIT_ALPHA(dst, src, r, g, b, alpha, sx);
		}
	    }
/* TODO: will this case ever appear? */
/*			else if (gb->bitmap.pixel_mode==ft_pixel_mode_mono)*/
	  else
	    {
	      NSLog(@"unhandled font bitmap format %i", gb->bitmap.pixel_mode);
	    }

	  ftdelta.x += gl->advance.x >> 10;
	  ftdelta.y += gl->advance.y >> 10;

	  FT_Done_Glyph(gl);
	}
    }
}

@end

