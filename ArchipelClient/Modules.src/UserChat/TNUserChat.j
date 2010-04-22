/*
 * TNUserChat.j
 *
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

@import "TNMessageView.j"

/*! @defgroup userchat Module UserChat
    @desc this module allows to chat with XMPP entities.
*/

/*! @ingroup userchat
    This is the main module view.
*/
@implementation TNUserChat : TNModule
{
    @outlet CPTextField     fieldJID                @accessors;
    @outlet CPTextField     fieldName               @accessors;
    @outlet CPTextField     fieldUserJid            @accessors;
    @outlet CPTextField     fieldMessage            @accessors;
    @outlet CPScrollView    messagesScrollView      @accessors;
    @outlet CPImageView     imageSpinnerWriting     @accessors;

    CPCollectionView        _messageCollectionView;
    CPArray                 _messages;
    CPTimer                 _composingMessageTimer;
}

/*! initialize some stuffs at CIB awakening
*/
- (void)awakeFromCib
{
    CPLog.debug(messagesScrollView);
    _messages = [CPArray array];
     
     [messagesScrollView setBorderedWithHexColor:@"#9e9e9e"];
     [messagesScrollView setAutoresizingMask:CPViewWidthSizable];
     [messagesScrollView setAutohidesScrollers:YES];
     
     var frame           = [[messagesScrollView contentView] bounds];
     var messageView     = [[TNMessageView alloc] initWithFrame:CGRectMakeZero()];
     
     [messageView setAutoresizingMask:CPViewWidthSizable];
     
     _messageCollectionView = [[CPCollectionView alloc] initWithFrame:frame];
     [_messageCollectionView setAutoresizingMask:CPViewWidthSizable];
     [_messageCollectionView setMinItemSize:CGSizeMake(100, 60)];
     [_messageCollectionView setMaxItemSize:CGSizeMake(1700, 2024)];
     [_messageCollectionView setMaxNumberOfColumns:1];
     [_messageCollectionView setVerticalMargin:2.0];
     [_messageCollectionView setSelectable:NO]
     [_messageCollectionView setItemPrototype:[[CPCollectionViewItem alloc] init]];
     [[_messageCollectionView itemPrototype] setView:messageView];
     [_messageCollectionView setContent:_messages];
     
     [messagesScrollView setDocumentView:_messageCollectionView];
     
     var mainBundle = [CPBundle mainBundle];
     
     [imageSpinnerWriting setImage:[[CPImage alloc] initWithContentsOfFile:[mainBundle pathForResource:@"spinner.gif"]]];
     [imageSpinnerWriting setHidden:YES];
     
     [fieldMessage addObserver:self forKeyPath:@"stringValue" options:CPKeyValueObservingOptionNew context:nil];
}

/*! TNModule implementation.
    Will register to notification and see if messages are present in queue.
    Will recover the contents of the localstorage history.
*/
- (void)willLoad
{
    [super willLoad];

    var center = [CPNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(didReceivedMessage:) name:TNStropheContactMessageReceivedNotification object:[self entity]];
    [center addObserver:self selector:@selector(didReceivedMessageComposing:) name:TNStropheContactMessageComposing object:[self entity]];
    [center addObserver:self selector:@selector(didReceivedMessagePause:) name:TNStropheContactMessagePaused object:[self entity]];
    [center addObserver:self selector:@selector(didNickNameUpdated:) name:TNStropheContactNicknameUpdatedNotification object:[self entity]];

    var frame = [[messagesScrollView documentView] bounds];
    [_messageCollectionView setFrame:frame];

    // var defaults = [TNUserDefaults standardUserDefaults];
    // var lastConversation = [defaults objectForKey:"communicationWith" + [[self entity] jid]];
    // 
    // console.log(lastConversation);
    // if (lastConversation)
    //     _messages = lastConversation;
    
    var lastConversation = JSON.parse(localStorage.getItem("communicationWith" + [[self entity] jid]));
    
    if (lastConversation)
    {
        for (var i = 0; i < lastConversation.length; i++)
        {
            var dict        = lastConversation[i];
            var aSender     = dict._buckets.name        // yes I know this is awful. But
            var aMessage    = dict._buckets.message;    // I've passed 2 hours, and I'm tired of this shitty bug.
            var aColor      = dict._buckets.color;
    
            if (! aColor)
                aColor = "ffffff";
    
            [_messages addObject:[CPDictionary dictionaryWithObjectsAndKeys:aSender, @"name", aMessage, @"message", aColor, @"color"]];
        }
    }

    [_messageCollectionView reloadContent];
    
    var frame = [[messagesScrollView documentView] frame];
    newScrollOrigin = CPMakePoint(0.0, frame.size.height);
    [_messageCollectionView scrollPoint:newScrollOrigin];
}

