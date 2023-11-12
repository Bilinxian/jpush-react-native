#import "RCTJPushModule.h"
#import <CoreLocation/CoreLocation.h>

//常量
#define CODE           @"code"
#define BADGE          @"badge"
#define SEQUENCE       @"sequence"
#define REGISTER_ID    @"registerID"
#define MOBILE_NUMBER  @"mobileNumber"
#define CONNECT_ENABLE @"connectEnable"

//通知消息
#define MESSAGE_ID @"messageID"
#define TITLE      @"title"
#define CONTENT    @"content"
#define EXTRAS     @"extras"
#define BADGE      @"badge"
#define RING       @"ring"
#define BROADCASTTIME @"broadcastTime"

//本地角标
#define APP_BADGE @"appBadge"

//tagAlias
#define TAG         @"tag"
#define TAGS        @"tags"
#define TAG_ENABLE  @"tagEnable"

#define ALIAS       @"alias"

//properties
#define PROS        @"pros"

//地理围栏
#define GEO_FENCE_ID         @"geoFenceID"
#define GEO_FENCE_MAX_NUMBER @"geoFenceMaxNumber"

//通知事件类型
#define NOTIFICATION_EVENT_TYPE   @"notificationEventType"
#define NOTIFICATION_ARRIVED      @"notificationArrived"
#define NOTIFICATION_OPENED       @"notificationOpened"
#define NOTIFICATION_DISMISSED    @"notificationDismissed"
//通知消息事件
#define NOTIFICATION_EVENT        @"NotificationEvent"
//自定义消息
#define CUSTOM_MESSAGE_EVENT      @"CustomMessageEvent"
//应用内消息事件类型
#define INAPP_MESSAGE_EVENT_TYPE   @"inappEventType"
#define INAPP_MESSAGE_SHOW         @"inappShow"
#define INAPP_MESSAGE_CLICK        @"inappClick"
//应用内消息
#define INAPP_MESSAGE_EVENT       @"InappMessageEvent"
//本地通知
#define LOCAL_NOTIFICATION_EVENT  @"LocalNotificationEvent"
//连接状态
#define CONNECT_EVENT             @"ConnectEvent"
//tag alias
#define TAG_ALIAS_EVENT           @"TagAliasEvent"
//properties
#define PROPERTIES_EVENT           @"PropertiesEvent"
//phoneNumber
#define MOBILE_NUMBER_EVENT       @"MobileNumberEvent"


@interface RCTJPushModule ()

@end

@implementation RCTJPushModule

RCT_EXPORT_MODULE(JPushModule);

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

- (id)init
{
    self = [super init];
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];

    [defaultCenter removeObserver:self];

    [defaultCenter addObserver:self
                      selector:@selector(sendApnsNotificationEvent:)
                          name:J_APNS_NOTIFICATION_ARRIVED_EVENT
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendApnsNotificationEvent:)
                          name:J_APNS_NOTIFICATION_OPENED_EVENT
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendLocalNotificationEvent:)
                          name:J_LOCAL_NOTIFICATION_ARRIVED_EVENT
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendLocalNotificationEvent:)
                          name:J_LOCAL_NOTIFICATION_OPENED_EVENT
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendCustomNotificationEvent:)
                          name:J_CUSTOM_NOTIFICATION_EVENT
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendConnectEvent:)
                          name:kJPFNetworkDidCloseNotification
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendConnectEvent:)
                          name:kJPFNetworkFailedRegisterNotification
                        object:nil];

    [defaultCenter addObserver:self
                      selector:@selector(sendConnectEvent:)
                          name:kJPFNetworkDidLoginNotification
                        object:nil];

    return self;
}


RCT_EXPORT_METHOD(setDebugMode: (BOOL *)enable)
{
    if(enable){
        [JPUSHService setDebugMode];
    }
}

