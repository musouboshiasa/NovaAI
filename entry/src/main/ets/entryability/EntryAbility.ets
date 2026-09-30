import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { StorageService } from '../service/StorageService';
import { Constants } from '../common/Constants';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, Constants.LOG_TAG, 'Ability onCreate');
    // 初始化本地存储
    StorageService.init(this.context);
    // 记录系统深浅色，供 UI 响应
    AppStorage.setOrCreate('colorMode', this.context.config.colorMode);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('colorMode', newConfig.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(0x0000, Constants.LOG_TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const win: window.Window = windowStage.getMainWindowSync();
        win.setWindowBackgroundColor('#0A0E17');
      } catch (e) {
        hilog.warn(0x0000, Constants.LOG_TAG, 'set window background failed');
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, Constants.LOG_TAG, 'onWindowStageDestroy');
  }

  onDestroy(): void {
    hilog.info(0x0000, Constants.LOG_TAG, 'onDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
