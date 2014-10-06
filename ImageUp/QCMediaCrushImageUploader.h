//
//  QCMediaCrushImageUploader.h
//  ImageUp
//
//  Created by Ian McCullough on 10/6/14.
//  Copyright (c) 2014 Quenton Cook. All rights reserved.
//

#import "QCGenericMultipartImageUploader.h"

@interface QCMediaCrushImageUploader : QCGenericMultipartImageUploader <NSXMLParserDelegate>{
    NSData						*resultData;
    NSXMLParser					*responseParser;
    
    // Parsing
    NSMutableDictionary			*lastElement;
    NSMutableDictionary			*currentElement;
    NSMutableDictionary			*response;
}

@end
