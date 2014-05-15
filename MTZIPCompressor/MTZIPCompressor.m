// Papers for Mac
// Author: Matias Piipari
//
// Copyright 2012 Mekentosj BV. All rights reserved.

#import "MTZIPCompressor.h"

#import "NSFileManager+MTBufferedReading.h"

#import "ZipFile.h"
#import "ZipException.h"
#import "FileInZipInfo.h"
#import "ZipWriteStream.h"
#import "ZipReadStream.h"



NSString * const MTZIPCompressorErrorDomain = @"MTZIPCompressorErrorDomain";

@implementation MTZIPCompressor
@synthesize compressionQueue;

- (id)init
{
    if (self = [super init])
    {
        readQueue = dispatch_queue_create("com.mekentosj.compress.read", 0);
        compressionQueue = dispatch_queue_create("com.mekentosj.compress.process", 0);
        compressionStreams = dispatch_semaphore_create(1); // just one write stream at a time
    }
    
    return self;
}

- (void)compressFileAtPath:(NSString *)filePath
               intoZIPFile:(ZipFile *)zipF
               ZIPFilePath:(NSString *)zipFPath
         completionHandler:(void(^)(NSError *e))completionHandler
{
    dispatch_semaphore_wait(compressionStreams, DISPATCH_TIME_FOREVER);
    __block ZipWriteStream *stream =
    [zipF writeFileInZipWithName:zipFPath compressionLevel:ZipCompressionLevelFastest];
    streamCount++;
    assert(streamCount < 2); // only one stream should be there at a time
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    [fm readFileAtPath:filePath readChannelQueue:readQueue processingQueue:compressionQueue
        inChunksOfSize:16384
          forEachChunk:^BOOL(dispatch_data_t region, size_t offset, const void *buffer, size_t size)
     {
         [stream writeBytes:buffer length:(unsigned int)size];
         return YES;
     }
     completionHandler:^(NSError *e)
     {
         [stream finishedWriting];
         stream = nil;
         completionHandler(e);
         streamCount--;
         dispatch_semaphore_signal(compressionStreams);
     }];
}

- (BOOL)compressFileAtPath:(NSString *)filePath intoZIPFileAtPath:(NSString *)zipPath error:(NSError **)error
{
    __block BOOL success = YES;
    dispatch_semaphore_t completion = dispatch_semaphore_create(0);
    [self compressFileAtPath:filePath intoZIPFileAtPath:zipPath completionHandler:^(NSError *e) {
        if (e)
        {
            success = NO;
            if (*error) *error = e;
        }
        dispatch_semaphore_signal(completion);
    }];
    dispatch_semaphore_wait(completion, DISPATCH_TIME_FOREVER);
    return success;
}

- (void)compressFileAtPath:(NSString *)filePath
         intoZIPFileAtPath:(NSString *)zipPath
         completionHandler:(void(^)(NSError *e))completionHandler
{
    NSDate *start = [NSDate date];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                   ^{
                       NSFileManager *fm = [[NSFileManager alloc] init];
                       BOOL isDir = NO;
                       BOOL fileExists = [fm fileExistsAtPath:filePath isDirectory:&isDir];
                       
                       
                       ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipPath mode:ZipFileModeCreate];
                       
                       if (fileExists && isDir)
                       {
                           dispatch_group_t compressions = dispatch_group_create();
                           
                           __block NSError *err = nil;
                           
                           NSURL *directoryURL = [NSURL fileURLWithPath:filePath];
                           NSArray *keys = @[NSURLIsDirectoryKey];
                           
                           NSDirectoryEnumerator *enumerator =
                           [fm enumeratorAtURL:directoryURL includingPropertiesForKeys:keys
                                       options:0
                                  errorHandler:^(NSURL *url, NSError *error)
                            { err = error; completionHandler(error); return NO; }];
                           
                           for (NSURL *url in enumerator)
                           {
                               if (err) break;
                               
                               NSNumber *isDirectory = nil;
                               if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&err])
                               {
                                   break;
                               }
                               else if (![isDirectory boolValue]) // a regular file under the enumerated dir
                               {
                                   dispatch_group_enter(compressions);
                                   NSString *relativePath = [[url path] pathRelativeToDirectory:filePath];
                                   [self compressFileAtPath:[url path]
                                                intoZIPFile:zipFile
                                                ZIPFilePath:relativePath
                                          completionHandler:^(NSError *compressionError)
                                    {
                                        if (compressionError) { err = compressionError; }
                                        dispatch_group_leave(compressions);
                                    }];
                               }
                           }
                           
                           dispatch_group_notify(compressions, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                 ^{
                                                     [zipFile close];
                                                     completionHandler(err);
                                                     NSLog(@"Total compression time: %f.1", [[NSDate date] timeIntervalSinceDate:start]);
                                                 });
                           return;
                       }
                       else if (fileExists) // a single regular file to compress
                       {
                           
                           [self compressFileAtPath:filePath
                                        intoZIPFile:zipFile
                                        ZIPFilePath:[filePath lastPathComponent]
                                  completionHandler:^(NSError *error) { completionHandler(error); }];
                           [zipFile close];
                           return;
                       }
                       else
                       {
                           completionHandler([NSError errorWithDomain:MTZIPCompressorErrorDomain
                                                                 code:MTZIPCompressorErrorCodeFileNotFound
                                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Compressing file failed because file could not be found at path '%@'", filePath]}]);
                           return;
                       }
                   });
}

@end