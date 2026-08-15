import React from 'react'
import { interpolate, useCurrentFrame } from 'remotion'
import { colors, font } from '../theme'

/** The iOS incoming-call screen, with the ring pulse driven by the frame. */
export const CallScreen: React.FC<{ name: string; startAt?: number }> = ({
  name,
  startAt = 0,
}) => {
  const frame = useCurrentFrame() - startAt

  // Two expanding rings, half a beat apart, so the pulse never looks mechanical.
  const ring = (offset: number) => {
    const t = ((frame + offset) % 45) / 45
    return {
      transform: `translate(-50%, -50%) scale(${1 + t * 1.1})`,
      opacity: (1 - t) * 0.35,
    }
  }

  const buttonBob = Math.sin(frame / 7) * 2

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        background: 'linear-gradient(180deg, #1C1C1E 0%, #000 100%)',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        fontFamily: font,
      }}
    >
      <div style={{ marginTop: 54, textAlign: 'center' }}>
        <div style={{ color: colors.secondary, fontSize: 13, letterSpacing: 0.3 }}>
          incoming call
        </div>
        <div
          style={{
            color: colors.label,
            fontSize: 28,
            fontWeight: 600,
            marginTop: 6,
            letterSpacing: -0.4,
          }}
        >
          {name}
        </div>
        <div style={{ color: colors.secondary, fontSize: 14, marginTop: 2 }}>mobile</div>
      </div>

      <div style={{ position: 'relative', marginTop: 44, width: 120, height: 120 }}>
        {[0, 22].map((offset) => (
          <div
            key={offset}
            style={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              width: 120,
              height: 120,
              borderRadius: 60,
              border: `2px solid ${colors.tint}`,
              ...ring(offset),
            }}
          />
        ))}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            width: 104,
            height: 104,
            borderRadius: 52,
            background: '#3A3A3C',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 46,
          }}
        >
          🙍‍♂️
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          bottom: 46,
          left: 0,
          right: 0,
          display: 'flex',
          justifyContent: 'space-evenly',
        }}
      >
        <CallButton color={colors.danger} glyph="✕" label="Decline" bob={-buttonBob} />
        <CallButton color={colors.success} glyph="✆" label="Accept" bob={buttonBob} />
      </div>
    </div>
  )
}

const CallButton: React.FC<{
  color: string
  glyph: string
  label: string
  bob: number
}> = ({ color, glyph, label, bob }) => (
  <div style={{ textAlign: 'center', transform: `translateY(${bob}px)` }}>
    <div
      style={{
        width: 62,
        height: 62,
        borderRadius: 31,
        background: color,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 26,
        color: '#fff',
        boxShadow: `0 8px 24px ${color}55`,
      }}
    >
      {glyph}
    </div>
    <div style={{ color: colors.secondary, fontSize: 11, marginTop: 7 }}>{label}</div>
  </div>
)

/** What the screen becomes once the call has gone unanswered. */
export const MissedCallScreen: React.FC<{ name: string; startAt: number }> = ({
  name,
  startAt,
}) => {
  const frame = useCurrentFrame() - startAt
  const enter = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        background: '#000',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: font,
        opacity: enter,
      }}
    >
      <div
        style={{
          width: 72,
          height: 72,
          borderRadius: 36,
          background: 'rgba(255,69,58,0.15)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 32,
          transform: `scale(${interpolate(frame, [0, 14], [0.7, 1], {
            extrapolateRight: 'clamp',
          })})`,
        }}
      >
        📵
      </div>
      <div
        style={{
          color: colors.danger,
          fontSize: 17,
          fontWeight: 600,
          marginTop: 16,
        }}
      >
        Missed call
      </div>
      <div style={{ color: colors.secondary, fontSize: 14, marginTop: 4 }}>{name}</div>
    </div>
  )
}
