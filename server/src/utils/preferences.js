const { z } = require('zod');


const ACCENTS = ['olive', 'clay', 'indigo', 'plum', 'amber'];
const THEME_MODES = ['system', 'light', 'dark'];
const LANGUAGES = ['system', 'ru', 'en'];

const DEFAULTS = Object.freeze({
  notifications: Object.freeze({
    friendRequests: true,
    sessionInvites: true,
  }),
  language: 'system',
  appearance: Object.freeze({
    themeMode: 'system',
    accent: 'olive',
    textScale: 1.0,
    compact: false,
    reduceMotion: false,
    artworkBackground: true,
    startTab: 0,
  }),
});

const notificationsSchema = z
  .object({
    friendRequests: z.boolean(),
    sessionInvites: z.boolean(),
  })
  .partial()
  .strict();

const appearanceSchema = z
  .object({
    themeMode: z.enum(THEME_MODES),
    accent: z.enum(ACCENTS),
    textScale: z.number().min(0.85).max(1.3),
    compact: z.boolean(),
    reduceMotion: z.boolean(),
    artworkBackground: z.boolean(),
    startTab: z.number().int().min(0).max(2),
  })
  .partial()
  .strict();

const preferencesSchema = z
  .object({
    notifications: notificationsSchema,
    appearance: appearanceSchema,
    language: z.enum(LANGUAGES),
    updatedAt: z.number().int().nonnegative(),
  })
  .partial()
  .strict();

function withDefaults(stored) {
  const value = stored && typeof stored === 'object' && !Array.isArray(stored) ? stored : {};

  return {
    notifications: { ...DEFAULTS.notifications, ...(value.notifications || {}) },
    appearance: { ...DEFAULTS.appearance, ...(value.appearance || {}) },
    language: LANGUAGES.includes(value.language) ? value.language : DEFAULTS.language,
    updatedAt: typeof value.updatedAt === 'number' ? value.updatedAt : 0,
  };
}

function mergePreferences(stored, patch) {
  const current = withDefaults(stored);

  return {
    notifications: { ...current.notifications, ...(patch.notifications || {}) },
    appearance: { ...current.appearance, ...(patch.appearance || {}) },
    language: patch.language ?? current.language,
    updatedAt: patch.updatedAt ?? Date.now(),
  };
}

module.exports = {
  DEFAULTS,
  preferencesSchema,
  withDefaults,
  mergePreferences,
};
