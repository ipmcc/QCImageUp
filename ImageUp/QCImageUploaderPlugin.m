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

#import "QCImageUploaderPlugin.h"
#import "QCImageShackImageUploader.h"
#import "QCImgurImageUploader.h"
#import "QCImageUploaderWindowController.h"

#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIChat.h>
#import <Adium/AITextAttachmentExtension.h>
#import <Adium/AIMessageEntryTextView.h>

#import <AIUtilities/AIWindowAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>

@interface QCImageUploaderPlugin()
- (void)uploadImage:(NSImage*)image fromChat:(AIChat*)textView;

- (void)insertImageAddress:(NSString *)inAddress intoTextView:(NSTextView *)textView;
- (void)setImageUploader:(NSMenuItem *)menuItem;
@end

@implementation QCImageUploaderPlugin
- (void)installPlugin
{
	uploaders = [[NSMutableArray alloc] init];
	windowControllers = [[NSMutableDictionary alloc] init];
	uploadInstances = [[NSMutableDictionary alloc] init];
		
	editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Auto Image Uploader"
											  target:self
											  action:@selector(setImageUploader:)
									   keyEquivalent:@"k" keyMask:NSCommandKeyMask | NSAlternateKeyMask];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(textDidChange:)
												 name:NSTextDidChangeNotification
											   object:nil];
	
	NSMenu* editSubmenu = [[NSMenu alloc] init];
	[editSubmenu setDelegate:self];
	
	[editMenuItem setSubmenu:editSubmenu];
	
	[adium.menuController addMenuItem:editMenuItem toLocation:LOC_Edit_Links];
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_FORMATTING];
	
	[self addUploader:[QCImageShackImageUploader class]];
	[self addUploader:[QCImgurImageUploader class]];
}

- (void)addUploader:(Class)uploader
{
	// using indexOfObjectIdenticalTo: because Class instances don't implement the NSObject protocol, causing all kinds
	// of weirdness when using them with NSArrays
	if ([uploaders indexOfObjectIdenticalTo:uploader] != NSNotFound)
		return;
	
	[uploaders addObject:uploader];
	[self menuNeedsUpdate:[editMenuItem submenu]];
}

- (void)removeUploader:(Class)uploader
{
	// using indexOfObjectIdenticalTo: because Class instances don't implement the NSObject protocol, causing all kinds
	// of weirdness when using them with NSArrays
	NSUInteger index = [uploaders indexOfObjectIdenticalTo:uploader];
	if (index == NSNotFound)
		return;
	
	[uploaders removeObjectAtIndex:index];
	[self menuNeedsUpdate:[editMenuItem submenu]];
}

- (void)uninstallPlugin
{
	[[editMenuItem menu] removeItem:editMenuItem];
	[adium.preferenceController unregisterPreferenceObserver:self];
}

#pragma mark Preferences
@synthesize defaultService;

- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (object)
		return;
	
	if (!key || [key isEqualToString:PREF_KEY_DEFAULT_QC_IMAGE_UPLOADER]) {
		self.defaultService = [prefDict objectForKey:PREF_KEY_DEFAULT_QC_IMAGE_UPLOADER];
	}
}

#pragma mark Services
/*!
 * @brief Set the submenu as a menu of all possible services
 */
- (void)menuNeedsUpdate:(NSMenu *)menu
{
	[menu removeAllItems];

	for (Class service in uploaders) {
		NSMenuItem *newItem = [menu addItemWithTitle:[service serviceName]
											  target:self 
											  action:@selector(setImageUploader:)
									   keyEquivalent:@""];
		
		[newItem setRepresentedObject:[service serviceName]];
		
		[newItem setState:[[service serviceName] isEqualToString:defaultService]];
	}
}

/*!
 * @brief Set the default upload service, then upload.
 */
- (void)setImageUploader:(NSMenuItem *)menuItem
{
	NSString *serviceName = [menuItem representedObject];
	
	[adium.preferenceController setPreference:serviceName
									   forKey:PREF_KEY_DEFAULT_QC_IMAGE_UPLOADER
										group:PREF_GROUP_FORMATTING];
}