RCT_EXPORT_METHOD(setupWithConfig:(NSDictionary *)params)
{
//初始化语音合成器
  self._avSpeaker = [AVSpeechSynthesizer new];
  self._avSpeaker.delegate = self;

  self._notificationQueue = [NSMutableArray new];
    if (params[@"appKey"] && params[@"channel"] && params[@"production"]) {
           // JPush初始化配置
           NSMutableDictionary *launchOptions = [NSMutableDictionary dictionaryWithDictionary:self.bridge.launchOptions];
           [JPUSHService setupWithOption:launchOptions appKey:params[@"appKey"]
                                 channel:params[@"channel"] apsForProduction:[params[@"production"] boolValue]];

           dispatch_async(dispatch_get_main_queue(), ^{
               // APNS
               JPUSHRegisterEntity * entity = [[JPUSHRegisterEntity alloc] init];
               if (@available(iOS 12.0, *)) {
                 entity.types = JPAuthorizationOptionAlert|JPAuthorizationOptionBadge|JPAuthorizationOptionSound|JPAuthorizationOptionProvidesAppNotificationSettings;
               }
               [JPUSHService registerForRemoteNotificationConfig:entity delegate:self];
               [launchOptions objectForKey: UIApplicationLaunchOptionsRemoteNotificationKey];
               // 自定义消息
               NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
               [defaultCenter addObserver:self.bridge.delegate selector:@selector(networkDidReceiveMessage:) name:kJPFNetworkDidReceiveMessageNotification object:nil];
               // 地理围栏
               [JPUSHService registerLbsGeofenceDelegate:self.bridge.delegate withLaunchOptions:launchOptions];
               // 应用内消息
               [JPUSHService setInAppMessageDelegate:self];
           });

           NSMutableArray *notificationList = [RCTJPushEventQueue sharedInstance]._notificationQueue;
           if(notificationList.count) {
               [self sendApnsNotificationEventByDictionary:notificationList[0]];
           }
           NSMutableArray *localNotificationList = [RCTJPushEventQueue sharedInstance]._localNotificationQueue;
           if(localNotificationList.count) {
               [self sendLocalNotificationEventByDictionary:localNotificationList[0]];
           }
       }
}


//获取当前时间戳
- (NSString*)currentTimeStr{
  NSDate* date = [NSDate dateWithTimeIntervalSinceNow:0];//获取当前时间0秒后的时间
//  NSTimeInterval time=[date timeIntervalSince1970]*1000;// *1000 是精确到毫秒，不乘就是精确到秒
  NSString *timeString = [NSString stringWithFormat:@"%ld", (long)[date timeIntervalSince1970]*1000];
//  NSInteger currentTime=[timeString integerValue];
  return timeString;
}

//已经说完
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance{

  [SpeechSynthesizerModule emitEventWithName: @{@"success":@"1"}];
    //如果朗读要循环朗读，可以在这里再次调用朗读方法
    //[_avSpeaker speakUtterance:utterance];
  NSUInteger length = [self._notificationQueue count];

  if(length > 0){
    NSDictionary *pushMessageInfo = [self._notificationQueue objectAtIndex:0];
    [self._notificationQueue removeObjectAtIndex:0];
    [self addPushMessage:pushMessageInfo];
  }else{

//    [self endBack];
  }

}

- (void)boFangTextWithString:(NSString *)stra
{
    //初始化要说出的内容
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:stra];
    //设置语速,语速介于AVSpeechUtteranceMaximumSpeechRate和AVSpeechUtteranceMinimumSpeechRate之间
    //AVSpeechUtteranceMaximumSpeechRate
    //AVSpeechUtteranceMinimumSpeechRate
    //AVSpeechUtteranceDefaultSpeechRate
    utterance.rate = 0.5;

    //设置音高,[0.5 - 2] 默认 = 1
    //AVSpeechUtteranceMaximumSpeechRate
    //AVSpeechUtteranceMinimumSpeechRate
    //AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier =1 ;

    //设置音量,[0-1] 默认 = 1
    utterance.volume = 1;

    //读一段前的停顿时间
    utterance.preUtteranceDelay = 0;
    //读完一段后的停顿时间
    utterance.postUtteranceDelay = 0;

    //设置声音,是AVSpeechSynthesisVoice对象
    //AVSpeechSynthesisVoice定义了一系列的声音, 主要是不同的语言和地区.
    //voiceWithLanguage: 根据制定的语言, 获得一个声音.
    //speechVoices: 获得当前设备支持的声音
    //currentLanguageCode: 获得当前声音的语言字符串, 比如”ZH-cn”
    //language: 获得当前的语言
    //通过特定的语言获得声音
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    //通过voicce标示获得声音
    //AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithIdentifier:AVSpeechSynthesisVoiceIdentifierAlex];
    utterance.voice = voice;
    //开始朗读
  [__avSpeaker speakUtterance:utterance];

}

