//
//  RootViewController.m
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright  James A Zucker 2010. All rights reserved.
//

#import "RootViewController.h"
#import "FeelViewController.h"
#import "NeedViewController.h"
#import "NeedHelpViewController.h"
#import "WantViewController.h"
#import "SnacksViewController.h"
#import "DrinksViewController.h"
#import "FoodViewController.h"

#include "iInteractAppDelegate.h"
#include "BoyGirlViewController.h"

static NSString *kCellIdentifier = @"MyIdentifier";
static NSString *kTitleKey = @"title";
static NSString *kViewControllerKey = @"viewController";

@implementation RootViewController

@synthesize menuList;

- (void)viewDidLoad {
    [super viewDidLoad];
	
	UIActionSheet *alert = [[UIActionSheet alloc] initWithTitle:@"Select Voice\n"
													   delegate:self
											  cancelButtonTitle:@"Boy"
										 destructiveButtonTitle:@"Girl"
											  otherButtonTitles:nil];	
	[alert showInView:[self view]];	
    [alert release];
/*		
	// construct the array of page descriptions we will use (each description is a dictionary)
	//
	self.menuList = [NSMutableArray array];
	
	// I feel ..
	FeelViewController *feelViewControler = [FeelViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //NSLocalizedString(@"I feel ...", @""), kTitleKey,
							  @"feel.gif", kTitleKey,
							  feelViewControler, kViewControllerKey,
							  nil]];
	[feelViewControler release];
	
	// I need ...
	NeedViewController *needViewController = [NeedViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //NSLocalizedString(@"I need ...", @""), kTitleKey,
							  @"need.gif", kTitleKey,
							  needViewController, kViewControllerKey,
							  nil]];
	[needViewController release];

	// I want ...
	WantViewController *wantViewController = [WantViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //NSLocalizedString(@"I want ...", @""), kTitleKey,
							  @"want.gif", kTitleKey,
							  wantViewController, kViewControllerKey,
							  nil]];
	[wantViewController release];
	
	
	// I need help
	NeedHelpViewController *needHelpViewController = [NeedHelpViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //  NSLocalizedString(@"I need help!", @""), kTitleKey,
							  @"needhelp.gif", kTitleKey,
							  needHelpViewController, kViewControllerKey,
							  nil]];
	[needHelpViewController release];
	
	// food
	FoodViewController *foodViewControler = [FoodViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  // NSLocalizedString(@"Food", @""), kTitleKey,
							  @"food.gif", kTitleKey,
							  foodViewControler, kViewControllerKey,
							  nil]];
	[foodViewControler release];
	
	// Drinks
	DrinksViewController *drinksViewControler = [DrinksViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //NSLocalizedString(@"Drinks", @""), kTitleKey,
							  @"drinks.gif", kTitleKey,
							  drinksViewControler, kViewControllerKey,
							  nil]];
	[drinksViewControler release];
	

	// Snacks
	SnacksViewController *snacksViewController = [SnacksViewController alloc];
	[self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  //NSLocalizedString(@"Snacks", @""), kTitleKey,
							  @"snacks.gif", kTitleKey,
							  snacksViewController, kViewControllerKey,
							  nil]];
	[snacksViewController release];
    */
	
}

/*
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}
*/


- (void)viewDidAppear:(BOOL)animated
{
	self.title = @"iInteract Menu";    
	[super viewDidAppear:animated];

	//pick the gender
	
	/*
	 BoyGirlViewController *gender = [[BoyGirlViewController alloc] 
					   initWithNibName:@"BoyGirlViewController" 
					   bundle:nil];

		[gender showActionSheet:self.view];
	[gender release];
	 */
	
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex == 1) {
		[(iInteractAppDelegate*)[[UIApplication sharedApplication] delegate] setBoy:YES];
	}
}


/*
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
}
*/
/*
- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
}
*/

/*
 // Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	// Return YES for supported orientations.
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
 */

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
	// Release anything that can be recreated in viewDidLoad or on demand.
	// e.g. self.myOutlet = nil;
}


