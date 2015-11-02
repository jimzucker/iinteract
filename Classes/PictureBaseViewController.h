//
//  PictureBaseViewController.h
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface PictureBaseViewController : UIViewController {
	//The Zoomed out button
	IBOutlet UIButton	*zoomButton;			
	IBOutlet UILabel	*theLabel;
	
	//the original button that was zoomed
	UIButton			*originalButton;
	
	//sound
	NSThread			*soundPlayerThread;
	AVAudioPlayer		*soundPlayer;	
	
	BOOL				boy;
}

- (void) zoomIn: (UIButton *)theBtn interaction:(NSString *)theInteraction;
- (IBAction)zoomOut:(id)sender;

@property (nonatomic, retain) IBOutlet UILabel	*theLabel;
@property (nonatomic, retain) UIButton			*originalButton;

@property (nonatomic,assign,getter=isBoy) BOOL boy;

@end