- (void)addPushMessage:(NSDictionary *)pushMessageInfo{
  BOOL status=[VoiceSwitch getStatus];
  if(!status)
    return;
  NSString *speakWord = pushMessageInfo[@"speak_word"];
  NSString *receiveTimeStr = pushMessageInfo[@"receive_time"];
  NSString *currentTimeStr = [self currentTimeStr];

  NSInteger receiveTime=[receiveTimeStr integerValue];
  NSInteger currentTime=[currentTimeStr integerValue];

  if(currentTime - receiveTime > 60*1000)
    return;
//  if ([self.iFlySpeechSynthesizer isSpeaking]) {
  if ([self._avSpeaker isSpeaking]) {
    [self._notificationQueue addObject:pushMessageInfo];
    return;
  }
  [self boFangTextWithString:speakWord];
}

-(void)activeAudio
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error;

  [session setCategory:AVAudioSessionCategoryPlayback
           withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers | AVAudioSessionCategoryOptionAllowAirPlay | AVAudioSessionCategoryOptionAllowBluetooth
                 error:&error];
  [session setActive:YES error:&error];
}

- (void)jpushNotificationAuthorization:(JPAuthorizationStatus)status withInfo:(nullable NSDictionary *)info {

}

//iOS 7 APNS
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

  UIApplicationState state = [[UIApplication sharedApplication] applicationState];
  if(state == UIApplicationStateBackground){
    NSString *speakWord = userInfo[@"speak_word"];
    if (speakWord != nil) {
      [self activeAudio];
      NSString *currentTimeStr = [self currentTimeStr];
      NSDictionary *dict = @{@"speak_word":speakWord, @"receive_time":currentTimeStr};
      [self addPushMessage:dict];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:J_APNS_NOTIFICATION_ARRIVED_EVENT object:userInfo];
    [JPUSHService handleRemoteNotification:userInfo];
  }

  completionHandler(UIBackgroundFetchResultNewData);
}

//iOS 10 前台收到消息
- (void)jpushNotificationCenter:(UNUserNotificationCenter *)center  willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(NSInteger))completionHandler {

  NSDictionary * userInfo = notification.request.content.userInfo;

  if([notification.request.trigger isKindOfClass:[UNPushNotificationTrigger class]]) {
    // Apns
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if(state != UIApplicationStateBackground){

      NSString *speakWord = userInfo[@"speak_word"];
      if (speakWord != nil) {
       NSString *currentTimeStr=[self currentTimeStr];
       NSDictionary *dict = @{@"speak_word":speakWord, @"receive_time":currentTimeStr};
       [self addPushMessage:dict];
      }
      [[NSNotificationCenter defaultCenter] postNotificationName:J_APNS_NOTIFICATION_ARRIVED_EVENT object:userInfo];
      [JPUSHService handleRemoteNotification:userInfo];
    }
  }
  else {
    // 本地通知 todo

    [[NSNotificationCenter defaultCenter] postNotificationName:J_LOCAL_NOTIFICATION_ARRIVED_EVENT object:userInfo];
  }
  //需要执行这个方法，选择是否提醒用户，有 Badge、Sound、Alert 三种类型可以选择设置
  completionHandler(UNNotificationPresentationOptionAlert);
}

//iOS 10 消息事件回调
- (void)jpushNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *userInfo = response.notification.request.content.userInfo;

    if ([response.notification.request.trigger isKindOfClass:[UNPushNotificationTrigger class]]) {
      // Apns
//      NSLog(@"iOS 10 APNS 消息事件回调");
      [JPUSHService handleRemoteNotification:userInfo];
      NSString *speakWord = userInfo[@"speak_word"];
      if (speakWord != nil) {
       NSString *currentTimeStr=[self currentTimeStr];
       NSDictionary *dict = @{@"speak_word":speakWord, @"receive_time":currentTimeStr};
       [self addPushMessage:dict];
      }
      // 保障应用被杀死状态下，用户点击推送消息，打开app后可以收到点击通知事件
      [[RCTJPushEventQueue sharedInstance]._notificationQueue insertObject:userInfo atIndex:0];
      [[NSNotificationCenter defaultCenter] postNotificationName:J_APNS_NOTIFICATION_OPENED_EVENT object:userInfo];

    } else {
//        NSLog(@"iOS 10 本地通知 消息事件回调");
        // 保障应用被杀死状态下，用户点击推送消息，打开app后可以收到点击通知事件
        [[RCTJPushEventQueue sharedInstance]._localNotificationQueue insertObject:userInfo atIndex:0];
        [[NSNotificationCenter defaultCenter] postNotificationName:J_LOCAL_NOTIFICATION_OPENED_EVENT object:userInfo];

    }
    // 系统要求执行这个方法
    completionHandler();
}

