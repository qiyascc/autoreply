import React from 'react'
import { AbsoluteFill, interpolate, Sequence, useCurrentFrame } from 'remotion'
import { AngryMessages } from './scenes/AngryMessages'
import { AutoReply } from './scenes/AutoReply'
import { CallAgain } from './scenes/CallAgain'
import { MissedCall } from './scenes/MissedCall'
import { Outro } from './scenes/Outro'
import { TitleCard } from './scenes/TitleCard'
import { timeline } from './theme'

/** Softens every cut, so the film reads as one take rather than six clips. */
const Fade: React.FC<{ durationInFrames: number; children: React.ReactNode }> = ({
  durationInFrames,
  children,
}) => {
  const frame = useCurrentFrame()
  const opacity = interpolate(
    frame,
    [0, 8, durationInFrames - 8, durationInFrames],
    [0, 1, 1, 0],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
  )
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>
}

const SCENES = [
  { key: 'missedCall', component: MissedCall, ...timeline.missedCall },
  { key: 'angry', component: AngryMessages, ...timeline.angry },
  { key: 'title', component: TitleCard, ...timeline.title },
  { key: 'callAgain', component: CallAgain, ...timeline.callAgain },
  { key: 'autoReply', component: AutoReply, ...timeline.autoReply },
  { key: 'outro', component: Outro, ...timeline.outro },
] as const

export const Explainer: React.FC = () => (
  <AbsoluteFill style={{ background: '#0A0A0B' }}>
    {SCENES.map(({ key, component: Scene, from, durationInFrames }) => (
      <Sequence key={key} from={from} durationInFrames={durationInFrames} name={key}>
        <Fade durationInFrames={durationInFrames}>
          <Scene />
        </Fade>
      </Sequence>
    ))}
  </AbsoluteFill>
)
