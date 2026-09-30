import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';

export class Logger {
  private static readonly DOMAIN: number = 0xA100;

  static debug(msg: string): void {
    hilog.debug(Logger.DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static info(msg: string): void {
    hilog.info(Logger.DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(Logger.DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(Logger.DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }
}