/*! TNModule implementation
    Will save the messages to localstorage
*/
- (void)willUnload
{
    [super willUnload];

    localStorage.setItem("communicationWith" + [[self entity] jid], JSON.stringify(_messages));
    // var defaults = [TNUserDefaults standardUserDefaults];
    // [defaults setArray:_messages forKey:"communicationWith" + [[self entity] jid]];
    // console.log("HERE" + _messages);
    
    [_messages removeAllObjects];
    [_messageCollectionView reloadContent];
}

/*! TNModule implementation
*/
- (void)willShow
{
    [super willShow];

    var messageQueue = [[self entity] messagesQueue];
    var stanza;

    while (stanza = [[self entity] popMessagesQueue])
    {
        if ([stanza containsChildrenWithName:@"body"])
        {
            [self appendMessageToBoard:[[stanza firstChildWithName:@"body"] text] from:[stanza valueForAttribute:@"from"]];
        }
    }

    [[self entity] freeMessagesQueue];
    
    [fieldName setStringValue:[[self entity] nickname]];
    [fieldJID setStringValue:[[self entity] jid]];
}

/*! update the nickname if TNStropheContactNicknameUpdatedNotification received from contact
*/
- (void)didNickNameUpdated:(CPNotification)aNotification
{
    if ([aNotification object] == [self entity])
    {
       [fieldName setStringValue:[[self entity] nickname]]
    }
}

/*! observe if user is typing. If yes then send the "compose" XMPP status.
    @param aKeyPath the key path observed
    @param anObject the object observed
    @param aChange changes
    @param aContext a context
*/
- (void)observeValueForKeyPath:(CPString)aKeyPath ofObject:(id)anObject change:(CPDictionary)aChange context:(id)aContext
{
    if ([anObject stringValue] == @"")
    {
        [[self entity] sendComposePaused];
    }
    else
    {
        if (_composingMessageTimer)
            [_composingMessageTimer invalidate];

        _composingMessageTimer = [CPTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(sendComposingPaused:) userInfo:nil repeats:NO];
        [[self entity] sendComposing];
    }

}

/*! this message is sent when user is not typing for some time
    @param aTimer the timer that call the selector
*/
- (void)sendComposingPaused:(CPTimer)aTimer
{
    [[self entity] sendComposePaused];
}

/*! append a new message to the message board
    @param aMessage the message body
    @param aSender the nickname of the sender
*/
- (void)appendMessageToBoard:(CPString)aMessage from:(CPString)aSender
{
    var color           = (aSender == @"me") ? "d9dfe8" : "ffffff";
    var newMessageDict  = [CPDictionary dictionaryWithObjectsAndKeys:aSender, @"name", aMessage, @"message", color, @"color"];
    var frame           = [[messagesScrollView documentView] frame];
    
    [_messages addObject:newMessageDict];
    [_messageCollectionView reloadContent];
    
    // scroll to bottom;
    newScrollOrigin = CPMakePoint(0.0, frame.size.height);
    [_messageCollectionView scrollPoint:newScrollOrigin];
}

/*! performed when TNStropheContactMessageReceivedNotification is received from current entity.
    @param aNotification the notification containing the contact that send the notification
*/
- (void)didReceivedMessage:(CPNotification)aNotification
{
    if ([[aNotification object] jid] == [[self entity] jid])
    {
        var stanza =  [[self entity] popMessagesQueue];

        if ([stanza containsChildrenWithName:@"body"])
        {
            var messageBody = [[stanza firstChildWithName:@"body"] text];
            [imageSpinnerWriting setHidden:YES];
            [self appendMessageToBoard:messageBody from:[stanza valueForAttribute:@"from"]];

            CPLog.info("message received : " + messageBody);
        }
    }
    else
    {
        _audioTagReceive.play();
    }
}

/*! performed when TNStropheContactMessageComposing is received from current entity.
    @param aNotification the notification containing the contact that send the notification
*/
- (void)didReceivedMessageComposing:(CPNotification)aNotification
{
    [imageSpinnerWriting setHidden:NO];
}

/*! performed when TNStropheContactMessagePaused is received from current entity.
    @param aNotification the notification containing the contact that send the notification
*/
- (void)didReceivedMessagePause:(CPNotification)aNotification
{
    [imageSpinnerWriting setHidden:YES];
}

/*! send a message to the contact containing the content of the outlet message CPTextField
    @param aSender the sender of the action
*/
- (IBAction)sendMessage:(id)aSender
{
     if (_composingMessageTimer)
            [_composingMessageTimer invalidate];

    [[self entity] sendMessage:[fieldMessage stringValue]];
    [self appendMessageToBoard:[fieldMessage stringValue] from:@"me"];
    [fieldMessage setStringValue:@""];
}

/*! Clear all localstorage  of the old messages
    @param aSender the sender of the action
*/
- (IBAction)clearHistory:(id)aSender
{
    localStorage.removeItem("communicationWith" + [[self entity] jid]);
    [_messages removeAllObjects];
    [_messageCollectionView reloadContent];
}

@end