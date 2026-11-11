//
//  AyuGramPushRelay.m
//
//  Твик для rootless-джейлбрейка (Dopamine / ElleKit).
//  Работает в приложениях, которые УЖЕ получают push (App Store Swiftgram,
//  официальный Telegram), и ретранслирует факт прихода push в AyuGram
//  через Darwin notification.
//
//  Почему так: APNs-токен привязан к bundle id, под которым его запросили.
//  Сервер Telegram шлёт push только на тот topic, для которого в
//  my.telegram.org/apps загружен APNs-сертификат владельца приложения.
//  У нашей сборки AyuGram (app.ayugram.ios) своего сертификата нет, поэтому
//  push прилетает в Swiftgram — а этот твик доставляет сигнал в AyuGram.
//
//  Твик не подменяет обработку push: оригинальный метод вызывается как есть,
//  так что Swiftgram продолжает работать штатно.
//
//  Зависимостей нет: используется Objective-C runtime (method_exchangeImplementations),
//  поэтому не нужен ни substrate.h, ни Logos — достаточно обычного clang.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#pragma mark - Константы

/// Darwin-сигнал, который слушает AyuGram (см. AyuGramPushSignal.swift).
static NSString *const kAYUSignalName = @"com.ayugram.push.signal";

/// Файл лога внутри контейнера инжектированного приложения (Documents/).
static NSString *const kAYULogFileName = @"AyuGramRelay.log";

/// Показывать тестовое локальное уведомление при перехвате (для проверки).
static BOOL const kAYUShowTestNotification = YES;

#pragma mark - Логирование

static void AYULog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[AyuGramRelay] %@", message);

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) {
        return;
    }
    NSString *path = [docs stringByAppendingPathComponent:kAYULogFileName];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

#pragma mark - Сигнал в AyuGram

static void AYUPostSignal(NSString *reason) {
    // Darwin notification — единственный канал, который работает между
    // двумя sandbox'ами без общих App Group / Keychain entitlements.
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFNotificationName)kAYUSignalName,
        NULL,
        NULL,
        YES
    );
    AYULog(@"posted darwin signal '%@' (reason: %@)", kAYUSignalName, reason);
}

static void AYUPostTestNotification(NSString *body) {
    if (!kAYUShowTestNotification) {
        return;
    }
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"AyuGram relay";
    content.body = body;
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                         content:content
                                                                         trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                          withCompletionHandler:^(NSError *_Nullable error) {
        if (error) {
            AYULog(@"test notification failed: %@", error);
        }
    }];
}

#pragma mark - Хуки

typedef void (^AYUBackgroundFetchCompletion)(UIBackgroundFetchResult);
typedef void (^AYUVoIPCompletion)(void);

static IMP g_origDidReceiveRemoteNotification = NULL;
static IMP g_origDidRegisterForRemoteNotifications = NULL;
static IMP g_origPushRegistryDidReceiveIncomingPush = NULL;

/// application:didReceiveRemoteNotification:fetchCompletionHandler:
static void AYU_hookDidReceiveRemoteNotification(id self,
                                                 SEL _cmd,
                                                 UIApplication *application,
                                                 NSDictionary *userInfo,
                                                 AYUBackgroundFetchCompletion completionHandler) {
    AYULog(@"didReceiveRemoteNotification, keys=%@", userInfo.allKeys);
    AYUPostSignal(@"remote-notification");
    AYUPostTestNotification([NSString stringWithFormat:@"Push перехвачен в %@. Сигнал отправлен в AyuGram.",
                                                      [[NSBundle mainBundle] bundleIdentifier] ?: @"?"]);

    if (g_origDidReceiveRemoteNotification) {
        ((void (*)(id, SEL, UIApplication *, NSDictionary *, AYUBackgroundFetchCompletion))g_origDidReceiveRemoteNotification)(
            self, _cmd, application, userInfo, completionHandler);
    } else if (completionHandler) {
        completionHandler(UIBackgroundFetchResultNewData);
    }
}