//自定义消息
- (void)networkDidReceiveMessage:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:J_CUSTOM_NOTIFICATION_EVENT object:userInfo];
}


RCT_EXPORT_METHOD(loadJS)
{
    NSMutableArray *notificationList = [RCTJPushEventQueue sharedInstance]._notificationQueue;
    if(notificationList.count) {
        [self sendApnsNotificationEventByDictionary:notificationList[0]];
    }
    NSMutableArray *localNotificationList = [RCTJPushEventQueue sharedInstance]._localNotificationQueue;
    if(localNotificationList.count) {
        [self sendLocalNotificationEventByDictionary:localNotificationList[0]];
    }
}

RCT_EXPORT_METHOD(getRegisterId:(RCTResponseSenderBlock) callback)
{
    [JPUSHService registrationIDCompletionHandler:^(int resCode, NSString *registrationID) {
        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        [response setValue:registrationID?registrationID:@"" forKey:REGISTER_ID];
        callback(@[response]);
    }];
}

RCT_EXPORT_METHOD(isNotificationEnabled:(RCTResponseSenderBlock) callback) {
    [JPUSHService requestNotificationAuthorization:^(JPAuthorizationStatus status) {
        if (status <= JPAuthorizationStatusDenied) {
            callback(@[@(NO)]);
        }else {
            callback(@[@(YES)]);
        }
    }];
}

//tag
RCT_EXPORT_METHOD(addTags:(NSDictionary *)params)
{
    if([params[@"tags"] isKindOfClass:[NSArray class]]){
        NSArray *tags = [params[TAGS] copy];
        if (tags != NULL) {
            NSSet *tagSet = [NSSet setWithArray:tags];
            NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
            [JPUSHService addTags:tagSet completion:^(NSInteger iResCode, NSSet *iTags, NSInteger seq) {
                NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),TAGS:[iTags allObjects]};
                [self sendTagAliasEvent:data];
            } seq:sequence];
        }
    }
}

RCT_EXPORT_METHOD(setTags:(NSDictionary *)params)
{
    if([params[@"tags"] isKindOfClass:[NSArray class]]){
        NSArray *tags = [params[TAGS] copy];
        if (tags != NULL) {
            NSSet *tagSet = [NSSet setWithArray:tags];
            NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
            [JPUSHService setTags:tagSet completion:^(NSInteger iResCode, NSSet *iTags, NSInteger seq) {
                NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),TAGS:[iTags allObjects]};
                [self sendTagAliasEvent:data];
            } seq:sequence];
        }
    }
}

RCT_EXPORT_METHOD(deleteTags:(NSDictionary *)params)
{
    if([params[@"tags"] isKindOfClass:[NSArray class]]){
        NSArray *tags = [params[TAGS] copy];
        if (tags != NULL) {
            NSSet *tagSet = [NSSet setWithArray:tags];
            NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
            [JPUSHService deleteTags:tagSet completion:^(NSInteger iResCode, NSSet *iTags, NSInteger seq) {
                NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),TAGS:[iTags allObjects]};
                [self sendTagAliasEvent:data];
            } seq:sequence];
        }
    }
}

RCT_EXPORT_METHOD(cleanTags:(NSDictionary *)params)
{
    NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
    [JPUSHService cleanTags:^(NSInteger iResCode, NSSet *iTags, NSInteger seq) {
        NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq)};
        [self sendTagAliasEvent:data];
    } seq:sequence];
}

