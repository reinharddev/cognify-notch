// "Yang sedang diputar" untuk notch Cognify (lagu/video dari Spotify, Apple Music, YouTube di
// browser, VLC, dll.) + tombol putar/jeda/lagu berikutnya.
//
// Sejak macOS 15.4, framework privat MediaRemote hanya menjawab proses milik Apple. Karena itu
// library ini tidak dipanggil langsung oleh notch, tapi dimuat ke /usr/bin/perl (program Apple),
// lalu perl memanggil `cognify_media_run` (lihat MediaMonitor di Media.swift untuk perintahnya).
// Loop tidak boleh berjalan di constructor library: di sana proses pemuatan masih terkunci dan
// pembaruan MediaRemote tidak pernah diterima (teruji: judul tetap lagu lama setelah skip).
// Cara yang sama dipakai Boring Notch (mediaremote-adapter). Bisa berhenti bekerja jika Apple
// menutup celah ini; notch lalu menyembunyikan bagian media.
//
// Keluar (stdout, satu baris JSON per perubahan):
//   {"title","artist","album","duration","elapsed","rate","timestamp","playing","bundle","shuffle","repeat","artworkKey","artwork"?}
//   `shuffle`/`repeat`: mode MediaRemote (1 = mati; shuffle 2/3 = album/lagu; repeat 2 = satu lagu, 3 = semua), null = app tidak melapor.
//   `artwork` (base64) hanya dikirim saat gambarnya berubah. {"idle":true} = tidak ada yang diputar.
// Masuk (stdin): toggle | play | pause | next | prev | shuffle | repeat | seek:<detik>. stdin tertutup → keluar.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, NSDictionary *);
typedef void (*MRSetElapsed)(double);
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientString)(id);

static MRGetInfo getInfo;
static MRGetIsPlaying getIsPlaying;
static MRSendCommand sendCommand;
static MRSetElapsed setElapsed;
static MRGetClient getClient;
static MRClientString clientBundle;
static MRClientString clientParentBundle;
static NSUInteger lastArtworkKey;
static NSString *lastSignature;
static dispatch_queue_t queue;

static void writeLine(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id orNull(id value) { return value ?: [NSNull null]; }

static void emit(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getIsPlaying(queue, ^(BOOL playing) {
            void (^finish)(NSString *) = ^(NSString *bundle) {
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (title.length == 0) {
                    if (![lastSignature isEqualToString:@"idle"]) writeLine(@{@"idle": @YES});
                    lastSignature = @"idle";
                    return;
                }
                NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                // Hanya melapor jika ada yang berubah (dipanggil juga oleh pemeriksaan tiap detik).
                id shuffle = info[@"kMRMediaRemoteNowPlayingInfoShuffleMode"];
                id repeat = info[@"kMRMediaRemoteNowPlayingInfoRepeatMode"];
                NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%d|%@|%lu|%@|%@|%@|%@",
                    title, info[@"kMRMediaRemoteNowPlayingInfoArtist"], info[@"kMRMediaRemoteNowPlayingInfoAlbum"], playing, bundle,
                    (unsigned long)(art ? (art.length ^ art.hash) : 0), info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"], stamp,
                    shuffle, repeat];
                if ([signature isEqualToString:lastSignature]) return;
                lastSignature = signature;
                NSMutableDictionary *out = [@{
                    @"title": title,
                    @"artist": orNull(info[@"kMRMediaRemoteNowPlayingInfoArtist"]),
                    @"album": orNull(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
                    @"duration": orNull(info[@"kMRMediaRemoteNowPlayingInfoDuration"]),
                    @"elapsed": orNull(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]),
                    @"rate": orNull(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
                    @"timestamp": stamp ? @(stamp.timeIntervalSince1970) : [NSNull null],
                    @"playing": @(playing),
                    @"bundle": orNull(bundle),
                    @"shuffle": orNull(shuffle),
                    @"repeat": orNull(repeat),
                    @"artworkKey": @(art ? (art.length ^ art.hash) : 0),
                } mutableCopy];
                NSUInteger key = art ? (art.length ^ art.hash) : 0;
                if (art && key != lastArtworkKey) out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                lastArtworkKey = key;
                writeLine(out);
            };
            if (!getClient) { finish(nil); return; }
            getClient(queue, ^(id client) {
                NSString *parent = client && clientParentBundle ? clientParentBundle(client) : nil;
                NSString *own = client && clientBundle ? clientBundle(client) : nil;
                finish(parent.length ? parent : own); // video di browser → bundle browsernya
            });
        });
    });
}

static void runCommand(NSString *line) {
    if ([line hasPrefix:@"seek:"]) {
        if (setElapsed) setElapsed([[line substringFromIndex:5] doubleValue]);
        return;
    }
    NSDictionary *codes = @{@"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"prev": @5, @"shuffle": @6, @"repeat": @7};
    NSNumber *code = codes[line];
    if (code) sendCommand(code.intValue, nil);
}

// Dipasang perl sebagai fungsi XS (argumennya diabaikan) lalu dipanggil; tidak pernah kembali.
__attribute__((visibility("default"))) void cognify_media_run(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { writeLine(@{@"error": @"MediaRemote tidak tersedia"}); exit(1); }
    getInfo = (MRGetInfo)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetIsPlaying)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    sendCommand = (MRSendCommand)dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsed)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    getClient = (MRGetClient)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (MRClientString)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (MRClientString)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MRRegister reg = (MRRegister)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !sendCommand || !reg) { writeLine(@{@"error": @"MediaRemote berubah"}); exit(1); }

    queue = dispatch_get_main_queue();
    reg(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { emit(); }];
    }
    emit();
    // Notifikasi MediaRemote tidak selalu datang (mis. Spotify memperbarui info lagu sesudahnya),
    // jadi diperiksa juga tiap detik; `emit` hanya melapor jika ada perubahan.
    dispatch_source_t tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(tick, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(tick, ^{ emit(); });
    dispatch_resume(tick);

    [NSThread detachNewThreadWithBlock:^{
        char buffer[256];
        while (fgets(buffer, sizeof buffer, stdin)) {
            NSString *line = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(queue, ^{
                runCommand(line);
                for (int ms = 150; ms <= 1200; ms += 350) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), queue, ^{ emit(); });
                }
            });
        }
        exit(0); // notch sudah tidak ada
    }];
    dispatch_main();
}
