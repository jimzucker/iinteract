//
//  WantViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface WantViewController : PictureBaseViewController {
	IBOutlet UIButton	*computerBtn;
	IBOutlet UIButton	*playBtn;
	IBOutlet UIButton	*bookBtn;
	IBOutlet UIButton	*tvBtn;
}


- (IBAction)computer:(id)sender;
- (IBAction)play:(id)sender;
- (IBAction)book:(id)sender;
- (IBAction)tv:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*computerBtn;
@property (nonatomic, retain) IBOutlet UIButton	*playBtn;
@property (nonatomic, retain) IBOutlet UIButton	*bookBtn;
@property (nonatomic, retain) IBOutlet UIButton	*tvBtn;

@end
