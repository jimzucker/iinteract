//
//  RootViewController.h
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright  James A Zucker 2010. All rights reserved.
//

@interface RootViewController : UITableViewController <UIActionSheetDelegate> {
	
	NSMutableArray *menuList;
}

@property (nonatomic, retain) NSMutableArray *menuList;

@end
