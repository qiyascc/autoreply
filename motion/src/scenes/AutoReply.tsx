import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { Bubble, ChatScreen } from '../components/Chat'
import { Phone } from '../components/Phone'
import { Caption, Stage } from '../components/Stage'
import { colors } from '../theme'

const REPLY_AT = 22
const READ_AT = 74
const ANSWER_AT = 104

/** The payoff: the message goes out on its own, and the other side calms down. */
export const AutoReply: React.FC = () => {
  const frame = useCurrentFrame()

  return (
    <Stage
      background="linear-gradient(150deg, #0E1F1A 0%, #0A0A0B 100%)"
      caption={
        <Caption
          kicker="One minute later"
          title="They hear from you anyway."
          body="Sent over WhatsApp by the bridge, or as a plain text message. Your phone stays in your pocket, locked."
        />
      }
    >
      <Phone time="14:06">
        <ChatScreen name="Elvin" status="online">
          <Bubble
            text="I’m busy right now — I’ll get back to you shortly."
            appearAt={REPLY_AT}
            outgoing
            time="14:06"
            ticks={frame >= READ_AT ? 'read' : 'sent'}
          />
          <Bubble text="👍 No problem, talk later!" appearAt={ANSWER_AT} time="14:07" />
        </ChatScreen>
        <SentAutomatically startAt={REPLY_AT + 6} />
      </Phone>
    </Stage>
  )
}

/** A floating note so viewers understand nobody typed that message. */
const SentAutomatically: React.FC<{ startAt: number }> = ({ startAt }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const local = frame - startAt
  if (local < 0) return null

  const enter = spring({ frame: local, fps, config: { damping: 15, stiffness: 120 } })
  const fade = interpolate(local, [58, 74], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <div
      style={{
        position: 'absolute',
        top: 52,
        left: 0,
        right: 0,
        display: 'flex',
        justifyContent: 'center',
        opacity: enter * fade,
        transform: `translateY(${(1 - enter) * -12}px)`,
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 7,
          padding: '8px 14px',
          borderRadius: 18,
          background: 'rgba(48,209,88,0.16)',
          border: '1px solid rgba(48,209,88,0.42)',
          backdropFilter: 'blur(8px)',
        }}
      >
        <span style={{ color: colors.success, fontSize: 12 }}>✓</span>
        <span style={{ color: '#fff', fontSize: 12, fontWeight: 500 }}>
          Sent automatically
        </span>
      </div>
    </div>
  )
}
