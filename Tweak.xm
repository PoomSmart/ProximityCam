#import <substrate.h>
#import <SpringBoard/SpringBoard.h>
#import <notify.h>
#import "../PS.h"

NSString *PREF_PATH = @"/var/mobile/Library/Preferences/com.PS.HandCapture.plist";
CFStringRef PreferencesChangedNotification = CFSTR("com.PS.HandCapture.prefs");
NSString *TAKE_PHOTO_IDENT = @"com.PS.ProximityCam.takePhoto";
NSString *BURST_PHOTO_IDENT = @"com.PS.ProximityCam.burstPhoto";

@interface NSDistributedNotificationCenter : NSNotificationCenter
@end

static BOOL PanEnabled = YES;
static BOOL BurstEnabled = YES;

static double startTime;
static double endTime;
static double limitTime;
static double burstTime;

static NSTimer *burstHC;

%group iOS7

%hook PLCameraView

%new
- (void)hcTakePhoto
{
	PLCameraController *cont = [%c(PLCameraController) sharedInstance];
	if ([cont isReady]) {
		if (cont.cameraMode == 0 || cont.cameraMode == 4)
			[self _shutterButtonClicked];
	}
}

%new
- (void)hcBurstPhoto:(NSNotification *)notification
{
	if ([notification.userInfo[@"State"] intValue] == 1)
		[self _beginTimedCapture];
	else
		[self _finishTimedCapture];
}

- (id)initWithFrame:(CGRect)frame spec:(id)spec
{
	self = %orig;
	[[UIDevice currentDevice] setProximityMonitoringEnabled:PanEnabled];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(hcTakePhoto) name:TAKE_PHOTO_IDENT object:nil];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(hcBurstPhoto:) name:BURST_PHOTO_IDENT object:nil];
	return self;
}

- (void)dealloc
{
	[[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	%orig;
}

%end

%end

%group iOS8

%hook CAMCameraView

%new
- (void)hcTakePhoto
{
	CAMCaptureController *cont = [%c(CAMCaptureController) sharedInstance];
	if ([cont isReady]) {
		if (cont.cameraMode == 0 || cont.cameraMode == 4)
			[self _shutterButtonClicked];
	}
}

%new
- (void)hcBurstPhoto:(NSNotification *)notification
{
	if ([notification.userInfo[@"State"] intValue] == 1)
		[self _startAvalancheCapture];
	else
		[self _finishAvalancheCapture];
}

- (id)initWithFrame:(CGRect)frame spec:(id)spec
{
	self = %orig;
	[[UIDevice currentDevice] setProximityMonitoringEnabled:PanEnabled];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(hcTakePhoto) name:TAKE_PHOTO_IDENT object:nil];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(hcBurstPhoto:) name:BURST_PHOTO_IDENT object:nil];
	return self;
}

- (void)dealloc
{
	[[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	%orig;
}

%end

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
	BOOL shouldRun = [ident isEqualToString:@"com.apple.camera"] || ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] && [self isCameraApp]);
	BOOL classExist = objc_getClass("PLCameraView") || objc_getClass("CAMCameraView");
	if (!shouldRun || !classExist) {
		%orig;
		return;
	}
	BOOL proximate = [notification.userInfo[@"kSBNotificationKeyState"] boolValue];
	if (proximate) {
    	startTime = [NSDate timeIntervalSinceReferenceDate];
    	if (BurstEnabled) {
    		burstHC = [NSTimer scheduledTimerWithTimeInterval:burstTime target:self selector:@selector(hcBurst) userInfo:nil repeats:NO];
    		[burstHC retain];
    	}
        } else {
    	endTime = [NSDate timeIntervalSinceReferenceDate];
    	if (burstHC && BurstEnabled) {
    		[burstHC invalidate];
    		burstHC = nil;
    		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:BURST_PHOTO_IDENT object:nil userInfo:@{@"State" : @"0"}];
    	}
    	double interval = endTime - startTime;
    	if (interval <= limitTime) {
			if (shouldRun && classExist && PanEnabled) {
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
	id value = dict[@"PanEnabled"];
	PanEnabled = value ? [value boolValue] : YES;
	value = dict[@"BurstEnabled"];
	BurstEnabled = value ? [value boolValue] : YES;
	value = dict[@"interval"];
	limitTime = value ? [value doubleValue] : 1;
	value = dict[@"Binterval"];
	burstTime = value ? [value doubleValue] : 1.7;
}

static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	HC();
}

%ctor
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PreferencesChangedCallback, PreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
	HC();
	if (isiOS8Up) {
		%init(iOS8);
	} else {
		%init(iOS7);
	}
	%init;
	[pool drain];
}
