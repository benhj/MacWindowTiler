//
//  AppDelegate.m
//  Windowing
//
//  Created by Ben Jones on 10/4/17.
//  Copyright © 2017 benhj. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate () {
    id m_keyHandlerID;
    id m_clickHandlerID;
    NSWindow * m_messageWindow;
    NSWindow * m_selectedWindowA;
    NSWindow * m_selectedWindowB;
    BOOL m_selectedA;
    BOOL m_selectedB;
}

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
            [userWindows addObject:window];
        }
        //NSString *bounds = [window objectForKey:@"kCGWindowBounds" ];
        //NSLog(@"%@",bounds);
        
    }
    return userWindows;
}

/// Retrieve a list of all PIDs associated with visible windows
- (NSArray*)retrieveWindowPIDs:(NSArray*)windows {
    NSMutableArray* encounteredPIDs = [[NSMutableArray alloc] init];
    /// Also filter on PID of 'this' app
    int pid = [[NSProcessInfo processInfo] processIdentifier];
    for (NSDictionary *window in windows) {
        
        /// Skip over windows for which we've already processed
        NSString *pidStr = [window objectForKey:@"kCGWindowOwnerPID" ];
        if ([encounteredPIDs containsObject: pidStr] ||
            [encounteredPIDs containsObject:[NSString stringWithFormat:@"%d",pid]]) {
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

- (CGFloat)windowX:(AXUIElementRef)windowRef {
    CFTypeRef tref;
    CGPoint position;
    AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute, (CFTypeRef *)&tref);
    AXValueGetValue(tref, kAXValueCGPointType, &position);
    return position.x;
}

- (CGFloat)windowY:(AXUIElementRef)windowRef {
    CFTypeRef tref;
    CGPoint position;
    AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute, (CFTypeRef *)&tref);
    AXValueGetValue(tref, kAXValueCGPointType, &position);
    return position.y;
}

- (NSUInteger)rowsAvailable:(NSUInteger)windowCount withMaxPerRow:(NSUInteger)maxPerRow {
    NSUInteger remainder = windowCount % maxPerRow;
    NSUInteger perfect = windowCount - remainder;
    NSUInteger additionBit = (remainder > 0) ? 1 : 0;
    return windowCount > maxPerRow ? (perfect / maxPerRow + additionBit) : 1;
}

- (void)tileWindows:(id)sender  {

    // Disable any currently selected windows
    [self disableAnySelectedWindows];
    
    NSArray* windows = [self retrieveUserVisibleWindows];
    NSRect screenDim = [self screenResolution];
    CGSize screenSize = screenDim.size;
    CGFloat screenWidth = screenSize.width;
    CGFloat screenHeight = screenSize.height;

    // Figure out number of rows and columns. Assuming, we allow
    // N windows per row. When that is exhausted, we add
    // another row
    NSUInteger count = [windows count];
    NSUInteger maxPerRow = 2;
    NSUInteger rows = [self rowsAvailable:count withMaxPerRow:maxPerRow];

    CGFloat widthToPlayWith = screenWidth;
    CGFloat heightToPlayWith = screenHeight;
    NSUInteger columns = count < maxPerRow ? count : maxPerRow;
    //NSLog(@"columns: %lu",columns);
    CGFloat widthToSet = (widthToPlayWith - (5 * columns)) / columns;

    // Tiling vertically only happens when we run out of space horizontally
    CGFloat heightToSet = (rows > 1) ? (heightToPlayWith - (5 * rows)) / rows : heightToPlayWith;
    CGFloat xCounter = 0;
    CGFloat yCounter = 25;

    NSUInteger windowsPlaced = 0;

    // Retreive all open window associated PIDs
    NSArray* windowPIDs = [self retrieveWindowPIDs:windows];
    for (NSString * pidStr in windowPIDs) {

        // Find all windows associated with PID
        CFArrayRef windowList = [self windowListForPID:pidStr];
        if (!windowList) {
            continue;
        }
        CFIndex windowCount = CFArrayGetCount(windowList);
        if(windowCount < 1) {
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

                // See if another row needed to be added
                if(windowsPlaced > 0 && windowsPlaced % maxPerRow == 0) {
                    xCounter = 0;
                    yCounter += heightToSet + 5;
                    widthToPlayWith = screenWidth;

                    // Adjust for remaining windows
                    if(count - windowsPlaced < maxPerRow) {
                        columns = count - windowsPlaced;
                    }
                    widthToSet = (widthToPlayWith - (5 * columns)) / columns;
                }

                [self setWindowPosition:windowRef withX:xCounter andY:yCounter];
                [self setWindowDim:windowRef withWidth:widthToSet andHeight:heightToSet];

                // Check here if widthToSet bigger than actual
                CGFloat actualWidth = [self windowWidth:windowRef];
                if(actualWidth > widthToSet) {
                    xCounter += actualWidth + 5;
                    widthToPlayWith -= (actualWidth);
                } else {
                    xCounter += widthToSet + 5;
                    widthToPlayWith -= (widthToSet);
                }
                //widthToSet = (widthToPlayWith - (5 * columns)) / columns;
                ++windowsPlaced;
            } else {
                --count;
            }
        }
    }
}

