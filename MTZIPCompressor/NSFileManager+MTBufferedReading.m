//
//  NSFileManager+MTBufferedReading.m
//  MTZIPCompressor
//
//  Created by Matias Piipari on 15/05/2014.
//  Copyright (c) 2014 Mekentosj BV. All rights reserved.
//

#import "NSFileManager+MTBufferedReading.h"

NSString *MTFileReaderErrorDomain = @"MTFileReaderErrorDomain";

@implementation NSFileManager (MTBufferedReading)

- (void)readFileAtPath:(NSString *)filePath
      readChannelQueue:(dispatch_queue_t)readQueue
       processingQueue:(dispatch_queue_t)processQueue
        inChunksOfSize:(size_t)chunkSize
          forEachChunk:(BOOL(^)(dispatch_data_t region,
                                size_t offset, const void *buffer, size_t size))applyBlock
     completionHandler:(void(^)(NSError *e))completionHandler
{
    if (readQueue == processQueue)
        @throw [NSException exceptionWithName:@"MTInvalidArgumentException"
                                       reason:@"readQueue == processQueue: will deadlock" userInfo:nil];
    // Open the channel for reading.
    
    __block NSError *err = nil;
    __block dispatch_io_t channel
        = dispatch_io_create_with_path(DISPATCH_IO_STREAM, [filePath UTF8String], O_RDONLY, 0, readQueue,
                                       ^(int error) {
        // Cleanup code
        if (error == 0)
        {
            channel = nil;
            completionHandler(err);
        }
    });
    
    // If the file channel could not be created, abort
    if (!channel)
    {
        completionHandler([NSError errorWithDomain:MTFileReaderErrorDomain
                                              code:MTFileReaderErrorCodeFailedToOpenReadChannel userInfo:nil]);
        return;
    }
    
    NSNumber* theSize = nil;
    NSInteger fileSize = 0;
    
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    if ([fileURL getResourceValue:&theSize forKey:NSURLFileSizeKey error:nil])
        fileSize = [theSize integerValue];
    
    if (fileSize == 0)
    {
        completionHandler([NSError errorWithDomain:MTFileReaderErrorDomain
                                              code:MTFileReaderErrorCodeFailedToDetermineFileSize userInfo:nil]);
        return;
    }
    
    __block off_t currentOffset = 0;
    
    static dispatch_once_t onceToken;
    static dispatch_queue_t scheduler_queue;
    dispatch_once(&onceToken,
                  ^{ scheduler_queue = dispatch_queue_create("com.mekentosj.reader.scheduler", DISPATCH_QUEUE_SERIAL); });
    
    dispatch_sync(scheduler_queue,
    ^{
        for (currentOffset = 0; currentOffset < fileSize; currentOffset += chunkSize) {
            // Read through file in buffers of chunkSize
            // offset constant at 0 because channel is opened in mode DISPATCH_IO_STREAM.
            // In mode DISPATCH_IO_STREAM the offset is incremented on each read.
            dispatch_io_read(channel, 0, chunkSize, processQueue,
                             ^(bool done, dispatch_data_t data, int error)
            {
                if (error)
                {
                    err = [NSError errorWithDomain:MTFileReaderErrorDomain code:MTFileReaderErrorCodeFailedToReadFromChannel userInfo:nil];
                    return;
                }
                
                dispatch_data_apply(data,
                                    (dispatch_data_applier_t)^(dispatch_data_t region,
                                                               size_t offset,
                                                               const void *buffer,
                                                               size_t size)
                {
                    @autoreleasepool
                    {
                        BOOL shouldContinue = applyBlock(region, offset, buffer, size);
                        assert(shouldContinue);
                        return shouldContinue;
                    }
                });
            });
        }
        
        dispatch_sync(readQueue, ^{ dispatch_io_close(channel, 0); });
    });
}

@end


@implementation NSString (MTRelativePath)

// From https://github.com/karelia/KSFileUtilities/blob/master/KSPathUtilities.m
- (NSString *)pathRelativeToDirectory:(NSString *)dirPath
{
    if ([dirPath isAbsolutePath])
    {
        if (![self isAbsolutePath]) return self;    // job's already done for us!
    }
    else
    {
        // An absolute path relative to a relative path is always going to be self
        if ([self isAbsolutePath]) return self;
        
        // But comparing two relative paths is a bit of an edge case. Internally, pretend they're absolute
        dirPath = (dirPath ? [@"/" stringByAppendingString:dirPath] : @"/");
        return [[@"/" stringByAppendingString:self] pathRelativeToDirectory:dirPath];
    }
    
    
    // Easy way out
    if ([self isEqualToString:dirPath])
        return @""; // . is not a relative path - took it out. Also messes up the dropbox controller
    
    
    // Determine the common ancestor directory containing both paths. String comparison is a naive first pass...
    NSString *commonDir = [self commonPrefixWithString:dirPath options:NSLiteralSearch];
	if ([commonDir isEqualToString:@""]) return self;
    
    // ...as what the paths have in common could be two similar folder names
    // e.g. /foo/barnicle and /foo/bart/baz
    // If so, wind back to the nearest slash
    if (![commonDir hasSuffix:@"/"])
    {
        if ([self length] > [commonDir length] &&
            [self characterAtIndex:[commonDir length]] != '/')
        {
            NSUInteger separatorLocation = [commonDir rangeOfString:@"/" options:NSBackwardsSearch].location;
            if (separatorLocation == NSNotFound) separatorLocation = 0;
            commonDir = [commonDir substringToIndex:separatorLocation];
        }
        else if ([dirPath length] > [commonDir length] &&
                 [dirPath characterAtIndex:[commonDir length]] != '/')
        {
            NSUInteger separatorLocation = [commonDir rangeOfString:@"/" options:NSBackwardsSearch].location;
            if (separatorLocation == NSNotFound) separatorLocation = 0;
            commonDir = [commonDir substringToIndex:separatorLocation];
        }
    }
    
    
    NSMutableString *result = [NSMutableString stringWithCapacity:
                               [self length] + [dirPath length] - 2*[commonDir length]];
    
    
    // How do you get from the directory path, to commonDir?
    NSString *otherDifferingPath = [dirPath substringFromIndex:[commonDir length]];
	NSArray *hopsUpArray = [otherDifferingPath componentsSeparatedByString:@"/"];
    
	for (NSString *aComponent in hopsUpArray)
    {
        if ([aComponent length] && ![aComponent isEqualToString:@"."])
        {
            NSAssert(![aComponent isEqualToString:@".."], @".. unsupported");
            if ([result length]) [result appendString:@"/"];
            [result appendString:@".."];
        }
    }
    
    
    // And then navigating from commonDir, to self, is mostly a simple append
	NSString *pathRelativeToCommonDir = [self substringFromIndex:[commonDir length]];
    
    // But ignore leading slash(es) since they cause relative path to be reported as absolute
    while ([pathRelativeToCommonDir hasPrefix:@"/"])
    {
        pathRelativeToCommonDir = [pathRelativeToCommonDir substringFromIndex:1];
    }
    
    if ([pathRelativeToCommonDir length])
    {
        if ([result length]) [result appendString:@"/"];
        [result appendString:pathRelativeToCommonDir];
    }
    
    
    // Were the paths found to be equal?
	if ([result length] == 0)
    {
        [result appendString:@"."];
        [result appendString:[self substringFromIndex:[commonDir length]]]; // match original's oddities
    }
    
    
	return result;
}

@end