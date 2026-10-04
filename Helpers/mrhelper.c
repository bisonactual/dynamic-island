#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

// Bridge to the private MediaRemote framework. Loaded inside an Apple-signed host
// (/usr/bin/python3) so the now-playing calls aren't blocked for us.

typedef void (*GetInfo)(dispatch_queue_t, void(^)(CFDictionaryRef));
typedef void (*GetPlaying)(dispatch_queue_t, void(^)(Boolean));
typedef void (*GetPID)(dispatch_queue_t, void(^)(int));
typedef void (*RegisterNotify)(dispatch_queue_t);
typedef Boolean (*SendCmd)(int, CFDictionaryRef);

static char gTitle[2048], gArtist[2048], gAlbum[2048], gId[512];
static double gDur, gEla; static int gPlaying; static int gPid;
static const unsigned char* gArt; static long gArtLen; static CFDataRef gArtData;
static GetInfo gGetInfo; static GetPlaying gGetPlaying; static GetPID gGetPID;

static void* mrHandle(void){
    static void* h;
    if(!h) h=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_NOW);
    return h;
}
static void jsonEscape(CFStringRef s, char* out, size_t cap){
    out[0]=0; if(!s) return; char buf[1024]; if(!CFStringGetCString(s,buf,sizeof(buf),kCFStringEncodingUTF8)) return;
    size_t o=0; for(size_t i=0; buf[i] && o<cap-2; i++){ char c=buf[i];
        if(c=='"'||c=='\\'){out[o++]='\\';out[o++]=c;} else if(c=='\n'){out[o++]='\\';out[o++]='n';} else if((unsigned char)c>=32){out[o++]=c;} }
    out[o]=0;
}
static const char B64[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static void base64_print(const unsigned char* d, long n){
    for(long i=0;i<n;i+=3){ unsigned v=d[i]<<16; if(i+1<n)v|=d[i+1]<<8; if(i+2<n)v|=d[i+2];
        putchar(B64[(v>>18)&63]); putchar(B64[(v>>12)&63]);
        putchar(i+1<n?B64[(v>>6)&63]:'='); putchar(i+2<n?B64[v&63]:'='); }
}
static void loadSyms(void){
    void* h=mrHandle(); if(!h) return;
    if(!gGetInfo) gGetInfo=(GetInfo)dlsym(h,"MRMediaRemoteGetNowPlayingInfo");
    if(!gGetPlaying) gGetPlaying=(GetPlaying)dlsym(h,"MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if(!gGetPID) gGetPID=(GetPID)dlsym(h,"MRMediaRemoteGetNowPlayingApplicationPID");
}
static void fillFrom(CFDictionaryRef info){
    gTitle[0]=gArtist[0]=gAlbum[0]=gId[0]=0; gDur=gEla=0; gPlaying=-1; gArt=NULL; gArtLen=0;
    if(!info) return;
    jsonEscape(CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoTitle")),gTitle,sizeof(gTitle));
    jsonEscape(CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoArtist")),gArtist,sizeof(gArtist));
    jsonEscape(CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoAlbum")),gAlbum,sizeof(gAlbum));
    jsonEscape(CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoContentItemIdentifier")),gId,sizeof(gId));
    CFNumberRef d=CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoDuration")); if(d)CFNumberGetValue(d,kCFNumberDoubleType,&gDur);
    CFNumberRef e=CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime")); if(e)CFNumberGetValue(e,kCFNumberDoubleType,&gEla);
    CFNumberRef r=CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate")); if(r){double rr=0;CFNumberGetValue(r,kCFNumberDoubleType,&rr);gPlaying=rr>0;}
    gArtData=CFDictionaryGetValue(info,CFSTR("kMRMediaRemoteNowPlayingInfoArtworkData"));
    if(gArtData){ gArt=CFDataGetBytePtr(gArtData); gArtLen=CFDataGetLength(gArtData); }
}
static void printMeta(int isPlaying){
    printf("{\"title\":\"%s\",\"artist\":\"%s\",\"album\":\"%s\",\"id\":\"%s\",\"duration\":%.2f,\"elapsed\":%.2f,\"isPlaying\":%s,\"pid\":%d}\n",
        gTitle,gArtist,gAlbum,gId,gDur,gEla,isPlaying>0?"true":"false",gPid);
    fflush(stdout);
}

// --- Persistent stream: emits immediately on change (via MediaRemote
//     notifications) plus a 1s heartbeat for elapsed drift / missed events. ---
static void emitInfo(void){
    gGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info){
        fillFrom(info);
        if(gPlaying<0 && gGetPlaying){ gGetPlaying(dispatch_get_main_queue(), ^(Boolean p){ printMeta(p?1:0); }); }
        else printMeta(gPlaying);
    });
}
static void streamTick(void){
    if(!gGetInfo) return;
    // Fetch the PID first, then the info *inside* its callback, so `pid` is current
    // for this emit instead of lagging one tick behind (it's set asynchronously).
    if(gGetPID) gGetPID(dispatch_get_main_queue(), ^(int pid){ gPid=pid; emitInfo(); });
    else emitInfo();
}
static void notifCallback(CFNotificationCenterRef c, void* observer, CFNotificationName name,
                          const void* object, CFDictionaryRef userInfo){
    streamTick();   // play/pause or track changed → emit right away
}
void mr_stream(void){
    loadSyms(); if(!gGetInfo){ printf("{}\n"); fflush(stdout); return; }
    void* h=mrHandle();
    RegisterNotify reg=(RegisterNotify)dlsym(h,"MRMediaRemoteRegisterForNowPlayingNotifications");
    if(reg) reg(dispatch_get_main_queue());

    // React instantly to play/pause and track changes.
    CFNotificationCenterRef nc=CFNotificationCenterGetLocalCenter();
    const char* names[]={
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRNowPlayingPlaybackQueueChangedNotification"
    };
    for(int i=0;i<3;i++){
        CFStringRef n=CFStringCreateWithCString(NULL,names[i],kCFStringEncodingUTF8);
        CFNotificationCenterAddObserver(nc,NULL,notifCallback,n,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        CFRelease(n);
    }

    // Heartbeat so elapsed stays in sync and nothing is missed.
    static dispatch_source_t timer;
    timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,1LL*NSEC_PER_SEC,200LL*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{ streamTick(); });
    dispatch_resume(timer);
    CFRunLoopRun();
}

// --- One-off artwork fetch (heavy; called only on track change). ---
static int gArtDone;
void mr_get_artwork(void){
    loadSyms(); if(!gGetInfo){ printf("\n"); fflush(stdout); return; }
    gArtDone=0;
    gGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info){
        fillFrom(info);
        if(gArt && gArtLen>0) base64_print(gArt,gArtLen);
        printf("\n"); fflush(stdout); gArtDone=1; CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3LL*NSEC_PER_SEC),dispatch_get_main_queue(),^{ if(!gArtDone){printf("\n");fflush(stdout);CFRunLoopStop(CFRunLoopGetMain());} });
    CFRunLoopRun();
}

// --- Transport command: 0 play,1 pause,2 toggle,4 next,5 previous. ---
void mr_command(int cmd){
    void* h=mrHandle(); if(!h) return;
    SendCmd s=(SendCmd)dlsym(h,"MRMediaRemoteSendCommand");
    if(s) s(cmd,NULL);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.5,false);
}
