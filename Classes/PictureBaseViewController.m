//
//  PictureBaseViewController.m
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"
#include "iInteractAppDelegate.h"

@implementation PictureBaseViewController

@synthesize theLabel, originalButton, boy;

#define MIN_DURATION 2.5

/*

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        // Custom initialization
    }
    return self;
}
*/

/*
// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];

}
*/


- (void) viewWillAppear:(BOOL)animated {
	[zoomButton setAlpha:0.0];	
	[super viewWillAppear:animated];
}


// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft);
}


- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}


- (void)dealloc {
	[theLabel release];
	
    [super dealloc];
}

/*
- (void)animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
	
} //animationDidStop
*/

- (void) zoomIn: (UIButton *)theBtn interaction:(NSString *)theInteraction {
	/*
	 Set up sounds and views.
	 */
	// Create and prepare audio players for tick and tock sounds
	CFTimeInterval duration = MIN_DURATION;
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSError *error;
	
		//rember the original button
	originalButton = theBtn;
		
	NSURL *soundURL = nil;
	if (theInteraction) {
		
		NSString *gender = @"girl_";
		if ([(iInteractAppDelegate*)[[UIApplication sharedApplication] delegate] isBoy]) {
			gender = @"boy_";
		}
		NSString *theSound = [gender stringByAppendingString:theInteraction];
		soundURL = [NSURL fileURLWithPath:[mainBundle pathForResource:theSound ofType:@"mp3"]];
		
		//cleanup the previous
		if (soundPlayer) {
			[soundPlayer stop];
			[soundPlayer release];
			soundPlayer = nil;
		}	
		
		soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:soundURL error:&error];
		if (!soundPlayer) {
			NSLog(@"no soundPlayer: %@", [error localizedDescription]);	
		} else {
			[soundPlayer prepareToPlay];
			duration = [soundPlayer duration];
			[soundPlayer play];
		}
	}
	
	//ensure we have a min duration
	if (duration < MIN_DURATION) {
		duration = MIN_DURATION;
	}			
	
	//set the image on the zoomed out button
	UIImage *theImage = [originalButton backgroundImageForState:UIControlStateNormal];
	[zoomButton setBackgroundImage:theImage forState:UIControlStateNormal];
	theImage = nil;
	
	//zoom in on the selected picture
	[UIView beginAnimations:nil context:NULL];
	//	[UIView setAnimationDuration:0.8];
	[UIView setAnimationDuration:duration];

	[zoomButton setAlpha:1.0];
	//	[originalButton setAlpha:0.0];
	
	[UIView commitAnimations];
	
	/*
		//flash the button :)
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:.6];
		[theBtn setAlpha:0];
		[UIView setAnimationRepeatCount:5];
		[theBtn setAlpha:1];
		[UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:context:)];
		[UIView commitAnimations];
	*/

	//cleanup old player
	/*
	 if (soundPlayer) {
		[soundPlayer stop];
		[soundPlayer release];
		soundPlayer = nil;
	}
	*/
}

- (IBAction)zoomOut:(id)sender {
	
	if (!soundPlayer || ![soundPlayer isPlaying]) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.8];
	
		[zoomButton setAlpha:0.0];
		[originalButton setAlpha:1.0];
	
		[UIView commitAnimations];
		originalButton = nil;
	}
}

@end
