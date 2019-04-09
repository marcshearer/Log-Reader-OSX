//
//  GrayTextFieldCell.m
//  Log Reader OSX
//
//  Created by Marc Shearer on 08/04/2019.
//  Copyright © 2019 Marc Shearer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GrayTextFieldCell : NSTextFieldCell

@end

@implementation GrayTextFieldCell

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [self setTextColor:(backgroundStyle==NSBackgroundStyleDark ? [NSColor blackColor] : [NSColor blueColor])];
}

@end
