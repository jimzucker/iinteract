//
//  FeelingsViewController.m
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "FeelingsViewController.h"


@implementation FeelingsViewController

@synthesize happyBtn, sadBtn, angryBtn, iFeelLabel;

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        // Custom initialization
    }
    return self;
}

/*
// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];

}
*/

- (void) viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[iFeelLabel setText:@"..."];	

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
    [super dealloc];
}

- (void) enableBtns:(BOOL) theState {
	happyBtn.enabled	= theState;
	sadBtn.enabled		= theState;
	angryBtn.enabled	= theState;
}

- (void)animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
	[self enableBtns:YES];
} //animationDidStop


- (void) runSound: (NSString *) theSound button: (UIButton *)theBtn {
	/*
	 Set up sounds and views.
	 */
	// Create and prepare audio players for tick and tock sounds
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSError *error;
	
	NSURL *soundURL = [NSURL fileURLWithPath:[mainBundle pathForResource:theSound ofType:@"mp3"]];
	
	//cleanup old player
	if (soundPlayer) {
		[soundPlayer stop];
		
		[soundPlayer release];
		soundPlayer = nil;
	}
	
	//	soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:soundURL error:&error];
	soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:soundURL error:&error];
	if (!soundPlayer) {
		NSLog(@"no soundPlayer: %@", [error localizedDescription]);	
	} else {
		[soundPlayer prepareToPlay];
		[soundPlayer play];
		
		//wait til the sound is done
		//		while ([soundPlayer isPlaying]) {
		//}
		
		//	soundPlayer = nil;
		//[soundPlayer release];

		//flash the button :)
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:.6];
		[theBtn setAlpha:0];
		[UIView setAnimationRepeatCount:5];
		[theBtn setAlpha:1];
		[UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:context:)];
		[UIView commitAnimations];
	
		//clean up
		[soundPlayer stop];	
		[soundPlayer release];
		soundPlayer = nil;	
	}

}

- (IBAction)iAmHappy:(id)sender {
	//	if ( !soundPlayer || (soundPlayer && ![soundPlayer isPlaying])) {
	[self enableBtns:NO];
	[iFeelLabel setText:@"Happy!"];	
	[self runSound:@"iFeelHappy" button:sender];
}
	

- (IBAction)iAmSad:(id)sender {
	//	if ( !soundPlayer || (soundPlayer && ![soundPlayer isPlaying])) {
		[iFeelLabel setText:@"Sad!"];
		[self runSound:@"iFeelSad" button:sender];
	//}
}

- (IBAction)iAmAngry:(id)sender {
	//if ( !soundPlayer || (soundPlayer && ![soundPlayer isPlaying])) {
		[iFeelLabel setText:@"Angry!"];
		[self runSound:@"iFeelAngry" button:sender];
	//}
}



@end
