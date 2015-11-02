//
//  FoodViewController.m
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "FoodViewController.h"


@implementation FoodViewController

@synthesize breakfastBtn, lunchBtn, dinnerBtn, desertBtn;

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
	[breakfastBtn release];
	[lunchBtn release];
	[dinnerBtn release];
	[desertBtn release];
	
    [super dealloc];
}

- (IBAction)breakfast:(id)sender {
	[self zoomIn:sender interaction:@"breakfast"];
}
- (IBAction)lunch:(id)sender {
	[self zoomIn:sender interaction:@"lunch"];
}
- (IBAction)dinner:(id)sender {
	[self zoomIn:sender interaction:@"dinner"];
}
- (IBAction)dessert:(id)sender {
	[self zoomIn:sender interaction:@"dessert"];
}

@end
