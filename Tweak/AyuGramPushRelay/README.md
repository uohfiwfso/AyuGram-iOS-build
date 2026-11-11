# AyuGramPushRelay — твик для возврата push в AyuGram

## Зачем он нужен

APNs-токен выдаётся приложению под тем bundle id, под которым его запросили,
и APNs-сертификат, которым Telegram шлёт push, имеет topic `org.telegram.messenger`.
Поэтому сборка AyuGram (`app.ayugram.ios`) не может получить push от серверов
Telegram: её токен просто не покрыт ни одним загруженным сертификатом.

Но приложения, у которых **свой** APNs-сертификат загружен в
`my.telegram.org/apps` — push получают штатно. Это, например, Swiftgram из
App Store (`app.swiftgram.ios`): он получает уведомления нормально, хотя
bundle id у него тоже не официальный.

Этот твик работает в таком приложении (Swiftgram или официальный Telegram),
перехватывает приход push **до штатной обработки** и отправляет в AyuGram
Darwin-уведомление. AyuGram на него реагирует форсированным запросом разницы
с сервером (`account.stateManager.standalonePollDifference()`) и догоняет
обновления.

Твик **не ломает** штатную работу: оригинальный метод вызывается как есть,
так что Swiftgram продолжает показывать уведомления сам.

## Как устроен канал

Darwin notification (`com.ayugram.push.signal`) — единственный способ обмена
между двумя sandbox'ами без общих App Group / Keychain entitlements.
На стороне AyuGram приёмник живёт в `submodules/TelegramUI/Sources/AyuGramPushSignal.swift`.

## Сборка

```bash
make -C Tweak/AyuGramPushRelay
```

Нужен macOS с Xcode (`xcrun --sdk iphoneos`). Готовый артефакт собирается
в CI: workflow `build-tweak` → артефакт `AyuGramPushRelay-tweak`.

Зависимостей нет: используется Objective-C runtime
(`method_exchangeImplementations`), поэтому не нужен ни `substrate.h`,
ни Logos — достаточно обычного `clang`.

## Установка (rootless, Dopamine / ElleKit)

1. Взять из артефакта `AyuGramPushRelay.dylib` и `AyuGramPushRelay.plist`.
2. Скопировать оба файла в
   `/var/jb/Library/MobileSubstrate/DynamicLibraries/`
   (через Filza или Sileo — можно установить `.deb`).
3. Перезапустить интерфейс (respring): `ldrestart` или «Перезагрузить интерфейс»
   в настройках джейлбрейка.

Фильтр по умолчанию:

```xml
<key>Filter</key>
<dict>
    <key>Bundles</key>
    <array>
        <string>app.swiftgram.ios</string>
        <string>org.telegram.messenger</string>
    </array>
</dict>
```

## Проверка, что твик загрузился

Твик пишет лог в `Documents/AyuGramRelay.log` внутри контейнера
инжектированного приложения (Filza → Swiftgram → Documents).

Ожидаемые строки:

```
[AyuGramRelay] loaded into app.swiftgram.ios (pid 1234)
[AyuGramRelay] AppDelegate found: AppDelegate
[AyuGramRelay] hooked application:didReceiveRemoteNotification:fetchCompletionHandler:
```

При приходе push дополнительно показывается локальное уведомление
«AyuGram relay» — это подтверждает, что перехват работает.

## Ограничения

- Твик работает только в приложениях, которые **уже получают push**.
  Для чистой сборки AyuGram без Swiftgram/Telegram рядом push не появится —
  там нужен собственный APNs-сертификат (Apple Developer Program, 99$/год)
  и его загрузка в `my.telegram.org/apps`.
- Darwin-сигнал доставляется живому (foreground/suspended) процессу AyuGram.
  Если AyuGram был убит системой, сигнал не дойдёт — приложение поднимется
  при следующем запуске.
- Подмены текста уведомления на стороне AyuGram нет: AyuGram получает только
  факт прихода push.
