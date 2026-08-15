import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { colors, font } from '../theme'

export const ChatHeader: React.FC<{ name: string; status?: string }> = ({
  name,
  status = 'online',
}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '10px 14px',
      background: colors.chatBar,
      fontFamily: font,
      flexShrink: 0,
    }}
  >
    <div style={{ color: colors.label, fontSize: 18, opacity: 0.75 }}>‹</div>
    <div
      style={{
        width: 32,
        height: 32,
        borderRadius: 16,
        background: '#4A5A63',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 15,
      }}
    >
      🙍‍♂️
    </div>
    <div>
      <div style={{ color: colors.label, fontSize: 14, fontWeight: 600 }}>{name}</div>
      <div style={{ color: colors.secondary, fontSize: 11 }}>{status}</div>
    </div>
  </div>
)

/**
 * A chat bubble that springs in at `appearAt`. Outgoing bubbles can also show the
 * delivery ticks, which is how the film says "the reply actually went out".
 */
export const Bubble: React.FC<{
  text: string
  appearAt: number
  outgoing?: boolean
  time?: string
  ticks?: 'none' | 'sent' | 'read'
  /** Angry messages land with a shake instead of a gentle rise. */
  shake?: boolean
  fontSize?: number
}> = ({
  text,
  appearAt,
  outgoing = false,
  time = '14:06',
  ticks = 'none',
  shake = false,
  fontSize = 14,
}) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const local = frame - appearAt

  if (local < 0) return null

  const enter = spring({
    frame: local,
    fps,
    config: shake
      ? { damping: 9, stiffness: 220, mass: 0.5 }
      : { damping: 14, stiffness: 120, mass: 0.7 },
  })

  const wobble = shake
    ? Math.sin(local / 1.6) * interpolate(local, [0, 14], [4, 0], {
        extrapolateRight: 'clamp',
      })
    : 0

  return (
    <div
      style={{
        display: 'flex',
        justifyContent: outgoing ? 'flex-end' : 'flex-start',
        padding: '0 10px',
        marginTop: 6,
        opacity: enter,
        transform: `translateY(${(1 - enter) * 16}px) translateX(${wobble}px)`,
      }}
    >
      <div
        style={{
          maxWidth: '78%',
          background: outgoing ? colors.bubbleOut : colors.bubbleIn,
          borderRadius: 10,
          borderTopRightRadius: outgoing ? 2 : 10,
          borderTopLeftRadius: outgoing ? 10 : 2,
          padding: '7px 10px 5px',
          fontFamily: font,
          color: colors.label,
          fontSize,
          lineHeight: 1.35,
          boxShadow: '0 1px 1px rgba(0,0,0,0.3)',
        }}
      >
        <div>{text}</div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'flex-end',
            gap: 3,
            marginTop: 2,
            fontSize: 9,
            color: 'rgba(233,237,239,0.6)',
          }}
        >
          <span>{time}</span>
          {ticks !== 'none' && (
            <span style={{ color: ticks === 'read' ? '#53BDEB' : 'rgba(233,237,239,0.6)' }}>
              ✓✓
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

export const ChatInputBar: React.FC = () => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '8px 10px 12px',
      flexShrink: 0,
    }}
  >
    <div
      style={{
        flex: 1,
        height: 32,
        borderRadius: 16,
        background: colors.chatBar,
        display: 'flex',
        alignItems: 'center',
        padding: '0 12px',
        fontFamily: font,
        fontSize: 12,
        color: colors.secondary,
      }}
    >
      Message
    </div>
    <div
      style={{
        width: 32,
        height: 32,
        borderRadius: 16,
        background: '#00A884',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 14,
      }}
    >
      🎤
    </div>
  </div>
)

export const ChatScreen: React.FC<{ name: string; status?: string; children: React.ReactNode }> = ({
  name,
  status,
  children,
}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      background: colors.chatBg,
      display: 'flex',
      flexDirection: 'column',
    }}
  >
    <ChatHeader name={name} status={status} />
    <div
      style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'flex-end',
        paddingBottom: 4,
      }}
    >
      {children}
    </div>
    <ChatInputBar />
  </div>
)