RCT_EXPORT_METHOD(getAllTags:(NSDictionary *)params)
{
    NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
    [JPUSHService getAllTags:^(NSInteger iResCode, NSSet *iTags, NSInteger seq) {
        NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),TAGS:[iTags allObjects]};
        [self sendTagAliasEvent:data];
    } seq:sequence];
}

RCT_EXPORT_METHOD(validTag:(NSDictionary *)params)
{
    if(params[TAG]){
        NSString *tag = params[TAG];
        NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
        [JPUSHService validTag:(tag)
                    completion:^(NSInteger iResCode, NSSet *iTags, NSInteger seq, BOOL isBind) {
            NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),TAG_ENABLE:@(isBind),TAG:tag};
            [self sendTagAliasEvent:data];
        } seq:sequence];
    }
}

//alias
RCT_EXPORT_METHOD(setAlias:(NSDictionary *)params) {
    if(params[ALIAS]){
        NSString *alias = params[ALIAS];
        NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
        [JPUSHService setAlias:alias
                    completion:^(NSInteger iResCode, NSString *iAlias, NSInteger seq) {
            NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),ALIAS:iAlias};
            [self sendTagAliasEvent:data];
        }
                           seq:sequence];
    }
}

RCT_EXPORT_METHOD(deleteAlias:(NSDictionary *)params) {
    NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
    [JPUSHService deleteAlias:^(NSInteger iResCode, NSString *iAlias, NSInteger seq) {
        NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq)};
        [self sendTagAliasEvent:data];
    } seq:sequence];
}

RCT_EXPORT_METHOD(getAlias:(NSDictionary *)params) {
    NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
    [JPUSHService getAlias:^(NSInteger iResCode, NSString *iAlias, NSInteger seq) {
        NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),ALIAS:iAlias};
        [self sendTagAliasEvent:data];
    } seq:sequence];
}

//properties
RCT_EXPORT_METHOD(setProperties:(NSDictionary *)params) {
     if(params[PROS]){
         NSDictionary *properties = params[PROS];
        NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
         [JPUSHService setProperties:properties completion:^(NSInteger iResCode, NSDictionary *properties, NSInteger seq) {
             NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),PROS:properties};
             [self sendPropertiesEvent:data];
         } seq:sequence];
     }
}

RCT_EXPORT_METHOD(deleteProperties:(NSDictionary *)params) {
    if(params[PROS]){
        NSDictionary *properties = params[PROS];
        NSSet *set = [NSSet setWithArray:properties.allKeys];
        NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
        [JPUSHService deleteProperties:set completion:^(NSInteger iResCode, NSDictionary *properties, NSInteger seq) {
            NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq), PROS:properties};
            [self sendTagAliasEvent:data];
        } seq:sequence];
    }
}

RCT_EXPORT_METHOD(cleanProperties:(NSDictionary *)params) {
    NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
    [JPUSHService cleanProperties:^(NSInteger iResCode, NSDictionary *properties, NSInteger seq) {
        NSDictionary *data = @{CODE:@(iResCode),SEQUENCE:@(seq),PROS:properties};
        [self sendTagAliasEvent:data];
    } seq:sequence];
}

// 应用内消息
RCT_EXPORT_METHOD(pageEnterTo:(NSString *)pageName)
{
    [JPUSHService pageEnterTo:pageName];
}

RCT_EXPORT_METHOD(pageLeave:(NSString *)pageName)
{
    [JPUSHService pageLeave:pageName];
}

//应用内消息 代理
- (void)jPushInAppMessageDidShow:(JPushInAppMessage *)inAppMessage {
    NSDictionary *responseData = [self convertInappMsg:inAppMessage isShow:YES];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[INAPP_MESSAGE_EVENT,responseData ]
                    completion:NULL];

}

- (void)jPushInAppMessageDidClick:(JPushInAppMessage *)inAppMessage {
    NSDictionary *responseData = [self convertInappMsg:inAppMessage isShow:NO];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[INAPP_MESSAGE_EVENT,responseData ]
                    completion:NULL];
}

//badge 角标
RCT_EXPORT_METHOD(setBadge:(NSDictionary *)params)
{
    if(params[BADGE]){
        NSNumber *number = params[BADGE];
        if(number < 0) return;
        [JPUSHService setBadge:[number integerValue]];
    }
    if (params[APP_BADGE]) {
        NSNumber *number = params[APP_BADGE];
        if(number < 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].applicationIconBadgeNumber = [number integerValue];
        });
    }
}

