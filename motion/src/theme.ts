/** Shared with the app and the landing page, so the film looks like the product. */
export const colors = {
  tint: '#0A84FF',
  tintDeep: '#003AC2',
  accent: '#FF9F0A',
  success: '#30D158',
  danger: '#FF453A',

  screen: '#000000',
  card: '#1C1C1E',
  cardHigh: '#2C2C2E',
  label: '#F2F2F7',
  secondary: '#8E8E93',

  // WhatsApp's chat surfaces, close enough to read as "that app" without copying it.
  chatBg: '#0B141A',
  chatBar: '#1F2C34',
  bubbleIn: '#1F2C34',
  bubbleOut: '#005C4B',
} as const

// None of the Apple/Windows faces exist on the render host, so the stack ends at the
// system sans — and Chrome then picks a monochrome symbol font for emoji unless the
// colour font is named explicitly. Hence the trailing entries.
export const font =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif, ' +
  '"Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"'

/** For runs of pure emoji, where the colour font should be first choice. */
export const emojiFont =
  '"Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji", sans-serif'

/** Scene boundaries in frames at 30 fps. */
export const timeline = {
  missedCall: { from: 0, durationInFrames: 120 },
  angry: { from: 120, durationInFrames: 165 },
  title: { from: 285, durationInFrames: 90 },
  callAgain: { from: 375, durationInFrames: 105 },
  autoReply: { from: 480, durationInFrames: 165 },
  outro: { from: 645, durationInFrames: 75 },
} as const

export const TOTAL_FRAMES = 720
export const FPS = 30
