//
//  ViewController.m
//  MOKORecorder
//
//  Created by Spring on 2017/4/27.
//  Copyright © 2017年 Spring. All rights reserved.
//

#import "ViewController.h"
#import "MOKORecorderTool.h"
#import "MOKORecordShowManager.h"
#import "MOKORecordButton.h"

#define kFakeTimerDuration       1
#define kMaxRecordDuration       60     //最长录音时长
#define kRemainCountingDuration  10     //剩余多少秒开始倒计时

@interface ViewController () <MOKOSecretTrainRecorderDelegate>
@property (nonatomic, strong) MOKORecordShowManager *voiceRecordCtrl;
@property (nonatomic, assign) MOKORecordState currentRecordState;
@property (nonatomic, strong) NSTimer *fakeTimer;
@property (nonatomic, assign) float duration;
@property (nonatomic, assign) BOOL canceled;

@property (nonatomic, strong) MOKORecordButton *recordButton;
@property (nonatomic, strong) MOKORecorderTool *recorder;

@property (nonatomic, strong) UIButton *playBtn;

@end

@implementation ViewController

- (void)playVoice
{
    NSLog(@"播放录音");
    [self.recorder playRecordingFile];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor yellowColor];
    
    self.playBtn = [[UIButton alloc] initWithFrame:CGRectMake((self.view.frame.size.width - 150) * 0.5, 20, 150, 80)];
    [self.playBtn addTarget:self action:@selector(playVoice) forControlEvents:UIControlEventTouchUpInside];
    [self.playBtn setTitle:@"点击我 播放语音" forState:UIControlStateNormal];
    self.playBtn.backgroundColor = [UIColor blueColor];
    [self.view addSubview:self.playBtn];
    
    self.recordButton = [MOKORecordButton buttonWithType:UIButtonTypeCustom];
    self.recorder = [MOKORecorderTool sharedRecorder];
    self.recorder.delegate = self;
    self.recordButton.frame = CGRectMake(20, self.view.frame.size.height - 50, self.view.frame.size.width - 40, 40);
    self.recordButton.backgroundColor = [UIColor whiteColor];
    self.recordButton.titleLabel.font = [UIFont systemFontOfSize:14];
    self.recordButton.layer.cornerRadius = 4;
    self.recordButton.clipsToBounds = YES;
    [self.recordButton setTitle:@"按住 说话" forState:UIControlStateNormal];
    [self.recordButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:self.recordButton];
    
    //录音相关
    [self toDoRecord];
}

#pragma mark ---- 录音全部状态的监听 以及视图的构建 切换
-(void)toDoRecord
{
    __weak typeof(self) weak_self = self;
    //手指按下
    self.recordButton.recordTouchDownAction = ^(MOKORecordButton *sender){
        //如果用户没有开启麦克风权限,不能让其录音
        if (![weak_self canRecord]) return;
        
        NSLog(@"开始录音");
        if (sender.highlighted) {
            sender.highlighted = YES;
            [sender setButtonStateWithRecording];
        }
        [weak_self.recorder startRecording];
        weak_self.currentRecordState = MOKORecordState_Recording;
        [weak_self dispatchVoiceState];
    };
    
    //手指抬起
    self.recordButton.recordTouchUpInsideAction = ^(MOKORecordButton *sender){
        NSLog(@"完成录音");
        [sender setButtonStateWithNormal];
        [weak_self.recorder stopRecording];
        weak_self.currentRecordState = MOKORecordState_Normal;
        [weak_self dispatchVoiceState];
    };
    
    //手指滑出按钮
    self.recordButton.recordTouchUpOutsideAction = ^(MOKORecordButton *sender){
        NSLog(@"取消录音");
        [sender setButtonStateWithNormal];
        weak_self.currentRecordState = MOKORecordState_Normal;
        [weak_self dispatchVoiceState];
    };
    
    //中间状态  从 TouchDragInside ---> TouchDragOutside
    self.recordButton.recordTouchDragExitAction = ^(MOKORecordButton *sender){
        weak_self.currentRecordState = MOKORecordState_ReleaseToCancel;
        [weak_self dispatchVoiceState];
    };
    
    //中间状态  从 TouchDragOutside ---> TouchDragInside
    self.recordButton.recordTouchDragEnterAction = ^(MOKORecordButton *sender){
        NSLog(@"继续录音");
        weak_self.currentRecordState = MOKORecordState_Recording;
        [weak_self dispatchVoiceState];
    };
}

