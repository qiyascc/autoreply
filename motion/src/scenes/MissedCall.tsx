import React from 'react'
import { useCurrentFrame } from 'remotion'
import { CallScreen, MissedCallScreen } from '../components/CallScreen'
import { Phone } from '../components/Phone'
import { Caption, Stage } from '../components/Stage'

const RINGS_UNTIL = 78

/** A call arrives. Nobody picks up. */
export const MissedCall: React.FC = () => {
  const frame = useCurrentFrame()
  const ringing = frame < RINGS_UNTIL

  // A tight buzz while it rings, settling to still the moment it is missed.
  const tilt = ringing ? Math.sin(frame / 2.1) * 0.7 : 0

  return (
    <Stage
      background="linear-gradient(150deg, #14161A 0%, #0A0A0B 100%)"
      caption={
        <Caption
          kicker="Every day"
          title="A call you can’t take."
          body="In a meeting, driving, hands full. The phone rings out and the other person is left with nothing."
        />
      }
    >
      <Phone tilt={tilt} time="14:05">
        {ringing ? (
          <CallScreen name="Elvin" />
        ) : (
          <MissedCallScreen name="Elvin" startAt={RINGS_UNTIL} />
        )}
      </Phone>
    </Stage>
  )
}
