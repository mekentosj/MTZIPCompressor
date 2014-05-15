// Papers for Mac
// Author: Matias Piipari
//
// Copyright 2012 Mekentosj BV. All rights reserved.

#import <Foundation/Foundation.h>

extern NSString * const MTZIPCompressorErrorDomain;

typedef enum MTZIPCompressorErrorCode
{
    MTZIPCompressorErrorCodeUnknown = 0,
    MTZIPCompressorErrorCodeFileNotFound = 1
} MTZIPCompressorErrorCode;

@interface MTZIPCompressor : NSObject
{
    dispatch_queue_t readQueue;
    dispatch_queue_t compressionQueue;
    dispatch_semaphore_t compressionStreams;
    
@private
    NSInteger streamCount;
}

@property (readonly) dispatch_queue_t compressionQueue;

- (void)compressFileAtPath:(NSString *)filePath
         intoZIPFileAtPath:(NSString *)zipPath
         completionHandler:(void(^)(NSError *e))completionHandler;

- (BOOL)compressFileAtPath:(NSString *)filePath
         intoZIPFileAtPath:(NSString *)zipPath
                     error:(NSError **)error;

@end