//Properties
- (void)sendPropertiesEvent:(NSDictionary *)data
{
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[PROPERTIES_EVENT, data]
                    completion:NULL];
}

//设置手机号码
RCT_EXPORT_METHOD(setMobileNumber:(NSDictionary *)params)
{
    if(params[MOBILE_NUMBER]){
        NSString *number = params[MOBILE_NUMBER];
        NSInteger sequence = params[SEQUENCE]?[params[SEQUENCE] integerValue]:-1;
        [JPUSHService setMobileNumber:number completion:^(NSError *error) {
            NSDictionary *data = @{CODE:@(error.code),SEQUENCE:@(sequence)};
            [self sendMobileNumberEvent:data];
        }];
    }
}

//崩溃日志统计
RCT_EXPORT_METHOD(crashLogON:(NSDictionary *)params)
{
    [JPUSHService crashLogON];
}

//本地通知
RCT_EXPORT_METHOD(addNotification:(NSDictionary *)params)
{
    NSString *messageID = params[MESSAGE_ID]?params[MESSAGE_ID]:@"";
    JPushNotificationContent *content = [[JPushNotificationContent alloc] init];
    NSString *notificationTitle = params[TITLE]?params[TITLE]:@"";
    NSString *notificationContent = params[CONTENT]?params[CONTENT]:@"";
    content.title = notificationTitle;
    content.body = notificationContent;
    if (@available(iOS 15.0, *)) {
        content.interruptionLevel = 1;
    } else {
        // Fallback on earlier versions
    }
    if(params[EXTRAS]){
        content.userInfo = @{MESSAGE_ID:messageID,TITLE:notificationTitle,CONTENT:notificationContent,EXTRAS:params[EXTRAS]};
    }else{
        content.userInfo = @{MESSAGE_ID:messageID,TITLE:notificationTitle,CONTENT:notificationContent};
    }
    NSString *broadcastTime = params[BROADCASTTIME];
    JPushNotificationTrigger *trigger = [[JPushNotificationTrigger alloc] init];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    NSDate *now = [NSDate date];
    if (broadcastTime && [broadcastTime isKindOfClass:[NSString class]]) {
        now = [NSDate dateWithTimeIntervalSince1970:[broadcastTime integerValue]/1000];
    }
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSUInteger unitFlags = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    NSDateComponents *dateComponent = [calendar components:unitFlags fromDate:now];
    components = dateComponent;
    components.second = [dateComponent second]+1;
    if (@available(iOS 10.0, *)) {
        trigger.dateComponents = components;
    } else {
        return;
    }
    JPushNotificationRequest *request = [[JPushNotificationRequest alloc] init];
    request.requestIdentifier = messageID;
    request.content = content;
    request.trigger = trigger;
    [JPUSHService addNotification:request];
}

RCT_EXPORT_METHOD(removeNotification:(NSDictionary *)params)
{
    NSString *requestIdentifier = params[MESSAGE_ID];
    if ([requestIdentifier isKindOfClass:[NSString class]]) {
        JPushNotificationIdentifier *identifier = [[JPushNotificationIdentifier alloc] init];
        identifier.identifiers = @[requestIdentifier];
        if (@available(iOS 10.0, *)) {
            identifier.delivered = YES;
        }
        [JPUSHService removeNotification:identifier];
    }
}

RCT_EXPORT_METHOD(clearLocalNotifications)
{
    [JPUSHService removeNotification:nil];
}

//地理围栏
RCT_EXPORT_METHOD(removeGeofenceWithIdentifier:(NSDictionary *)params)
{
    if(params[GEO_FENCE_ID]){
        [JPUSHService removeGeofenceWithIdentifier:params[GEO_FENCE_ID]];
    }
}

RCT_EXPORT_METHOD(setGeofeneceMaxCount:(NSDictionary *)params)
{
    if(params[GEO_FENCE_MAX_NUMBER]){
        [JPUSHService setGeofeneceMaxCount:[params[GEO_FENCE_MAX_NUMBER] integerValue]];
    }
}

