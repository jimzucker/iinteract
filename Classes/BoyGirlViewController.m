    //
//  BoyGirlViewController.m
//  iInteract
//
//  Created by James Zucker on 3/31/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "BoyGirlViewController.h"
#import "iInteractAppDelegate.h"

@implementation BoyGirlViewController

@synthesize boyBtn, girlBtn;

/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
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
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}


- (void)dealloc {
    [super dealloc];
}


- (IBAction) boy {
	//	[(iInteractAppDelegate*)[[UIApplication sharedApplication] delegate] setBoy:NO];

	//close the action sheet
	//	[self actionSheet:[sender superview] clickedButtonAtIndex:0];
}

- (IBAction) girl {

	//	[(iInteractAppDelegate*)[[UIApplication sharedApplication] delegate] setBoy:NO];
	//close the action sheet
	//	[self actionSheet:[sender superview] clickedButtonAtIndex:0];
}


- (void) showActionSheet: (UIView *)theView
{	
	//create the alert
	//	UIActionSheet *alert = [[UIActionSheet alloc] initWithTitle:@"Select Quoted Spread\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
	UIActionSheet *alert = [[UIActionSheet alloc] initWithTitle:@"\n\n\n\n\n\n\n\n\n\n\n"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	
	//  	[alert setBounds:CGRectMake(0,0,320,700)];

	[alert addSubview:self.view];
	[alert showInView:theView];	
    [alert release];
}

@end
