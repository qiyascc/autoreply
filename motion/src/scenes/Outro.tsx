import React from 'react'
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion'
import { colors, font } from '../theme'

export const Outro: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const icon = spring({ frame, fps, config: { damping: 13, stiffness: 105 } })
  const text = interpolate(frame, [10, 28], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const url = interpolate(frame, [22, 40], [0, 1], {
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
      }}
    >
      <Img
        src={staticFile('icon.png')}
        style={{
          width: 110,
          height: 110,
          borderRadius: 25,
          transform: `scale(${icon})`,
          boxShadow: '0 26px 64px rgba(0,0,0,0.35)',
        }}
      />
      <div
        style={{
          color: '#fff',
          fontSize: 54,
          fontWeight: 700,
          letterSpacing: -1.4,
          marginTop: 26,
          opacity: text,
        }}
      >
        Autoreply
      </div>
      <div
        style={{
          color: 'rgba(255,255,255,0.75)',
          fontSize: 20,
          marginTop: 10,
          opacity: text,
        }}
      >
        Answers the calls you miss, so you don’t have to.
      </div>
      <div
        style={{
          marginTop: 34,
          padding: '11px 22px',
          borderRadius: 22,
          background: 'rgba(255,255,255,0.16)',
          border: '1px solid rgba(255,255,255,0.28)',
          color: '#fff',
          fontSize: 17,
          fontWeight: 500,
          letterSpacing: 0.2,
          opacity: url,
          transform: `translateY(${(1 - url) * 12}px)`,
        }}
      >
        ctm.ubermensch.cc
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 34,
          color: 'rgba(255,255,255,0.5)',
          fontSize: 13,
          fontWeight: 600,
          letterSpacing: 1.6,
          opacity: url,
        }}
      >
        QIYAS CC
      </div>
    </AbsoluteFill>
  )
}
