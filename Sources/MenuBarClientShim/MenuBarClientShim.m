// Based on Hidden Bar (https://github.com/dwarvesf/hidden), HBNativeVisibilityShim.
// Copyright (c) 2019 Dwarves Foundation. MIT License.

#import "MenuBarClientShim.h"
#import <dlfcn.h>
#import <objc/message.h>

// 시험 모드(assessment mode)용 프레임워크. 메뉴바를 허용 목록으로 제한할 수 있다.
// 런타임에 찾아서, macOS 가 이걸 바꾸거나 없애면 실행 실패가 아니라 "사용 불가"가 된다.
static const char *kFrameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";

static NSError *BDZError(NSString *reason) {
    return [NSError errorWithDomain:@"BDZMenuBarClient" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// 프레임워크, 두 클래스, 쓰는 셀렉터가 전부 있는가.
static BOOL BDZMenuBarClientIsAvailable(void) {
    if (!dlopen(kFrameworkPath, RTLD_NOW | RTLD_LOCAL)) return NO;
    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return configuration && assertion
        && [configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
        && [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
        && [assertion instancesRespondToSelector:@selector(invalidate)];
}

void BDZMenuBarClientActivate(NSArray<NSNumber *> *allowedSystemItems,
                              NSArray<NSString *> *allowedBundleIDs,
                              void (^completion)(id _Nullable, NSError * _Nullable)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!BDZMenuBarClientIsAvailable()) {
        finish(nil, BDZError(@"MenuBarClientCore 를 쓸 수 없는 macOS"));
        return;
    }
    @try {
        // 둘 다 NSArray 여야 한다. 프레임워크가 인덱스로 읽는다
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:),
            [allowedSystemItems copy], [allowedBundleIDs copy]);
        id assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !assertion) {
            finish(nil, BDZError(@"설정 객체를 만들 수 없음"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, @selector(activateWithConfiguration:completionHandler:), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, BDZError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void BDZMenuBarClientInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:@selector(invalidate)]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, @selector(invalidate));
        }
    } @catch (NSException *exception) {
        NSLog(@"BDZMenuBarClient: invalidate 예외 %@: %@", exception.name, exception.reason);
    }
}
