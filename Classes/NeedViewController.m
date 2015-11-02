//
//  NeedViewController.m
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "NeedViewController.h"


@implementation NeedViewController
@synthesize drinkBtn, eatBtn, bathroomBtn,takeBreakBtn;

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
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView {
}
*/

/*
// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
}
*/


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
	[drinkBtn release];
	[eatBtn	release];
	[bathroomBtn release];
	[takeBreakBtn release];

    [super dealloc];
}


- (IBAction)drink:(id)sender {
	[self zoomIn:sender interaction:@"drink"];
}

- (IBAction)eat:(id)sender {
	[self zoomIn:sender interaction:@"eat"];
}

- (IBAction)bathroom:(id)sender {
	[self zoomIn:sender interaction:@"bathroom"];
}

- (IBAction)takeBreak:(id)sender {
	[self zoomIn:sender interaction:@"break"];
}

@end
