//
//  NeedHelpViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface NeedHelpViewController : PictureBaseViewController {
	IBOutlet UIButton	*headacheBtn;
	IBOutlet UIButton	*cutBtn;
	IBOutlet UIButton	*stomachBtn;
}


- (IBAction)headache:(id)sender;
- (IBAction)cut:(id)sender;
- (IBAction)stomach:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*headacheBtn;
@property (nonatomic, retain) IBOutlet UIButton	*cutBtn;
@property (nonatomic, retain) IBOutlet UIButton	*stomachBtn;

@end
