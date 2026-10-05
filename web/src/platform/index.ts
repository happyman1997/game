import { createDesktopPlatform, type DesktopBridge } from './desktop';
import type { Platform } from './types';
import { createWebPlatform } from './web';

export type { FolderKind, Platform, SaveMeta, SaveStore, Settings } from './types';

const bridge = (globalThis as { desktop?: DesktopBridge }).desktop;

/** Текущая платформа: настольное приложение, если есть мост Electron, иначе браузер. */
export const platform: Platform = bridge ? createDesktopPlatform(bridge) : createWebPlatform();
export const isDesktop = platform.kind === 'desktop';
