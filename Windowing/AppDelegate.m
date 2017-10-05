//
//  AppDelegate.m
//  Windowing
//
//  Created by Ben Jones on 10/4/17.
//  Copyright © 2017 benhj. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

/// Retrieve the current screen resolution; note assumes a single monitor
- (NSRect) screenResolution {
    NSArray *screenArray = [NSScreen screens];
    NSScreen *screen = [screenArray objectAtIndex: 0];
    return [screen visibleFrame];
}

/// A routine to figure out only those windows that are currently user-visible
- (NSArray*)retrieveUserVisibleWindows {
    NSMutableArray *userWindows=[[NSMutableArray alloc] init];
    // Routine to figure out all user-visible windows
    uint32_t options = kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements;
    NSMutableArray *windows = (NSMutableArray *)CFBridgingRelease(CGWindowListCopyWindowInfo(options, kCGNullWindowID));

    for (NSDictionary *window in windows) {
        // User-visible windows appear to have layer 0
        NSString *layer = [window objectForKey:@"kCGWindowLayer" ];
        NSString * onScreen = [window objectForKey:@"kCGWindowIsOnscreen" ];
        int layerInt = [layer intValue];
        if(layerInt == 0 && [onScreen boolValue]) {
            for (NSString * str in window.allKeys) {
                NSString * val = [window objectForKey:str ];
                NSLog(@"%@ is %@", str, val);
            }
            [userWindows addObject:window];
        }
    }
    return userWindows;
}

- (NSArray*)retrieveWindowPIDs:(NSArray*)windows {
    NSMutableArray* encounteredPIDs = [[NSMutableArray alloc] init];
    for (NSDictionary *window in windows) {
        
        /// Skip over windows for which we've already processed
        NSString *pidStr = [window objectForKey:@"kCGWindowOwnerPID" ];
        if ([encounteredPIDs containsObject: pidStr]) {
            continue;
        } else {
            [encounteredPIDs addObject:pidStr];
        }
    }
    return encounteredPIDs;
}

/// Sets the position of a window
- (void)setWindowPosition:(AXUIElementRef) windowRef withX:(CGFloat)x andY:(CGFloat)y {
    CFTypeRef position;
    CGPoint newPoint;
    newPoint.x = x;
    newPoint.y = y;
    position = (CFTypeRef)(AXValueCreate(kAXValueCGPointType, (const void *)&newPoint));
    // Set the position attribute of the window (runtime error over here)
    AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute, position);
}

/// Sets the width and height of a window
- (void)setWindowDim:(AXUIElementRef) windowRef withWidth:(CGFloat)width andHeight:(CGFloat)height {

    CFTypeRef dim;
    // Create a new size
    CGSize newSize;
    newSize.width = width;
    newSize.height = height;
    dim = (CFTypeRef)(AXValueCreate(kAXValueCGSizeType, (const void *)&newSize));
    // Set the position attribute of the window (runtime error over here)
    AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute, dim);
}

- (CFArrayRef) windowListForPID:(NSString*)pidStr {
    pid_t pid = [pidStr intValue];
    // Get AXUIElement using PID
    AXUIElementRef appRef = AXUIElementCreateApplication(pid);

    // Pull out window list for given application; since applications can
    // have multiple windows open for it
    CFArrayRef windowList;
    AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&windowList);
    return windowList;
}

- (CGFloat)windowWidth:(AXUIElementRef)windowRef {
    CFTypeRef tref;
    CGSize size;
    AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute, (CFTypeRef *)&tref);
    AXValueGetValue(tref, kAXValueCGSizeType, &size);
    return size.width;
}

- (CGFloat)windowHeight:(AXUIElementRef)windowRef {
    CFTypeRef tref;
    CGSize size;
    AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute, (CFTypeRef *)&tref);
    AXValueGetValue(tref, kAXValueCGSizeType, &size);
    return size.height;
}

- (void)tileWindows:(id)sender  {
    
    NSArray* windows = [self retrieveUserVisibleWindows];
    NSRect screenDim = [self screenResolution];
    CGSize screenSize = screenDim.size;
    CGFloat screenWidth = screenSize.width;
    CGFloat screenHeight = screenSize.height;

    NSUInteger count =  [windows count];//[self totalWindowCount:windows];
    NSLog(@"number of: %lu", count);
    CGFloat widthToPlayWith = screenWidth;
    CGFloat heightToPlayWith = screenHeight;
    CGFloat widthToSet = (widthToPlayWith - (5 * count)) / count;
    
    // Tiling vertically only happens when we run out of space horizontally
    CGFloat heightToSet = heightToPlayWith;
    CGFloat xCounter = 0;
    CGFloat yCounter = 0;
    
    // Retreive all open window associated PIDs
    NSArray* windowPIDs = [self retrieveWindowPIDs:windows];
    for (NSString * pidStr in windowPIDs) {
        
        // Find all windows associated with PID
        CFArrayRef windowList = [self windowListForPID:pidStr];
        CFIndex windowCount = CFArrayGetCount(windowList);
        if ((!windowList) || windowCount < 1) {
            continue;
        }

        // Loop over windows -- set new size and positions
        for(CFIndex i = 0; i < windowCount; ++i) {
            AXUIElementRef windowRef = (AXUIElementRef) CFArrayGetValueAtIndex( windowList, i);
            
            // Only proceed if the element for the window can actually be set. Take this
            // to mean that it's size can be updated.
            Boolean isPosSettable;
            Boolean isSizeSettable;
            AXUIElementIsAttributeSettable(windowRef, kAXPositionAttribute, &isPosSettable);
            AXUIElementIsAttributeSettable(windowRef, kAXSizeAttribute, &isSizeSettable);
            if(isPosSettable && isSizeSettable) {
                NSLog(@"x pos: %f",xCounter);
                [self setWindowPosition:windowRef withX:xCounter andY:yCounter];
                [self setWindowDim:windowRef withWidth:widthToSet andHeight:heightToSet];
                
                // Check here if widthToSet bigger than actual
                CGFloat actualWidth = [self windowWidth:windowRef];
                NSLog(@"%f %f", actualWidth, widthToSet);
                if(actualWidth > widthToSet) {
                    xCounter += actualWidth + 5;
                    widthToPlayWith -= (actualWidth);
                } else {
                    xCounter += widthToSet + 5;
                    widthToPlayWith -= (widthToSet);
                }
                --count;
                widthToSet = (widthToPlayWith - (5 * count)) / count;
            }
        }

    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // Set up the icon that is displayed in the status bar
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.title = @"";
    _statusItem.button.toolTip = @"Desktop Window Tiler";
    //NSImage* img = [NSImage imageNamed:@"statusBarIcon"];
    //[img setTemplate:YES];
    //_statusItem.button.image = img;
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Tile windows"
                    action:@selector(tileWindows:)
             keyEquivalent:@""];
    
    _statusItem.menu = menu;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