#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	// return 0;
    
    if (!self.menuList) {
        // construct the array of page descriptions we will use (each description is a dictionary)
        //
        self.menuList = [NSMutableArray array];
        
        // I feel ..
        FeelViewController *feelViewControler = [FeelViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //NSLocalizedString(@"I feel ...", @""), kTitleKey,
                                  @"feel.gif", kTitleKey,
                                  feelViewControler, kViewControllerKey,
                                  nil]];
        [feelViewControler release];
        
        // I need ...
        NeedViewController *needViewController = [NeedViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //NSLocalizedString(@"I need ...", @""), kTitleKey,
                                  @"need.gif", kTitleKey,
                                  needViewController, kViewControllerKey,
                                  nil]];
        [needViewController release];
        
        // I want ...
        WantViewController *wantViewController = [WantViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //NSLocalizedString(@"I want ...", @""), kTitleKey,
                                  @"want.gif", kTitleKey,
                                  wantViewController, kViewControllerKey,
                                  nil]];
        [wantViewController release];
        
        
        // I need help
        NeedHelpViewController *needHelpViewController = [NeedHelpViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //  NSLocalizedString(@"I need help!", @""), kTitleKey,
                                  @"needhelp.gif", kTitleKey,
                                  needHelpViewController, kViewControllerKey,
                                  nil]];
        [needHelpViewController release];
        
        // food
        FoodViewController *foodViewControler = [FoodViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  // NSLocalizedString(@"Food", @""), kTitleKey,
                                  @"food.gif", kTitleKey,
                                  foodViewControler, kViewControllerKey,
                                  nil]];
        [foodViewControler release];
        
        // Drinks
        DrinksViewController *drinksViewControler = [DrinksViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //NSLocalizedString(@"Drinks", @""), kTitleKey,
                                  @"drinks.gif", kTitleKey,
                                  drinksViewControler, kViewControllerKey,
                                  nil]];
        [drinksViewControler release];
        
        
        // Snacks
        SnacksViewController *snacksViewController = [SnacksViewController alloc];
        [self.menuList addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  //NSLocalizedString(@"Snacks", @""), kTitleKey,
                                  @"snacks.gif", kTitleKey,
                                  snacksViewController, kViewControllerKey,
                                  nil]];
        [snacksViewController release];        
    }
	return [self.menuList count];
    // return 7;
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
/*
	static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }
    
	// Configure the cell.

    return cell;
*/
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
	if (cell == nil)
	{
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellIdentifier] autorelease];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	
	//cell.textLabel.text = [[self.menuList objectAtIndex:indexPath.row] objectForKey:kTitleKey];
	cell.imageView.image = [UIImage imageNamed:[[self.menuList objectAtIndex:indexPath.row] objectForKey:kTitleKey]];

	return cell;
	
}



#pragma mark -
#pragma mark UITableViewDelegate

// Override to support row selection in the table view.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {	
    // Navigation logic may go here -- for example, create and push another view controller.
	// AnotherViewController *anotherViewController = [[AnotherViewController alloc] initWithNibName:@"AnotherView" bundle:nil];
	// [self.navigationController pushViewController:anotherViewController animated:YES];
	// [anotherViewController release];
	
	UIViewController *targetViewController = [[self.menuList objectAtIndex: indexPath.row] objectForKey:kViewControllerKey];
	if (targetViewController) {
		//check the app to see if it isBoy
		[(PictureBaseViewController*) targetViewController setBoy:[(iInteractAppDelegate*)[[UIApplication sharedApplication] delegate] isBoy]];
		
		[[self navigationController] pushViewController:targetViewController animated:YES];
	}
}




/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/


/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source.
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }   
}
*/


/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/


/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	
	//set the row color to match the view it navigates to
	//Reference: <<http://www.iphonedevsdk.com/forum/iphone-sdk-development/4999-uitableviewcell-backgroundcolor.html>>
	UIViewController *targetViewController = [[self.menuList objectAtIndex: indexPath.row] objectForKey:kViewControllerKey];
	if (targetViewController) {
		[cell setBackgroundColor:[[[[self.menuList objectAtIndex:indexPath.row] objectForKey:kViewControllerKey] view] backgroundColor]];
	}
	[[cell textLabel] setFont:[UIFont fontWithName:@"Arial" size:48.0] ];
	if ( [targetViewController isKindOfClass:[FoodViewController class]] ) {
		[[cell textLabel] setTextColor:[UIColor whiteColor]];
		[[cell textLabel] setTextColor:[UIColor whiteColor]];
		[[cell accessoryView] setBackgroundColor:[UIColor whiteColor]];
	}
}

- (void)dealloc {
    [super dealloc];
}


@end

