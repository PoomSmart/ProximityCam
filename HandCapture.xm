#import <substrate.h>
#import <SpringBoard/SpringBoard.h>
#import <notify.h>

#define PREF_PATH @"/var/mobile/Library/Preferences/com.PS.HandCapture.plist"
#define PreferencesChangedNotification "com.PS.HandCapture.prefs"
#define TAKE_PHOTO_IDENT @"com.PS.ProximityCam.takePhoto"
#define BURST_PHOTO_IDENT @"com.PS.ProximityCam.burstPhoto"

@interface NSDistributedNotificationCenter : NSNotificationCenter
@end

@interface PLCameraView
- (void)_shutterButtonClicked;
- (void)_beginTimedCapture;
- (void)_finishTimedCapture;
@end

@interface PLCameraController
+ (id)sharedInstance;
- (PLCameraView *)delegate;
- (int)cameraMode;
- (BOOL)isReady;
@end

static BOOL PanEnabled = YES;
static BOOL BurstEnabled = YES;

static double startTime;
static double endTime;
static double limitTime;
static double burstTime;

static NSTimer *burstHC;

%hook PLCameraView

%new
- (void)hcTakePhoto
{
	PLCameraController *cont = [%c(PLCameraController) sharedInstance];
	if ([cont isReady]) {
		if ([cont cameraMode] == 0 || [cont cameraMode] == 4)
			[self _shutterButtonClicked];
	}
}

%new
- (void)hcBurstPhoto:(NSNotification *)notification
{
	if ([[notification.userInfo objectForKey:@"State"] intValue] == 1)
		[self _beginTimedCapture];
	else
		[self _finishTimedCapture];
}

- (id)initWithFrame:(CGRect)frame spec:(id)spec
{
	id ret = %orig;
	[[UIDevice currentDevice] setProximityMonitoringEnabled:PanEnabled];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:ret selector:@selector(hcTakePhoto) name:TAKE_PHOTO_IDENT object:nil];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:ret selector:@selector(hcBurstPhoto:) name:BURST_PHOTO_IDENT object:nil];
	return ret;
}

- (void)dealloc
{
	[[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	%orig;
}

%end

%hook SpringBoard

%new
- (void)hcBurst
{
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:BURST_PHOTO_IDENT object:nil userInfo:@{@"State" : @"1"}];
}

- (void)_proximityChanged:(NSNotification *)notification
{
	SBApplication *runningApp = [(SpringBoard *)self _accessibilityFrontMostApplication];
	NSString *ident = [runningApp bundleIdentifier];
	BOOL shouldRun = [ident isEqualToString:@"com.apple.camera"] || ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"] && [self isCameraApp]);
	BOOL plExist = objc_getClass("PLCameraView") != nil;
	if (!shouldRun || !plExist) {
		%orig;
		return;
	}
	BOOL proximate = [[notification.userInfo objectForKey:@"kSBNotificationKeyState"] boolValue];
	if (proximate) {
    	startTime = [NSDate timeIntervalSinceReferenceDate];
    	if (BurstEnabled) {
    		burstHC = [NSTimer scheduledTimerWithTimeInterval:burstTime target:self selector:@selector(hcBurst) userInfo:nil repeats:NO];
    		[burstHC retain];
    	}
        } else {
    	endTime = [NSDate timeIntervalSinceReferenceDate];
    	if (burstHC != nil && BurstEnabled) {
    		[burstHC invalidate];
    		burstHC = nil;
    		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:BURST_PHOTO_IDENT object:nil userInfo:@{@"State" : @"0"}];
    	}
    	double interval = endTime - startTime;
    	if (interval <= limitTime) {
			if (shouldRun && plExist && PanEnabled) {
				[[NSDistributedNotificationCenter defaultCenter] postNotificationName:TAKE_PHOTO_IDENT object:nil];
				return;
			}
		}
	}
}

%end

static void HC()
{
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
	PanEnabled = [dict objectForKey:@"PanEnabled"] ? [[dict objectForKey:@"PanEnabled"] boolValue] : YES;
	BurstEnabled = [dict objectForKey:@"BurstEnabled"] ? [[dict objectForKey:@"BurstEnabled"] boolValue] : YES;
	limitTime = [dict objectForKey:@"interval"] ? [[dict objectForKey:@"interval"] doubleValue] : 1;
	burstTime = [dict objectForKey:@"Binterval"] ? [[dict objectForKey:@"Binterval"] doubleValue] : 1.7;
}

static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	HC();
}

%ctor {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PreferencesChangedCallback, CFSTR(PreferencesChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);
	HC();
	%init;
	[pool drain];
}
