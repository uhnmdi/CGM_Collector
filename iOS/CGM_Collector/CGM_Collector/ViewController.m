//
//  ViewController.m
//  CGM_Collector
//
//  Created by Nathaniel Hamming on 2015-01-06.
//  Copyright (c) 2015 eHealth. All rights reserved.
//

#import "ViewController.h"
#import "UHNCGMController.h"
#import "UHNScrollingTimeSeriesPlotView.h"
#import "NHArrowView.h"
#import "UHNDebug.h"
#import "UHNCGMConstants.h"
#import "NSDictionary+CGMExtensions.h"

#define kGlucoseLabelDefaultString @"--"
#define kTimeLabelDefaultString @"N/A"

@interface ViewController () <UHNCGMControllerDelegate>
@property(nonatomic,strong) UHNCGMController *cgmController;
@property(nonatomic,strong) NSDateFormatter *dateFormatter;
@property(nonatomic,strong) IBOutlet UIButton *startSessionButton;
@property(nonatomic,strong) IBOutlet UIButton *connectButton;
@property(nonatomic,strong) IBOutlet UILabel *glucoseValueLabel;
@property(nonatomic,strong) IBOutlet UILabel *deviceNameLabel;
@property(nonatomic,strong) IBOutlet UILabel *startTimeLabel;
@property(nonatomic,strong) IBOutlet UILabel *runTimeLabel;
@property(nonatomic,strong) IBOutlet UILabel *trendWarningLabel;
@property(nonatomic,strong) IBOutlet UILabel *patientLowerLabel;
@property(nonatomic,strong) IBOutlet UILabel *patientUpperLabel;
@property(nonatomic,strong) IBOutlet UILabel *trendLowerLabel;
@property(nonatomic,strong) IBOutlet UILabel *trendUpperLabel;
@property(nonatomic,strong) IBOutlet UILabel *messageLabel;
@property(nonatomic,strong) IBOutlet UILabel *versionLabel;
@property(nonatomic,strong) IBOutlet UIButton *dismissButton;
@property(nonatomic,strong) IBOutlet UIView *messagingView;
@property(nonatomic,strong) IBOutlet UIView *hypoThresholdView;
@property(nonatomic,strong) IBOutlet UITextField *hypoThresholdTextField;
@property(nonatomic,strong) IBOutlet UIActivityIndicatorView *messagingActivity;
@property(nonatomic,strong) IBOutlet UHNScrollingTimeSeriesPlotView *plotView;
@property(nonatomic,strong) IBOutlet NHArrowView *trendArrow;
@property(nonatomic,assign) float tempPatientLowLevel;
@property(nonatomic,assign) float tempPatientHighLevel;
@property(nonatomic,assign) float tempHypoValue;
@property(nonatomic,assign) float tempHyperValue;
@property(nonatomic,assign) float tempRateDecreaseLevel;
@property(nonatomic,assign) float tempRateIncreaseLevel;
@property(nonatomic,assign) BOOL shouldStartNewSession;
@property(nonatomic,assign) BOOL isHistoricalData;
- (IBAction)connectButtonPressed:(id)sender;
- (IBAction)startSessionButtonPressed:(id)sender;
- (IBAction)dismissButtonPressed:(id)sender;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setNeedsStatusBarAppearanceUpdate];
    self.versionLabel.text = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"];
    self.glucoseValueLabel.text = kGlucoseLabelDefaultString;
    self.startTimeLabel.text = kTimeLabelDefaultString;
    self.runTimeLabel.text = kTimeLabelDefaultString;

    self.cgmController = [[UHNCGMController alloc] initWithDelegate: self];
    self.dateFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter.dateStyle = NSDateFormatterShortStyle;
    self.dateFormatter.timeStyle = NSDateFormatterShortStyle;
    
    //setup the plot Scrolling Time Series Plot View
    [self.plotView setupPlotWithXAxisMin: 0.
                                xAxisMax: 60.
                              xMinorStep: 100.
                              xMajorStep: 100.
                              xAxisLabel: nil
                       xAxisFormatString: nil
                                yAxisMin: 0.
                                yAxisMax: 325.
                              yMinorStep: 0.
                              yMajorStep: 0.
                              yAxisLabel: nil
                       yAxisFormatString: nil
                               gridColor: [UIColor grayColor]
                          gridFrameWidth: 1.
                           drawGridFrame: NO
                       fadeGridLineEdges: NO
                               lineColor: [UIColor whiteColor]
                           lineHeadColor: [UIColor blueColor]
                            andLineWidth: 1.];

    self.plotView.plotRefreshRateInHz = 1;
    self.plotView.samplingRateInHz = 1;
    self.plotView.windowMaxSize = 60;
    self.plotView.backgroundColor = [UIColor clearColor];

