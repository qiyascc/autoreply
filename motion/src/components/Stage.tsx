import React from 'react'
import { AbsoluteFill, interpolate, useCurrentFrame } from 'remotion'
import { font } from '../theme'

/**
 * The layout every scene shares: a caption on the left, the phone on the right.
 * Keeping it in one place means the handset never jumps between scenes.
 */
export const Stage: React.FC<{
  background: string
  caption?: React.ReactNode
  children: React.ReactNode
  /** Fades and lifts the caption in over the first frames of the scene. */
  captionDelay?: number
}> = ({ background, caption, children, captionDelay = 6 }) => {
  const frame = useCurrentFrame()
  const captionIn = interpolate(frame, [captionDelay, captionDelay + 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <AbsoluteFill style={{ background, fontFamily: font }}>
      <AbsoluteFill
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 72,
          padding: '0 90px',
        }}
      >
        <div
          style={{
            width: 440,
            opacity: captionIn,
            transform: `translateY(${(1 - captionIn) * 18}px)`,
          }}
        >
          {caption}
        </div>
        <div>{children}</div>
      </AbsoluteFill>
    </AbsoluteFill>
  )
}

export const Caption: React.FC<{
  kicker?: string
  title: string
  body?: string
  tone?: 'light' | 'dark'
}> = ({ kicker, title, body, tone = 'light' }) => {
  const primary = tone === 'light' ? '#FFFFFF' : '#0A0A0B'
  const secondary = tone === 'light' ? 'rgba(255,255,255,0.62)' : 'rgba(10,10,11,0.6)'

  return (
    <div>
      {kicker && (
        <div
          style={{
            color: secondary,
            fontSize: 15,
            fontWeight: 600,
            letterSpacing: 2.4,
            textTransform: 'uppercase',
            marginBottom: 14,
          }}
        >
          {kicker}
        </div>
      )}
      <div
        style={{
          color: primary,
          fontSize: 52,
          lineHeight: 1.08,
          fontWeight: 700,
          letterSpacing: -1.4,
        }}
      >
        {title}
      </div>
      {body && (
        <div
          style={{
            color: secondary,
            fontSize: 20,
            lineHeight: 1.45,
            marginTop: 18,
            maxWidth: 400,
          }}
        >
          {body}
        </div>
      )}
    </div>
  )
}
