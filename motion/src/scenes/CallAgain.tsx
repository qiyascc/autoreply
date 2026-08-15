import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { CallScreen, MissedCallScreen } from '../components/CallScreen'
import { Phone } from '../components/Phone'
import { Caption, Stage } from '../components/Stage'
import { colors } from '../theme'

const RINGS_UNTIL = 52

/** Same missed call as before — except this time something is watching. */
export const CallAgain: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const ringing = frame < RINGS_UNTIL
  const tilt = ringing ? Math.sin(frame / 2.1) * 0.7 : 0

  return (
    <Stage
      background="linear-gradient(150deg, #101820 0%, #0A0A0B 100%)"
      caption={
        <Caption
          kicker="With Autoreply"
          title="The same missed call."
          body="Nothing on screen, nothing to tap. It notices the call was never answered and starts a one-minute clock."
        />
      }
    >
      <Phone tilt={tilt} time="14:05">
        {ringing ? (
          <CallScreen name="Elvin" />
        ) : (
          <>
            <MissedCallScreen name="Elvin" startAt={RINGS_UNTIL} />
            <ArmedPill startAt={RINGS_UNTIL + 12} fps={fps} />
          </>
        )}
      </Phone>
    </Stage>
  )
}

/** The quiet confirmation that a reply is queued — the app's whole personality. */
const ArmedPill: React.FC<{ startAt: number; fps: number }> = ({ startAt, fps }) => {
  const frame = useCurrentFrame()
  const local = frame - startAt
  if (local < 0) return null

  const enter = spring({ frame: local, fps, config: { damping: 14, stiffness: 130 } })
  const seconds = Math.max(0, 60 - Math.floor(local / 3))

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 44,
        display: 'flex',
        justifyContent: 'center',
        opacity: enter,
        transform: `translateY(${(1 - enter) * 14}px)`,
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          padding: '9px 15px',
          borderRadius: 20,
          background: 'rgba(10,132,255,0.16)',
          border: `1px solid rgba(10,132,255,0.4)`,
        }}
      >
        <div
          style={{
            width: 7,
            height: 7,
            borderRadius: 4,
            background: colors.tint,
            opacity: interpolate(Math.sin(local / 4), [-1, 1], [0.35, 1]),
          }}
        />
        <span style={{ color: '#fff', fontSize: 12, fontWeight: 500 }}>
          Replying in {seconds}s
        </span>
      </div>
    </div>
  )
}
