import { Config } from '@remotion/cli/config'

Config.setVideoImageFormat('jpeg')
Config.setOverwriteOutput(true)
// The film is flat colour and type; a high CRF here would show as banding on gradients.
Config.setCrf(18)
