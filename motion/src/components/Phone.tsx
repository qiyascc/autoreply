import React from 'react'
import { colors, font } from '../theme'

/**
 * The handset the whole film happens inside. Deliberately plain — a bezel, a notch and a
 * status bar — so attention stays on what is happening on the screen.
 */
export const Phone: React.FC<{
  children: React.ReactNode
  /** Small rotation used when the phone is ringing. */
  tilt?: number
  scale?: number
  time?: string
}> = ({ children, tilt = 0, scale = 1, time = '14:06' }) => {
  return (
    <div
      style={{
        width: 306,
        height: 622,
        borderRadius: 46,
        background: 'linear-gradient(160deg, #3A3A3C 0%, #1A1A1C 40%, #0A0A0B 100%)',
        padding: 9,
        boxShadow: '0 40px 90px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.06)',
        transform: `rotate(${tilt}deg) scale(${scale})`,
        transformOrigin: 'center center',
      }}
    >
      <div
        style={{
          position: 'relative',
          width: '100%',
          height: '100%',
          borderRadius: 38,
          overflow: 'hidden',
          background: colors.screen,
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        {/* Status bar */}
        <div
          style={{
            height: 34,
            flexShrink: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '0 20px',
            fontFamily: font,
            fontSize: 12,
            fontWeight: 600,
            color: colors.label,
            zIndex: 3,
          }}
        >
          <span>{time}</span>
          <span style={{ letterSpacing: 1.5, opacity: 0.9 }}>▮▮▮ ⌁</span>
        </div>

        {/* Notch */}
        <div
          style={{
            position: 'absolute',
            top: 8,
            left: '50%',
            transform: 'translateX(-50%)',
            width: 92,
            height: 22,
            borderRadius: 12,
            background: '#000',
            zIndex: 4,
          }}
        />

        <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>{children}</div>
      </div>
    </div>
  )
}
