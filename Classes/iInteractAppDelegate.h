//
//  iInteractAppDelegate.h
//  iInteract
//
//  Created by James Zucker on 3/22/10.
//  Copyright  James A Zucker 2010. All rights reserved.
//

@interface iInteractAppDelegate : NSObject <UIApplicationDelegate> {
    
    UIWindow *window;
    UINavigationController *navigationController;
	
	BOOL boy;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UINavigationController *navigationController;

@property (nonatomic,assign,getter=isBoy) BOOL boy;

@end

