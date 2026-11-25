import { describe, expect, test } from 'bun:test'

import { Effect } from 'effect'
import { FetchHttpClient, HttpClient, HttpServer } from 'effect/http'
import { HttpApiClient } from 'effect/http-api'

import { Api } from '@/api/api'
import { makeServer } from '@/server/server'

const runAgainstServer = <Success, Failure>(use: (baseUrl: string) => Effect.Effect<Success, Failure, HttpClient.HttpClient>) =>
  HttpServer.addressFormattedWith(use).pipe(Effect.provide([makeServer(0), FetchHttpClient.layer]), Effect.runPromise)

describe('server', () => {
  test('serves the client page at /', async () => {
    const html = await runAgainstServer((baseUrl) =>
      HttpClient.get(baseUrl).pipe(
        Effect.flatMap((response) => response.text),
        Effect.scoped
      )
    )

    expect(html).toContain('<div id="root"></div>')
  })

  test('answers the health check through the shared API contract', async () => {
    const health = await runAgainstServer((baseUrl) => HttpApiClient.make(Api, { baseUrl }).pipe(Effect.flatMap((client) => client.health.check())))

    expect(health).toEqual({ status: 'ok' })
  })
})
