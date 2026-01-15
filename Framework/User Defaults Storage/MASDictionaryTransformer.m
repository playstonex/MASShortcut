#import "MASDictionaryTransformer.h"
#import "MASShortcut.h"

NSString *const MASDictionaryTransformerName = @"MASDictionaryTransformer";

static NSString *const MASKeyCodeKey = @"keyCode";
static NSString *const MASModifierFlagsKey = @"modifierFlags";

@implementation MASDictionaryTransformer

+ (BOOL) allowsReverseTransformation
{
    return YES;
}

// Storing nil values as an empty dictionary lets us differ between
// “not available, use default value” and “explicitly set to none”.
// See http://stackoverflow.com/questions/5540760 for details.
- (NSDictionary*) reverseTransformedValue: (MASShortcut*) shortcut
{
    if (shortcut == nil) {
        return [NSDictionary dictionary];
    } else {
        return @{
            MASKeyCodeKey: @([shortcut keyCode]),
            MASModifierFlagsKey: @([shortcut modifierFlags])
        };
    }
}

- (MASShortcut*) transformedValue: (id) value
{
    // We have to be defensive here as the value may come from user defaults.

    // Handle legacy NSData format (from NSKeyedArchiver)
    if ([value isKindOfClass:[NSData class]]) {
        @try {
            MASShortcut *shortcut = [NSKeyedUnarchiver unarchivedObjectOfClass:[MASShortcut class] fromData:value error:NULL];
            if (shortcut) {
                return shortcut;
            }
        } @catch (NSException *exception) {
            // Fall through to nil
        }
        return nil;
    }

    // Handle new NSDictionary format
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)value;
    id keyCodeBox = [dictionary objectForKey:MASKeyCodeKey];
    id modifierFlagsBox = [dictionary objectForKey:MASModifierFlagsKey];

    SEL integerValue = @selector(integerValue);
    if (![keyCodeBox respondsToSelector:integerValue] || ![modifierFlagsBox respondsToSelector:integerValue]) {
        return nil;
    }

    return [MASShortcut
        shortcutWithKeyCode:[keyCodeBox integerValue]
        modifierFlags:[modifierFlagsBox integerValue]];
}

@end