//事件处理
- (NSArray<NSString *> *)supportedEvents
{
    return @[CONNECT_EVENT,NOTIFICATION_EVENT,CUSTOM_MESSAGE_EVENT,LOCAL_NOTIFICATION_EVENT,TAG_ALIAS_EVENT,MOBILE_NUMBER_EVENT,INAPP_MESSAGE_EVENT];
}

//长连接登录
- (void)sendConnectEvent:(NSNotification *)data {
    NSDictionary *responseData = [self convertConnect:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[CONNECT_EVENT,responseData]
                    completion:NULL];
}

//APNS通知消息
- (void)sendApnsNotificationEvent:(NSNotification *)data
{
    NSDictionary *responseData = [self convertApnsMessage:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[NOTIFICATION_EVENT, responseData]
                    completion:NULL];
    if([RCTJPushEventQueue sharedInstance]._notificationQueue.count){
        [[RCTJPushEventQueue sharedInstance]._notificationQueue removeAllObjects];
    }
}

- (void)sendApnsNotificationEventByDictionary:(NSDictionary *)data
{
    NSDictionary *responseData = [self convertApnsMessage:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[NOTIFICATION_EVENT, responseData]
                    completion:NULL];
    if([RCTJPushEventQueue sharedInstance]._notificationQueue.count){
        [[RCTJPushEventQueue sharedInstance]._notificationQueue removeAllObjects];
    }
}

- (void)sendLocalNotificationEventByDictionary:(NSDictionary *)data
{
    NSDictionary *responseData = [self convertLocalMessage:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[LOCAL_NOTIFICATION_EVENT, responseData]
                    completion:NULL];
    if([RCTJPushEventQueue sharedInstance]._localNotificationQueue.count){
        [[RCTJPushEventQueue sharedInstance]._localNotificationQueue removeAllObjects];
    }
}

//自定义消息
- (void)sendCustomNotificationEvent:(NSNotification *)data
{
    NSDictionary *responseData = [self convertCustomMessage:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[CUSTOM_MESSAGE_EVENT,responseData ]
                    completion:NULL];
}

//本地通知
- (void)sendLocalNotificationEvent:(NSNotification *)data
{
    NSDictionary *responseData = [self convertLocalMessage:data];
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[LOCAL_NOTIFICATION_EVENT, responseData]
                    completion:NULL];
}

//TagAlias
- (void)sendTagAliasEvent:(NSDictionary *)data
{
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[TAG_ALIAS_EVENT, data]
                    completion:NULL];
}

//电话号码
- (void)sendMobileNumberEvent:(NSDictionary *)data
{
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                        method:@"emit"
                          args:@[MOBILE_NUMBER_EVENT, data]
                    completion:NULL];
}

//工具类
-(NSDictionary *)convertConnect:(NSNotification *)data {
    NSNotificationName notificationName = data.name;
    BOOL isConnect = false;
    if([notificationName isEqualToString:kJPFNetworkDidLoginNotification]){
        isConnect = true;
    }
    NSDictionary *responseData = @{CONNECT_ENABLE:@(isConnect)};
    return responseData;
}

