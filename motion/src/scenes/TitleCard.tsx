import React from 'react'
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion'
import { colors, font } from '../theme'

/** The turn: state the promise plainly, then get back to showing it. */
export const TitleCard: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badge = spring({ frame, fps, config: { damping: 13, stiffness: 110 } })
  const titleIn = interpolate(frame, [12, 32], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const subIn = interpolate(frame, [24, 44], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const out = interpolate(frame, [72, 88], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(150deg, ${colors.tint} 0%, ${colors.tintDeep} 100%)`,
        fontFamily: font,
        alignItems: 'center',
        justifyContent: 'center',
        opacity: out,
      }}
    >
      <Img
        src={staticFile('icon.png')}
        style={{
          width: 96,
          height: 96,
          borderRadius: 22,
          transform: `scale(${badge}) rotate(${(1 - badge) * -12}deg)`,
          boxShadow: '0 24px 60px rgba(0,0,0,0.35)',
        }}
      />
      <div
        style={{
          color: '#fff',
          fontSize: 62,
          fontWeight: 700,
          letterSpacing: -1.8,
          marginTop: 30,
          opacity: titleIn,
          transform: `translateY(${(1 - titleIn) * 18}px)`,
        }}
      >
        Let’s fix that.
      </div>
      <div
        style={{
          color: 'rgba(255,255,255,0.72)',
          fontSize: 22,
          marginTop: 14,
          opacity: subIn,
          transform: `translateY(${(1 - subIn) * 14}px)`,
        }}
      >
        Autoreply answers the calls you miss — for you.
      </div>
    </AbsoluteFill>
  )
}
