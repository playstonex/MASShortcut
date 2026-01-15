#import "MASShortcutBinder.h"
#import "MASShortcut.h"
#import "MASDictionaryTransformer.h"

@interface MASShortcutBinder ()
@property(strong) NSMutableDictionary *actions;
@property(strong) NSMutableDictionary *shortcuts;
@end

@implementation MASShortcutBinder

#pragma mark Initialization

- (id) init
{
    self = [super init];
    [self setActions:[NSMutableDictionary dictionary]];
    [self setShortcuts:[NSMutableDictionary dictionary]];
    [self setShortcutMonitor:[MASShortcutMonitor sharedMonitor]];
    [self setBindingOptions:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    [self migrateLegacyShortcutsIfNeeded];
    return self;
}

- (void) dealloc
{
    for (NSString *bindingName in [_actions allKeys]) {
        [self unbind:bindingName];
    }
}

+ (instancetype) sharedBinder
{
    static dispatch_once_t once;
    static MASShortcutBinder *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark Registration

- (void) bindShortcutWithDefaultsKey: (NSString*) defaultsKeyName toAction: (dispatch_block_t) action
{
    NSAssert([defaultsKeyName rangeOfString:@"."].location == NSNotFound,
        @"Illegal character in binding name (“.”), please see http://git.io/x5YS.");
    NSAssert([defaultsKeyName rangeOfString:@" "].location == NSNotFound,
        @"Illegal character in binding name (“ ”), please see http://git.io/x5YS.");
    [_actions setObject:[action copy] forKey:defaultsKeyName];
    [self bind:defaultsKeyName
        toObject:[NSUserDefaultsController sharedUserDefaultsController]
        withKeyPath:[@"values." stringByAppendingString:defaultsKeyName]
        options:_bindingOptions];
}

- (void) breakBindingWithDefaultsKey: (NSString*) defaultsKeyName
{
    [_shortcutMonitor unregisterShortcut:[_shortcuts objectForKey:defaultsKeyName]];
    [_shortcuts removeObjectForKey:defaultsKeyName];
    [_actions removeObjectForKey:defaultsKeyName];
    [self unbind:defaultsKeyName];
}

- (void) registerDefaultShortcuts: (NSDictionary*) defaultShortcuts
{
    NSValueTransformer *transformer = [_bindingOptions valueForKey:NSValueTransformerBindingOption];
    if (transformer == nil) {
        NSString *transformerName = [_bindingOptions valueForKey:NSValueTransformerNameBindingOption];
        if (transformerName) {
            transformer = [NSValueTransformer valueTransformerForName:transformerName];
        }
    }

    NSAssert(transformer != nil, @"Can’t register default shortcuts without a transformer.");

    [defaultShortcuts enumerateKeysAndObjectsUsingBlock:^(NSString *defaultsKey, MASShortcut *shortcut, BOOL *stop) {
        id value = [transformer reverseTransformedValue:shortcut];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{defaultsKey:value}];
    }];
}

#pragma mark Bindings

- (BOOL) isRegisteredAction: (NSString*) name
{
    return !![_actions objectForKey:name];
}

- (id) valueForUndefinedKey: (NSString*) key
{
    return [self isRegisteredAction:key] ?
        [_shortcuts objectForKey:key] :
        [super valueForUndefinedKey:key];
}

- (void) setValue: (id) value forUndefinedKey: (NSString*) key
{
    if (![self isRegisteredAction:key]) {
        [super setValue:value forUndefinedKey:key];
        return;
    }

    MASShortcut *newShortcut = value;
    MASShortcut *currentShortcut = [_shortcuts objectForKey:key];

    // Unbind previous shortcut if any
    if (currentShortcut != nil) {
        [_shortcutMonitor unregisterShortcut:currentShortcut];
    }

    // Just deleting the old shortcut
    if (newShortcut == nil) {
        [_shortcuts removeObjectForKey:key];
        return;
    }

    // Bind new shortcut
    [_shortcuts setObject:newShortcut forKey:key];
    [_shortcutMonitor registerShortcut:newShortcut withAction:[_actions objectForKey:key]];
}

#pragma mark Migration

- (void) migrateLegacyShortcutsIfNeeded
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    MASDictionaryTransformer *transformer = [MASDictionaryTransformer new];
    BOOL hasMigrated = NO;

    for (NSString *key in allDefaults) {
        id value = [defaults objectForKey:key];

        // Check if this value is legacy NSData format
        if ([value isKindOfClass:[NSData class]]) {
            @try {
                // Try to decode as MASShortcut
                MASShortcut *shortcut = [NSKeyedUnarchiver unarchivedObjectOfClass:[MASShortcut class] fromData:value error:NULL];

                if (shortcut) {
                    // Convert to new dictionary format
                    NSDictionary *newValue = [transformer reverseTransformedValue:shortcut];

                    // Save the new format (overwrites the old NSData)
                    [defaults setObject:newValue forKey:key];
                    hasMigrated = YES;
                }
            } @catch (NSException *exception) {
                // If decoding fails, this key doesn't contain a MASShortcut, skip it
            }
        }
    }

    // Sync if any migration occurred
    if (hasMigrated) {
        [defaults synchronize];
    }
}

@end
