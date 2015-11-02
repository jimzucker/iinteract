//
//  NeedViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface NeedViewController : PictureBaseViewController {
	
	//feelings
	IBOutlet UIButton	*drinkBtn;
	IBOutlet UIButton	*eatBtn;
	IBOutlet UIButton	*bathroomBtn;
	IBOutlet UIButton	*takeBreakBtn;
	
}

- (IBAction)drink:(id)sender;
- (IBAction)eat:(id)sender;
- (IBAction)bathroom:(id)sender;
- (IBAction)takeBreak:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*drinkBtn;
@property (nonatomic, retain) IBOutlet UIButton	*eatBtn;
@property (nonatomic, retain) IBOutlet UIButton	*bathroomBtn;
@property (nonatomic, retain) IBOutlet UIButton	*takeBreakBtn;
@end
