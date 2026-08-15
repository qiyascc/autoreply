import React from 'react'
import { useCurrentFrame } from 'remotion'
import { Bubble, ChatScreen } from '../components/Chat'
import { Phone } from '../components/Phone'
import { Caption, Stage } from '../components/Stage'

// Bright faces only — Noto's 😠 is nearly black and disappears on a dark chat surface.
const MESSAGES = [
  { text: 'Where are you??', at: 10 },
  { text: '😡😡😡', at: 34, fontSize: 28 },
  { text: 'Pick up the phone!!', at: 58 },
  { text: '🤬🤬🤬🤬', at: 82, fontSize: 28 },
  { text: 'Seriously?! 😤', at: 106 },
]

/** Silence reads as rudeness. The other side fills it in for you. */
export const AngryMessages: React.FC = () => {
  const frame = useCurrentFrame()

  // Each arriving message knocks the handset; the jolt decays before the next one.
  const jolt = MESSAGES.reduce((acc, m) => {
    const since = frame - m.at
    if (since < 0 || since > 12) return acc
    return acc + Math.sin(since / 1.3) * (1 - since / 12) * 1.1
  }, 0)

  return (
    <Stage
      background="linear-gradient(150deg, #2A1214 0%, #0A0A0B 100%)"
      caption={
        <Caption
          kicker="What happens next"
          title="Silence looks like you’re ignoring them."
          body="You never meant it that way. They have no way of knowing."
        />
      }
    >
      <Phone tilt={jolt} time="14:06">
        <ChatScreen name="Elvin" status="online">
          {MESSAGES.map((m) => (
            <Bubble
              key={m.at}
              text={m.text}
              appearAt={m.at}
              shake
              fontSize={m.fontSize}
              time="14:06"
            />
          ))}
        </ChatScreen>
      </Phone>
    </Stage>
  )
}