- (void)startFakeTimer
{
    if (_fakeTimer) {
        [_fakeTimer invalidate];
        _fakeTimer = nil;
    }
    self.fakeTimer = [NSTimer scheduledTimerWithTimeInterval:kFakeTimerDuration target:self selector:@selector(onFakeTimerTimeOut) userInfo:nil repeats:YES];
    [_fakeTimer fire];
}

- (void)stopFakeTimer
{
    if (_fakeTimer) {
        [_fakeTimer invalidate];
        _fakeTimer = nil;
    }
}

- (void)onFakeTimerTimeOut
{
    self.duration += kFakeTimerDuration;
    NSLog(@"+++duration+++ %f",self.duration);
    float remainTime = kMaxRecordDuration - self.duration;
    if ((int)remainTime == 0) {
        self.currentRecordState = MOKORecordState_Normal;
        [self dispatchVoiceState];
    }
    else if ([self shouldShowCounting]) {
        self.currentRecordState = MOKORecordState_RecordCounting;
        [self dispatchVoiceState];
        [self.voiceRecordCtrl showRecordCounting:remainTime];
    }
    else
    {
        [self.recorder.recorder updateMeters];
        float   level = 0.0f;                // The linear 0.0 .. 1.0 value we need.
        
        float   minDecibels = -80.0f; // Or use -60dB, which I measured in a silent room.
        float decibels = [self.recorder.recorder peakPowerForChannel:0];
        if (decibels < minDecibels)
        {
            level = 0.0f;
        }
        else if (decibels >= 0.0f)
        {
            level = 1.0f;
        }
        else
        {
            float   root            = 2.0f;
            float   minAmp          = powf(10.0f, 0.05f * minDecibels);
            float   inverseAmpRange = 1.0f / (1.0f - minAmp);
            float   amp             = powf(10.0f, 0.05f * decibels);
            float   adjAmp          = (amp - minAmp) * inverseAmpRange;
            level = powf(adjAmp, 1.0f / root);
        }
        
        [self.voiceRecordCtrl updatePower:level];
    }
}
- (BOOL)shouldShowCounting
{
    if (self.duration >= (kMaxRecordDuration - kRemainCountingDuration) && self.duration < kMaxRecordDuration && self.currentRecordState != MOKORecordState_ReleaseToCancel) {
        return YES;
    }
    return NO;
}

- (void)resetState
{
    [self stopFakeTimer];
    self.duration = 0;
    self.canceled = YES;
}

- (void)dispatchVoiceState
{
    if (_currentRecordState == MOKORecordState_Recording) {
        self.canceled = NO;
        [self startFakeTimer];
    }
    else if (_currentRecordState == MOKORecordState_Normal)
    {
        [self resetState];
    }
    [self.voiceRecordCtrl updateUIWithRecordState:_currentRecordState];
}

- (MOKORecordShowManager *)voiceRecordCtrl
{
    if (_voiceRecordCtrl == nil) {
        _voiceRecordCtrl = [MOKORecordShowManager new];
    }
    return _voiceRecordCtrl;
}

//判断是否允许使用麦克风7.0新增的方法requestRecordPermission
-(BOOL)canRecord
{
    __block BOOL bCanRecord = YES;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    if ([audioSession respondsToSelector:@selector(requestRecordPermission:)]) {
        [audioSession performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
            if (granted) {
                bCanRecord = YES;
            }
            else {
                bCanRecord = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[UIAlertView alloc] initWithTitle:nil
                                                message:@"app需要访问您的麦克风。\n请启用麦克风-设置/隐私/麦克风"
                                               delegate:nil
                                      cancelButtonTitle:@"关闭"
                                      otherButtonTitles:nil] show];
                });
            }
        }];
    }
    return bCanRecord;
}

@end
