// Based on Hidden Bar (https://github.com/dwarvesf/hidden), HBNativeVisibilityShim.
// Copyright (c) 2019 Dwarves Foundation. MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// macOS 27 비공개 프레임워크 MenuBarClientCore 와 닿는 유일한 경계.
// Objective-C 로 둔 이유: 비공개 API 가 바뀌어 예외를 던져도 앱이 죽지 않게 @try 로 잡으려고.

// 시스템 아이템 번호와 허용한 앱만 메뉴바에 남기고 나머지 앱 아이콘을 숨긴다.
// completion 은 메인 큐에서 돌고, 숨김을 유지하는 assertion 또는 오류를 준다.
// 숨김은 assertion 을 invalidate 하거나 이 프로세스가 끝나면 풀린다.
void BDZMenuBarClientActivate(NSArray<NSNumber *> *allowedSystemItems,
                              NSArray<NSString *> *allowedBundleIDs,
                              void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void BDZMenuBarClientInvalidate(id assertion);

NS_ASSUME_NONNULL_END