-(NSDictionary *)convertApnsMessage:(id)data
{
    NSNotificationName notificationName;
    NSDictionary *objectData;
    if([data isKindOfClass:[NSNotification class]]){
        notificationName = [(NSNotification *)data name];
        objectData = [(NSNotification *)data object];
    }else if([data isKindOfClass:[NSDictionary class]]){
        notificationName = J_APNS_NOTIFICATION_OPENED_EVENT;
        objectData = data;
    }
    NSString *notificationEventType = ([notificationName isEqualToString:J_APNS_NOTIFICATION_OPENED_EVENT])?NOTIFICATION_OPENED:NOTIFICATION_ARRIVED;
    id alertData =  objectData[@"aps"][@"alert"];
    NSString *badge = objectData[@"aps"][@"badge"]?[objectData[@"aps"][@"badge"] stringValue]:@"";
    NSString *sound = objectData[@"aps"][@"sound"]?objectData[@"aps"][@"sound"]:@"";

    NSString *title = @"";
    NSString *content = @"";
    if([alertData isKindOfClass:[NSString class]]){
        content = alertData;
    }else if([alertData isKindOfClass:[NSDictionary class]]){
        title = alertData[@"title"]?alertData[@"title"]:@"";
        content = alertData[@"body"]?alertData[@"body"]:@"";
    }
    NSDictionary *responseData;
    NSMutableDictionary * copyData = [[NSMutableDictionary alloc] initWithDictionary:objectData];
    if (copyData[@"_j_business"]) {
        [copyData removeObjectForKey:@"_j_business"];
    }
    if (copyData[@"_j_uid"]) {
        [copyData removeObjectForKey:@"_j_uid"];
    }
    [copyData removeObjectForKey:@"_j_msgid"];
    if (copyData[@"aps"]) {
        [copyData removeObjectForKey:@"aps"];
    }
    NSMutableDictionary * extrasData = [[NSMutableDictionary alloc] init];

    NSArray * allkeys = [copyData allKeys];
    for (int i = 0; i < allkeys.count; i++)
    {
        NSString *key = [allkeys objectAtIndex:i];
        NSString *value = [copyData objectForKey:key];
        [extrasData setObject:value forKey:key];
    };
    NSString *messageID = objectData[@"_j_msgid"]?[objectData[@"_j_msgid"] stringValue]:@"";
    if (extrasData.count > 0) {
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content,BADGE:badge,RING:sound,EXTRAS:extrasData,NOTIFICATION_EVENT_TYPE:notificationEventType};
    }
    else {
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content,BADGE:badge,RING:sound,NOTIFICATION_EVENT_TYPE:notificationEventType};
    }
    return responseData;
}

-(NSDictionary *)convertLocalMessage:(id)data
{
    NSNotificationName notificationName;
    NSDictionary *objectData;
    if([data isKindOfClass:[NSNotification class]]){
        notificationName = [(NSNotification *)data name];
        objectData = [(NSNotification *)data object];
    }else if([data isKindOfClass:[NSDictionary class]]){
        notificationName = J_APNS_NOTIFICATION_OPENED_EVENT;
        objectData = data;
    }
    NSString *notificationEventType = ([notificationName isEqualToString:J_LOCAL_NOTIFICATION_OPENED_EVENT])?NOTIFICATION_OPENED:NOTIFICATION_ARRIVED;
    NSString *messageID = objectData[MESSAGE_ID]?objectData[MESSAGE_ID]:@"";
    NSString *title = objectData[TITLE]?objectData[TITLE]:@"";
    NSString *content = objectData[CONTENT]?objectData[CONTENT]:@"";
    NSDictionary *responseData = [[NSDictionary alloc] init];
    if(objectData[EXTRAS]){
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content,EXTRAS:objectData[EXTRAS],NOTIFICATION_EVENT_TYPE:notificationEventType};
    }else{
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content,NOTIFICATION_EVENT_TYPE:notificationEventType};
    }
    return responseData;
}

-(NSDictionary *)convertCustomMessage:(NSNotification *)data
{
    NSDictionary *objectData = data.object;
    NSDictionary *responseData;
    NSString *messageID = objectData[@"_j_msgid"]?objectData[@"_j_msgid"]:@"";
    NSString *title = objectData[@"title"]?objectData[@"title"]:@"";
    NSString *content = objectData[@"content"]?objectData[@"content"]:@"";
    if(objectData[@"extras"]){
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content,EXTRAS:objectData[@"extras"]};
    }else{
        responseData = @{MESSAGE_ID:messageID,TITLE:title,CONTENT:content};
    }
    return responseData;
}

- (NSDictionary *)convertInappMsg:(JPushInAppMessage *)inAppMessage isShow:(BOOL)isShow{
    NSDictionary *result = @{
        @"mesageId": inAppMessage.mesageId ?: @"",    // 消息id
        @"title": inAppMessage.title ?:@"",       // 标题
        @"content": inAppMessage.content ?: @"",    // 内容
        @"target": inAppMessage.target ?: @[],      // 目标页面
        @"clickAction": inAppMessage.clickAction ?: @"", // 跳转地址
        @"extras": inAppMessage.extras ?: @{}, // 附加字段
        INAPP_MESSAGE_EVENT_TYPE: isShow ? INAPP_MESSAGE_SHOW : INAPP_MESSAGE_CLICK // 类型
    };
    return result;
}

@end
