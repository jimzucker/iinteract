//
//  FeelingsViewController.h
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>


@interface FeelingsViewController : UIViewController {

	//feelings
	IBOutlet UIButton	*happyBtn;
	IBOutlet UIButton	*sadBtn;
	IBOutlet UIButton	*angryBtn;
	IBOutlet UILabel	*iFeelLabel;
	
	//sound
	NSThread *soundPlayerThread;
	AVAudioPlayer *soundPlayer;
	
}

- (IBAction)iAmHappy:(id)sender ;
- (IBAction)iAmSad:(id)sender ;
- (IBAction)iAmAngry:(id)sender ;

- (void) runSound: (NSString *) theSound;

@property (nonatomic, retain) IBOutlet UIButton	*happyBtn;
@property (nonatomic, retain) IBOutlet UIButton	*sadBtn;
@property (nonatomic, retain) IBOutlet UIButton	*angryBtn;
@property (nonatomic, retain) IBOutlet UILabel	*iFeelLabel;

@end
