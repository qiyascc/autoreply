import React from 'react'
import { Composition } from 'remotion'
import { Explainer } from './Explainer'
import { FPS, TOTAL_FRAMES } from './theme'

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Explainer"
      component={Explainer}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1280}
      height={720}
    />
    {/* Square cut for social posts; same film, different frame. */}
    <Composition
      id="ExplainerSquare"
      component={Explainer}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1080}
      height={1080}
    />
  </>
)
