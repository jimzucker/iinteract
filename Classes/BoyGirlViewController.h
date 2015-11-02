//
//  BoyGirlViewController.h
//  iInteract
//
//  Created by James Zucker on 3/31/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface BoyGirlViewController : UIViewController <UIActionSheetDelegate> {
	IBOutlet UIButton *boyBtn;
	IBOutlet UIButton *girlBtn;
}

- (IBAction) boy ;
- (IBAction) girl ;

@property (nonatomic, retain) IBOutlet UIButton *boyBtn;
@property (nonatomic, retain) IBOutlet UIButton *girlBtn;
@end
