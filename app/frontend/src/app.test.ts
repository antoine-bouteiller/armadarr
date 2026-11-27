import { create } from '@bufbuild/protobuf'
import { ConnectError, createClient, createRouterTransport } from '@connectrpc/connect'
import { mount, unmount } from 'svelte'
import { afterEach, expect, test } from 'vite-plus/test'

import App from '@/app.svelte'
import { CheckResponseSchema, HealthService, Status } from '@/gen/armadarr/v1/health_pb'

const mounted: ReturnType<typeof mount>[] = []

const render = (check: () => ReturnType<typeof create<typeof CheckResponseSchema>>) => {
  const transport = createRouterTransport(({ service }) => {
    service(HealthService, { check })
  })
  const target = document.createElement('div')
  mounted.push(mount(App, { props: { health: createClient(HealthService, transport) }, target }))
  return target
}

afterEach(async () => {
  await Promise.all(mounted.splice(0).map((app) => unmount(app)))
})

test('shows the status the health service returns', async () => {
  const target = render(() => create(CheckResponseSchema, { status: Status.OK }))

  await expect.poll(() => target.textContent).toContain('Server: ok')
})

test('shows the server as unreachable when the call fails', async () => {
  const target = render(() => {
    throw new ConnectError('down')
  })

  await expect.poll(() => target.textContent).toContain('Server: unreachable')
})