- (void)processExit:(id)sender {
    [NSApp terminate: nil];
}

- (void)fadeInMessageWindow {
    
    NSLog(@"windows is nil %d",(m_messageWindow == nil));
    NSLog(@"windows is null %d",(m_messageWindow == NULL));
    
    if (m_messageWindow == nil) {
        CGRect rect;
        rect.size.width = 400;
        rect.size.height = 100;
        rect.origin.x = 0;
        rect.origin.y = 0 ;

        m_messageWindow  = [[NSWindow alloc] initWithContentRect:rect
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        [m_messageWindow setOpaque:NO];
        NSColor *semiTransparentGray = [NSColor colorWithDeviceRed:0.5
                                                             green:0.5
                                                              blue:0.5
                                                             alpha:0.5];
        [m_messageWindow setBackgroundColor:semiTransparentGray];
        [m_messageWindow makeKeyAndOrderFront:NSApp];
        NSRect cFrame =[[m_messageWindow contentView] frame];
        NSTextView *theTextView = [[NSTextView alloc] initWithFrame:cFrame];
        NSFont* font = [NSFont fontWithName:@"Helvetica" size:25.0];
        [theTextView setBackgroundColor:semiTransparentGray];
        [theTextView setFont:font];
        [theTextView setString:@"Click on two windows, hit space when done!"];
        m_messageWindow.releasedWhenClosed = YES;
        [m_messageWindow center];
        [theTextView alignCenter:NULL];
        [m_messageWindow setContentView:theTextView];
        [m_messageWindow makeFirstResponder:theTextView];
    }
    [m_messageWindow orderFrontRegardless];
    [m_messageWindow setAlphaValue:0.0];
    [[m_messageWindow animator] setAlphaValue:0.5];
}

- (void)fadeOutMessageWindow {
    if(m_messageWindow) {
        [[m_messageWindow animator] setAlphaValue:0.0];
    }
}

/// To indicate that two windows should be swapped
- (void)swapWindows:(id)sender {
    // Display message in middle of screen indicating to user what to do
    [self fadeInMessageWindow];
    
    // Setup an event handler to detect when windows are clicked on
    m_clickHandlerID = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^(NSEvent * mouseEvent) {
        [self clickHandler:mouseEvent];
    }];
    
    // Setup handler to detect when the space bar is hit
    m_keyHandlerID = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent * keyEvent) {
        [self keyHandler:keyEvent];
    }];
}

- (void)initializeMenu {
    
    // Set up the icon that is displayed in the status bar
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.title = @"";
    _statusItem.button.toolTip = @"Desktop Window Tiler";
    NSImage* img = [NSImage imageNamed:@"if_grid2_226575-3"];
    [img setTemplate:YES];
    _statusItem.button.image = img;
    
    // Add menu entries
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Tile windows"
                    action:@selector(tileWindows:)
             keyEquivalent:@""];
    [menu addItemWithTitle:@"Swap two windows"
                    action:@selector(swapWindows:)
             keyEquivalent:@""];
    
    [menu addItem:[NSMenuItem separatorItem]]; // A thin grey line
    
    // Add an exit item to exit program
    [menu addItemWithTitle:@"Exit"
                    action:@selector(processExit:)
             keyEquivalent:@""];
    
    // Add the menu to the status item
    _statusItem.menu = menu;
}

