/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "QCImageUploaderWindowController.h"

#import <AIUtilities/AIStringAdditions.h>

@interface QCImageUploaderWindowController()
- (id)initWithWindowNibName:(NSString *)nibName
				   delegate:(id)inDelegate
					   chat:(AIChat *)inChat;

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end

@implementation QCImageUploaderWindowController
+ (id)displayProgressInWindow:(NSWindow *)window
					 delegate:(id)inDelegate
						 chat:(AIChat *)inChat
{
	QCImageUploaderWindowController *newController = [[self alloc] initWithWindowNibName:@"QCImageUploaderProgress"
																				delegate:inDelegate
																					chat:inChat];

	[NSApp beginSheet:newController.window
	   modalForWindow:window
		modalDelegate:newController
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
		  contextInfo:nil];
	
	return newController;
}

- (id)initWithWindowNibName:(NSString *)nibName
				   delegate:(id)inDelegate
					   chat:(AIChat *)inChat
{
	if ((self = [super initWithWindowNibName:nibName])) {
		chat = inChat;
		delegate = inDelegate;
	}
	
	return self;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	[label_uploadingImage setStringValue:[@"Uploading image to server" stringByAppendingEllipsis]];
	[button_cancel setStringValue:@"Cancel"];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:nil];
}

- (IBAction)cancel:(id)sender
{
    id strongSelf = self; // In case calling cancelForChat releases the last retain on self.
	[delegate cancelForChat:chat];
	[strongSelf closeWindow:nil];
}

- (BOOL)indeterminate
{
	return progressIndicator.isIndeterminate;
}

- (void)setIndeterminate:(BOOL)indeterminate
{
	[progressIndicator setIndeterminate:indeterminate];
}

- (void)updateProgress:(NSUInteger)uploaded total:(NSUInteger)total
{
	progressIndicator.doubleValue = (CGFloat)uploaded/(CGFloat)total;
	[label_uploadProgress setStringValue:[NSString stringWithFormat:@"%.1f KB of %.1f KB", (CGFloat)uploaded/1024.0, (CGFloat)total/1024.0]];
}

@end
