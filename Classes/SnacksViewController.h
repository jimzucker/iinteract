//
//  SnacksViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface SnacksViewController : PictureBaseViewController {
	IBOutlet UIButton	*pretzelBtn;
	IBOutlet UIButton	*fruitBtn;
	IBOutlet UIButton	*chipsBtn;
	IBOutlet UIButton	*cookieBtn;
}


- (IBAction)pretzel:(id)sender;
- (IBAction)fruit:(id)sender;
- (IBAction)chips:(id)sender;
- (IBAction)cookie:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*pretzelBtn;
@property (nonatomic, retain) IBOutlet UIButton	*fruitBtn;
@property (nonatomic, retain) IBOutlet UIButton	*chipsBtn;
@property (nonatomic, retain) IBOutlet UIButton	*cookieBtn;

@end
