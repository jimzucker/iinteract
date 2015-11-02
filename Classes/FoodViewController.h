//
//  FoodViewController.h
//  iInteract
//
//  Created by James Zucker on 3/27/10.
//  Copyright 2010  James A Zucker. All rights reserved.
//

#import "PictureBaseViewController.h"

@interface FoodViewController : PictureBaseViewController {

	IBOutlet UIButton	*breakfastBtn;
	IBOutlet UIButton	*lunchBtn;
	IBOutlet UIButton	*dinnerBtn;
	IBOutlet UIButton	*desertBtn;

}

- (IBAction)breakfast:(id)sender;
- (IBAction)lunch:(id)sender;
- (IBAction)dinner:(id)sender;
- (IBAction)dessert:(id)sender;

@property (nonatomic, retain) IBOutlet UIButton	*breakfastBtn;
@property (nonatomic, retain) IBOutlet UIButton	*lunchBtn;
@property (nonatomic, retain) IBOutlet UIButton	*dinnerBtn;
@property (nonatomic, retain) IBOutlet UIButton	*desertBtn;

@end
