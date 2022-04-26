//
//  liboscparseTests.m
//  liboscparseTests
//
//  Created by Robert Kylberg on 11/10/21.
//  Copyright © 2021 Line6. All rights reserved.
//

#import <XCTest/XCTest.h>
#include <iostream>

#include "lop.h"

@interface liboscparseTests : XCTestCase

@end

@implementation liboscparseTests

// int generic_handler(const char *path, const char *types, lop_arg ** argv,
//                     int argc, struct _lop_message* data, void *user_data)
// {
//     int i;

//     printf("path: <%s>\n", path);
//     for (i = 0; i < argc; i++) {
//         printf("arg %d '%c' ", i, types[i]);
//         lop_arg_pp((lop_type)types[i], argv[i]);
//         printf("\n");
//     }
//     printf("\n");
//     fflush(stdout);

//     return 1;
// }

void error(int num, const char *msg, const char *path)
{
    printf("liblo server error %d in path %s: %s\n", num, path, msg);
    fflush(stdout);
}

/* catch any incoming messages and display them. returning 1 means that the
 * message has not been fully handled and the server should try other methods */
int generic_handler(const char *path, const char *types, lop_arg ** argv,
                    int argc, struct _lop_message* data, void *user_data)
{
    int i;

    printf("generic:\n");
    printf("path: <%s>\n", path);
    for (i = 0; i < argc; i++) {
        printf("arg %d '%c' ", i, types[i]);
        lop_arg_pp((lop_type)types[i], argv[i]);
        printf("\n");
    }
    printf("\n");
    fflush(stdout);

    return 1;
}

int foo_handler(const char *path, const char *types, lop_arg ** argv,
                int argc, lop_message data, void *user_data)
{
    /* example showing pulling the argument values out of the argv array */
    printf("foo: %s <- f:%f, i:%d\n\n", path, argv[0]->f, argv[1]->i);
    fflush(stdout);

    return 0;
}

int blobtest_handler(const char *path, const char *types, lop_arg ** argv,
                     int argc, lop_message data, void *user_data)
{
    /* example showing how to get data for a blob */
    int i, size = lop_blob_datasize((lop_blob)argv[0]);
    char mydata[6];

    unsigned char *blobdata = (unsigned char*)lop_blob_dataptr((lop_blob)argv[0]);
    int blobsize = lop_blob_datasize((lop_blob)argv[0]);

    /* Alternatively:
     * blobdata = &argv[0]->blob.data;
     * blobsize = argv[0]->blob.size;
     */

    /* Don't trust network input! Blob can be anything, so check if
       each character is a letter A-Z. */
    for (i=0; i<6 && i<blobsize; i++)
        if (blobdata[i] >= 'A' && blobdata[i] <= 'Z')
            mydata[i] = blobdata[i];
        else
            mydata[i] = '.';
    mydata[5] = 0;

    printf("blob:\n");
    printf("%s <- length:%d '%s'\n\n", path, size, mydata);
    fflush(stdout);

    return 0;
}

int blobalt_handler(const char *path, const char *types, lop_arg ** argv,
                     int argc, lop_message data, void *user_data)
{
    printf("blobalt ");
    return blobtest_handler(path, types, argv, argc, data, user_data);
}

int pattern_handler(const char *path, const char *types, lop_arg ** argv,
                    int argc, lop_message data, void *user_data)
{
    printf("pattern handler matched: %s\n\n", path);
    fflush(stdout);

    // Let the dispatcher continue by returning non-zero, so
    // quit_handler can also catch the message
    return 1;
}

static int done = 0;

int quit_handler(const char *path, const char *types, lop_arg ** argv,
                 int argc, lop_message data, void *user_data)
{
    done = 1;
    printf("quiting\n\n");
    fflush(stdout);

    return 0;
}

- (void) send:(std::string)path server:(lop_server)s message:(lop_message)m {
    size_t      size = 250;
    char        buffer[size];

    lop_server_dispatch_data(s, lop_message_serialise(m, path.c_str(), buffer, &size), size);
}

const char testdata[6] = "ABCDE";

- (void) testInit {
    lop_err_handler  eh  = error;
    lop_send_handler sh  = NULL;
    void*            sha = NULL;

    lop_server s = lop_server_new(eh, sh, sha);
    XCTAssertTrue(s != 0);

    /* add method that will match any path and args */
    lop_server_add_method(s, NULL, NULL, generic_handler, NULL);

    /* add method that will match the path /foo/bar, with two numbers, coerced
     * to float and int */
    lop_server_add_method(s, "/foo/bar", "fi", foo_handler, NULL);

    /* add method that will match the path /blobtest with one blob arg */
    lop_server_add_method(s, "/blobtest", "b", blobtest_handler, NULL);

    /* add method that will match the path /blobtest with one blob arg */
    lop_server_add_method(s, "/blobalt", "b", blobalt_handler, NULL);

    /* catch any message starting with /g using a pattern method */
    lop_server_add_method(s, "/p*", "", pattern_handler, NULL);

    /* also catch "/q*", but glob_handle returns 1, so quit_handler
     * gets called after */
    lop_server_add_method(s, "/q*", "", pattern_handler, NULL);

    /* add method that will match the path /quit with no args */
    lop_server_add_method(s, "/quit", "", quit_handler, NULL);

    printf("\n");

    /* build a blob object from some data */
    lop_blob btest = lop_blob_new(sizeof(testdata), testdata);

    lop_message m = lop_message_new();
    lop_message_add(m, "is", 786, "hello");
    [self send:"/Bismillah/ar/Rahman/ar/Rahim" server:s message:m];
    lop_message_free(m);

    /* send a pattern message to /foo/bar handler; note that
     * pattern messages will be dispatched by all matching
     * handlers, so the generic handler will also trigger. */
    m = lop_message_new();
    lop_message_add(m, "ff", 0.12345678f, 34.0f);
    [self send:"/f*/bar" server:s message:m];
    lop_message_free(m);

    /* send a pattern message to /foo/bar handler */
    m = lop_message_new();
    lop_message_add(m, "ff", 0.12345678f, 56.0f);
    [self send:"/foo/b*" server:s message:m];
    lop_message_free(m);

    /* send a pattern message to /foo/bar handler */
    m = lop_message_new();
    lop_message_add(m, "ff", 0.12345678f, 78.0f);
    [self send:"/f*" server:s message:m];
    lop_message_free(m);

    /* send a message to /a/b/c/d with a mixture of float and string arguments */
    m = lop_message_new();
    lop_message_add(m, "sfsff", "one", 0.12345678f, "three", -0.00000023001f, 1.0);
    [self send:"/a/b/c/d" server:s message:m];
    lop_message_free(m);

    /* send a 'blob' object to /a/b/c/d */
    m = lop_message_new();
    lop_message_add(m, "b", btest);
    [self send:"/a/b/c/d" server:s message:m];
    
    /* send a 'blob' object to /blobtest */
    [self send:"/blobtest" server:s message:m];
    
    /* send a 'blob' object to /blobtest */
    [self send:"/b*" server:s message:m];
    lop_message_free(m);

    /* send a message to test method dispatch pattern matching */
    m = lop_message_new();
    lop_message_add(m, "");
    [self send:"/patterntest" server:s message:m];
    lop_message_free(m);

    /* send a jamin scene change instruction with a 32bit integer argument */
    m = lop_message_new();
    lop_message_add(m, "i", 2);
    [self send:"/jamin/scene" server:s message:m];
    lop_message_free(m);

    lop_server_free(s);
}

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