/*!
 * @brief If we have a selected image, we can do something.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	return true;
}

#pragma mark Image uploading

- (void)textDidChange:(NSNotification *)notification
{
    if (![notification.object isKindOfClass:[AIMessageEntryTextView class]]) {
        return;
    }
    AIMessageEntryTextView * textView = (AIMessageEntryTextView *)notification.object;
    NSAttributedString *text = [textView textStorage];
    __block NSImage *image = nil;
    [text enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, [text length]) options:NSAttributedStringEnumerationReverse usingBlock:^(id value, NSRange range, BOOL *stop) {
        if ([value isKindOfClass:[AITextAttachmentExtension class]]) {
            AITextAttachmentExtension * attachment = (AITextAttachmentExtension*)value;
            if ([attachment respondsToSelector:@selector(image)])
                image = [attachment performSelector:@selector(image)];
            else if ([[attachment attachmentCell] respondsToSelector:@selector(image)])
                image = [[attachment attachmentCell] performSelector:@selector(image)];
            [textView setSelectedRange:range];
            *stop = YES;
        }
    }];
    if (image) {
        [self uploadImage:image fromChat:textView.chat];
    }
}

- (void)uploadImage:(NSImage*)image fromChat:(AIChat*)chat
{
	Class uploader = nil;
	
	for (Class service in uploaders) {
		uploader = service;
		if ([[service serviceName] isEqualToString:defaultService]) {
			break;
		}
	}

	QCImageUploaderWindowController *controller = [QCImageUploaderWindowController displayProgressInWindow:[NSApp keyWindow]
																								  delegate:self
																									  chat:chat];
	controller.indeterminate = YES;
	id <QCImageUploader> uploadInstance = [uploader uploadImage:image forUploader:self inChat:chat];
	
	[windowControllers setValue:controller forKey:chat.internalObjectID];
	[uploadInstances setValue:uploadInstance forKey:chat.internalObjectID];
}

/*!
 * @brief Request a URL, insert into text view
 *
 * @param inAddress The NSString to insert
 * @param textView the NSTextView to insert the address itno
 *
 * Replaces the selected image in textView with the given address.
 */
- (void)insertImageAddress:(NSString *)inAddress intoTextView:(NSTextView *)textView
{	
	NSParameterAssert(inAddress.length);
	
	NSRange selectedRange = textView.selectedRange;
	
	
	// Replace the current selection with the new URL
	NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithDictionary:[textView.attributedString attributesAtIndex:selectedRange.location effectiveRange:nil]];
	[attrs setObject:inAddress forKey:NSLinkAttributeName];
	
	[textView.textStorage replaceCharactersInRange:selectedRange
							  withAttributedString:[[NSAttributedString alloc] initWithString:inAddress attributes:attrs]];
	
	// Select the inserted URL
	textView.selectedRange = NSMakeRange(selectedRange.location, inAddress.length);
	
	// Post a notification that we've changed the text
	[[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification
														object:textView];
}

- (void)errorWithMessage:(NSString *)message forChat:(AIChat *)chat
{
	[adium.interfaceController handleErrorMessage:AILocalizedString(@"Error during image upload", nil)
								  withDescription:message];
	
	[self uploadedURL:nil forChat:chat];
}

/*!
 * @brief The upload has finished
 *
 * @param url The URL or nil if failed
 * @param chat The AIChat for this upload
*/
- (void)uploadedURL:(NSString *)url forChat:(AIChat *)chat
{
	QCImageUploaderWindowController *windowController = [windowControllers objectForKey:chat.internalObjectID];
	
	[windowController closeWindow:nil];
	
	[windowControllers setValue:nil forKey:chat.internalObjectID];
	[uploadInstances setValue:nil forKey:chat.internalObjectID];
	
	if (url) {
		NSWindow *window = ((AIWindowController *)chat.chatContainer.windowController).window;
		NSTextView *textView = (NSTextView *)[window earliestResponderOfClass:[NSTextView class]];
		
		[self insertImageAddress:url intoTextView:textView];
	}
}

/*!
 * @brief Update the progress's percent
 *
 * @param uploaded The uploaded amount in bytes
 * @param total The total amount in bytes
 * @param chat The AIChat for the upload
 */
- (void)updateProgress:(NSUInteger)uploaded total:(NSUInteger)total forChat:(AIChat *)chat;
{
	[[windowControllers objectForKey:chat.internalObjectID] setIndeterminate:NO];
	[[windowControllers objectForKey:chat.internalObjectID] updateProgress:uploaded total:total];
}

/*!
 * @brief Cancel an update
 *
 * @param chat The AIChat to cancel for
 */
- (void)cancelForChat:(AIChat *)chat
{
	NSObject <QCImageUploader> *imageUploader = [uploadInstances objectForKey:chat.internalObjectID];
	
	[imageUploader cancel];
	
	[windowControllers setValue:nil forKey:chat.internalObjectID];
	[uploadInstances setValue:nil forKey:chat.internalObjectID];
}

@end
