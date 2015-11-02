//
//  FeelViewController.h
//  iInteract
//
//  Created by James Zucker on 3/28/10.
//  Copyright 2010 James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface FeelViewController : PictureBaseViewController {
	
	//feelings
	IBOutlet UIButton	*happyBtn;
	IBOutlet UIButton	*sadBtn;
	IBOutlet UIButton	*angryBtn;
	
}

- (IBAction)happy:(id)sender;
- (IBAction)sad:(id)sender;
- (IBAction)angry:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*happyBtn;
@property (nonatomic, retain) IBOutlet UIButton	*sadBtn;
@property (nonatomic, retain) IBOutlet UIButton	*angryBtn;

@end
