//
//  ComplicationController.swift
//  iInteractWatch Extension
//
//  Created by Jim Zucker on 12/4/15.
//  Copyright © 2015 Strategic Software Engineering LLC. All rights reserved.
//

import ClockKit


class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirectionsForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTimeTravelDirections) -> Void) {
        // Turn off time travelling
        handler([.None])
    }
    
    func getTimelineStartDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehaviorForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.ShowOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntryForComplication(complication: CLKComplication, withHandler handler: ((CLKComplicationTimelineEntry?) -> Void)) {
        // Call the handler with the current timeline entry
        handler(nil)
    }
    
    func getTimelineEntriesForComplication(complication: CLKComplication, beforeDate date: NSDate, limit: Int, withHandler handler: (([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries prior to the given date
        handler(nil)
    }
    
    func getTimelineEntriesForComplication(complication: CLKComplication, afterDate date: NSDate, limit: Int, withHandler handler: (([CLKComplicationTimelineEntry]?) -> Void)) {
        // Call the handler with the timeline entries after to the given date
        handler(nil)
    }
    
    // MARK: - Update Scheduling
    
    func getNextRequestedUpdateDateWithHandler(handler: (NSDate?) -> Void) {
        // Call the handler with the date when you would next like to be given the opportunity to update your complication content
        handler(nil);
    }
    
    // MARK: - Placeholder Templates
    
    func getPlaceholderTemplateForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTemplate?) -> Void) {
        // This method will be called once per supported complication, and the results will be cached
        var template: CLKComplicationTemplate? = nil
        let iconColor = UIColor(red: 255.0, green: 222.0, blue: 0.0, alpha: 1.0)
//        let iconColor = UIColor.yellowColor()
        
        switch complication.family {
        case .ModularSmall:
            let imageTemplate = CLKComplicationTemplateModularSmallSimpleImage()
            imageTemplate.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Complication/Modular")!)
            imageTemplate.tintColor = iconColor
            template = imageTemplate as CLKComplicationTemplate
        case .ModularLarge:
            template = nil
        case .UtilitarianSmall:
            let imageTemplate = CLKComplicationTemplateUtilitarianSmallRingImage()
            imageTemplate.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Complication/Utilitarian")!)
            imageTemplate.tintColor = iconColor
            template = imageTemplate as CLKComplicationTemplate
        case .UtilitarianLarge:
            template = nil
        case .CircularSmall:
            let imageTemplate = CLKComplicationTemplateCircularSmallSimpleImage()
            imageTemplate.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "Complication/Circular")!)
            imageTemplate.tintColor = iconColor
            template = imageTemplate as CLKComplicationTemplate
        }
        handler(template)
    }
}
