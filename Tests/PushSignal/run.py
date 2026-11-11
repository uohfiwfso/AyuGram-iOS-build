"""
Fast type-check for the AyuGram Darwin push-signal receiver.

The full app build (bazel + Xcode) costs 75-95 minutes per cycle, so a two-line Swift
mistake in TelegramUI costs an hour and a half. This harness compiles the *real* production
files - submodules/TelegramUI/Sources/AyuGramPushSignal.swift and the AyuGram block of
AppDelegate.swift - against the *real* SwiftSignalKit sources, with small stubs for the
TelegramCore types the block touches. It runs in minutes on a free Intel runner.

It also probes the exact Swift signature of the CoreFoundation API we call, by asking the
compiler to print it: a deliberate type error makes swiftc spell out the full type of
CFNotificationCenterAddObserver for the SDK that is actually installed. That way the
Darwin-notification code is written against the SDK, not against memory.

Usage: python3 Tests/PushSignal/run.py
"""

import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
signal_file = root / 'submodules/TelegramUI/Sources/AyuGramPushSignal.swift'
app_delegate_file = root / 'submodules/TelegramUI/Sources/AppDelegate.swift'
tweak_file = root / 'Tweak/AyuGramPushRelay/AyuGramPushRelay.m'

# Real SwiftSignalKit sources: the receiver is built on Signal/Promise, and the harness
# only compiles something meaningful if the real operator semantics are in play.
signalkit_dir = root / 'submodules/SSignalKit/SwiftSignalKit/Source'
signalkit_sources = sorted(p for p in signalkit_dir.glob('*.swift'))
# Signal_Reduce.swift is the only user of os_unfair_lock and is not needed here.
signalkit_sources = [p for p in signalkit_sources if p.name != 'Signal_Reduce.swift']


def read_production_sources():
    """Extract the real code under test, without re-typing it."""
    signal = signal_file.read_text(encoding='utf-8')
    # TelegramCore is not available standalone; Logger is stubbed below instead.
    signal = signal.replace('import TelegramCore\n', '')

    app_delegate = app_delegate_file.read_text(encoding='utf-8')
    begin = app_delegate.index('// AYUGRAM-PUSH-SIGNAL-BEGIN')
    end = app_delegate.index('// AYUGRAM-PUSH-SIGNAL-END')
    handler = app_delegate[begin:end]
    # The block is a set of methods on AppDelegate; drop the markers and keep the body.
    handler = handler.replace('// AYUGRAM-PUSH-SIGNAL-BEGIN', '').replace('// AYUGRAM-PUSH-SIGNAL-END', '')
    return signal, handler


# Minimal stand-ins for the TelegramCore / TelegramUI types the AyuGram block touches.
# Signatures are copied from the real declarations:
#   Account.stateManager            -> TelegramCore/Sources/Account/Account.swift
#   AccountStateManager             -> TelegramCore/Sources/State/AccountStateManager.swift
#   AccountContext.account          -> submodules/AccountContext/Sources/AccountContext.swift
#   activeAccountContexts           -> submodules/TelegramUI/Sources/SharedAccountContext.swift
STUBS = r'''
import Foundation

final class Logger {
    static let shared = Logger()
    func log(_ tag: String, _ what: @autoclosure () -> String) {}
}

struct AccountRecordId {
}

final class UnauthorizedAccount {
}

final class AccountStateManager {
    func standalonePollDifference() -> Signal<Bool, NoError> {
        return Signal<Bool, NoError> { _ in EmptyDisposable }
    }
}

final class Account {
    var stateManager: AccountStateManager!
}

protocol AccountContext: AnyObject {
    var account: Account { get }
}

final class SharedAccountContextImpl {
    var activeAccountContexts: Signal<(primary: AccountContext?, accounts: [(AccountRecordId, AccountContext, Int32)], currentAuth: UnauthorizedAccount?), NoError> {
        return Signal<(primary: AccountContext?, accounts: [(AccountRecordId, AccountContext, Int32)], currentAuth: UnauthorizedAccount?), NoError> { _ in EmptyDisposable }
    }
}

final class SharedApplicationContext {
    let sharedContext: SharedAccountContextImpl
    init() {
        self.sharedContext = SharedAccountContextImpl()
    }
}
'''

# The AyuGram block is written as AppDelegate methods; give it the same shape.
HARNESS_CLASS = r'''
final class AppDelegateHarness {
    private let sharedContextPromise = Promise<SharedApplicationContext>()
'''