//    [self.plotView generateRandomData: YES];
    
    // setup the temp ranges
    self.tempHypoValue = 40;
    self.tempHyperValue = 210;
    self.tempPatientLowLevel = 75.;
    self.tempPatientHighLevel = 150.;
    self.tempRateDecreaseLevel = -2.;
    self.tempRateIncreaseLevel = 2.;
    
    // setup the trend arrow
    self.trendArrow.strokeColor = [UIColor clearColor];
    self.trendArrow.fillColor = [UIColor blueColor];
    self.trendArrow.hidden = YES;
    
    // setup messaging view
    self.messagingView.backgroundColor = [UIColor clearColor];
    self.messageLabel.hidden = YES;
    self.messagingActivity.hidden = YES;
    
    self.hypoThresholdView.backgroundColor = [UIColor clearColor];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}

- (void)updateGlucoseValueDisplay: (NSNumber*)glucoseValue;
{
    if (glucoseValue) {
        self.glucoseValueLabel.text = [glucoseValue stringValue];
        if ([glucoseValue floatValue] < self.tempHypoValue || [glucoseValue floatValue] > self.tempHyperValue) {
            self.glucoseValueLabel.textColor = [UIColor redColor];
            self.plotView.lineHeadColor = [UIColor redColor];
        } else if ([glucoseValue floatValue] < self.tempPatientLowLevel || [glucoseValue floatValue] > self.tempPatientHighLevel) {
            self.glucoseValueLabel.textColor = [UIColor yellowColor];
            self.plotView.lineHeadColor = [UIColor yellowColor];
        } else {
            self.glucoseValueLabel.textColor = [UIColor blueColor];
            self.plotView.lineHeadColor = [UIColor blueColor];
        }
    } else {
        self.glucoseValueLabel.text = kGlucoseLabelDefaultString;
    }
}

- (void)updateTrendArrow: (NSNumber*)trendValue;
{
    // trend arrow can be drawn at any degree, but only the following degrees are used
    //
    // -90 = x >= severWarningValue
    // -60 = moderateWarningValue <= x <= severWarningValue
    // -30 = mildWarningValue <= x <= moderateWarningValue
    // 0 = -1 * mildWarningValue < x < mildWarningValue
    // 30 = -1 * moderateWarningValue < x <= -1 * mildWarningValue
    // 60 = -1 * severWarningValue < x <= -1 * moderateWarningValue
    // 90 = x <= -1 * severWarningValue
    //
    float mildWarningValue = 2.;
    float moderateWarningValue = 15.;
    float severeWarningValue = 25.;
    
    if (trendValue) {
        self.trendWarningLabel.hidden = YES;
        self.trendArrow.hidden = NO;
        float value = [trendValue floatValue];
        CGFloat degrees = 0.;
        if (value >= severeWarningValue) {
            degrees = -90;
            self.trendArrow.fillColor = [UIColor redColor];
        } else if (value >= moderateWarningValue && value < severeWarningValue) {
            degrees = -60;
            self.trendArrow.fillColor = [UIColor yellowColor];
        } else if (value >= mildWarningValue && value < moderateWarningValue) {
            degrees = -30.;
            self.trendArrow.fillColor = [UIColor blueColor];
        } else if (value > -1 * mildWarningValue && value < mildWarningValue) {
            degrees = 0.;
            self.trendArrow.fillColor = [UIColor blueColor];
        } else if (value <= -1 * mildWarningValue && value > -1 * moderateWarningValue) {
            degrees = 30.;
            self.trendArrow.fillColor = [UIColor blueColor];
        } else if (value <= -1 * moderateWarningValue && value > -1 * severeWarningValue) {
            degrees = 60.;
            self.trendArrow.fillColor = [UIColor yellowColor];
        } else if (value <= -1 * severeWarningValue) {
            degrees = 90.;
            self.trendArrow.fillColor = [UIColor redColor];
        }
        [self.trendArrow animatedRotateToDegree: degrees];
    } else {
        self.trendWarningLabel.hidden = NO;
        self.trendArrow.hidden = YES;
    }
}

- (void)loadStoredData;
{
    // get historical data
    self.isHistoricalData = YES;
    self.messageLabel.text = @"Loading data...";
    self.messageLabel.hidden = NO;
    self.messagingActivity.hidden = NO;
    [self.messagingActivity startAnimating];
    [self.cgmController getAllStoredRecords];
}

