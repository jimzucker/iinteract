//
//  WantViewController.m
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "WantViewController.h"


@implementation WantViewController

@synthesize computerBtn, playBtn, tvBtn, bookBtn;

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
	[computerBtn release];
	[bookBtn release];
	[playBtn release];
	[tvBtn release];

    [super dealloc];
}

- (IBAction)computer:(id)sender {
	[self zoomIn:sender interaction:@"computer"];
}


- (IBAction)book:(id)sender {
	[self zoomIn:sender interaction:@"book"];
}


- (IBAction)play:(id)sender {
	[self zoomIn:sender interaction:@"play"];
}


- (IBAction)tv:(id)sender {
	[self zoomIn:sender interaction:@"tv"];
}



@end
