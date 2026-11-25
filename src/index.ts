import { runMain } from '@effect/platform-bun/BunRuntime'
import { Layer } from 'effect'

import { LoggerLive } from '@/config/logger'
import { ServerLive } from '@/server/server'

ServerLive.pipe(Layer.provide(LoggerLive), Layer.launch, runMain)