- (void)finishedLoadingStoredData;
{
    self.isHistoricalData = NO;
    self.startSessionButton.enabled = YES;
    [self.messagingActivity stopAnimating];
    self.messagingActivity.hidden = YES;
    self.messageLabel.hidden = YES;
    [self.cgmController sendCurrentTime];
}

#pragma mark - IBAction Methods

- (IBAction)connectButtonPressed:(id)sender;
{
    self.connectButton.enabled = NO;
    [self.cgmController tryToReconnect];
}

- (IBAction)startSessionButtonPressed:(id)sender;
{
    [self.cgmController stopSession];
    self.shouldStartNewSession = YES;
    [self.plotView removeAllDataPoints];
}

- (IBAction)dismissButtonPressed:(id)sender;
{
    [self.hypoThresholdTextField resignFirstResponder];
}

#pragma mark - CGM Profile Delegate Methods

- (void) cgmController: (UHNCGMController*)controller didDiscoverCGMWithName: (NSString*)cgmDeviceName services:(NSArray *)serviceUUIDs RSSI:(NSNumber *)RSSI;
{
    [self.cgmController connectToDevice: cgmDeviceName];
}

- (void) cgmController: (UHNCGMController*)controller didConnectToCGMWithName:(NSString *)cgmDeviceName;
{
    self.deviceNameLabel.text = cgmDeviceName;
    self.connectButton.enabled = NO;
    [self.cgmController enableNotificationRACP: YES];
}

- (void) cgmController: (UHNCGMController*)controller didDisconnectFromCGM: (NSString*)cgmDeviceName;
{
    self.startSessionButton.enabled = NO;
    self.connectButton.enabled = YES;
    self.startTimeLabel.text = kTimeLabelDefaultString;
    self.runTimeLabel.text = kTimeLabelDefaultString;
    self.trendArrow.hidden = YES;
    self.trendWarningLabel.hidden = NO;
    self.glucoseValueLabel.text = kGlucoseLabelDefaultString;
    self.glucoseValueLabel.textColor = [UIColor whiteColor];
}

- (void) cgmController: (UHNCGMController*)controller notificationMeasurement: (BOOL)enabled;
{
    DLog(@"all notifications are set");
    [self loadStoredData];
}

- (void) cgmController: (UHNCGMController*)controller notificationRACP: (BOOL)enabled;
{
    [self.cgmController enableNotificationCGMCP: YES];
}

- (void) cgmController: (UHNCGMController*)controller notificationCGMCP: (BOOL)enabled;
{
    [self.cgmController enableNotificationMeasurement: YES];
}

- (void) cgmController: (UHNCGMController*)controller measurementDetails: (NSDictionary*)measurementDetails;
{
    NSNumber *glucoseValue = [measurementDetails glucoseValue];
    NSNumber *trendValue = [measurementDetails trendValue];
    
    if (!self.isHistoricalData) {
        // display the current value
        [self updateGlucoseValueDisplay: glucoseValue];
    
        // update the current trend arrow
        [self updateTrendArrow: trendValue];
    }
    
    // update the plot
    [self.plotView addDataPoint: glucoseValue];
    
    if ([measurementDetails hasExceededLevelHypo]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"CGM Alert"
                                                        message: @"Hypo level exceeded"
                                                       delegate: nil
                                              cancelButtonTitle: @"OK"
                                              otherButtonTitles: nil];
        [alert  show];
    }
}

- (void) cgmController: (UHNCGMController*)controller didReadSessionStartTime:(NSDate *)sessionStartTime
{
    self.startTimeLabel.text = [self.dateFormatter stringFromDate: sessionStartTime];
    [self.cgmController readSessionRunTime];
}

- (void) cgmController: (UHNCGMController*)controller didReadSessionRunTime:(NSDate *)sessionRunTime
{
    self.runTimeLabel.text = [self.dateFormatter stringFromDate: sessionRunTime];
}

- (void)cgmControllerDidStopSession:(UHNCGMController*)controller;
{
    if (self.shouldStartNewSession) {
        self.shouldStartNewSession = NO;
        [self.cgmController startSession];
    }
}

- (void)cgmControllerDidStartSession:(UHNCGMController*)controller;
{
    [self.cgmController sendCurrentTime];
}

- (void)cgmControllerDidGetStoredRecords:(UHNCGMController*)controller;
{
    [self finishedLoadingStoredData];
}

- (void) cgmController: (UHNCGMController*)controller RACPOperation: (RACPOpCode)opCode failed: (RACPResponseCode)responseCode;
{
    if (opCode == RACPOpCodeStoredRecordsReport) {
        [self finishedLoadingStoredData];
    }
}

@end
