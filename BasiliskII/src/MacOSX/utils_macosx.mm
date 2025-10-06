/*
 *	utils_macosx.mm - Mac OS X utility functions.
 *
 *  Copyright (C) 2011 Alexei Svitkine
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include <Cocoa/Cocoa.h>
#include "sysdeps.h"
#include <SDL.h>
#include "utils_macosx.h"

#if SDL_VERSION_ATLEAST(2, 0, 0) && !SDL_VERSION_ATLEAST(3, 0, 0)
#include <SDL_syswm.h>
#endif

#include <sys/sysctl.h>
#include <Metal/Metal.h>

#if SDL_VERSION_ATLEAST(2, 0, 0)

static id eventMonitor = nil;
static void (*g_toggle_fullscreen_callback)(void) = NULL;

void install_macosx_hotkey_handler(void (*toggle_fullscreen_callback)(void)) {
	g_toggle_fullscreen_callback = toggle_fullscreen_callback;

	// Install a local event monitor to catch Fn+F
	// The Fn key on macOS sends function key codes (F1-F12) but Fn+F sends kVK_ANSI_F
	// with NSEventModifierFlagFunction set
	eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent*(NSEvent* event) {
		if ((event.modifierFlags & NSEventModifierFlagFunction) &&
		    event.keyCode == 0x03) {
			if (g_toggle_fullscreen_callback) {
				g_toggle_fullscreen_callback();
			}
			return nil;
		}
		return event;
	}];
}

void remove_macosx_hotkey_handler() {
	if (eventMonitor) {
		[NSEvent removeMonitor:eventMonitor];
		eventMonitor = nil;
	}
	g_toggle_fullscreen_callback = NULL;
}

void disable_SDL2_macosx_menu_bar_keyboard_shortcuts() {
	for (NSMenuItem * menu_item in [NSApp mainMenu].itemArray) {
		if (menu_item.hasSubmenu) {
			for (NSMenuItem * sub_item in menu_item.submenu.itemArray) {
				sub_item.keyEquivalent = @"";
				sub_item.keyEquivalentModifierMask = 0;
			}
		}
		if ([menu_item.title isEqualToString:@"View"]) {
			[[NSApp mainMenu] removeItem:menu_item];
			break;
		}
	}
}

static NSWindow *get_nswindow(SDL_Window *window) {
#if SDL_VERSION_ATLEAST(3, 0, 0)
	SDL_PropertiesID props = SDL_GetWindowProperties(window);
	return (NSWindow *)SDL_GetPointerProperty(props, "SDL.window.cocoa.window", NULL);
#else
	SDL_SysWMinfo wmInfo;
	SDL_VERSION(&wmInfo.version);
	return SDL_GetWindowWMInfo(window, &wmInfo) ? wmInfo.info.cocoa.window : nil;
#endif
}

bool is_fullscreen_osx(SDL_Window * window)
{
	if (!window) {
		return false;
	}
	
	const NSWindowStyleMask styleMask = [get_nswindow(window) styleMask];
	return (styleMask & NSWindowStyleMaskFullScreen) != 0;
}

void enable_fullscreen_button_osx(SDL_Window * window)
{
	if (!window) {
		return;
	}
    
	NSWindow *nsWindow = get_nswindow(window);
	if (!nsWindow) {
		return;
	}
    
	NSButton *fullscreenButton = [nsWindow standardWindowButton:NSWindowZoomButton];
	if (fullscreenButton) {
		[fullscreenButton setEnabled:YES];
	}
}

void set_window_aspect_ratio_osx(SDL_Window * window, int width, int height)
{
	if (!window || width <= 0 || height <= 0) {
		return;
	}

	NSWindow *nsWindow = get_nswindow(window);
	if (!nsWindow) {
		return;
	}

	[nsWindow setContentAspectRatio:NSMakeSize(width, height)];
}

#endif // SDL_VERSION_ATLEAST(2, 0, 0)

#if SDL_VERSION_ATLEAST(3, 0, 0) && defined(VIDEO_CHROMAKEY)

// from https://github.com/zydeco/macemu/tree/rootless/

void make_window_transparent(SDL_Window *window)
{
	if (!window) {
		return;
	}
	NSWindow *cocoaWindow = get_nswindow(window);
    NSView *sdlView = cocoaWindow.contentView;
	sdlView.wantsLayer = YES;
    sdlView.layer.backgroundColor = [NSColor clearColor].CGColor;
	static bool observing;
    if (!observing) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:NSWindowDidBecomeKeyNotification object:cocoaWindow queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            NSWindow *window = (NSWindow *)note.object;
            window.level = NSMainMenuWindowLevel + 1;
        }];
        [nc addObserverForName:NSWindowDidResignKeyNotification object:cocoaWindow queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            NSWindow *window = (NSWindow *)note.object;
            // hack for window to be sent behind new key window
            [window setIsVisible:NO];
            [window setLevel:NSNormalWindowLevel];
            [window setIsVisible:YES];
        }];
        observing = true;
    }
}

void set_mouse_ignore(SDL_Window *window, int flag) {
	if (!window) {
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		get_nswindow(window).ignoresMouseEvents = flag;
	});
}

#endif // SDL_VERSION_ATLEAST(3, 0, 0) && defined(VIDEO_CHROMAKEY)

void set_menu_bar_visible_osx(bool visible)
{
	[NSMenu setMenuBarVisible:(visible ? YES : NO)];
}

void set_current_directory()
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	chdir([[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] UTF8String]);
	[pool release];
}

bool MetalIsAvailable() {
	const int EL_CAPITAN = 15; // Darwin major version of El Capitan
	char s[16];
	size_t size = sizeof(s);
	int v;
	if (sysctlbyname("kern.osrelease", s, &size, NULL, 0) || sscanf(s, "%d", &v) != 1 || v < EL_CAPITAN) return false;
	id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
	bool r = dev != nil;
	[dev release];
	return r;
}
