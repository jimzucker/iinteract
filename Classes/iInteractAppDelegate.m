//
//  iInteractAppDelegate.m
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright  James A Zucker 2010. All rights reserved.
//

#import "RootViewController.h"
#import "iInteractAppDelegate.h"


@implementation iInteractAppDelegate

@synthesize window;
@synthesize navigationController;
@synthesize boy;

#pragma mark -
#pragma mark Application lifecycle

- (void)applicationDidFinishLaunching:(UIApplication *)application {    
    
    // Override point for customization after app launch    
	
	//default to a girls voice
	[self setBoy:NO];
	
	//[window addSubview:[navigationController view]];
    [self.window setRootViewController:self.navigationController] ;
    [window makeKeyAndVisible];
}


- (void)applicationWillTerminate:(UIApplication *)application {
	// Save data if appropriate
}


#pragma mark -
#pragma mark Memory management

- (void)dealloc {
	[navigationController release];
	[window release];
	[super dealloc];
}


@end

