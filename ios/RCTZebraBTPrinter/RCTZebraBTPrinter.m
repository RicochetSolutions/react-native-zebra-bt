//
//  RCTZebraBTPrinter.m
//  RCTZebraBTPrinter
//
//  Created by Jakub Martyčák on 17.04.16.
//  Copyright © 2016 Jakub Martyčák. All rights reserved.
//

#import "RCTZebraBTPrinter.h"

//ZEBRA
#import "ZebraPrinterConnection.h"
#import "ZebraPrinter.h"
#import "ZebraPrinterFactory.h"
#import "TcpPrinterConnection.h"
#import "MfiBtPrinterConnection.h"
#import "NetworkDiscoverer.h"
#import <SGD.h>

@interface RCTZebraBTPrinter ()



@end


@implementation RCTZebraBTPrinter

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
    // run all module methods in main thread
    // if we don't no timer callbacks got called
    return dispatch_get_main_queue();
}

#pragma mark - Methods available form Javascript

RCT_EXPORT_METHOD(
    printLabel: (NSString *)userPrinterSerial
    userCommand:(NSString *)userCommand
    btEnabled: (NSString *)userBtEnabled
    resolve: (RCTPromiseResolveBlock)resolve
    rejector:(RCTPromiseRejectBlock)reject){

    NSLog(@"IOS >> printLabel triggered");

    //NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSLog(@"IOS >> Connecting");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {

        id<ZebraPrinterConnection, NSObject> thePrinterConn = nil;

        if(userBtEnabled){
            thePrinterConn = [[MfiBtPrinterConnection alloc] initWithSerialNumber:userPrinterSerial];

            [((MfiBtPrinterConnection*)thePrinterConn) setTimeToWaitAfterWriteInMilliseconds:30];
        } else {
            NSString *ipAddress = userPrinterSerial;
            thePrinterConn = [[[TcpPrinterConnection alloc] initWithAddress:ipAddress andWithPort:TcpPrinterConnection.DEFAULT_ZPL_TCP_PORT] autorelease];
        }

        BOOL success = [thePrinterConn open];

        if(success == YES){
            // set to zpl language
            NSError *error = nil;
            [SGD SET:@"device.languages" withValue:@"zpl" andWithPrinterConnection:thePrinterConn error:&error];

            if(error) {
                NSLog(@"Could not set language %@", error.localizedDescription);
                [thePrinterConn close];
                resolve((id)kCFBooleanFalse);
                
                return;
            }

//          NSLog(@"IOS >> Connected %@", userText1);

//          NSString *testLabel = @"^XA^FO100,60^A0N,25,25^FB400,2,10,C,0^FDTest label ZPL^FS^XZ";

            NSString *printLabel;
            
            printLabel = [NSString stringWithFormat: @"%@", userCommand];

            error = nil;

            // Send the data to printer as a byte array.
            // NSData *data = [NSData dataWithBytes:[testLabel UTF8String] length:[testLabel length]];

            success = success && [thePrinterConn write:[printLabel dataUsingEncoding:NSUTF8StringEncoding] error:&error];

            NSLog(@"IOS >> Sending Data");

            dispatch_async(dispatch_get_main_queue(), ^{
                if (success != YES || error != nil) {

                    NSLog(@"IOS >> Failed to send");

                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Printing Error" message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action)];

                    [errorAlert addAction:defaultAction];
                    [self presentViewController:errorAlert animated:YES completion:nil];

                    //UIAlertView *errorAlert = [[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                    //[errorAlert show];
                    //[errorAlert release];
                }
            });
            // Close the connection to release resources.
            [thePrinterConn close];
            //[thePrinterConn release];
            resolve((id)kCFBooleanTrue);
        } else {

            NSLog(@"IOS >> Failed to connect");
            resolve((id)kCFBooleanFalse);

        }
    });
}


RCT_EXPORT_METHOD(checkPrinterStatus: (NSString *)serialCode
                            resolver: (RCTPromiseResolveBlock)resolve
                            rejector: (RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
        id<ZebraPrinterConnection, NSObject> connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:serialCode];
        [((MfiBtPrinterConnection*)connection) setTimeToWaitAfterWriteInMilliseconds:80];
        BOOL success = [connection open];
        if (success) {
            NSError *error = nil;
            [SGD SET:@"device.languages" withValue:@"zpl" andWithPrinterConnection:connection error:&error];
            [SGD SET:@"ezpl.media_type" withValue:@"continuous" andWithPrinterConnection:connection error:&error];
            [SGD SET:@"zpl.label_length" withValue:@"100" andWithPrinterConnection:connection error:&error];
            if (error) {
                NSLog(@"asssddd %@", error.localizedDescription);
                resolve((id)kCFBooleanFalse);
                return;
            }
        }
        if (success) {
            NSError *error = nil;
            id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
            if (error) {
                NSLog(@"%@", error.localizedDescription);
                [connection close];
                resolve((id)kCFBooleanFalse);
                return;
            }

            PrinterStatus *status = [printer getCurrentStatus:&error];
            if (error) {
                NSLog(@"wtf %@", error.localizedDescription);
                [connection close];
                resolve((id)kCFBooleanFalse);
                return;
            }

            NSLog(@"Is printer ready to print: %d", (int)status.isReadyToPrint);
            [connection close];
            resolve(status.isReadyToPrint ? (id)kCFBooleanTrue : (id)kCFBooleanFalse);
        } else {
            [connection close];
            resolve((id)kCFBooleanFalse);
            NSLog(@"Failed to connect to printer");
        }
    });
}

RCT_EXPORT_METHOD(discoverPrinters:
        resolver: (RCTPromiseResolveBlock)resolve
        rejector: (RCTPromiseRejectBlock)reject){

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
                NSArray *printers = [NetworkDiscoverer localBroadcast:nil];

                if(printers){
                    resolve(printers);
                } else {
                    NSError *error;
                    reject(@"no_printers_found", @"Printers not found", error);
                }
            });

}

@end
