/**
 * 设计系统：颜色 / 圆角 / 间距 / 字体
 * 支持亮色与暗色两套调色板
 */

export interface Palette {
  /** 页面背景 */
  bg: string;
  /** 页面背景渐变（顶部） */
  bgTop: string;
  /** 卡片/表面 */
  surface: string;
  /** 次级表面 */
  surfaceAlt: string;
  /** 悬浮层（弹窗/抽屉） */
  elevated: string;
  /** 分隔线 */
  border: string;
  /** 强分隔线 */
  borderStrong: string;
  /** 主要文字 */
  text: string;
  /** 次要文字 */
  textSecondary: string;
  /** 弱化文字 */
  textTertiary: string;
  /** 主题色 */
  accent: string;
  /** 主题色浅 */
  accentSoft: string;
  /** 渐变起点 */
  gradStart: string;
  /** 渐变终点 */
  gradEnd: string;
  /** 用户气泡背景 */
  userBubble: string;
  /** 用户气泡文字 */
  userBubbleText: string;
  /** AI 气泡背景 */
  aiBubble: string;
  /** 代码块背景 */
  codeBg: string;
  /** 代码块头部 */
  codeHeader: string;
  /** 代码文字 */
  codeText: string;
  /** 行内代码背景 */
  inlineCodeBg: string;
  /** 行内代码文字 */
  inlineCodeText: string;
  /** 成功 */
  success: string;
  /** 警告 */
  warning: string;
  /** 错误 */
  error: string;
  /** 遮罩 */
  scrim: string;
  /** 思维链背景 */
  reasonBg: string;
  /** 思维链文字 */
  reasonText: string;
  /** 思维链描边 */
  reasonBorder: string;
  /** 阴影色 */
  shadow: string;
  /** 输入框背景 */
  inputBg: string;
}

export class Themes {
  static readonly dark: Palette = {
    bg: '#0A0E17',
    bgTop: '#101728',
    surface: '#141B2B',
    surfaceAlt: '#1B2334',
    elevated: '#18202F',
    border: '#232C40',
    borderStrong: '#2E3950',
    text: '#EAEFF9',
    textSecondary: '#9AA6BF',
    textTertiary: '#66728C',
    accent: '#6C8CFF',
    accentSoft: '#1E2A4A',
    gradStart: '#6366F1',
    gradEnd: '#22D3EE',
    userBubble: '#3B5BDB',
    userBubbleText: '#FFFFFF',
    aiBubble: '#141B2B',
    codeBg: '#0D1421',
    codeHeader: '#151E2E',
    codeText: '#D7E2F5',
    inlineCodeBg: '#1E2A42',
    inlineCodeText: '#8FD3FF',
    success: '#3DD68C',
    warning: '#F5B544',
    error: '#FF6B6B',
    scrim: '#CC02060E',
    reasonBg: '#101A2B',
    reasonText: '#93A5C6',
    reasonBorder: '#22314B',
    shadow: '#66000000',
    inputBg: '#1A2233'
  };

  static readonly light: Palette = {
    bg: '#F5F7FC',
    bgTop: '#FFFFFF',
    surface: '#FFFFFF',
    surfaceAlt: '#F2F5FB',
    elevated: '#FFFFFF',
    border: '#E4E9F3',
    borderStrong: '#D2D9E8',
    text: '#111827',
    textSecondary: '#5B6577',
    textTertiary: '#8B94A7',
    accent: '#4C6EF5',
    accentSoft: '#E8EDFF',
    gradStart: '#6366F1',
    gradEnd: '#06B6D4',
    userBubble: '#4C6EF5',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FFFFFF',
    codeBg: '#F7F9FD',
    codeHeader: '#EDF1F9',
    codeText: '#1F2937',
    inlineCodeBg: '#EEF2FB',
    inlineCodeText: '#2563EB',
    success: '#12B76A',
    warning: '#F79009',
    error: '#F04438',
    scrim: '#66101828',
    reasonBg: '#F6F8FE',
    reasonText: '#5A6A85',
    reasonBorder: '#E1E8F5',
    shadow: '#14000000',
    inputBg: '#FFFFFF'
  };

  static of(isDark: boolean): Palette {
    return isDark ? Themes.dark : Themes.light;
  }
}

export class Dim {
  static readonly r4: number = 4;
  static readonly r8: number = 8;
  static readonly r10: number = 10;
  static readonly r12: number = 12;
  static readonly r14: number = 14;
  static readonly r16: number = 16;
  static readonly r18: number = 18;
  static readonly r20: number = 20;
  static readonly r24: number = 24;
  static readonly r28: number = 28;
  static readonly r32: number = 32;

  static readonly s2: number = 2;
  static readonly s4: number = 4;
  static readonly s6: number = 6;
  static readonly s8: number = 8;
  static readonly s10: number = 10;
  static readonly s12: number = 12;
  static readonly s14: number = 14;
  static readonly s16: number = 16;
  static readonly s20: number = 20;
  static readonly s24: number = 24;
  static readonly s32: number = 32;
  static readonly s40: number = 40;
  static readonly s48: number = 48;
}

export class Font {
  static readonly xs: number = 11;
  static readonly sm: number = 13;
  static readonly base: number = 15;
  static readonly md: number = 16;
  static readonly lg: number = 18;
  static readonly xl: number = 22;
  static readonly xxl: number = 28;
  static readonly mono: number = 13;
  static readonly code: string = 'monospace';
}
