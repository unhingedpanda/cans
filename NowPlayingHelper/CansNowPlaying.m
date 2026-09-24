// CansNowPlaying: reads macOS's system Now Playing (the Control Center source) for Cans.
//
// Since macOS 15.4 MediaRemote only answers Apple-signed processes, so Cans loads this
// library into /usr/bin/perl and calls in after load (the approach of the open-source
// mediaremote-adapter project). Two entry points, both called as perl XSUBs:
//   cans_stream   prints one JSON line per Now Playing change until stdin closes.
//   cans_command  sends the MediaRemote command named in $CANS_COMMAND, then returns.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetAppFn)(dispatch_queue_t, void (^)(id));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, NSDictionary *);

static void *MR(const char *name) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    return handle ? dlsym(handle, name) : NULL;
}

static void emit(void) {
    GetInfoFn getInfo = (GetInfoFn)MR("MRMediaRemoteGetNowPlayingInfo");
    GetAppFn getApp = (GetAppFn)MR("MRMediaRemoteGetNowPlayingClient");
    if (!getInfo) return;
    getInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        if ([title isKindOfClass:NSString.class]) out[@"title"] = title;
        if ([artist isKindOfClass:NSString.class]) out[@"artist"] = artist;
        out[@"playing"] = @([rate doubleValue] > 0);
        void (^finish)(NSString *) = ^(NSString *app) {
            if (app) out[@"app"] = app;
            NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
            if (json) {
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            }
        };
        if (!getApp) { finish(nil); return; }
        getApp(dispatch_get_main_queue(), ^(id client) {
            NSString *bundleID = nil;
            SEL sel = NSSelectorFromString(@"bundleIdentifier");
            if (client && [client respondsToSelector:sel]) bundleID = [client performSelector:sel];
            finish(bundleID);
        });
    });
}

void cans_stream(void *interpreter, void *cv) {
    RegisterFn registerFn = (RegisterFn)MR("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (registerFn) registerFn(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { emit(); }];
    }
    emit();
    // Exit when Cans goes away (its end of the pipe closes).
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        char buffer[64];
        if (read(STDIN_FILENO, buffer, sizeof buffer) <= 0) exit(0);
    });
    dispatch_resume(source);
    CFRunLoopRun();
}

void cans_command(void *interpreter, void *cv) {
    SendCommandFn send = (SendCommandFn)MR("MRMediaRemoteSendCommand");
    const char *name = getenv("CANS_COMMAND");
    if (!send || !name) return;
    // MRMediaRemoteCommand values: 2 toggle play/pause, 4 next track, 5 previous track.
    int command = strcmp(name, "next") == 0 ? 4 : strcmp(name, "previous") == 0 ? 5 : 2;
    send(command, nil);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);  // let the XPC message leave
}
