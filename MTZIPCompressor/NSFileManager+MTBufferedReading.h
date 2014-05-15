//
//  NSFileManager+MTBufferedReading.h
//  MTZIPCompressor
//
//  Created by Matias Piipari on 15/05/2014.
//  Copyright (c) 2014 Mekentosj BV. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *MTFileReaderErrorDomain;

typedef NS_ENUM(NSUInteger, MTFileReaderErrorCode)
{
    MTFileReaderErrorCodeUnknown = 0,
    MTFileReaderErrorCodeFailedToDetermineFileSize = 1,
    MTFileReaderErrorCodeFailedToReadFromChannel = 2,
    MTFileReaderErrorCodeFailedToOpenReadChannel = 3
};

@interface NSFileManager (MTBufferedReading)

- (void)readFileAtPath:(NSString *)filePath
      readChannelQueue:(dispatch_queue_t)readQueue
       processingQueue:(dispatch_queue_t)processQueue
        inChunksOfSize:(size_t)chunkSize
          forEachChunk:(BOOL(^)(dispatch_data_t region,
                                size_t offset, const void *buffer, size_t size))applyBlock
     completionHandler:(void(^)(NSError *e))completionHandler;

@end

@interface NSString (MTRelativePath)

// From https://github.com/karelia/KSFileUtilities/blob/master/KSPathUtilities.m
- (NSString *)pathRelativeToDirectory:(NSString *)dirPath;

@end