- (void)clickHandler:(NSEvent*)mouseEvent {
    NSLog(@"Mouse clicked: %@", NSStringFromPoint([mouseEvent locationInWindow]));
    
    // Retrive user visible windows to figure out which one was clicked on
    NSArray * windows = [self retrieveUserVisibleWindows];
    NSPoint clickPoint = [mouseEvent locationInWindow];
    
    // Loop over all open windows to see if click point is inside of one of them
    NSArray * windowPIDs = [self retrieveWindowPIDs:windows];
    NSRect selectedRect;
    Boolean found = false;
    for (NSString * pidStr in windowPIDs) {
        // Find all windows associated with PID
        CFArrayRef windowList = [self windowListForPID:pidStr];
        if (!windowList) {
            continue;
        }
        CFIndex windowCount = CFArrayGetCount(windowList);
        if(windowCount < 1) {
            continue;
        }
        for(CFIndex i = 0; i < windowCount; ++i) {
            AXUIElementRef windowRef = (AXUIElementRef) CFArrayGetValueAtIndex( windowList, i);
            CGPoint origin;
            CGSize size;
            origin.x = [self windowX:windowRef];
            origin.y = [self windowY:windowRef];
            size.width = [self windowWidth:windowRef];
            size.height = [self windowHeight:windowRef];
            
            NSLog(@"origin.x: %f", origin.x);
            NSLog(@"origin.y: %f", origin.y);
            
            if(clickPoint.x > origin.x && clickPoint.x <= origin.x + size.width &&
               clickPoint.y > origin.y && clickPoint.y <= origin.y + size.height) {
                NSLog(@"Found!!");
                found = true;
                selectedRect.origin = origin;
                selectedRect.size = size;
                break;
            }
        }
        if(found) {
            break;
        }
    }
    
    if(found) {
        NSRect frame = NSRectFromCGRect(selectedRect);
        NSLog(@"selectedRec.origin.x: %f", selectedRect.origin.x);
        NSLog(@"selectedRec.origin.y: %f", selectedRect.origin.y);
        
        if (!m_selectedB || !m_selectedA) {
            NSWindow * theWindow  = [[NSWindow alloc] initWithContentRect:frame
                                                                styleMask:NSWindowStyleMaskBorderless
                                                                  backing:NSBackingStoreBuffered
                                                                    defer:NO];
            [theWindow setOpaque:NO];
            NSColor *semiTransparentBlue = [NSColor colorWithDeviceRed:0.0
                                                                 green:0.0
                                                                  blue:1.0
                                                                 alpha:0.2];
            [theWindow setBackgroundColor:semiTransparentBlue];
            [theWindow makeKeyAndOrderFront:NSApp];
            [theWindow display];
            [theWindow orderFrontRegardless];
            //[theWindow setReleasedWhenClosed:YES];

            if (!m_selectedA) {
                m_selectedWindowA = theWindow;
                m_selectedWindowA.releasedWhenClosed = YES;
                //[m_selectedWindowA setReleasedWhenClosed:YES];
                // Close the message window
                [self fadeOutMessageWindow];
                m_selectedA = YES;
            } else {
                if(!m_selectedB) {
                    m_selectedWindowB = theWindow;
                    m_selectedWindowB.releasedWhenClosed = YES;
                    //[m_selectedWindowB setReleasedWhenClosed:YES];
                    m_selectedB = YES;
                }
            }
        }
    }
}

- (void)keyHandler:(NSEvent*)keyEvent {
    short keyCode = [keyEvent keyCode];
    if(keyCode == 49) {
        // Disable window slection
        [self disableAnySelectedWindows];
        
        // De-register global events handlers
        [NSEvent removeMonitor:m_keyHandlerID];
        [NSEvent removeMonitor:m_clickHandlerID];
        
    }
}

- (void)disableAnySelectedWindows {
    if(m_selectedWindowB) {
        [m_selectedWindowB setIsVisible:NO];
        m_selectedB = NO;
        
    }
    if(m_selectedWindowA) {
        [m_selectedWindowA setIsVisible:NO];
        m_selectedA = NO;
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    m_selectedA = NO;
    m_selectedB = NO;
    [self initializeMenu];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