def check_signal_name_matches_tweak(signal_source):
    """The Swift receiver and the Objective-C tweak must agree on the signal name.

    If they disagree, the relay silently does nothing: no crash, no log line,
    the user just never gets notifications. Both sides hardcode the name, so
    the only way to catch a mismatch is to compare the two sources.
    """
    swift_names = re.findall(r'"(com\.[A-Za-z0-9._-]+)"', signal_source)
    tweak_names = re.findall(r'@"(com\.[A-Za-z0-9._-]+)"', tweak_file.read_text(encoding='utf-8'))

    if not swift_names:
        print('--- Darwin signal name: FAILED (no com.* name found in AyuGramPushSignal.swift) ---')
        return False
    if not tweak_names:
        print('--- Darwin signal name: FAILED (no com.* name found in the tweak) ---')
        return False

    swift_set = set(swift_names)
    tweak_set = set(tweak_names)
    print(f'--- Darwin signal name: receiver {sorted(swift_set)} / tweak {sorted(tweak_set)} ---')
    if swift_set != tweak_set:
        print('--- Darwin signal name: FAILED (receiver and tweak use different names) ---')
        return False
    return True


def swiftc_available():
    try:
        subprocess.run(['swiftc', '--version'], check=True, capture_output=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def sdk_path():
    for sdk in ('iphoneos', 'macosx'):
        result = subprocess.run(['xcrun', '--sdk', sdk, '--show-sdk-path'], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return sdk, result.stdout.strip()
    return None, None


def compile_check(label, files, extra_args):
    """Type-check the given files; return (ok, combined output)."""
    cmd = ['swiftc', '-typecheck', '-swift-version', '5'] + extra_args + [str(f) for f in files]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = (result.stdout or '') + (result.stderr or '')
    ok = result.returncode == 0
    print(f'--- {label}: {"OK" if ok else "FAILED"} ---')
    if output.strip():
        print(output.strip())
    return ok, output


def main():
    signal, handler = read_production_sources()
    name_ok = check_signal_name_matches_tweak(signal)

    if not swiftc_available():
        print('swiftc not available - skipping type-check (this runner has no Swift toolchain)')
        return 0 if name_ok else 1

    sdk, sdk_path_value = sdk_path()
    if sdk is None:
        print('no SDK found - skipping type-check')
        return 0 if name_ok else 1

    target = 'arm64-apple-ios15.0' if sdk == 'iphoneos' else 'arm64-apple-macos12.0'
    sdk_args = ['-sdk', sdk_path_value, '-target', target]

    with tempfile.TemporaryDirectory(prefix='ayupush-check-') as tmp:
        tmpdir = pathlib.Path(tmp)
        stubs = tmpdir / 'Stubs.swift'
        stubs.write_text(STUBS, encoding='utf-8')
        signal_src = tmpdir / 'AyuGramPushSignal.swift'
        signal_src.write_text(signal, encoding='utf-8')
        handler_src = tmpdir / 'AppDelegateHarness.swift'
        handler_src.write_text(HARNESS_CLASS + handler + '\n}\n', encoding='utf-8')

        files = [stubs, signal_src, handler_src] + signalkit_sources
        ok, output = compile_check('AyuGram push-signal receiver', files, sdk_args)

        # Warnings that point at our own code are build failures in the real build
        # (TelegramUI compiles with -warnings-as-errors), so treat them as errors here.
        own_warnings = [
            line for line in output.splitlines()
            if re.search(r'(warning|error):', line)
            and ('AyuGramPushSignal.swift' in line or 'AppDelegateHarness.swift' in line)
        ]
        if own_warnings:
            print('--- FAILED: warnings/errors in AyuGram code (real build uses -warnings-as-errors) ---')
            for line in own_warnings:
                print(line)
            ok = False

        probe_signature(sdk_args)

    if not ok or not name_ok:
        print('Darwin push-signal receiver: FAILED')
        return 1
    print('Darwin push-signal receiver: type-check passed')
    return 0


def probe_signature(sdk_args):
    """Print the exact Swift type of the CoreFoundation API we call.

    Assigning the function to the wrong type makes swiftc spell out its full
    signature for the SDK that is installed, so the Darwin-notification code is
    written against the real SDK instead of against memory. The probe is expected
    to fail to compile - that failure *is* the output we want.
    """
    probe = r'''
import Foundation
import CoreFoundation
let _: Int = CFNotificationCenterAddObserver
let _: Int = CFNotificationCenterGetDarwinNotifyCenter
let _: Int = CFNotificationCenterPostNotification
'''
    with tempfile.TemporaryDirectory(prefix='ayupush-probe-') as tmp:
        path = pathlib.Path(tmp) / 'Probe.swift'
        path.write_text(probe, encoding='utf-8')
        cmd = ['swiftc', '-typecheck', '-swift-version', '5'] + sdk_args + [str(path)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = (result.stdout or '') + (result.stderr or '')
        print('--- CoreFoundation API as imported by the installed SDK ---')
        for line in output.splitlines():
            if 'cannot convert value of type' in line:
                print(line.strip())
        if not output.strip():
            print('(probe produced no diagnostics)')



if __name__ == '__main__':
    sys.exit(main())
