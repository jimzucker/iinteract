//
//  DrinksViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface DrinksViewController : PictureBaseViewController {
	IBOutlet UIButton	*milkBtn;
	IBOutlet UIButton	*waterBtn;
	IBOutlet UIButton	*juiceBtn;
	IBOutlet UIButton	*sodaBtn;

}

- (IBAction)milk:(id)sender;
- (IBAction)water:(id)sender;
- (IBAction)juice:(id)sender;
- (IBAction)soda:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*milkBtn;
@property (nonatomic, retain) IBOutlet UIButton	*waterBtn;
@property (nonatomic, retain) IBOutlet UIButton	*juiceBtn;
@property (nonatomic, retain) IBOutlet UIButton	*sodaBtn;

@end
