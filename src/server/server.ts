import { BunHttpServer } from '@effect/platform-bun'
import { Config, Effect, Layer } from 'effect'
import { HttpRouter } from 'effect/http'
import { HttpApiBuilder } from 'effect/http-api'

import { Api } from '@/api/api'
import index from '@/client/index.html'
import { HealthLive } from '@/server/health.handlers'

const ApiLive = HttpApiBuilder.layer(Api).pipe(Layer.provide(HealthLive))

/**
 * Serves the API under `/api` and the bundled client at `/`.
 *
 * @internal
 */
export const makeServer = (port: number) => HttpRouter.serve(ApiLive).pipe(Layer.provideMerge(BunHttpServer.layer({ port, routes: { '/': index } })))

export const ServerLive = Layer.unwrap(
  Effect.gen(function* () {
    const port = yield* Config.Port('PORT').pipe(Config.withDefault(3000))
    return makeServer(port)
  })
)
