//
//  QCMediaCrushImageUploader.m
//  ImageUp
//
//  Created by Ian McCullough on 10/6/14.
//  Copyright (c) 2014 Quenton Cook. All rights reserved.
//

#import "QCMediaCrushImageUploader.h"
#import <Adium/AIChat.h>
#import <AIUtilities/AIImageAdditions.h>

NSString* QCMediaCrushHostConfigKey = @"mediacrushHost";
NSString* QCMediaCrushPortConfigKey = @"mediacrushPort";
NSString* QCMediaCrushSchemeConfigKey = @"mediacrushScheme";

@implementation QCMediaCrushImageUploader

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults: @{ QCMediaCrushHostConfigKey : @"mediacru.sh",
                                                                    QCMediaCrushPortConfigKey : @((in_port_t)443),
                                                                    QCMediaCrushSchemeConfigKey : @"https" }];
    });
}

- (NSString*)scheme
{
    return [[NSUserDefaults standardUserDefaults] objectForKey: QCMediaCrushSchemeConfigKey];
}

- (NSString*)host
{
    return [[NSUserDefaults standardUserDefaults] objectForKey: QCMediaCrushHostConfigKey];
}

- (in_port_t)port
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey: QCMediaCrushPortConfigKey] unsignedShortValue];
}

+ (NSString *)serviceName
{
    return @"Mediacru.sh";
}

- (NSString *)uploadURL
{
    NSString* host = [NSString stringWithFormat: @"%@:%@", self.host, @(self.port)];
    return [[[NSURL alloc] initWithScheme: self.scheme host: host path: @"/api/upload/file"] absoluteString];
}

- (NSString *)fieldName
{
    return @"image";
}

- (NSArray *)additionalFields
{
    return nil;
}

- (NSUInteger)maximumSize
{
    return 2500000;
}

+ (NSData *)contentPartObjectsForKeys:(NSDictionary *)dict content:(NSData *)content
{
    NSMutableData *partData = [[NSMutableData alloc] init];
    NSMutableString *header = [[NSMutableString alloc] init];
    
    [header appendString:@"Content-Disposition: form-data;"];
    
    if (dict)
    {
        NSArray *keys = [dict allKeys];
        
        for(NSString *key in keys)
        {
            [header appendFormat:@" %@=\"%@\";", key, [dict objectForKey:key]];
        }
    }
    [header appendString:@"\r\n"];
    
    [header appendString:@"Content-Type: application/octet-stream\r\n"];
    [header appendString:[NSString stringWithFormat:@"Content-Length: %li\r\n", content ? [content length] : 0]];
    [header appendFormat:@"Content-Transfer-Encoding: binary\r\n"];
    
    [header appendString:@"\r\n"];
    
    [partData appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    if (content)
        [partData appendData:content];
    
    return partData;
}

+ (NSMutableURLRequest *)defaultRequestWithUrl:(NSString *)urlString httpMethod:(NSString *)httpMethod contentParts:(NSArray *)parts
{
    NSMutableURLRequest *request= [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:100.0];
    [request setHTTPMethod:httpMethod];
    
    NSString *boundary = @"---------------------------14737809831466499882746641449";
    [request addValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField: @"Content-Type"];
    NSBundle* bundle = [NSBundle bundleForClass: [QCMediaCrushImageUploader class]];
    if (bundle)
    {
        [request addValue:[NSString stringWithFormat:@"%@ v%@", bundle.bundlePath.lastPathComponent, bundle.infoDictionary[@"CFBundleVersion"]] forHTTPHeaderField: @"User-Agent"];
    }
    [request addValue:@"text" forHTTPHeaderField: @"Accept"];
    
    NSMutableData *postbody = [NSMutableData data];
    
    if (parts)
    {
        for (NSData *data in parts)
        {
            [postbody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            
            [postbody appendData:data];
            
            [postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    [request setHTTPBody:postbody];
    [request addValue:[NSString stringWithFormat:@"%d", (int)[postbody length]] forHTTPHeaderField: @"Content-Length"];
    
    return request;
}

- (void)uploadImage
{
    NSBitmapImageFileType bestType;
    
    NSData *pngRepresentation = [[image largestBitmapImageRep] representationUsingType:NSPNGFileType properties:nil];
    NSData *jpgRepresentation = [[image largestBitmapImageRep] representationUsingType:NSJPEGFileType properties:nil];
    NSData *imageRepresentation;
    
    if (pngRepresentation.length > jpgRepresentation.length) {
        bestType = NSJPEGFileType;
        imageRepresentation = jpgRepresentation;
    } else {
        bestType = NSPNGFileType;
        imageRepresentation = pngRepresentation;
    }
    
    if (imageRepresentation.length > self.maximumSize) {
        imageRepresentation = [image representationWithFileType:bestType maximumFileSize:self.maximumSize];
    }
    
    if (!imageRepresentation) {
        [uploader errorWithMessage:@"Unable to upload" forChat:chat];
        return;
    }
    
    NSData *contentPart = [[self class] contentPartObjectsForKeys:
                           @{ @"name" : @"file",
                              @"filename" : @"image",
                              @"private" : @"false"} content: imageRepresentation];
    
    NSArray *requestParts = [NSArray arrayWithObject: contentPart];
    
    NSString* urlString = [NSString stringWithFormat: @"%@://%@:%@/api/upload/file", self.scheme, self.host, @(self.port)];
    
    NSURLRequest *request = [[self class] defaultRequestWithUrl: urlString httpMethod: @"POST" contentParts: requestParts];
    
    dataUploader = [AIProgressDataUploader dataUploaderWithData: request.HTTPBody
                                                            URL: request.URL
                                                        headers: request.allHTTPHeaderFields
                                                       delegate: self
                                                        context: nil];
    
    [dataUploader upload];
}

#pragma mark Response parsing

- (void)parseResponse:(NSData *)data
{
    NSError* error = nil;
    NSDictionary* d = [NSJSONSerialization JSONObjectWithData: data options:(NSJSONReadingOptions)0 error: &error];
    
    if (error)
    {
        [uploader errorWithMessage: error.localizedDescription forChat: chat];
    }
    else
    {
        NSString* hash = d[@"hash"];
        if (hash.length)
        {
            BOOL hidePort = ([self.scheme isEqual: @"http"] && self.port == 80) || ([self.scheme isEqual: @"https"] && self.port == 443);
            NSString* host = hidePort ? self.host : [NSString stringWithFormat: @"%@:%@", self.host, @(self.port)];
            NSString* urlString = [NSString stringWithFormat: @"%@://%@/%@", self.scheme, host, hash];
            [uploader uploadedURL: urlString forChat: chat];
        }
        else
        {
            [uploader errorWithMessage: @"Image appeared to upload, but we didn't get a hash back from the service." forChat: chat];
        }
    }
}

@end
