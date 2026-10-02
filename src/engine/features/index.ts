/**
 * Встроенные механики движка. Порядок установки важен только для
 * систем с одинаковым order.
 */
import type { EngineFeature } from './feature';
import { councilFeature } from './council';
import { lifestylesFeature } from './lifestyles';
import { prisonFeature } from './prison';
import { factionsFeature } from './factions';
import { regimentsFeature } from './regiments';

export type { EngineFeature, ContentValidator } from './feature';
export const builtinFeatures: EngineFeature[] = [lifestylesFeature, councilFeature, prisonFeature, factionsFeature, regimentsFeature];
