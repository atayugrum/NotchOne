// NotchOne system Now Playing reader.
//
// Run as: /usr/bin/osascript -l JavaScript SystemNowPlaying.js <parent-pid>
//
// Since macOS 15.4, MediaRemote only answers Apple-signed processes. osascript is one,
// so this script reads the system-wide Now Playing state and prints one JSON line to
// stdout whenever it changes. It exits when the parent app is gone.

ObjC.import('Foundation');
ObjC.import('AppKit');

function run(argv) {
    const parentPID = parseInt(argv[0] || '0', 10);
    const loaded = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework').load;
    const Request = $.NSClassFromString('MRNowPlayingRequest');
    const stdout = $.NSFileHandle.fileHandleWithStandardOutput;

    function emit(object) {
        const line = $.NSString.alloc.initWithUTF8String(JSON.stringify(object) + '\n');
        stdout.writeData(line.dataUsingEncoding($.NSUTF8StringEncoding));
    }

    if (!loaded || Request.isNil()) {
        emit({ unavailable: true });
        return;
    }

    function value(info, key) {
        const object = info.objectForKey('kMRMediaRemoteNowPlayingInfo' + key);
        return object.isNil() ? null : ObjC.unwrap(object);
    }

    function stringFrom(target, selector) {
        try {
            if (!target.respondsToSelector(selector)) return null;
            const result = target.performSelector(selector);
            return result.isNil() ? null : ObjC.unwrap(result);
        } catch (error) {
            return null;
        }
    }

    function snapshot() {
        const item = Request.localNowPlayingItem;
        if (item.isNil()) return { none: true };
        const info = item.nowPlayingInfo;
        if (info.isNil()) return { none: true };

        const client = Request.localNowPlayingPlayerPath.client;
        const timestamp = info.objectForKey('kMRMediaRemoteNowPlayingInfoTimestamp');

        return {
            bundle: client.isNil() ? null : stringFrom(client, 'bundleIdentifier'),
            parentBundle: client.isNil() ? null : stringFrom(client, 'parentApplicationBundleIdentifier'),
            title: value(info, 'Title'),
            artist: value(info, 'Artist'),
            album: value(info, 'Album'),
            duration: value(info, 'Duration'),
            elapsed: value(info, 'ElapsedTime'),
            rate: value(info, 'PlaybackRate'),
            timestamp: timestamp.isNil() ? null : timestamp.timeIntervalSince1970,
            playing: Request.localIsPlaying === true,
        };
    }

    let last = '';
    while (true) {
        if (parentPID > 0 && $.NSRunningApplication.runningApplicationWithProcessIdentifier(parentPID).isNil()) {
            return;
        }
        let current;
        try {
            current = JSON.stringify(snapshot());
        } catch (error) {
            current = JSON.stringify({ error: String(error) });
        }
        if (current !== last) {
            last = current;
            emit(JSON.parse(current));
        }
        delay(1);
    }
}
