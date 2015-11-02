//
//  DrinksViewController.m
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "DrinksViewController.h"


@implementation DrinksViewController

@synthesize milkBtn, juiceBtn, waterBtn, sodaBtn;

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

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

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
	[milkBtn release];
	[juiceBtn release];
	[waterBtn release];
	[sodaBtn release];
	
    [super dealloc];
}

- (IBAction)milk:(id)sender {
	[self zoomIn:sender interaction:@"milk"];
}
- (IBAction)water:(id)sender {
	[self zoomIn:sender interaction:@"water"];
}
- (IBAction)juice:(id)sender {
	[self zoomIn:sender interaction:@"juice"];
}
- (IBAction)soda:(id)sender {
	[self zoomIn:sender interaction:@"soda"];
}

@end
