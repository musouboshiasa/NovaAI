import { textToSpeech, speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

/** 朗读状态回调 */
export interface TtsHandlers {
  onStart: (requestId: string) => void;
  onDone: (requestId: string) => void;
  onError: (message: string) => void;
}

/** 识别状态回调 */
export interface AsrHandlers {
  /** 实时中间结果 */
  onPartial: (text: string) => void;
  /** 最终结果 */
  onFinal: (text: string) => void;
  /** 音量 0~1，用于波形动画 */
  onVolume: (level: number) => void;
  onError: (message: string) => void;
}

/**
 * 离线语音服务（华为 CoreSpeechKit）
 *
 * - TTS：textToSpeech，online=0 走端侧离线引擎，不耗流量、不依赖网络
 * - ASR：speechRecognizer + AudioCapturer 采集 16k/16bit/单声道 PCM 持续喂入
 *
 * 引擎都是重量级对象，按需创建、用完 shutdown，避免常驻内存。
 */
export class SpeechService {
  /**
   * CoreSpeechKit 的 online 字段语义与直觉相反：
   *   0 = 在线引擎，1 = 端侧离线引擎
   * 默认优先离线（不耗流量、离线可用），失败再降级到在线。
   */
  private static MODE_ONLINE: number = 0;
  private static MODE_OFFLINE: number = 1;
  /** 当前实际使用的引擎：offline / online / none */
  private static ttsMode: string = 'none';
  private static asrMode: string = 'none';

  static currentTtsMode(): string {
    return SpeechService.ttsMode;
  }

  static currentAsrMode(): string {
    return SpeechService.asrMode;
  }

  /* ------------------------- TTS ------------------------- */
  private static tts: textToSpeech.TextToSpeechEngine | null = null;
  private static ttsBusy: boolean = false;
  private static ttsSeq: number = 0;

  /** 优先创建离线引擎，失败则降级到在线引擎 */
  private static async createTtsEngine(person: number): Promise<textToSpeech.TextToSpeechEngine> {
    try {
      const off: textToSpeech.CreateEngineParams = {
        language: 'zh-CN', person: person, online: SpeechService.MODE_OFFLINE
      };
      const e: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(off);
      SpeechService.ttsMode = 'offline';
      Logger.info('tts engine ready: offline');
      return e;
    } catch (e1) {
      const err1 = e1 as BusinessError;
      Logger.warn('tts offline engine failed code=' + err1.code + ' msg=' + err1.message + ', fallback to online');
    }
    const on: textToSpeech.CreateEngineParams = {
      language: 'zh-CN', person: person, online: SpeechService.MODE_ONLINE
    };
    const e2: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(on);
    SpeechService.ttsMode = 'online';
    Logger.info('tts engine ready: online');
    return e2;
  }

  static isSpeaking(): boolean {
    return SpeechService.ttsBusy;
  }

  /** 朗读一段文本；会先打断正在播放的内容 */
  static async speak(text: string, speed: number, person: number, handlers: TtsHandlers): Promise<void> {
    const clean: string = SpeechService.sanitize(text);
    if (clean.length === 0) {
      handlers.onError('没有可朗读的内容');
      return;
    }
    try {
      if (SpeechService.tts === null) {
        SpeechService.tts = await SpeechService.createTtsEngine(person);
      }
      const engine: textToSpeech.TextToSpeechEngine = SpeechService.tts;
      SpeechService.ttsSeq = SpeechService.ttsSeq + 1;
      const requestId: string = 'nova-tts-' + SpeechService.ttsSeq.toString();

      try {
        if (engine.isBusy()) {
          engine.stop();
        }
      } catch (e) {
        Logger.warn('tts stop previous failed');
      }

      engine.setListener({
        onStart: (id: string, response: textToSpeech.StartResponse) => {
          SpeechService.ttsBusy = true;
          handlers.onStart(id);
        },
        onComplete: (id: string, response: textToSpeech.CompleteResponse) => {
          SpeechService.ttsBusy = false;
          handlers.onDone(id);
        },
        onStop: (id: string, response: textToSpeech.StopResponse) => {
          SpeechService.ttsBusy = false;
          handlers.onDone(id);
        },
        onError: (id: string, errorCode: number, errorMessage: string) => {
          SpeechService.ttsBusy = false;
          Logger.warn('tts error ' + errorCode + ': ' + errorMessage);
          handlers.onError('朗读失败（' + errorCode + '）');
        }
      });

      const extra: Record<string, Object> = {
        'speed': speed,
        'volume': 1.0,
        'pitch': 1.0,
        'queueMode': 1
      };
      const speakParams: textToSpeech.SpeakParams = { requestId: requestId, extraParams: extra };
      Logger.info('tts speak: ' + clean.length + ' chars speed=' + speed + ' person=' + person);
      engine.speak(clean, speakParams);
    } catch (e) {
      const err = e as BusinessError;
      SpeechService.ttsMode = 'none';
      Logger.error('tts createEngine failed code=' + err.code + ' msg=' + err.message);
      handlers.onError('语音引擎不可用（' + err.code + '）');
    }
  }

  static stopSpeaking(): void {
    try {
      if (SpeechService.tts !== null && SpeechService.tts.isBusy()) {
        SpeechService.tts.stop();
      }
    } catch (e) {
      Logger.warn('tts stop failed');
    }
    SpeechService.ttsBusy = false;
  }

  static shutdownTts(): void {
    try {
      if (SpeechService.tts !== null) {
        SpeechService.tts.shutdown();
      }
    } catch (e) {
      Logger.warn('tts shutdown failed');
    }
    SpeechService.tts = null;
    SpeechService.ttsBusy = false;
  }

  /** 把 Markdown 清洗成适合朗读的纯文本 */
  static sanitize(md: string): string {
    let t: string = md;
    let guard: number = 0;
    while (t.indexOf('```') >= 0 && guard < 64) {
      const a: number = t.indexOf('```');
      const b: number = t.indexOf('```', a + 3);
      if (b < 0) {
        t = t.substring(0, a);
        break;
      }
      t = t.substring(0, a) + t.substring(b + 3);
      guard = guard + 1;
    }
    t = t.replace(/`([^`]*)`/g, '$1');
    t = t.replace(/!\[[^\]]*\]\([^)]*\)/g, '');
    t = t.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
    t = t.replace(/^\s{0,3}#{1,6}\s*/gm, '');
    t = t.replace(/^\s{0,3}>\s?/gm, '');
    t = t.replace(/^\s*[-*+]\s+/gm, '');
    t = t.replace(/^\s*\d+\.\s+/gm, '');
    t = t.replace(/\*\*([^*]*)\*\*/g, '$1');
    t = t.replace(/(^|[^*])\*([^*]+)\*/g, '$1$2');
    t = t.replace(/~~([^~]*)~~/g, '$1');
    t = t.replace(/^\s*[-|: ]{3,}\s*$/gm, '');
    t = t.replace(/\|/g, ' ');
    t = t.replace(/\n{2,}/g, '\n');
    return t.trim();
  }

  /* ------------------------- ASR ------------------------- */
  private static asr: speechRecognizer.SpeechRecognitionEngine | null = null;
  private static capturer: audio.AudioCapturer | null = null;
  private static sessionId: string = '';
  private static listening: boolean = false;
  private static seq: number = 0;

  static isListening(): boolean {
    return SpeechService.listening;
  }

  /** 申请麦克风权限；已授权返回 true */
  static async ensureMicPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const mgr: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      // 用回调式重载，避免显式引用 PermissionRequestResult 类型名
      const granted: boolean = await new Promise<boolean>((resolve: (v: boolean) => void) => {
        mgr.requestPermissionsFromUser(context, perms,
          (err: BusinessError, data: PermissionRequestResult) => {
            if (err) {
              resolve(false);
              return;
            }
            resolve(data.authResults.length > 0 && data.authResults[0] === 0);
          });
      });
      Logger.info('mic permission granted=' + granted);
      return granted;
    } catch (e) {
      const err = e as BusinessError;
      Logger.error('mic permission request failed: ' + err.message);
      return false;
    }
  }

  /** 优先创建离线识别引擎，失败则降级到在线引擎 */
  private static async createAsrEngine(language: string): Promise<speechRecognizer.SpeechRecognitionEngine> {
    try {
      const off: speechRecognizer.CreateEngineParams = {
        language: language, online: SpeechService.MODE_OFFLINE
      };
      const e: speechRecognizer.SpeechRecognitionEngine = await speechRecognizer.createEngine(off);
      SpeechService.asrMode = 'offline';
      Logger.info('asr engine ready: offline lang=' + language);
      return e;
    } catch (e1) {
      const err1 = e1 as BusinessError;
      Logger.warn('asr offline engine failed code=' + err1.code + ' msg=' + err1.message + ', fallback to online');
    }
    const on: speechRecognizer.CreateEngineParams = {
      language: language, online: SpeechService.MODE_ONLINE
    };
    const e2: speechRecognizer.SpeechRecognitionEngine = await speechRecognizer.createEngine(on);
    SpeechService.asrMode = 'online';
    Logger.info('asr engine ready: online lang=' + language);
    return e2;
  }

  /** 开始识别：先接好 PCM 采集链路，再启动识别引擎 */
  static async startListening(language: string, handlers: AsrHandlers): Promise<void> {
    if (SpeechService.listening) {
      return;
    }
    try {
      if (SpeechService.asr === null) {
        SpeechService.asr = await SpeechService.createAsrEngine(language);
      }
      const engine: speechRecognizer.SpeechRecognitionEngine = SpeechService.asr;
      SpeechService.seq = SpeechService.seq + 1;
      const sid: string = 'nova-asr-' + SpeechService.seq.toString();
      SpeechService.sessionId = sid;

      engine.setListener({
        onStart: (sessionId: string, eventMessage: string) => {
          Logger.info('asr started session=' + sessionId);
        },
        onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
          if (eventCode === 3) {
            handlers.onVolume(SpeechService.parseVolume(eventMessage));
          }
        },
        onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
          if (result.isFinal) {
            handlers.onFinal(result.result);
          } else {
            handlers.onPartial(result.result);
          }
        },
        onComplete: (sessionId: string, eventMessage: string) => {
          Logger.info('asr complete: ' + eventMessage);
        },
        onError: (sessionId: string, errorCode: number, errorMessage: string) => {
          Logger.error('asr error ' + errorCode + ': ' + errorMessage);
          SpeechService.listening = false;
          SpeechService.releaseCapturer();
          handlers.onError(SpeechService.explainAsrError(errorCode, errorMessage));
        }
      });

      const audioInfo: speechRecognizer.AudioInfo = {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      };
      const startParams: speechRecognizer.StartParams = { sessionId: sid, audioInfo: audioInfo };
      engine.startListening(startParams);

      await SpeechService.startCapturer(engine, sid);
      SpeechService.listening = true;
      Logger.info('asr listening session=' + sid + ' lang=' + language);
    } catch (e) {
      const err = e as BusinessError;
      Logger.error('asr start failed: ' + err.message);
      SpeechService.listening = false;
      SpeechService.releaseCapturer();
      handlers.onError('语音识别启动失败：' + err.message);
    }
  }

  private static async startCapturer(
    engine: speechRecognizer.SpeechRecognitionEngine, sid: string): Promise<void> {
    const options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    };
    const cap: audio.AudioCapturer = await audio.createAudioCapturer(options);
    cap.on('readData', (buffer: ArrayBuffer) => {
      try {
        engine.writeAudio(sid, new Uint8Array(buffer));
      } catch (e) {
        // 会话已结束时 writeAudio 会抛错，忽略
      }
    });
    cap.on('audioInterrupt', (ev: audio.InterruptEvent) => {
      Logger.warn('capturer interrupted, hintType=' + ev.hintType);
    });
    SpeechService.capturer = cap;
    await cap.start();
    Logger.info('capturer started 16k mono s16le');
  }

  /** 结束说话，等待最终结果 */
  static finishListening(): void {
    try {
      if (SpeechService.asr !== null && SpeechService.sessionId.length > 0) {
        SpeechService.asr.finish(SpeechService.sessionId);
        Logger.info('asr finish requested');
      }
    } catch (e) {
      Logger.warn('asr finish failed');
    }
    SpeechService.releaseCapturer();
    SpeechService.listening = false;
  }

  /** 放弃本次识别 */
  static cancelListening(): void {
    try {
      if (SpeechService.asr !== null && SpeechService.sessionId.length > 0) {
        SpeechService.asr.cancel(SpeechService.sessionId);
      }
    } catch (e) {
      Logger.warn('asr cancel failed');
    }
    SpeechService.releaseCapturer();
    SpeechService.listening = false;
  }

  private static releaseCapturer(): void {
    const cap: audio.AudioCapturer | null = SpeechService.capturer;
    if (cap === null) {
      return;
    }
    SpeechService.capturer = null;
    try {
      cap.stop().then(() => {
        cap.release().then(() => {
          Logger.info('capturer released');
        }).catch(() => {});
      }).catch(() => {});
    } catch (e) {
      Logger.warn('capturer release failed');
    }
  }

  static shutdownAsr(): void {
    SpeechService.cancelListening();
    try {
      if (SpeechService.asr !== null) {
        SpeechService.asr.shutdown();
      }
    } catch (e) {
      Logger.warn('asr shutdown failed');
    }
    SpeechService.asr = null;
  }

  /** eventMessage 形如 "volume:8"，归一到 0~1 */
  private static parseVolume(eventMessage: string): number {
    try {
      const idx: number = eventMessage.indexOf(':');
      if (idx < 0) {
        return 0;
      }
      const raw: number = Number.parseFloat(eventMessage.substring(idx + 1).trim());
      if (Number.isNaN(raw)) {
        return 0;
      }
      return Math.max(0, Math.min(1, raw / 10));
    } catch (e) {
      return 0;
    }
  }

  private static explainAsrError(code: number, message: string): string {
    if (code === 1002) {
      return '麦克风权限被拒绝';
    }
    if (code === 1003) {
      return '没有检测到声音';
    }
    if (code === 1004) {
      return '网络异常，请检查连接';
    }
    if (code === 1005) {
      return '识别引擎忙，请稍候再试';
    }
    return '识别失败（' + code + '）：' + message;
  }
}
