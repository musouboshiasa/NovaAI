import { Usage } from '../model/Types';

/** 单位：美元 / 每 100 万 token */
export class PriceCard {
  /** 输入（缓存未命中） */
  inputMiss: number = 0;
  /** 输入（缓存命中） */
  inputHit: number = 0;
  /** 输出 */
  output: number = 0;
  currency: string = 'USD';
  label: string = '';
}

/**
 * 价格表（随官方调价可能变化，仅用于本地估算）
 */
export class Pricing {
  static readonly DEEPSEEK_FLASH: PriceCard = Pricing.card(0.30, 0.006, 1.20, 'DeepSeek-V4.1-Flash 高峰期');
  static readonly DEEPSEEK_PRO: PriceCard = Pricing.card(1.32, 0.044, 3.96, 'DeepSeek-V4-Pro 高峰期');
  static readonly DEEPSEEK_FLASH_OFF: PriceCard = Pricing.card(0.15, 0.003, 0.60, 'DeepSeek-V4.1-Flash 闲时');
  static readonly DEEPSEEK_PRO_OFF: PriceCard = Pricing.card(0.66, 0.022, 1.98, 'DeepSeek-V4-Pro 闲时');
  static readonly GPT5: PriceCard = Pricing.card(1.25, 0.125, 10.0, 'GPT-5');
  static readonly GPT5_MINI: PriceCard = Pricing.card(0.25, 0.025, 2.0, 'GPT-5 mini');
  static readonly GPT41: PriceCard = Pricing.card(2.0, 0.5, 8.0, 'GPT-4.1');
  static readonly GPT41_MINI: PriceCard = Pricing.card(0.4, 0.1, 1.6, 'GPT-4.1 mini');
  static readonly GPT4O: PriceCard = Pricing.card(2.5, 1.25, 10.0, 'GPT-4o');
  static readonly GPT4O_MINI: PriceCard = Pricing.card(0.15, 0.075, 0.6, 'GPT-4o mini');
  static readonly O3: PriceCard = Pricing.card(2.0, 0.5, 8.0, 'o3');
  static readonly O4_MINI: PriceCard = Pricing.card(1.1, 0.275, 4.4, 'o4-mini');
  static readonly UNKNOWN: PriceCard = Pricing.card(0, 0, 0, '未知模型');

  private static card(inputMiss: number, inputHit: number, output: number, label: string): PriceCard {
    const c: PriceCard = new PriceCard();
    c.inputMiss = inputMiss;
    c.inputHit = inputHit;
    c.output = output;
    c.label = label;
    return c;
  }

  /** DeepSeek 峰谷时段：UTC 周一至周五 01:00-04:00 与 06:00-10:00 为高峰 */
  static isDeepSeekPeak(now: Date): boolean {
    const day: number = now.getUTCDay();
    if (day === 0 || day === 6) {
      return false;
    }
    const h: number = now.getUTCHours();
    return (h >= 1 && h < 4) || (h >= 6 && h < 10);
  }

  static cardFor(model: string, peak: boolean): PriceCard {
    const m: string = model.toLowerCase();
    if (m.indexOf('deepseek') >= 0) {
      const isPro: boolean = m.indexOf('pro') >= 0;
      if (isPro) {
        return peak ? Pricing.DEEPSEEK_PRO : Pricing.DEEPSEEK_PRO_OFF;
      }
      return peak ? Pricing.DEEPSEEK_FLASH : Pricing.DEEPSEEK_FLASH_OFF;
    }
    if (m.indexOf('gpt-5-mini') >= 0) {
      return Pricing.GPT5_MINI;
    }
    if (m.indexOf('gpt-5') >= 0) {
      return Pricing.GPT5;
    }
    if (m.indexOf('gpt-4.1-mini') >= 0) {
      return Pricing.GPT41_MINI;
    }
    if (m.indexOf('gpt-4.1') >= 0) {
      return Pricing.GPT41;
    }
    if (m.indexOf('gpt-4o-mini') >= 0) {
      return Pricing.GPT4O_MINI;
    }
    if (m.indexOf('gpt-4o') >= 0) {
      return Pricing.GPT4O;
    }
    if (m.indexOf('o4-mini') >= 0) {
      return Pricing.O4_MINI;
    }
    if (m.startsWith('o3') || m.indexOf('/o3') >= 0) {
      return Pricing.O3;
    }
    return Pricing.UNKNOWN;
  }

  /** 估算一次调用的费用（美元） */
  static estimate(model: string, usage: Usage): number {
    const card: PriceCard = Pricing.cardFor(model, Pricing.isDeepSeekPeak(new Date()));
    if (card.inputMiss === 0 && card.output === 0) {
      return 0;
    }
    const missTokens: number = usage.cacheMissTokens > 0 ? usage.cacheMissTokens
      : Math.max(0, usage.promptTokens - usage.cacheHitTokens);
    const cost: number = (missTokens / 1000000) * card.inputMiss
      + (usage.cacheHitTokens / 1000000) * card.inputHit
      + (usage.completionTokens / 1000000) * card.output;
    return cost;
  }

  static formatUsd(v: number): string {
    if (v <= 0) {
      return '$0';
    }
    if (v < 0.0001) {
      return '<$0.0001';
    }
    if (v < 0.01) {
      return '$' + v.toFixed(4);
    }
    if (v < 1) {
      return '$' + v.toFixed(3);
    }
    return '$' + v.toFixed(2);
  }
}