/// application:didRegisterForRemoteNotificationsWithDeviceToken:
static void AYU_hookDidRegisterForRemoteNotifications(id self,
                                                      SEL _cmd,
                                                      UIApplication *application,
                                                      NSData *deviceToken) {
    AYULog(@"didRegisterForRemoteNotificationsWithDeviceToken, length=%lu",
           (unsigned long)deviceToken.length);

    if (g_origDidRegisterForRemoteNotifications) {
        ((void (*)(id, SEL, UIApplication *, NSData *))g_origDidRegisterForRemoteNotifications)(
            self, _cmd, application, deviceToken);
    }
}

/// pushRegistry:didReceiveIncomingPushWith:for:completion:  (VoIP-канал PushKit)
static void AYU_hookPushRegistryDidReceiveIncomingPush(id self,
                                                       SEL _cmd,
                                                       id registry,
                                                       id payload,
                                                       NSInteger type,
                                                       AYUVoIPCompletion completion) {
    AYULog(@"pushRegistry didReceiveIncomingPushWith, type=%ld", (long)type);
    AYUPostSignal(@"voip-push");

    if (g_origPushRegistryDidReceiveIncomingPush) {
        ((void (*)(id, SEL, id, id, NSInteger, AYUVoIPCompletion))g_origPushRegistryDidReceiveIncomingPush)(
            self, _cmd, registry, payload, type, completion);
    } else if (completion) {
        completion();
    }
}

#pragma mark - Swizzling

// Подмена IMP существующего метода на C-функцию.
// method_exchangeImplementations здесь не годится: наши хуки — обычные
// C-функции, а не Objective-C методы, поэтому ставим реализацию напрямую.
static BOOL AYUSwizzle(Class cls, SEL original, IMP replacement, IMP *outOriginal) {
    if (cls == nil) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, original);
    if (method == NULL) {
        return NO;
    }
    IMP originalIMP = method_setImplementation(method, replacement);
    if (originalIMP == NULL) {
        return NO;
    }
    if (outOriginal != NULL) {
        *outOriginal = originalIMP;
    }
    return YES;
}

static void AYUInstallHooks(void) {
    Class appDelegate = objc_getClass("AppDelegate");
    if (appDelegate == nil) {
        AYULog(@"AppDelegate not found, hooks not installed");
        return;
    }
    AYULog(@"AppDelegate found: %@", appDelegate);

    if (AYUSwizzle(appDelegate,
                   @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:),
                   (IMP)AYU_hookDidReceiveRemoteNotification,
                   &g_origDidReceiveRemoteNotification)) {
        AYULog(@"hooked application:didReceiveRemoteNotification:fetchCompletionHandler:");
    } else {
        AYULog(@"FAILED to hook application:didReceiveRemoteNotification:fetchCompletionHandler:");
    }

    if (AYUSwizzle(appDelegate,
                   @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:),
                   (IMP)AYU_hookDidRegisterForRemoteNotifications,
                   &g_origDidRegisterForRemoteNotifications)) {
        AYULog(@"hooked application:didRegisterForRemoteNotificationsWithDeviceToken:");
    } else {
        AYULog(@"FAILED to hook application:didRegisterForRemoteNotificationsWithDeviceToken:");
    }

    if (AYUSwizzle(appDelegate,
                   @selector(pushRegistry:didReceiveIncomingPushWith:for:completion:),
                   (IMP)AYU_hookPushRegistryDidReceiveIncomingPush,
                   &g_origPushRegistryDidReceiveIncomingPush)) {
        AYULog(@"hooked pushRegistry:didReceiveIncomingPushWith:for:completion:");
    } else {
        AYULog(@"FAILED to hook pushRegistry:didReceiveIncomingPushWith:for:completion:");
    }
}

__attribute__((constructor))
static void AYUConstructor(void) {
    @autoreleasepool {
        AYULog(@"loaded into %@ (pid %d)", [[NSBundle mainBundle] bundleIdentifier] ?: @"?", getpid());
        AYUInstallHooks();
    }
}
